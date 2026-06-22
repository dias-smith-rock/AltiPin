//
//  TrackingEngine.swift
//  AltiPin
//
//  无感单人自动化记录引擎：基站唤醒 + 运动过滤 + 动态高精度打点
//

import CoreLocation
import CoreMotion
import Foundation
import Observation
import SwiftData
import UIKit

// MARK: - Public Types

@MainActor
protocol TrackingEngineDelegate: AnyObject {
    func trackingEngine(_ engine: TrackingEngine, didAppend point: HistoryPoint)
    func trackingEngine(_ engine: TrackingEngine, didFinalizeDay fileName: String, pointCount: Int)
}

// MARK: - TrackingEngine

@MainActor
@Observable
final class TrackingEngine: NSObject {
    static let shared = TrackingEngine()

    enum Phase: String, Sendable {
        case sleeping
        case evaluating
        case tracking
        case stationaryWatch
    }

    private(set) var phase: Phase = .sleeping
    private(set) var navigationEnvironment: NavigationEnvironment = .outdoor
    private(set) var estimatedIndoorFloor: Int?

    weak var delegate: TrackingEngineDelegate?

    private let locationManager = CLLocationManager()
    private let motionActivityManager = CMMotionActivityManager()
    private let altimeter = CMAltimeter()
    private let pedometer = CMPedometer()
    private let navigationEnvironmentController = NavigationEnvironmentController()
    private let indoorFloorEstimator = IndoorFloorEstimator()
    private var buildingCalibrationStore: BuildingCalibrationStore?
    private var lastKnownLocation: CLLocation?
    private let locationQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.goodcraft.AltiPin.location"
        queue.maxConcurrentOperationCount = 1
        return queue
    }()

    private var backgroundSession: CLBackgroundActivitySession?
    private let gpxWriter = GPXTrackWriter()

    private var isConfigured = false
    private var isStarted = false
    private var stationarySince: Date?
    private var lastAcceptedLocation: CLLocation?
    private var lastAcceptedPoint: HistoryPoint?

    private var baselineElevation: Double?
    private var altimeterReference: Double?
    private var altimeterRelativeOffset: Double?
    private var sleepAltimeterRelativeBaseline: Double?
    private var lastSleepAltimeterSampleDate: Date?
    private var altitudeWakeMonitor = AltitudeWakeMonitor()
    private var stationaryAltitudeMonitor = StationaryAltitudeMonitor()
    private var lastSignificantHorizontalMoveDate: Date?
    private var isSleepAltimeterActive = false
    private var isFullAltimeterActive = false

    private var pointCountToday = 0
    private var hadSignificantChangeToday = false
    private var dailyStepCount = 0
    private var currentDayKey: String = GPXTrackWriter.dayKey(for: .now)

    private var midnightTimer: Timer?
    private var stationaryCheckTimer: Timer?

    private var lastPressureHPa: Double = 0
    private var latestMotionActivity: CMMotionActivity?

    private override init() {
        super.init()
    }

    // MARK: - Lifecycle

    func configure() {
        guard !isConfigured else { return }
        isConfigured = true

        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = Config.distanceFilter
        locationManager.activityType = .fitness
        locationManager.pausesLocationUpdatesAutomatically = true
        locationManager.showsBackgroundLocationIndicator = true

        scheduleMidnightRollover()
        refreshDailyStepCount()
    }

    func configureBuildingCalibration(modelContext: ModelContext) {
        buildingCalibrationStore = BuildingCalibrationStore(modelContext: modelContext)
    }

    func requestPermissions() {
        let status = locationManager.authorizationStatus
        switch status {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            locationManager.requestAlwaysAuthorization()
        default:
            break
        }
    }

    func start() {
        if !isConfigured {
            configure()
        }
        guard CLLocationManager.significantLocationChangeMonitoringAvailable() else {
            NSLog("TrackingEngine: significant location change monitoring unavailable")
            return
        }

        isStarted = true
        enterSleeping()
        refreshDailyStepCount()
    }

    func stop() {
        isStarted = false
        stopStationaryCheckTimer()
        stopMotionActivityUpdates()
        stopSleepMotionMonitoring()
        stopFullAltimeter()
        stopSleepAltimeter()
        pauseHighPrecisionGPS()
        locationManager.stopMonitoringSignificantLocationChanges()
        finalizeCurrentTrackIfNeeded()
        phase = .sleeping
    }

    func handleBackgroundWake() {
        guard isStarted else {
            start()
            return
        }

        hadSignificantChangeToday = true

        switch phase {
        case .sleeping:
            enterEvaluating()
        case .stationaryWatch:
            enterEvaluating()
        case .evaluating, .tracking:
            break
        }
    }

    // MARK: - State Machine

    private var canEnableBackgroundLocationUpdates: Bool {
        guard locationManager.authorizationStatus == .authorizedAlways else { return false }
        guard let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] else {
            return false
        }
        return modes.contains("location")
    }

    private func enterSleeping() {
        phase = .sleeping
        stationarySince = nil
        stopStationaryCheckTimer()
        stopFullAltimeter()
        pauseHighPrecisionGPS()
        startSleepAltimeter()
        startSleepMotionMonitoring()

        locationManager.allowsBackgroundLocationUpdates = false
        locationManager.stopMonitoringSignificantLocationChanges()
        locationManager.startMonitoringSignificantLocationChanges()

        baselineElevation = nil
        altimeterReference = nil
        altimeterRelativeOffset = nil
        sleepAltimeterRelativeBaseline = nil
        lastSleepAltimeterSampleDate = nil
        altitudeWakeMonitor.reset()
        stationaryAltitudeMonitor.reset()
        lastSignificantHorizontalMoveDate = nil
        lastAcceptedLocation = nil
        lastAcceptedPoint = nil
        lastPressureHPa = 0
        latestMotionActivity = nil
        navigationEnvironmentController.reset()
        indoorFloorEstimator.deactivate()
        navigationEnvironment = .outdoor
        estimatedIndoorFloor = nil

        NSLog("TrackingEngine: entered Sleeping (significant-change + sleep altimeter active)")
    }

    private func enterEvaluating() {
        guard isStarted else { return }
        phase = .evaluating
        hadSignificantChangeToday = true
        NSLog("TrackingEngine: entered Evaluating")

        guard CMMotionActivityManager.isActivityAvailable() else {
            enterSleeping()
            return
        }

        let from = Date().addingTimeInterval(-Config.motionLookback)
        motionActivityManager.queryActivityStarting(from: from, to: .now, to: locationQueue) { [weak self] activities, error in
            Task { @MainActor [weak self] in
                guard let self, self.phase == .evaluating else { return }

                if let error {
                    NSLog("TrackingEngine: motion query failed: \(error.localizedDescription)")
                    self.enterSleeping()
                    return
                }

                let qualifies = (activities ?? []).contains { activity in
                    Self.isQualifyingMotion(activity)
                }

                if qualifies {
                    self.enterTracking()
                } else {
                    self.enterSleeping()
                }
            }
        }
    }

    private func enterTracking() {
        guard isStarted else { return }
        phase = .tracking
        stationarySince = nil
        stopStationaryCheckTimer()

        stopSleepAltimeter()
        stopSleepMotionMonitoring()

        if canEnableBackgroundLocationUpdates {
            locationManager.allowsBackgroundLocationUpdates = true
        } else {
            locationManager.allowsBackgroundLocationUpdates = false
            NSLog(
                "TrackingEngine: background location disabled " +
                "(requires Always authorization and UIBackgroundModes location)"
            )
        }
        resumeHighPrecisionGPS()
        startMotionActivityUpdates()
        startFullAltimeter()
        altitudeWakeMonitor.reset()
        stationaryAltitudeMonitor.reset()
        navigationEnvironmentController.reset()
        indoorFloorEstimator.deactivate()
        navigationEnvironment = .outdoor
        estimatedIndoorFloor = nil
        applyOutdoorLocationConfiguration()

        NSLog("TrackingEngine: entered Tracking (altitude-driven high precision)")
    }

    private func enterStationaryWatch() {
        guard phase == .tracking else { return }
        phase = .stationaryWatch
        pauseHighPrecisionGPS()
        startStationaryCheckTimer()
        NSLog("TrackingEngine: entered StationaryWatch")
    }

    // MARK: - GPS Control

    private func resumeHighPrecisionGPS() {
        backgroundSession?.invalidate()
        backgroundSession = CLBackgroundActivitySession()
        locationManager.startUpdatingLocation()
    }

    private func pauseHighPrecisionGPS() {
        locationManager.stopUpdatingLocation()
        backgroundSession?.invalidate()
        backgroundSession = nil
    }

    // MARK: - Motion Activity

    private func startMotionActivityUpdates() {
        guard CMMotionActivityManager.isActivityAvailable() else { return }

        motionActivityManager.startActivityUpdates(to: locationQueue) { [weak self] activity in
            guard let activity else { return }
            Task { @MainActor [weak self] in
                self?.handleMotionActivity(activity)
            }
        }
    }

    private func stopMotionActivityUpdates() {
        motionActivityManager.stopActivityUpdates()
    }

    private func handleMotionActivity(_ activity: CMMotionActivity) {
        guard isStarted else { return }
        guard phase == .tracking || phase == .stationaryWatch else { return }

        latestMotionActivity = activity

        if Self.isQualifyingMotion(activity) {
            stationarySince = nil
            if phase == .stationaryWatch {
                enterTracking()
            }
            return
        }

        if activity.stationary, activity.confidence != .low {
            if stationarySince == nil {
                stationarySince = activity.startDate
            }
            if phase == .tracking {
                enterStationaryWatch()
            }
            checkStationaryTimeout()
        }
    }

    private static func isQualifyingMotion(_ activity: CMMotionActivity) -> Bool {
        (activity.walking || activity.running || activity.cycling) && activity.confidence != .low
    }

    // MARK: - Stationary Timeout

    private func startStationaryCheckTimer() {
        stopStationaryCheckTimer()
        stationaryCheckTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkStationaryTimeout()
            }
        }
    }

    private func stopStationaryCheckTimer() {
        stationaryCheckTimer?.invalidate()
        stationaryCheckTimer = nil
    }

    private func checkStationaryTimeout() {
        guard let stationarySince else { return }
        guard phase == .stationaryWatch || phase == .tracking else { return }

        let elapsed = Date().timeIntervalSince(stationarySince)
        guard elapsed >= Config.stationaryTimeout else { return }

        let altitudeStable = stationaryAltitudeMonitor.isAltitudeStable
        let horizontallyStill = isHorizontallyStationary

        if altitudeStable && horizontallyStill {
            finalizeCurrentTrackIfNeeded()
            enterSleeping()
            NSLog(
                "TrackingEngine: sleep — stationary \(Int(elapsed))s, " +
                "altitude Δ=\(String(format: "%.2f", stationaryAltitudeMonitor.peakToPeakMeters))m"
            )
        }
    }

    private var isHorizontallyStationary: Bool {
        guard let lastSignificantHorizontalMoveDate else { return true }
        return Date().timeIntervalSince(lastSignificantHorizontalMoveDate) >= Config.stationaryTimeout
    }

    // MARK: - Altimeter

    private func startSleepAltimeter() {
        guard CMAltimeter.isRelativeAltitudeAvailable(), !isSleepAltimeterActive else { return }
        isSleepAltimeterActive = true
        sleepAltimeterRelativeBaseline = nil
        lastSleepAltimeterSampleDate = nil

        altimeter.startRelativeAltitudeUpdates(to: locationQueue) { [weak self] data, error in
            guard let data, error == nil else { return }
            let relative = data.relativeAltitude.doubleValue
            let pressureHPa = data.pressure.doubleValue * 10
            Task { @MainActor [weak self] in
                self?.handleSleepAltimeterSample(relativeMeters: relative, pressureHPa: pressureHPa)
            }
        }
    }

    private func stopSleepAltimeter() {
        guard isSleepAltimeterActive else { return }
        isSleepAltimeterActive = false
        if !isFullAltimeterActive {
            altimeter.stopRelativeAltitudeUpdates()
        }
        sleepAltimeterRelativeBaseline = nil
        lastSleepAltimeterSampleDate = nil
    }

    private func handleSleepAltimeterSample(relativeMeters: Double, pressureHPa: Double) {
        let now = Date()
        if let lastSample = lastSleepAltimeterSampleDate,
           now.timeIntervalSince(lastSample) < Config.sleepAltimeterInterval {
            return
        }
        lastSleepAltimeterSampleDate = now
        lastPressureHPa = pressureHPa

        if sleepAltimeterRelativeBaseline == nil {
            sleepAltimeterRelativeBaseline = relativeMeters
        }

        let deltaFromBaseline = relativeMeters - (sleepAltimeterRelativeBaseline ?? relativeMeters)

        if phase == .sleeping, altitudeWakeMonitor.ingest(relativeMeters: deltaFromBaseline, date: now) {
            hadSignificantChangeToday = true
            NSLog("TrackingEngine: altitude wake — Δh ≥ \(Config.altitudeWakeThresholdMeters)m / \(Int(Config.altitudeWakeWindow))s")
            enterTracking()
            return
        }

        if phase == .tracking || phase == .stationaryWatch {
            stationaryAltitudeMonitor.ingest(relativeMeters: deltaFromBaseline, date: now)
        }
    }

    private func startFullAltimeter() {
        guard CMAltimeter.isRelativeAltitudeAvailable(), !isFullAltimeterActive else { return }
        isFullAltimeterActive = true

        altimeter.startRelativeAltitudeUpdates(to: locationQueue) { [weak self] data, error in
            guard let data, error == nil else { return }
            let relative = data.relativeAltitude.doubleValue
            let pressureHPa = data.pressure.doubleValue * 10
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.lastPressureHPa = pressureHPa
                if self.altimeterReference == nil {
                    self.altimeterReference = relative
                }
                self.altimeterRelativeOffset = relative - (self.altimeterReference ?? relative)

                let deltaFromReference = self.altimeterRelativeOffset ?? 0
                self.stationaryAltitudeMonitor.ingest(relativeMeters: deltaFromReference)

                if self.navigationEnvironment == .indoor {
                    self.beginIndoorFloorCalibrationIfNeeded(with: self.lastKnownLocation)
                    self.updateIndoorFloorEstimateIfNeeded()
                }

                if let location = self.lastKnownLocation,
                   self.phase == .tracking || self.phase == .stationaryWatch {
                    self.ingestFootprintIfNeeded(location: location)
                }
            }
        }
    }

    private func stopFullAltimeter() {
        guard isFullAltimeterActive else { return }
        isFullAltimeterActive = false
        altimeter.stopRelativeAltitudeUpdates()
        altimeterReference = nil
        altimeterRelativeOffset = nil
    }

    private func startSleepMotionMonitoring() {
        guard CMMotionActivityManager.isActivityAvailable() else { return }

        motionActivityManager.startActivityUpdates(to: locationQueue) { [weak self] activity in
            guard let activity else { return }
            Task { @MainActor [weak self] in
                self?.handleSleepMotionActivity(activity)
            }
        }
    }

    private func stopSleepMotionMonitoring() {
        motionActivityManager.stopActivityUpdates()
    }

    private func handleSleepMotionActivity(_ activity: CMMotionActivity) {
        guard phase == .sleeping else { return }
        guard Self.isQualifyingMotion(activity) else { return }

        hadSignificantChangeToday = true
        NSLog("TrackingEngine: motion wake — \(Self.motionLabel(activity))")
        enterTracking()
    }

    private static func motionLabel(_ activity: CMMotionActivity) -> String {
        if activity.running { return "running" }
        if activity.cycling { return "cycling" }
        if activity.walking { return "walking" }
        return "motion"
    }

    // MARK: - Location Processing

    private func handleLocationUpdates(_ locations: [CLLocation]) {
        guard isStarted else { return }

        if phase == .sleeping {
            handleBackgroundWake()
            return
        }

        guard phase == .tracking || phase == .stationaryWatch else { return }
        guard let latestLocation = locations.last else { return }
        lastKnownLocation = latestLocation

        evaluateNavigationEnvironment(with: latestLocation)
        updateHorizontalActivity(latestLocation)
        sampleChartPointIfNeeded(location: latestLocation)
        ingestFootprintIfNeeded(location: latestLocation)

        guard phase == .tracking, navigationEnvironment == .outdoor else { return }

        for location in locations {
            guard shouldAccept(location) else { continue }
            appendLocation(location)
        }
    }

    private func updateHorizontalActivity(_ location: CLLocation) {
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= Config.maxHorizontalAccuracy else {
            return
        }

        if let last = lastAcceptedLocation {
            let distance = location.distance(from: last)
            if distance >= Config.significantHorizontalMove {
                lastSignificantHorizontalMoveDate = location.timestamp
                hadSignificantChangeToday = true
            }
        } else {
            lastSignificantHorizontalMoveDate = location.timestamp
        }
    }

    private func sampleChartPointIfNeeded(location: CLLocation) {
        guard phase == .tracking || phase == .stationaryWatch else { return }

        let elevation = fusedElevation(for: location)
        RecentHistoryBuffer.shared.appendIfNeeded(
            timestamp: location.timestamp,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            elevation: elevation,
            isIndoor: navigationEnvironment == .indoor
        )
    }

    private func ingestFootprintIfNeeded(location: CLLocation) {
        guard phase == .tracking || phase == .stationaryWatch else { return }

        let elevation = fusedElevation(for: location)
        FootprintTrackingEngine.shared.ingest(
            location: location,
            elevation: elevation,
            isIndoor: navigationEnvironment == .indoor,
            motionActivity: latestMotionActivity
        )
    }

    // MARK: - Navigation Environment

    private func evaluateNavigationEnvironment(with location: CLLocation) {
        if NavigationEnvironmentOverrideCenter.isManual {
            let target = NavigationEnvironmentOverrideCenter.manualEnvironment ?? .outdoor
            if navigationEnvironment != target {
                if target == .indoor {
                    enterIndoorNavigationMode(triggerHaptic: false)
                } else {
                    enterOutdoorNavigationMode()
                }
            } else if navigationEnvironment == .indoor {
                beginIndoorFloorCalibrationIfNeeded(with: location)
                updateIndoorFloorEstimateIfNeeded()
            }
            return
        }

        if let transition = navigationEnvironmentController.evaluateEnvironment(
            currentLocation: location,
            currentPressureHPa: lastPressureHPa,
            motionActivity: latestMotionActivity
        ) {
            switch transition {
            case .indoor:
                enterIndoorNavigationMode(triggerHaptic: true)
            case .outdoor:
                enterOutdoorNavigationMode()
            }
        } else if navigationEnvironment == .indoor {
            beginIndoorFloorCalibrationIfNeeded(with: location)
            updateIndoorFloorEstimateIfNeeded()
        }
    }

    private func enterIndoorNavigationMode(triggerHaptic: Bool) {
        guard navigationEnvironment != .indoor else {
            beginIndoorFloorCalibrationIfNeeded(with: lastKnownLocation)
            updateIndoorFloorEstimateIfNeeded()
            return
        }

        navigationEnvironment = .indoor
        navigationEnvironmentController.adoptIndoorState()
        indoorFloorEstimator.deactivate()
        estimatedIndoorFloor = nil
        beginIndoorFloorCalibrationIfNeeded(with: lastKnownLocation)
        updateIndoorFloorEstimateIfNeeded()
        if triggerHaptic {
            triggerIndoorTransitionHaptic()
        }
        applyIndoorLocationConfiguration()
        NSLog("TrackingEngine: navigation → indoor (floor calibration attempted)")
    }

    private func enterOutdoorNavigationMode() {
        guard navigationEnvironment != .outdoor else { return }

        navigationEnvironment = .outdoor
        estimatedIndoorFloor = nil
        indoorFloorEstimator.deactivate()
        navigationEnvironmentController.adoptOutdoorState()
        applyOutdoorLocationConfiguration()
        if phase == .tracking {
            resumeHighPrecisionGPS()
        }
        NSLog("TrackingEngine: navigation → outdoor (high-precision tracking restored)")
    }

    private func beginIndoorFloorCalibrationIfNeeded(with location: CLLocation?) {
        guard navigationEnvironment == .indoor else { return }
        guard lastPressureHPa > 0 else { return }
        guard !indoorFloorEstimator.isCalibrated else { return }

        guard let location else {
            NSLog("TrackingEngine: indoor calibration deferred (no location)")
            return
        }

        switch IndoorFloorCalibrationHelper.resolve(
            location: location,
            buildingStore: buildingCalibrationStore
        ) {
        case let .calibrated(baseFloor, source, _):
            indoorFloorEstimator.calibrate(baseFloor: baseFloor, pressureHPa: lastPressureHPa)
            if source == .persisted, let record = buildingCalibrationStore?.findMatch(near: location)?.record {
                buildingCalibrationStore?.touch(record, baselinePressureHPa: lastPressureHPa)
            } else if source == .clFloor {
                buildingCalibrationStore?.saveCalibration(
                    location: location,
                    floor: baseFloor,
                    pressureHPa: lastPressureHPa
                )
            }
            NSLog("TrackingEngine: floor calibrated base=\(baseFloor) source=\(source.rawValue)")
        case .needsManual:
            NSLog("TrackingEngine: indoor floor calibration deferred (awaiting manual input)")
        }
    }

    private func updateIndoorFloorEstimateIfNeeded() {
        guard navigationEnvironment == .indoor, lastPressureHPa > 0 else { return }
        guard indoorFloorEstimator.isCalibrated else {
            estimatedIndoorFloor = nil
            return
        }
        estimatedIndoorFloor = indoorFloorEstimator.update(currentPressureHPa: lastPressureHPa)
            ?? indoorFloorEstimator.estimatedFloor
    }

    private func applyIndoorLocationConfiguration() {
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager.distanceFilter = Config.indoorDistanceFilter
    }

    private func applyOutdoorLocationConfiguration() {
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = Config.distanceFilter
    }

    private func triggerIndoorTransitionHaptic() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred()
    }

    // MARK: - GPX Recording

    private func shouldAccept(_ location: CLLocation) -> Bool {
        guard location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= Config.maxHorizontalAccuracy else {
            return false
        }

        if location.verticalAccuracy >= 0,
           location.verticalAccuracy > Config.maxVerticalAccuracy {
            return false
        }

        if let last = lastAcceptedLocation {
            let interval = location.timestamp.timeIntervalSince(last.timestamp)
            let distance = location.distance(from: last)
            if distance < Config.minPointDistance, interval < Config.minPointInterval {
                return false
            }
        }

        return true
    }

    private func appendLocation(_ location: CLLocation) {
        rolloverDayIfNeeded()

        let elevation = fusedElevation(for: location)
        let previousElevation = lastAcceptedPoint?.elevation ?? elevation
        let historyPoint = HistoryPoint(
            timestamp: location.timestamp,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            elevation: elevation,
            elevationDelta: elevation - previousElevation,
            isIndoor: navigationEnvironment == .indoor
        )

        do {
            try gpxWriter.append(point: historyPoint)
            pointCountToday += 1
            lastAcceptedLocation = location
            lastAcceptedPoint = historyPoint
            RecentHistoryBuffer.shared.ingestRecordedPoint(historyPoint)
            delegate?.trackingEngine(self, didAppend: historyPoint)
        } catch {
            NSLog("TrackingEngine: GPX write failed: \(error.localizedDescription)")
        }
    }

    private func fusedElevation(for location: CLLocation) -> Double {
        if baselineElevation == nil {
            baselineElevation = location.altitude
        }

        guard let baselineElevation,
              let altimeterRelativeOffset,
              CMAltimeter.isRelativeAltitudeAvailable() else {
            return location.altitude
        }

        return baselineElevation + altimeterRelativeOffset
    }

    // MARK: - Day Rollover

    private func scheduleMidnightRollover() {
        midnightTimer?.invalidate()

        let calendar = Calendar.current
        let startOfTomorrow = calendar.startOfDay(for: .now).addingTimeInterval(86_400)
        let interval = startOfTomorrow.timeIntervalSinceNow

        midnightTimer = Timer.scheduledTimer(withTimeInterval: max(interval, 1), repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.performMidnightRollover()
                self?.scheduleMidnightRollover()
            }
        }
    }

    private func rolloverDayIfNeeded() {
        let todayKey = GPXTrackWriter.dayKey(for: .now)
        guard todayKey != currentDayKey else { return }
        performMidnightRollover()
    }

    private func performMidnightRollover() {
        finalizeCurrentTrackIfNeeded()
        resetDailyCounters()
        currentDayKey = GPXTrackWriter.dayKey(for: .now)
        gpxWriter.resetForNewDay()
        refreshDailyStepCount()
    }

    private func resetDailyCounters() {
        pointCountToday = 0
        hadSignificantChangeToday = false
        dailyStepCount = 0
        lastAcceptedLocation = nil
        lastAcceptedPoint = nil
        baselineElevation = nil
    }

    private func finalizeCurrentTrackIfNeeded() {
        let result = gpxWriter.finalize()

        refreshDailyStepCount()

        let shouldDiscard = result.pointCount == 0
            || (dailyStepCount < Config.minDailySteps && !hadSignificantChangeToday)

        if !shouldDiscard {
            delegate?.trackingEngine(self, didFinalizeDay: result.fileName, pointCount: result.pointCount)
            NSLog("TrackingEngine: finalized \(result.fileName) with \(result.pointCount) points")
        } else {
            gpxWriter.deleteCurrentFileIfExists()
            NSLog("TrackingEngine: discarded track \(result.fileName) — insufficient activity")
        }
    }

    // MARK: - Pedometer

    private func refreshDailyStepCount() {
        guard CMPedometer.isStepCountingAvailable() else { return }

        let startOfDay = Calendar.current.startOfDay(for: .now)
        pedometer.queryPedometerData(from: startOfDay, to: .now) { [weak self] data, _ in
            Task { @MainActor [weak self] in
                self?.dailyStepCount = data?.numberOfSteps.intValue ?? 0
            }
        }
    }

    // MARK: - Authorization

    private func handleAuthorizationChange(_ status: CLAuthorizationStatus) {
        switch status {
        case .authorizedWhenInUse:
            locationManager.requestAlwaysAuthorization()
        case .authorizedAlways:
            if isStarted, phase == .sleeping {
                locationManager.startMonitoringSignificantLocationChanges()
            }
        case .denied, .restricted:
            stop()
        default:
            break
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension TrackingEngine: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            self.handleLocationUpdates(locations)
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.handleAuthorizationChange(status)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            NSLog("TrackingEngine: location error — \(error.localizedDescription)")
        }
    }
}

