//
//  OutdoorDashboardStore.swift
//  AltiPin
//

import Combine
import CoreLocation
import CoreMotion
import Foundation
import SwiftData
import UIKit

enum ActivitySessionPhase: String, Sendable {
    case idle
    case running
    case paused
}

struct ActivitySessionSnapshot: Sendable {
    let points: [HistoryPoint]
    let duration: TimeInterval
    let distanceMeters: Double
    let startTime: Date
    let endTime: Date
}

@MainActor
final class OutdoorDashboardStore: NSObject, ObservableObject {
    @Published private(set) var heading: Double = 0
    @Published private(set) var latitude: Double = 0
    @Published private(set) var longitude: Double = 0
    @Published private(set) var elevationMeters: Double = 0
    @Published private(set) var speedKmh: Double = 0
    @Published private(set) var pressureHPa: Double = 0
    @Published private(set) var sessionDuration: TimeInterval = 0
    @Published private(set) var cumulativeDistanceMeters: Double = 0
    @Published private(set) var horizontalAccuracy: Double = -1
    @Published private(set) var verticalAccuracy: Double = -1
    @Published private(set) var levelOffsetX: Double = 0
    @Published private(set) var levelOffsetY: Double = 0
    @Published private(set) var isLevel: Bool = true
    @Published private(set) var isMonitoring = false
    @Published private(set) var magneticFieldX: Double = 0
    @Published private(set) var magneticFieldY: Double = 0
    @Published private(set) var magneticFieldZ: Double = 0
    @Published private(set) var magneticFieldStrength: Double = 0

    @Published private(set) var navigationEnvironment: NavigationEnvironment = .outdoor
    @Published private(set) var estimatedIndoorFloor: Int?
    @Published private(set) var indoorBaselinePressureHPa: Double?
    @Published private(set) var navigationEnvironmentDiagnostic: String = "initial"
    @Published private(set) var needsFloorCalibration = false
    @Published private(set) var matchedBuildingLabel: String?
    @Published private(set) var floorCalibrationSource: FloorCalibrationSource?
    @Published private(set) var navigationEnvironmentControlMode: NavigationEnvironmentControlMode = .automatic

    @Published private(set) var isSpeedSessionActive = false
    @Published private(set) var speedSessionDuration: TimeInterval = 0
    @Published private(set) var speedSessionDistanceMeters: Double = 0
    @Published private(set) var speedSessionMaxSpeedKmh: Double = 0
    @Published private(set) var speedSessionElevationGainMeters: Double = 0
    @Published private(set) var recentHistoryPoints: [HistoryPoint] = []
    @Published private(set) var activitySessionPhase: ActivitySessionPhase = .idle

    var speedSessionAverageSpeedKmh: Double {
        guard speedSessionDuration > 0 else { return 0 }
        let hours = speedSessionDuration / 3600
        guard hours > 0 else { return 0 }
        return (speedSessionDistanceMeters / 1000) / hours
    }

