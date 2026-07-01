//
//  OfflineElevationOrchestrator.swift
//  TopoLog
//
//  网络状态监测 + GPS 搜星延迟保护 + 气压计离线托底 + 重连平滑对齐。
//

import Combine
import CoreLocation
import CoreMotion
import Foundation
import Network

// MARK: - TopoNetworkMonitor

/// 基于 `NWPathMonitor` 的极简网络可达性监听（省电、无轮询）。
@MainActor
final class TopoNetworkMonitor: ObservableObject {
    @Published private(set) var isOffline: Bool = false
    @Published private(set) var usesExpensivePath: Bool = false
    @Published private(set) var usesConstrainedPath: Bool = false

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "cc.sryze.topolog.network.monitor", qos: .utility)
    private var isStarted = false

    func start() {
        guard !isStarted else { return }
        isStarted = true

        monitor.pathUpdateHandler = { [weak self] path in
            let offline = path.status != .satisfied
            let expensive = path.isExpensive
            let constrained = path.isConstrained

            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isOffline = offline
                self.usesExpensivePath = expensive
                self.usesConstrainedPath = constrained
            }
        }
        monitor.start(queue: queue)

        let snapshot = monitor.currentPath
        isOffline = snapshot.status != .satisfied
        usesExpensivePath = snapshot.isExpensive
        usesConstrainedPath = snapshot.isConstrained
    }

    func stop() {
        guard isStarted else { return }
        monitor.cancel()
        isStarted = false
    }
}

// MARK: - Fusion Mode

enum OfflineElevationFusionMode: String, Sendable {
    case onlineGPS
    case barometerFallback
    case reconnectionCalibration
}

enum OfflineElevationSensorIssue: String, Sendable, Identifiable {
    case motionPermissionDenied
    case altimeterUnavailable
    case locationPermissionDenied

    var id: String { rawValue }

    var localizedMessage: String {
        switch self {
        case .motionPermissionDenied:
            return L10n.t("TopoLog uses motion activity to auto start/stop recording and save battery.")
        case .altimeterUnavailable:
            return L10n.t("Barometric elevation fallback is unavailable on this device.")
        case .locationPermissionDenied:
            return L10n.t("TopoLog needs your location to record tracks and elevation.")
        }
    }
}

// MARK: - OfflineElevationOrchestrator

/// 传感器融合调度引擎：在线 GPS 绝对海拔 ↔ 离线/弱星历气压计托底 ↔ 重连 anti-jump 校准。
@MainActor
final class OfflineElevationOrchestrator: NSObject, ObservableObject {
    static let shared = OfflineElevationOrchestrator()

    // MARK: Published State

    /// 与 `FootprintTrackingEngine` 同步的最近脚印滑动窗口（最多 `FootprintConfig.effectiveMaxFootprints` 条）。
    @Published private(set) var recentFootprints: [FootprintPoint] = []

    @Published private(set) var fusedElevationMeters: Double = 0
    @Published private(set) var fusionMode: OfflineElevationFusionMode = .onlineGPS
    @Published private(set) var isBarometerFallbackActive: Bool = false
    @Published private(set) var activeSensorIssue: OfflineElevationSensorIssue?

    let networkMonitor = TopoNetworkMonitor()

    /// 飞行模式 / 无网络 A-GPS，或 GPS 垂直精度不可用且气压计正在托底时为 true。
    var isBlackboxModeActive: Bool {
        isBarometerFallbackActive
            && (networkMonitor.isOffline || !lastGpsSampleWasReliable)
    }

    // MARK: Calibration State

    private var lastGpsAbsoluteAltitude: Double?
    private var accumulativeBarometricOffset: Double = 0
    private var barometerSessionAnchorRelative: Double?
    private var lastBarometerRelativeSample: Double?
    private var lastGpsSampleWasReliable = false

