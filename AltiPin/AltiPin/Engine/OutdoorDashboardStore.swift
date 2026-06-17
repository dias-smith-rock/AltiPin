//
//  OutdoorDashboardStore.swift
//  AltiPin
//

import Combine
import CoreLocation
import CoreMotion
import Foundation

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

    @Published private(set) var isSpeedSessionActive = false
    @Published private(set) var speedSessionDuration: TimeInterval = 0
    @Published private(set) var speedSessionDistanceMeters: Double = 0
    @Published private(set) var speedSessionMaxSpeedKmh: Double = 0
    @Published private(set) var speedSessionElevationGainMeters: Double = 0

    var speedSessionAverageSpeedKmh: Double {
        guard speedSessionDuration > 0 else { return 0 }
        let hours = speedSessionDuration / 3600
        guard hours > 0 else { return 0 }
        return (speedSessionDistanceMeters / 1000) / hours
    }

    private let locationManager = CLLocationManager()
    private let altimeter = CMAltimeter()
    private let motionManager = CMMotionManager()
    private let sensorQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.goodcraft.AltiPin.dashboard"
        queue.maxConcurrentOperationCount = 1
        return queue
    }()

    private var gpsBaselineAltitude: Double?
    private var altimeterReference: Double?
    private var lastDistanceSample: CLLocation?
    private var sessionStartDate: Date?
    private var durationTimer: Timer?
    private var lastMagneticFieldUpdateDate: Date?
    private let magneticFieldUpdateInterval: TimeInterval = 0.5

    private var speedSessionStartDate: Date?
    private var speedSessionLastSample: CLLocation?
    private var speedSessionTimer: Timer?

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 3
        locationManager.headingFilter = 1
        locationManager.activityType = .fitness
    }

    func startMonitoring() {
        guard !isMonitoring else { return }

        isMonitoring = true
        sessionStartDate = .now
        sessionDuration = 0
        cumulativeDistanceMeters = 0
        lastDistanceSample = nil
        gpsBaselineAltitude = nil
        altimeterReference = nil

        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
        locationManager.startUpdatingHeading()
        startAltimeter()
        startDurationTimer()
        startDeviceMotion()
        startMagnetometer()
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
        motionManager.stopDeviceMotionUpdates()
        motionManager.stopMagnetometerUpdates()
        durationTimer?.invalidate()
        durationTimer = nil
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

    var currentLocation: CLLocation? {
        guard horizontalAccuracy >= 0 else { return nil }
        return CLLocation(latitude: latitude, longitude: longitude)
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
            }
        }
    }

    private func startDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let start = self.sessionStartDate else { return }
                self.sessionDuration = Date().timeIntervalSince(start)
            }
        }
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
        latitude = location.coordinate.latitude
        longitude = location.coordinate.longitude
        horizontalAccuracy = location.horizontalAccuracy
        verticalAccuracy = location.verticalAccuracy

        if location.speed >= 0 {
            speedKmh = location.speed * 3.6
        }

        if gpsBaselineAltitude == nil, location.verticalAccuracy >= 0, location.verticalAccuracy <= 30 {
            gpsBaselineAltitude = location.altitude
            elevationMeters = location.altitude
        }

        if let last = lastDistanceSample, location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 40 {
            let delta = location.distance(from: last)
            if delta >= 2 {
                cumulativeDistanceMeters += delta
            }
        }

        if location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 40 {
            lastDistanceSample = location
        }

        if isSpeedSessionActive {
            ingestSpeedSessionSample(location)
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
        store.sessionDuration = 24 * 60
        store.cumulativeDistanceMeters = 1200
        store.horizontalAccuracy = 5
        store.verticalAccuracy = 8
        store.magneticFieldX = 22.5
        store.magneticFieldY = -8.3
        store.magneticFieldZ = 41.2
        store.magneticFieldStrength = 47.8
        store.isSpeedSessionActive = true
        store.speedSessionDuration = 129
        store.speedSessionDistanceMeters = 540
        store.speedSessionMaxSpeedKmh = 7.9
        store.speedSessionElevationGainMeters = 12.4
        return store
    }

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