    private let locationManager = CLLocationManager()
    private let altimeter = CMAltimeter()
    private let motionActivityManager = CMMotionActivityManager()
    private let motionManager = CMMotionManager()
    private let navigationEnvironmentController = NavigationEnvironmentController()
    private let indoorFloorEstimator = IndoorFloorEstimator()
    private var buildingCalibrationStore: BuildingCalibrationStore?
    private let sensorQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.goodcraft.AltiPin.dashboard"
        queue.maxConcurrentOperationCount = 1
        return queue
    }()

    private var gpsBaselineAltitude: Double?
    private var altimeterReference: Double?
    private var activityAccumulatedDuration: TimeInterval = 0
    private var activitySegmentStartDate: Date?
    private var activityDurationTimer: Timer?
    private var activityLastDistanceSample: CLLocation?
    private var activitySessionPoints: [HistoryPoint] = []
    private var activitySessionStartedAt: Date?
    private var lastMagneticFieldUpdateDate: Date?
    private let magneticFieldUpdateInterval: TimeInterval = 0.5

    private var speedSessionStartDate: Date?
    private var speedSessionLastSample: CLLocation?
    private var speedSessionTimer: Timer?
    private var lastHistoryPointSample: CLLocation?
    private var latestMotionActivity: CMMotionActivity?
    private var lastKnownLocation: CLLocation?
    private var recentHistoryCancellable: AnyCancellable?

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 3
        locationManager.headingFilter = 1
        locationManager.activityType = .fitness

        recentHistoryPoints = RecentHistoryBuffer.shared.points
        recentHistoryCancellable = RecentHistoryBuffer.shared.$points
            .receive(on: RunLoop.main)
            .sink { [weak self] points in
                self?.recentHistoryPoints = points
            }
    }

    func configure(modelContext: ModelContext) {
        buildingCalibrationStore = BuildingCalibrationStore(modelContext: modelContext)
    }

    var isManualNavigationOverride: Bool {
        navigationEnvironmentControlMode.isManual
    }

    var isIndoorFloorCalibrated: Bool {
        navigationEnvironment == .indoor && indoorFloorEstimator.isCalibrated
    }

    /// 切换环境判定模式：自动 / 手动室内 / 手动室外。
    func setNavigationEnvironmentControlMode(_ mode: NavigationEnvironmentControlMode) {
        navigationEnvironmentControlMode = mode
        NavigationEnvironmentOverrideCenter.apply(mode)

        switch mode {
        case .automatic:
            if let location = lastKnownLocation {
                evaluateNavigationEnvironment(with: location, triggerHaptic: false)
            } else {
                navigationEnvironmentDiagnostic = "automatic (awaiting location)"
            }
        case let .manual(environment):
            applyNavigationEnvironment(environment, location: lastKnownLocation, triggerHaptic: true)
            navigationEnvironmentDiagnostic = "\(environment.rawValue) (manual override)"
        }
    }

    func startMonitoring() {
        guard !isMonitoring else { return }

        isMonitoring = true
        lastHistoryPointSample = nil
        recentHistoryPoints = RecentHistoryBuffer.shared.points
        gpsBaselineAltitude = nil
        altimeterReference = nil
        navigationEnvironmentController.reset()
        indoorFloorEstimator.deactivate()
        navigationEnvironment = .outdoor
        estimatedIndoorFloor = nil
        indoorBaselinePressureHPa = nil
        needsFloorCalibration = false
        matchedBuildingLabel = nil
        floorCalibrationSource = nil
        navigationEnvironmentControlMode = .automatic
        NavigationEnvironmentOverrideCenter.reset()
        latestMotionActivity = nil

        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
        locationManager.startUpdatingHeading()
        startAltimeter()
        startMotionActivityUpdates()
        startDeviceMotion()
        startMagnetometer()

        if activitySessionPhase == .running {
            beginActivityDurationSegment()
        }
    }

    func stopMonitoring() {
        guard isMonitoring else { return }

        if isSpeedSessionActive {
            stopSpeedSession()
        }

        isMonitoring = false
        locationManager.stopUpdatingLocation()
        locationManager.stopUpdatingHeading()
        altimeter.stopRelativeAltitudeUpdates()
        motionActivityManager.stopActivityUpdates()
        motionManager.stopDeviceMotionUpdates()
        motionManager.stopMagnetometerUpdates()

        if activitySessionPhase == .running {
            freezeActivityDuration()
        }
        stopActivityDurationTimer()
    }

    func startActivitySession() {
        switch activitySessionPhase {
        case .idle:
            activityAccumulatedDuration = 0
            sessionDuration = 0
            cumulativeDistanceMeters = 0
            activitySessionPoints = []
            activitySessionStartedAt = Date()
            activityLastDistanceSample = lastKnownLocation
            activitySessionPhase = .running
            seedActivitySessionPointIfNeeded()
            beginActivityDurationSegment()
        case .paused:
            activitySessionPhase = .running
            activityLastDistanceSample = lastKnownLocation
            beginActivityDurationSegment()
        case .running:
            break
        }
    }

    func pauseActivitySession() {
        guard activitySessionPhase == .running else { return }
        freezeActivityDuration()
        stopActivityDurationTimer()
        activitySessionPhase = .paused
    }

    /// 结束当前运动会话段并返回快照。`endSession == true` 时回到 idle；否则保留 running（组队房主移交用）。
    @discardableResult
    func stopActivitySession(endSession: Bool) -> ActivitySessionSnapshot {
        if activitySessionPhase == .running {
            freezeActivityDuration()
            stopActivityDurationTimer()
        }

        appendActivitySessionPointIfNeeded(force: true)

        let snapshot = currentActivitySessionSnapshot()

        if endSession {
            resetActivitySession()
        } else {
            resetActivitySessionSegment()
        }

        return snapshot
    }

    func currentActivitySessionSnapshot(includeCurrentLocation: Bool = false) -> ActivitySessionSnapshot {
        if includeCurrentLocation {
            appendActivitySessionPointIfNeeded(force: true)
        }

        var duration = sessionDuration
        if activitySessionPhase == .running, let start = activitySegmentStartDate {
            duration = activityAccumulatedDuration + Date().timeIntervalSince(start)
        }

        return ActivitySessionSnapshot(
            points: activitySessionPoints,
            duration: duration,
            distanceMeters: cumulativeDistanceMeters,
            startTime: activitySessionStartedAt ?? Date(),
            endTime: Date()
        )
    }

    func resetActivitySession() {
        activitySessionPhase = .idle
        activityAccumulatedDuration = 0
        activitySegmentStartDate = nil
        sessionDuration = 0
        cumulativeDistanceMeters = 0
        activityLastDistanceSample = nil
        activitySessionPoints = []
        activitySessionStartedAt = nil
        stopActivityDurationTimer()
    }

    func startSpeedSession() {
        guard !isSpeedSessionActive else { return }

        isSpeedSessionActive = true
        speedSessionDuration = 0
        speedSessionDistanceMeters = 0
        speedSessionMaxSpeedKmh = 0
        speedSessionElevationGainMeters = 0
        speedSessionStartDate = .now
        speedSessionLastSample = nil

        startSpeedSessionTimer()
    }

    func stopSpeedSession() {
        guard isSpeedSessionActive else { return }

        isSpeedSessionActive = false
        speedSessionTimer?.invalidate()
        speedSessionTimer = nil
        speedSessionStartDate = nil
        speedSessionLastSample = nil
    }

    func toggleSpeedSession() {
        if isSpeedSessionActive {
            stopSpeedSession()
        } else {
            startSpeedSession()
        }
    }

    /// 进入海拔 Tab 时调用：基于最新定位/气压即时评估室内外，并请求一次 fresh 定位。
    func refreshNavigationEnvironmentForAltitudeTab() {
        if !isMonitoring {
            startMonitoring()
        }

        applySnapshotAssessmentForAltitudeTab()
        queryRecentMotionActivityForAssessment()
        locationManager.requestLocation()
    }

    /// 用户确认当前所在楼层（首次进入室内且无 CLFloor / 历史记录时）。
    func confirmFloorCalibration(floor: Int, label: String?) {
        guard navigationEnvironment == .indoor, pressureHPa > 0 else { return }
        applyFloorCalibration(
            baseFloor: floor,
            baselinePressureHPa: pressureHPa,
            currentPressureHPa: pressureHPa,
            label: label,
            source: .manual,
            persist: true
        )
    }

    /// 重新校准楼层基准（已在室内且需修正时）。
    func recalibrateIndoorFloor(to floor: Int, label: String?) {
        confirmFloorCalibration(floor: floor, label: label)
    }

    /// 供 UI 展示的环境诊断摘要。
    var navigationEnvironmentDebugSummary: String {
        let floorText = estimatedIndoorFloor.map { "\($0)F" } ?? "—"
        return "\(navigationEnvironmentDiagnostic) · floor=\(floorText)"
    }

    var currentLocation: CLLocation? {
        guard horizontalAccuracy >= 0 else { return nil }
        if let lastKnownLocation {
            return lastKnownLocation
        }
        return CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            altitude: elevationMeters,
            horizontalAccuracy: horizontalAccuracy,
            verticalAccuracy: verticalAccuracy,
            timestamp: Date()
        )
    }

    /// 脚印/历史采样使用的统一海拔解析。
    func resolvedElevation(for location: CLLocation) -> Double {
        if elevationMeters > 0 { return elevationMeters }
        if location.verticalAccuracy >= 0 { return location.altitude }
        if let lastKnownLocation, lastKnownLocation.verticalAccuracy >= 0 {
            return lastKnownLocation.altitude
        }
        return location.altitude
    }

    var compassDirectionName: String {
        Self.directionName(for: heading)
    }

    var coordinateDMSString: String {
        Self.formatCoordinateDMS(latitude: latitude, longitude: longitude)
    }

    var longitudeDMS: String {
        Self.dmsValue(value: longitude)
    }

    var latitudeDMS: String {
        Self.dmsValue(value: latitude)
    }

    var coordinateDecimalString: String {
        let latSuffix = latitude >= 0 ? "N" : "S"
        let lonSuffix = longitude >= 0 ? "E" : "W"
        return String(
            format: "%.6f°%@, %.6f°%@",
            abs(latitude), latSuffix,
            abs(longitude), lonSuffix
        )
    }

    // MARK: - Private

    private func startAltimeter() {
        guard CMAltimeter.isRelativeAltitudeAvailable() else { return }

        altimeter.startRelativeAltitudeUpdates(to: sensorQueue) { [weak self] data, error in
            guard let data, error == nil else { return }
            let relative = data.relativeAltitude.doubleValue
            let pressureKPa = data.pressure.doubleValue

            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.altimeterReference == nil {
                    self.altimeterReference = relative
                }
                let offset = relative - (self.altimeterReference ?? relative)
                if let baseline = self.gpsBaselineAltitude {
                    self.elevationMeters = baseline + offset
                }
                self.pressureHPa = pressureKPa * 10

                if self.navigationEnvironment == .indoor {
                    self.beginIndoorFloorCalibrationIfNeeded(with: self.lastKnownLocation)
                    self.updateIndoorFloorEstimateIfNeeded()
                }
            }
        }
    }

    private func startMotionActivityUpdates() {
        guard CMMotionActivityManager.isActivityAvailable() else { return }

        motionActivityManager.startActivityUpdates(to: sensorQueue) { [weak self] activity in
            guard let activity else { return }
            Task { @MainActor [weak self] in
                self?.latestMotionActivity = activity
            }
        }
    }

    private func resetActivitySessionSegment() {
        activitySessionPoints = []
        activitySessionStartedAt = Date()
        activityAccumulatedDuration = 0
        activitySegmentStartDate = nil
        sessionDuration = 0
        cumulativeDistanceMeters = 0
        activityLastDistanceSample = lastKnownLocation
        activitySessionPhase = .running
        seedActivitySessionPointIfNeeded()
        beginActivityDurationSegment()
    }

    private func seedActivitySessionPointIfNeeded() {
        guard activitySessionPoints.isEmpty, let location = lastKnownLocation else { return }
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 40 else { return }

        let elevation = resolvedElevation(for: location)
        activitySessionPoints.append(
            HistoryPoint(
                timestamp: location.timestamp,
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                elevation: elevation,
                elevationDelta: 0,
                isIndoor: navigationEnvironment == .indoor
            )
        )
    }

    private func appendActivitySessionPointIfNeeded(force: Bool = false) {
        guard activitySessionPhase == .running || force else { return }
        guard let location = lastKnownLocation else { return }
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 40 else { return }

        if !force {
            if let last = activitySessionPoints.last {
                let lastLocation = CLLocation(latitude: last.latitude, longitude: last.longitude)
                guard location.distance(from: lastLocation) >= 2 else { return }
            }
        } else if !activitySessionPoints.isEmpty {
            if let last = activitySessionPoints.last {
                let lastLocation = CLLocation(latitude: last.latitude, longitude: last.longitude)
                guard location.distance(from: lastLocation) >= 1 else { return }
            }
        }

        let elevation = resolvedElevation(for: location)
        let previousElevation = activitySessionPoints.last?.elevation ?? elevation
        activitySessionPoints.append(
            HistoryPoint(
                timestamp: location.timestamp,
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                elevation: elevation,
                elevationDelta: elevation - previousElevation,
                isIndoor: navigationEnvironment == .indoor
            )
        )
    }

    private func beginActivityDurationSegment() {
        activitySegmentStartDate = .now
        refreshActivityDurationDisplay()
        startActivityDurationTimer()
    }

    private func freezeActivityDuration() {
        guard let start = activitySegmentStartDate else { return }
        activityAccumulatedDuration += Date().timeIntervalSince(start)
        activitySegmentStartDate = nil
        sessionDuration = activityAccumulatedDuration
    }

    private func refreshActivityDurationDisplay() {
        if let start = activitySegmentStartDate {
            sessionDuration = activityAccumulatedDuration + Date().timeIntervalSince(start)
        } else {
            sessionDuration = activityAccumulatedDuration
        }
    }

    private func startActivityDurationTimer() {
        activityDurationTimer?.invalidate()
        activityDurationTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshActivityDurationDisplay()
            }
        }
    }

    private func stopActivityDurationTimer() {
        activityDurationTimer?.invalidate()
        activityDurationTimer = nil
    }

    private func startSpeedSessionTimer() {
        speedSessionTimer?.invalidate()
        speedSessionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let start = self.speedSessionStartDate else { return }
                self.speedSessionDuration = Date().timeIntervalSince(start)
            }
        }
    }

    private func startDeviceMotion() {
        guard motionManager.isDeviceMotionAvailable else { return }

        motionManager.deviceMotionUpdateInterval = 1.0 / 30.0
        motionManager.startDeviceMotionUpdates(using: .xArbitraryCorrectedZVertical, to: sensorQueue) { [weak self] motion, _ in
            guard let motion else { return }
            let roll = motion.attitude.roll
            let pitch = motion.attitude.pitch
            let field = motion.magneticField.field
            let fieldAccuracy = motion.magneticField.accuracy

            Task { @MainActor [weak self] in
                guard let self else { return }
                let maxTilt = 0.35
                self.levelOffsetX = max(-1, min(1, roll / maxTilt))
                self.levelOffsetY = max(-1, min(1, pitch / maxTilt))
                self.isLevel = abs(roll) < 0.05 && abs(pitch) < 0.05

                if fieldAccuracy != .uncalibrated {
                    self.updateMagneticField(x: field.x, y: field.y, z: field.z)
                }
            }
        }
    }

    private func startMagnetometer() {
        guard motionManager.isMagnetometerAvailable else { return }

        motionManager.magnetometerUpdateInterval = magneticFieldUpdateInterval
        motionManager.startMagnetometerUpdates(to: sensorQueue) { [weak self] data, error in
            guard let data, error == nil else { return }
            let field = data.magneticField

            Task { @MainActor [weak self] in
                self?.updateMagneticField(x: field.x, y: field.y, z: field.z)
            }
        }
    }

    private func updateMagneticField(x: Double, y: Double, z: Double) {
        let now = Date()
        if let last = lastMagneticFieldUpdateDate,
           now.timeIntervalSince(last) < magneticFieldUpdateInterval {
            return
        }
        lastMagneticFieldUpdateDate = now

        magneticFieldX = x
        magneticFieldY = y
        magneticFieldZ = z
        magneticFieldStrength = sqrt(x * x + y * y + z * z)
    }

    private func ingestLocation(_ location: CLLocation) {
        lastKnownLocation = location
        latitude = location.coordinate.latitude
        longitude = location.coordinate.longitude
        horizontalAccuracy = location.horizontalAccuracy
        verticalAccuracy = location.verticalAccuracy

        evaluateNavigationEnvironment(with: location)

        if location.speed >= 0 {
            speedKmh = location.speed * 3.6
        }

        if gpsBaselineAltitude == nil, location.verticalAccuracy >= 0, location.verticalAccuracy <= 30 {
            gpsBaselineAltitude = location.altitude
            elevationMeters = location.altitude
        }

        if activitySessionPhase == .running {
            if let last = activityLastDistanceSample,
               location.horizontalAccuracy >= 0,
               location.horizontalAccuracy <= 40 {
                let delta = location.distance(from: last)
                if delta >= 2 {
                    cumulativeDistanceMeters += delta
                }
            }

            if location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 40 {
                activityLastDistanceSample = location
            }

            appendActivitySessionPointIfNeeded()
        }

        if isSpeedSessionActive {
            ingestSpeedSessionSample(location)
        }

        appendHistoryPointIfNeeded(location)
        Task { @MainActor in
            self.ingestFootprintIfNeeded(location: location)
        }
    }

    private func ingestFootprintIfNeeded(location: CLLocation) {
        guard horizontalAccuracy >= 0 else { return }

        let elevation = resolvedElevation(for: location)
        FootprintTrackingEngine.shared.ingest(
            location: location,
            elevation: elevation,
            isIndoor: navigationEnvironment == .indoor,
            motionActivity: latestMotionActivity
        )
    }

    private func evaluateNavigationEnvironment(with location: CLLocation, triggerHaptic: Bool = true) {
        if NavigationEnvironmentOverrideCenter.isManual {
            enforceManualNavigationEnvironment(triggerHaptic: false)
            if navigationEnvironment == .indoor {
                beginIndoorFloorCalibrationIfNeeded(with: location)
                updateIndoorFloorEstimateIfNeeded()
            }
            if let manual = NavigationEnvironmentOverrideCenter.manualEnvironment {
                navigationEnvironmentDiagnostic = "\(manual.rawValue) (manual override)"
            }
            return
        }

        if let transition = navigationEnvironmentController.evaluateEnvironment(
            currentLocation: location,
            currentPressureHPa: pressureHPa,
            motionActivity: latestMotionActivity
        ) {
            applyNavigationTransition(transition, triggerHaptic: triggerHaptic)
        } else if navigationEnvironment == .indoor {
            beginIndoorFloorCalibrationIfNeeded(with: location)
            updateIndoorFloorEstimateIfNeeded()
        }

        syncNavigationDiagnosticFromController()
    }

    private func applySnapshotAssessmentForAltitudeTab() {
        guard let location = lastKnownLocation else { return }

        if NavigationEnvironmentOverrideCenter.isManual {
            enforceManualNavigationEnvironment(triggerHaptic: false)
            if let manual = NavigationEnvironmentOverrideCenter.manualEnvironment {
                navigationEnvironmentDiagnostic = "\(manual.rawValue) (manual override)"
            }
            return
        }

        let assessment = navigationEnvironmentController.snapshotEnvironment(
            currentLocation: location,
            motionActivity: latestMotionActivity
        )
        applyNavigationEnvironment(assessment.environment, location: location, triggerHaptic: false)
        navigationEnvironmentDiagnostic = "\(assessment.environment.rawValue) (\(assessment.reason))"
    }

    private func assessNavigationEnvironmentUsingCachedData(triggerHaptic: Bool) {
        guard let location = lastKnownLocation else { return }
        evaluateNavigationEnvironment(with: location, triggerHaptic: triggerHaptic)
    }

    private func applyNavigationEnvironment(
        _ target: NavigationEnvironment,
        location: CLLocation? = nil,
        triggerHaptic: Bool
    ) {
        let resolvedLocation = location ?? lastKnownLocation

        guard target != navigationEnvironment else {
            if target == .indoor {
                beginIndoorFloorCalibrationIfNeeded(with: resolvedLocation)
                updateIndoorFloorEstimateIfNeeded()
            }
            return
        }

        switch target {
        case .indoor:
            navigationEnvironment = .indoor
            navigationEnvironmentController.adoptIndoorState()
            indoorFloorEstimator.deactivate()
            needsFloorCalibration = false
            matchedBuildingLabel = nil
            floorCalibrationSource = nil
            estimatedIndoorFloor = nil
            indoorBaselinePressureHPa = nil
            beginIndoorFloorCalibrationIfNeeded(with: resolvedLocation)
            updateIndoorFloorEstimateIfNeeded()
            if triggerHaptic {
                triggerIndoorTransitionHaptic()
            }
        case .outdoor:
            navigationEnvironment = .outdoor
            estimatedIndoorFloor = nil
            indoorBaselinePressureHPa = nil
            needsFloorCalibration = false
            matchedBuildingLabel = nil
            floorCalibrationSource = nil
            indoorFloorEstimator.deactivate()
            navigationEnvironmentController.adoptOutdoorState()
        }
    }

    private func applyNavigationTransition(
        _ transition: NavigationEnvironment,
        triggerHaptic: Bool
    ) {
        applyNavigationEnvironment(transition, location: lastKnownLocation, triggerHaptic: triggerHaptic)
    }

    private func enforceManualNavigationEnvironment(triggerHaptic: Bool) {
        guard let target = NavigationEnvironmentOverrideCenter.manualEnvironment else { return }
        applyNavigationEnvironment(target, location: lastKnownLocation, triggerHaptic: triggerHaptic)
    }

    private func beginIndoorFloorCalibrationIfNeeded(with location: CLLocation?) {
        guard navigationEnvironment == .indoor else { return }
        guard pressureHPa > 0 else { return }
        guard !indoorFloorEstimator.isCalibrated else { return }

        guard let location else {
            needsFloorCalibration = true
            return
        }

        switch IndoorFloorCalibrationHelper.resolve(
            location: location,
            buildingStore: buildingCalibrationStore
        ) {
        case let .calibrated(baseFloor, storedBaselinePressure, source, label):
            let baselinePressure = storedBaselinePressure ?? pressureHPa
            applyFloorCalibration(
                baseFloor: baseFloor,
                baselinePressureHPa: baselinePressure,
                currentPressureHPa: pressureHPa,
                label: label,
                source: source,
                persist: source != .persisted
            )
            if source == .persisted, let record = buildingCalibrationStore?.findMatch(near: location)?.record {
                buildingCalibrationStore?.touchUsageOnly(record)
            }
        case .needsManual:
            needsFloorCalibration = true
            NSLog("OutdoorDashboardStore: indoor floor calibration required (no CLFloor / history)")
        }
    }

    private func applyFloorCalibration(
        baseFloor: Int,
        baselinePressureHPa: Double,
        currentPressureHPa: Double,
        label: String?,
        source: FloorCalibrationSource,
        persist: Bool
    ) {
        indoorFloorEstimator.calibrate(baseFloor: baseFloor, pressureHPa: baselinePressureHPa)
        indoorBaselinePressureHPa = baselinePressureHPa
        estimatedIndoorFloor = indoorFloorEstimator.update(currentPressureHPa: currentPressureHPa)
            ?? indoorFloorEstimator.estimatedFloor
        needsFloorCalibration = false
        matchedBuildingLabel = label
        floorCalibrationSource = source

        if persist, let location = lastKnownLocation ?? currentLocation {
            let savedLabel = label ?? matchedBuildingLabel
            buildingCalibrationStore?.saveCalibration(
                location: location,
                floor: baseFloor,
                pressureHPa: baselinePressureHPa,
                label: savedLabel
            )
            if savedLabel != nil {
                matchedBuildingLabel = savedLabel
            }
        }

        NSLog(
            "OutdoorDashboardStore: floor calibrated base=\(baseFloor) source=\(source.rawValue) " +
            "baseline=\(String(format: "%.1f", baselinePressureHPa))hPa " +
            "current=\(String(format: "%.1f", currentPressureHPa))hPa " +
            "estimated=\(estimatedIndoorFloor.map(String.init) ?? "—") " +
            "label=\(label ?? "—")"
        )
    }

    private func updateIndoorFloorEstimateIfNeeded() {
        guard navigationEnvironment == .indoor, pressureHPa > 0 else { return }
        guard indoorFloorEstimator.isCalibrated else {
            estimatedIndoorFloor = nil
            return
        }
        estimatedIndoorFloor = indoorFloorEstimator.update(currentPressureHPa: pressureHPa)
            ?? indoorFloorEstimator.estimatedFloor
    }

    private func syncNavigationDiagnosticFromController() {
        let assessment = navigationEnvironmentController.lastAssessment
        navigationEnvironmentDiagnostic = "\(assessment.environment.rawValue) (\(assessment.reason))"
    }

    private func queryRecentMotionActivityForAssessment() {
        guard CMMotionActivityManager.isActivityAvailable() else { return }

        let from = Date().addingTimeInterval(-120)
        motionActivityManager.queryActivityStarting(from: from, to: .now, to: sensorQueue) { [weak self] activities, _ in
            guard let latest = activities?.last else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.latestMotionActivity = latest
                self.assessNavigationEnvironmentUsingCachedData(triggerHaptic: false)
            }
        }
    }

    private func triggerIndoorTransitionHaptic() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred()
    }

    private func appendHistoryPointIfNeeded(_ location: CLLocation) {
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 40 else { return }

        let elevation = resolvedElevation(for: location)
        let isIndoor = navigationEnvironment == .indoor

        if RecentHistoryBuffer.shared.appendIfNeeded(
            timestamp: location.timestamp,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            elevation: elevation,
            isIndoor: isIndoor
        ) != nil {
            lastHistoryPointSample = location
        }
    }

    private func ingestSpeedSessionSample(_ location: CLLocation) {
        let currentSpeed = location.speed >= 0 ? location.speed * 3.6 : speedKmh
        if currentSpeed > speedSessionMaxSpeedKmh {
            speedSessionMaxSpeedKmh = currentSpeed
        }

        guard let last = speedSessionLastSample,
              location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= 40 else {
            if location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 40 {
                speedSessionLastSample = location
            }
            return
        }

        let horizontalDelta = location.distance(from: last)
        if horizontalDelta >= 2 {
            speedSessionDistanceMeters += horizontalDelta

            let elevationDelta = location.altitude - last.altitude
            if elevationDelta > 0 {
                speedSessionElevationGainMeters += elevationDelta
            }
        }

        speedSessionLastSample = location
    }

    #if DEBUG
    func applyDebugSimulatorTeamLocationIfNeeded() {
        #if targetEnvironment(simulator)
        guard latitude == 0, longitude == 0 else { return }

        let track = DebugTeamFixtures.taiWaiMockTrack()
        guard let latest = track.last else { return }

        latitude = latest.latitude
        longitude = latest.longitude
        elevationMeters = latest.elevation
        horizontalAccuracy = 5
        verticalAccuracy = 8
        recentHistoryPoints = track
        #endif
    }
    #endif

    static func directionName(for degrees: Double) -> String {
        let normalized = (degrees.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        let names = ["北", "东北", "东", "东南", "南", "西南", "西", "西北"]
        let index = Int((normalized + 22.5) / 45) % 8
        return names[index]
    }

    static func formatCoordinateDMS(latitude: Double, longitude: Double) -> String {
        let lon = dmsComponent(value: longitude, positiveLabel: "东经", negativeLabel: "西经")
        let lat = dmsComponent(value: latitude, positiveLabel: "北纬", negativeLabel: "南纬")
        return "\(lon)  \(lat)"
    }

    static func preview() -> OutdoorDashboardStore {
        let store = OutdoorDashboardStore()
        store.heading = 61
        store.latitude = 22.3678
        store.longitude = 114.1817
        store.elevationMeters = 91
        store.speedKmh = 1.50
        store.pressureHPa = 1013.2
        store.configurePreviewActivitySession(duration: 24 * 60, distanceMeters: 1200)
        store.horizontalAccuracy = 5
        store.verticalAccuracy = 8
        store.magneticFieldX = 22.5
        store.magneticFieldY = -8.3
        store.magneticFieldZ = 41.2
        store.magneticFieldStrength = 47.8
        store.navigationEnvironment = .indoor
        store.confirmFloorCalibration(floor: 3, label: "预览楼栋")
        store.isSpeedSessionActive = true
        store.speedSessionDuration = 129
        store.speedSessionDistanceMeters = 540
        store.speedSessionMaxSpeedKmh = 7.9
        store.speedSessionElevationGainMeters = 12.4
        RecentHistoryBuffer.shared.reset()
        for point in HistoryPoint.mockPoints {
            RecentHistoryBuffer.shared.ingestRecordedPoint(point)
        }
        return store
    }

    #if DEBUG
    func configurePreviewActivitySession(duration: TimeInterval, distanceMeters: Double) {
        activitySessionPhase = .running
        activityAccumulatedDuration = duration
        sessionDuration = duration
        cumulativeDistanceMeters = distanceMeters
    }
    #endif

    static func previewIdle() -> OutdoorDashboardStore {
        let store = preview()
        store.stopSpeedSession()
        return store
    }

    private static func dmsComponent(value: Double, positiveLabel: String, negativeLabel: String) -> String {
        let absolute = abs(value)
        let degrees = Int(absolute)
        let minutesDecimal = (absolute - Double(degrees)) * 60
        let minutes = Int(minutesDecimal)
        let seconds = Int((minutesDecimal - Double(minutes)) * 60)
        let label = value >= 0 ? positiveLabel : negativeLabel
        return "\(label) \(degrees)°\(minutes)'\(seconds)\""
    }

    private static func dmsValue(value: Double) -> String {
        let absolute = abs(value)
        let degrees = Int(absolute)
        let minutesDecimal = (absolute - Double(degrees)) * 60
        let minutes = Int(minutesDecimal)
        let seconds = Int((minutesDecimal - Double(minutes)) * 60)
        return "\(degrees)°\(minutes)'\(seconds)\""
    }
}

// MARK: - CLLocationManagerDelegate

extension OutdoorDashboardStore: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let value = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        Task { @MainActor in
            self.heading = value
            // CLHeading 也提供磁力计原始读数（μT），作为补充来源
            if newHeading.x != 0 || newHeading.y != 0 || newHeading.z != 0 {
                self.updateMagneticField(x: newHeading.x, y: newHeading.y, z: newHeading.z)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            self.ingestLocation(location)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            NSLog("OutdoorDashboardStore: \(error.localizedDescription)")
        }
    }
}