    private var pendingCalibrationResidual: Double = 0
    private var calibrationStepsRemaining: Int = 0
    private static let calibrationSpreadSteps = 5
    private static let gpsReliableVerticalAccuracy: CLLocationAccuracy = 15
    private static let gpsPoorVerticalAccuracy: CLLocationAccuracy = 50

    // MARK: Sensors

    private let locationManager = CLLocationManager()
    private let altimeter = CMAltimeter()
    private let motionActivityManager = CMMotionActivityManager()
    private let sensorQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "cc.sryze.topolog.sensor.fusion"
        queue.maxConcurrentOperationCount = 1
        return queue
    }()

    private var usesExternalLocationFeed = true
    private var isRunning = false
    private var isBarometerStreaming = false
    private var latestMotionActivity: CMMotionActivity?
    private var lastKnownLocation: CLLocation?
    private var lastHistoricalElevationHint: Double?
    private var footprintCancellable: AnyCancellable?

    private override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 3
        locationManager.activityType = .fitness
        bindFootprintEngine()
    }

    // MARK: Lifecycle

    /// - Parameter useExternalLocationFeed: `true` 时由 `OutdoorDashboardStore` 喂入定位，避免双 `CLLocationManager`。
    func configure(useExternalLocationFeed: Bool = true) {
        usesExternalLocationFeed = useExternalLocationFeed
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true

        networkMonitor.start()
        refreshMotionAuthorizationState()
        startMotionActivityUpdates()

        if !usesExternalLocationFeed {
            locationManager.requestWhenInUseAuthorization()
            locationManager.startUpdatingLocation()
        }

        seedHistoricalElevationHint()
        NSLog("OfflineElevationOrchestrator: started externalFeed=\(usesExternalLocationFeed)")
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false

        networkMonitor.stop()
        stopBarometerFallbackStream()

        if !usesExternalLocationFeed {
            locationManager.stopUpdatingLocation()
        }
        motionActivityManager.stopActivityUpdates()

        isBarometerFallbackActive = false
        fusionMode = .onlineGPS
        NSLog("OfflineElevationOrchestrator: stopped")
    }

    // MARK: External Feed (OutdoorDashboardStore)

    /// 主入口：融合海拔并驱动脚印写入。
    @discardableResult
    func feed(
        location: CLLocation,
        motionActivity: CMMotionActivity?,
        isIndoor: Bool
    ) -> Double {
        guard isRunning else { return fusedElevationMeters }

        lastKnownLocation = location
        if let motionActivity {
            latestMotionActivity = motionActivity
        }

        let gpsReliable = Self.isGpsVerticallyReliable(location)
        let shouldUseBarometer = shouldActivateBarometerFallback(for: location, gpsReliable: gpsReliable)

        let elevation: Double
        if shouldUseBarometer {
            elevation = resolveBarometricAbsoluteElevation()
            fusionMode = calibrationStepsRemaining > 0 ? .reconnectionCalibration : .barometerFallback
            ensureBarometerFallbackStream()
        } else if gpsReliable {
            elevation = applyCalibrationIfNeeded(to: location.altitude)
            enterOnlineGpsMode(with: location.altitude)
            fusionMode = calibrationStepsRemaining > 0 ? .reconnectionCalibration : .onlineGPS
        } else {
            // 在线但 GPS 尚未就绪：若已有气压流则继续托底，否则保持上次融合值。
            if isBarometerStreaming {
                elevation = resolveBarometricAbsoluteElevation()
                fusionMode = .barometerFallback
            } else {
                elevation = fusedElevationMeters > 0 ? fusedElevationMeters : location.altitude
                fusionMode = .onlineGPS
            }
        }

        lastGpsSampleWasReliable = gpsReliable
        fusedElevationMeters = elevation

        commitFootprintIfNeeded(
            location: location,
            elevation: elevation,
            isIndoor: isIndoor
        )

        return elevation
    }

    // MARK: Online / Offline Logic

    private func shouldActivateBarometerFallback(
        for location: CLLocation,
        gpsReliable: Bool
    ) -> Bool {
        if networkMonitor.isOffline { return true }
        if location.verticalAccuracy < 0 { return true }
        if location.verticalAccuracy > Self.gpsPoorVerticalAccuracy { return true }
        if !gpsReliable { return true }
        return false
    }

    private func enterOnlineGpsMode(with gpsAltitude: Double) {
        let previousMode = fusionMode
        let previousFused = fusedElevationMeters

        if isBarometerFallbackActive || previousMode == .barometerFallback {
            let barometricEstimate = previousFused > 0 ? previousFused : resolveBarometricAbsoluteElevation()
            let errorOffset = gpsAltitude - barometricEstimate
            if abs(errorOffset) >= 0.5 {
                beginSmoothCalibration(errorOffset: errorOffset)
            }
        }

        lastGpsAbsoluteAltitude = gpsAltitude
        resetBarometricAccumulation()
        stopBarometerFallbackStream()
        fusionMode = calibrationStepsRemaining > 0 ? .reconnectionCalibration : .onlineGPS
    }

    private func resolveBarometricAbsoluteElevation() -> Double {
        let anchor = lastGpsAbsoluteAltitude
            ?? lastHistoricalElevationHint
            ?? lastKnownLocation?.altitude
            ?? 0

        let relativeDelta = accumulativeBarometricOffset
        return anchor + relativeDelta
    }

    private func resetBarometricAccumulation() {
        accumulativeBarometricOffset = 0
        barometerSessionAnchorRelative = lastBarometerRelativeSample
    }

    // MARK: Barometer Stream

    private func ensureBarometerFallbackStream() {
        guard CMAltimeter.isRelativeAltitudeAvailable() else {
            activeSensorIssue = .altimeterUnavailable
            isBarometerFallbackActive = false
            return
        }

        activeSensorIssue = nil
        isBarometerFallbackActive = true
        guard !isBarometerStreaming else { return }
        isBarometerStreaming = true

        altimeter.startRelativeAltitudeUpdates(to: sensorQueue) { [weak self] data, error in
            guard let self else { return }

            if let error {
                Task { @MainActor in
                    NSLog("OfflineElevationOrchestrator: altimeter error \(error.localizedDescription)")
                    self.isBarometerStreaming = false
                    self.isBarometerFallbackActive = false
                }
                return
            }

            guard let data else { return }
            let relative = data.relativeAltitude.doubleValue

            Task { @MainActor in
                self.ingestBarometerSample(relativeMeters: relative)
            }
        }

        NSLog("OfflineElevationOrchestrator: barometer fallback stream started")
    }

    private func ingestBarometerSample(relativeMeters: Double) {
        lastBarometerRelativeSample = relativeMeters

        if barometerSessionAnchorRelative == nil {
            barometerSessionAnchorRelative = relativeMeters
        }

        let anchor = barometerSessionAnchorRelative ?? relativeMeters
        accumulativeBarometricOffset = relativeMeters - anchor

        guard isBarometerFallbackActive else { return }

        let absolute = resolveBarometricAbsoluteElevation()
        fusedElevationMeters = absolute

        if let location = lastKnownLocation {
            commitFootprintIfNeeded(
                location: location,
                elevation: absolute,
                isIndoor: false
            )
        }
    }

    private func stopBarometerFallbackStream() {
        guard isBarometerStreaming else {
            isBarometerFallbackActive = false
            return
        }
        altimeter.stopRelativeAltitudeUpdates()
        isBarometerStreaming = false
        isBarometerFallbackActive = false
        barometerSessionAnchorRelative = nil
    }

    // MARK: Anti-Jump Calibration

    private func beginSmoothCalibration(errorOffset: Double) {
        pendingCalibrationResidual = errorOffset
        calibrationStepsRemaining = Self.calibrationSpreadSteps
        fusionMode = .reconnectionCalibration

        // 对内存窗口内最近脚印做整体 Y 轴微调，避免图表出现垂直断崖。
        nudgeRecentFootprints(by: errorOffset * 0.35)

        NSLog(
            "OfflineElevationOrchestrator: smooth calibration started " +
            "offset=\(String(format: "%.2f", errorOffset))m"
        )
    }

    private func applyCalibrationIfNeeded(to gpsAltitude: Double) -> Double {
        guard calibrationStepsRemaining > 0 else { return gpsAltitude }

        let fraction = Double(calibrationStepsRemaining) / Double(Self.calibrationSpreadSteps)
        let blended = gpsAltitude - pendingCalibrationResidual * fraction
        calibrationStepsRemaining -= 1

        if calibrationStepsRemaining == 0 {
            pendingCalibrationResidual = 0
            fusionMode = .onlineGPS
        }

        return blended
    }

    private func nudgeRecentFootprints(by delta: Double) {
        guard abs(delta) > 0.01 else { return }

        let adjusted = recentFootprints.map { point in
            FootprintPoint(
                id: point.id,
                coordinate: point.coordinate,
                elevation: point.elevation + delta,
                timestamp: point.timestamp,
                isIndoor: point.isIndoor
            )
        }

        recentFootprints = adjusted
        FootprintTrackingEngine.shared.applyInMemoryFootprintAdjustments(adjusted)
    }

    // MARK: Footprints

    private func bindFootprintEngine() {
        footprintCancellable = FootprintTrackingEngine.shared.$recentFootprints
            .receive(on: RunLoop.main)
            .sink { [weak self] footprints in
                self?.recentFootprints = footprints
            }
    }

    private func commitFootprintIfNeeded(
        location: CLLocation,
        elevation: Double,
        isIndoor: Bool
    ) {
        guard location.horizontalAccuracy >= 0 else { return }

        FootprintTrackingEngine.shared.ingest(
            location: location,
            elevation: elevation,
            isIndoor: isIndoor,
            motionActivity: latestMotionActivity
        )
    }

    // MARK: Motion Permission

    private func startMotionActivityUpdates() {
        guard CMMotionActivityManager.isActivityAvailable() else { return }

        let status = CMMotionActivityManager.authorizationStatus()
        if status == .denied || status == .restricted {
            activeSensorIssue = .motionPermissionDenied
            return
        }

        motionActivityManager.startActivityUpdates(to: sensorQueue) { [weak self] activity in
            guard let activity else { return }
            Task { @MainActor [weak self] in
                self?.latestMotionActivity = activity
                if self?.activeSensorIssue == .motionPermissionDenied {
                    self?.activeSensorIssue = nil
                }
            }
        }
    }

    private func refreshMotionAuthorizationState() {
        let status = CMMotionActivityManager.authorizationStatus()
        if status == .denied || status == .restricted {
            activeSensorIssue = .motionPermissionDenied
        }
    }

    private func seedHistoricalElevationHint() {
        if let last = FootprintTrackingEngine.shared.recentFootprints.last {
            lastHistoricalElevationHint = last.elevation
            return
        }
        if let last = RecentHistoryBuffer.shared.points.last {
            lastHistoricalElevationHint = last.elevation
        }
    }

    // MARK: Helpers

    private static func isGpsVerticallyReliable(_ location: CLLocation) -> Bool {
        location.verticalAccuracy > 0
            && location.verticalAccuracy <= gpsReliableVerticalAccuracy
    }
}

// MARK: - Standalone CLLocationManagerDelegate

extension OfflineElevationOrchestrator: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            guard !self.usesExternalLocationFeed else { return }
            _ = self.feed(location: location, motionActivity: self.latestMotionActivity, isIndoor: false)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            NSLog("OfflineElevationOrchestrator: location error \(error.localizedDescription)")
            if let clError = error as? CLError, clError.code == .denied {
                self.activeSensorIssue = .locationPermissionDenied
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            switch manager.authorizationStatus {
            case .denied, .restricted:
                self.activeSensorIssue = .locationPermissionDenied
            default:
                if self.activeSensorIssue == .locationPermissionDenied {
                    self.activeSensorIssue = nil
                }
            }
        }
    }
}
