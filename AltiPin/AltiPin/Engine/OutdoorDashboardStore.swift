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
    @Published private(set) var isMonitoring = false

    private let locationManager = CLLocationManager()
    private let altimeter = CMAltimeter()
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
    }

    func stopMonitoring() {
        guard isMonitoring else { return }

        isMonitoring = false
        locationManager.stopUpdatingLocation()
        locationManager.stopUpdatingHeading()
        altimeter.stopRelativeAltitudeUpdates()
        durationTimer?.invalidate()
        durationTimer = nil
    }

    var compassDirectionName: String {
        Self.directionName(for: heading)
    }

    var coordinateDMSString: String {
        Self.formatCoordinateDMS(latitude: latitude, longitude: longitude)
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
}

// MARK: - CLLocationManagerDelegate

extension OutdoorDashboardStore: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let value = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        Task { @MainActor in
            self.heading = value
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