// MARK: - GPXTrackWriter

private enum Config {
    static let motionLookback: TimeInterval = 300
    static let stationaryTimeout: TimeInterval = 600
    static let minDailySteps = 50
    static let distanceFilter: CLLocationDistance = 8
    static let maxHorizontalAccuracy: CLLocationAccuracy = 65
    static let maxVerticalAccuracy: CLLocationAccuracy = 30
    static let minPointDistance: CLLocationDistance = 3
    static let minPointInterval: TimeInterval = 10
    static let indoorDistanceFilter: CLLocationDistance = 20
    static let altitudeWakeWindow: TimeInterval = 30
    static let altitudeWakeThresholdMeters: Double = 2.0
    static let sleepAltimeterInterval: TimeInterval = 5
    static let stationaryAltitudeVariation: Double = 0.5
    static let significantHorizontalMove: CLLocationDistance = 15
}

private final class GPXTrackWriter: @unchecked Sendable {
    struct FinalizeResult {
        let fileName: String
        let pointCount: Int
    }

    private let fileManager = FileManager.default
    private let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private var fileHandle: FileHandle?
    private var currentFileName: String?
    private var currentFileURL: URL?
    private var pointCount = 0
    private var isHeaderWritten = false
    private let writeLock = NSLock()

    static func dayKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyyMMdd"
        return formatter.string(from: date)
    }

    private var tracksDirectory: URL {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("Tracks", isDirectory: true)
    }

    func resetForNewDay() {
        writeLock.lock()
        defer { writeLock.unlock() }

        closeFileHandle()
        currentFileName = nil
        currentFileURL = nil
        pointCount = 0
        isHeaderWritten = false
    }

    func append(point: HistoryPoint) throws {
        writeLock.lock()
        defer { writeLock.unlock() }

        if currentFileName == nil {
            currentFileName = Self.dayKey(for: point.timestamp) + ".gpx"
        }

        if !isHeaderWritten {
            try createFileIfNeeded(for: point.timestamp)
            try writeHeader(trackDate: point.timestamp)
            isHeaderWritten = true
        }

        let timeString = isoFormatter.string(from: point.timestamp)
        let indoorValue = point.isIndoor ? "true" : "false"
        let fragment = """
            <trkpt lat="\(point.latitude)" lon="\(point.longitude)">
                <ele>\(String(format: "%.1f", point.elevation))</ele>
                <time>\(timeString)</time>
                <extensions>
                    <altipin:delta>\(String(format: "%.2f", point.elevationDelta))</altipin:delta>
                    <altipin:indoor>\(indoorValue)</altipin:indoor>
                </extensions>
            </trkpt>

        """

        guard let data = fragment.data(using: .utf8) else { return }
        try fileHandle?.write(contentsOf: data)
        pointCount += 1
    }

    func finalize() -> FinalizeResult {
        writeLock.lock()
        defer { writeLock.unlock() }

        let fileName = currentFileName ?? Self.dayKey(for: .now) + ".gpx"
        let count = pointCount

        if isHeaderWritten, let fileHandle {
            let footer = """
                </trkseg>
            </trk>
        </gpx>
        """
            if let data = footer.data(using: .utf8) {
                try? fileHandle.write(contentsOf: data)
            }
        }

        closeFileHandle()
        isHeaderWritten = false
        pointCount = 0

        return FinalizeResult(fileName: fileName, pointCount: count)
    }

    func deleteCurrentFileIfExists() {
        writeLock.lock()
        defer { writeLock.unlock() }

        if let url = currentFileURL {
            try? fileManager.removeItem(at: url)
        }

        currentFileName = nil
        currentFileURL = nil
        isHeaderWritten = false
        pointCount = 0
    }

    // MARK: - Private

    private func createFileIfNeeded(for date: Date) throws {
        let directory = tracksDirectory
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        let fileName = currentFileName ?? Self.dayKey(for: date) + ".gpx"
        let fileURL = directory.appendingPathComponent(fileName)

        if !fileManager.fileExists(atPath: fileURL.path) {
            fileManager.createFile(atPath: fileURL.path, contents: nil)
        }

        currentFileURL = fileURL
        fileHandle = try FileHandle(forWritingTo: fileURL)
        try fileHandle?.seekToEnd()
    }

    private func writeHeader(trackDate: Date) throws {
        let dayTitle = Self.displayDate(for: trackDate)
        let metadataTime = isoFormatter.string(from: trackDate)
        let header = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="AltiPin" xmlns="http://www.topografix.com/GPX/1/1" xmlns:altipin="https://altipin.app/gpx/1">
            <metadata>
                <time>\(metadataTime)</time>
            </metadata>
            <trk>
                <name>\(dayTitle) 自动记录</name>
                <trkseg>

        """

        guard let data = header.data(using: .utf8) else { return }
        try fileHandle?.write(contentsOf: data)
    }

    private static func displayDate(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale.current
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func closeFileHandle() {
        try? fileHandle?.close()
        fileHandle = nil
    }
}
