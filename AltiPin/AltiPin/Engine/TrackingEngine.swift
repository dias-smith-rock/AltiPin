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

// MARK: - Public Types

struct TrackPoint: Sendable, Equatable {
    let latitude: Double
    let longitude: Double
    let elevation: Double
    let timestamp: Date
}

@MainActor
protocol TrackingEngineDelegate: AnyObject {
    func trackingEngine(_ engine: TrackingEngine, didAppend point: TrackPoint)
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

    weak var delegate: TrackingEngineDelegate?

    private let locationManager = CLLocationManager()
    private let motionActivityManager = CMMotionActivityManager()
    private let altimeter = CMAltimeter()
    private let pedometer = CMPedometer()
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
    private var lastAcceptedPoint: TrackPoint?

    private var baselineElevation: Double?
    private var altimeterReference: Double?
    private var altimeterRelativeOffset: Double?

    private var pointCountToday = 0
    private var hadSignificantChangeToday = false
    private var dailyStepCount = 0
    private var currentDayKey: String = GPXTrackWriter.dayKey(for: .now)

    private var midnightTimer: Timer?
    private var stationaryCheckTimer: Timer?

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
        stopAltimeter()
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

    private func enterSleeping() {
        phase = .sleeping
        stationarySince = nil
        stopStationaryCheckTimer()
        stopMotionActivityUpdates()
        stopAltimeter()
        pauseHighPrecisionGPS()

        locationManager.allowsBackgroundLocationUpdates = false
        locationManager.stopMonitoringSignificantLocationChanges()
        locationManager.startMonitoringSignificantLocationChanges()

        baselineElevation = nil
        altimeterReference = nil
        altimeterRelativeOffset = nil
        lastAcceptedLocation = nil
        lastAcceptedPoint = nil

        NSLog("TrackingEngine: entered Sleeping")
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

        locationManager.allowsBackgroundLocationUpdates = true
        resumeHighPrecisionGPS()
        startMotionActivityUpdates()
        startAltimeter()

        NSLog("TrackingEngine: entered Tracking")
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

        if Date().timeIntervalSince(stationarySince) >= Config.stationaryTimeout {
            finalizeCurrentTrackIfNeeded()
            enterSleeping()
        }
    }

    // MARK: - Altimeter

    private func startAltimeter() {
        guard CMAltimeter.isRelativeAltitudeAvailable() else { return }

        altimeter.startRelativeAltitudeUpdates(to: locationQueue) { [weak self] data, error in
            guard let data, error == nil else { return }
            let relative = data.relativeAltitude.doubleValue
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.altimeterReference == nil {
                    self.altimeterReference = relative
                }
                self.altimeterRelativeOffset = relative - (self.altimeterReference ?? relative)
            }
        }
    }

    private func stopAltimeter() {
        altimeter.stopRelativeAltitudeUpdates()
        altimeterReference = nil
        altimeterRelativeOffset = nil
    }

    // MARK: - Location Processing

    private func handleLocationUpdates(_ locations: [CLLocation]) {
        guard isStarted else { return }

        if phase == .sleeping {
            handleBackgroundWake()
            return
        }

        guard phase == .tracking else { return }

        for location in locations {
            guard shouldAccept(location) else { continue }
            appendLocation(location)
        }
    }

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
        let point = TrackPoint(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            elevation: elevation,
            timestamp: location.timestamp
        )

        do {
            try gpxWriter.append(point: point)
            pointCountToday += 1
            lastAcceptedLocation = location
            lastAcceptedPoint = point
            delegate?.trackingEngine(self, didAppend: point)
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

    func append(point: TrackPoint) throws {
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
        let fragment = """
            <trkpt lat="\(point.latitude)" lon="\(point.longitude)">
                <ele>\(String(format: "%.1f", point.elevation))</ele>
                <time>\(timeString)</time>
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
        <gpx version="1.1" creator="AltiPin" xmlns="http://www.topografix.com/GPX/1/1">
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
