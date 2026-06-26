//
//  NavigationEnvironmentController.swift
//  AltiPin
//
//  室内外环境启发式判定：带计数器防抖，室外切回无延迟。
//

import CoreLocation
import CoreMotion
import Foundation

struct NavigationEnvironmentAssessment: Sendable, Equatable {
    let environment: NavigationEnvironment
    let reason: String
}

@MainActor
final class NavigationEnvironmentController {
    private enum Config {
        static let indoorHorizontalThreshold: CLLocationAccuracy = 25.0
        static let outdoorHorizontalThreshold: CLLocationAccuracy = 15.0
        static let outdoorVerticalThreshold: CLLocationAccuracy = 15.0
        static let poorVerticalThreshold: CLLocationAccuracy = 20.0
        static let grayZoneMaxHorizontal: CLLocationAccuracy = 65.0
        static let indoorSpeedThreshold: CLLocationSpeed = 1.3
        static let degradedMotionDuration: TimeInterval = 60
        static let poorVerticalDuration: TimeInterval = 30
        static let indoorFloorConfirmCount = 3
    }

    private(set) var environment: NavigationEnvironment = .outdoor
    private(set) var lastAssessment = NavigationEnvironmentAssessment(
        environment: .outdoor,
        reason: "initial"
    )

    private var indoorFloorSignalCounter = 0
    private var degradedMotionSince: Date?
    private var poorVerticalMotionSince: Date?

    func reset() {
        environment = .outdoor
        indoorFloorSignalCounter = 0
        degradedMotionSince = nil
        poorVerticalMotionSince = nil
        lastAssessment = NavigationEnvironmentAssessment(environment: .outdoor, reason: "reset")
    }

    /// 综合判定（带防抖）。返回值仅在新发生切换时非 nil。
    @discardableResult
    func evaluateEnvironment(
        currentLocation: CLLocation,
        currentPressureHPa: Double,
        motionActivity: CMMotionActivity?
    ) -> NavigationEnvironment? {
        let previous = environment

        if shouldSwitchToOutdoor(currentLocation) {
            indoorFloorSignalCounter = 0
            degradedMotionSince = nil
            poorVerticalMotionSince = nil
            if environment != .outdoor {
                environment = .outdoor
                recordAssessment(
                    location: currentLocation,
                    motionActivity: motionActivity,
                    environment: .outdoor,
                    reason: "goodGPS"
                )
                return .outdoor
            }
            recordAssessment(
                location: currentLocation,
                motionActivity: motionActivity,
                environment: .outdoor,
                reason: "goodGPS"
            )
            return nil
        }

        if environment == .indoor {
            recordAssessment(
                location: currentLocation,
                motionActivity: motionActivity,
                environment: .indoor,
                reason: "latchedIndoor"
            )
            return nil
        }

        let floorSignal = hasIndoorFloorSignal(currentLocation)
        let degradedMotionSignal = hasDegradedHorizontalMotionSignal(
            currentLocation: currentLocation,
            motionActivity: motionActivity,
            requireDuration: true
        )
        let poorVerticalSignal = hasPoorVerticalMotionSignal(
            currentLocation: currentLocation,
            motionActivity: motionActivity,
            requireDuration: true
        )
        let grayZoneSignal = hasGrayZoneMotionSignal(
            currentLocation: currentLocation,
            motionActivity: motionActivity,
            requireDuration: true
        )

        if floorSignal {
            indoorFloorSignalCounter += 1
        } else {
            indoorFloorSignalCounter = 0
        }

        let floorConfirmed = indoorFloorSignalCounter >= Config.indoorFloorConfirmCount
        let shouldEnterIndoor = floorConfirmed || degradedMotionSignal || poorVerticalSignal || grayZoneSignal

        if shouldEnterIndoor {
            indoorFloorSignalCounter = 0
            degradedMotionSince = nil
            poorVerticalMotionSince = nil
            environment = .indoor

            let reason: String
            if floorConfirmed {
                reason = "clFloor"
            } else if poorVerticalSignal {
                reason = "poorVertical"
            } else if grayZoneSignal {
                reason = "grayZone"
            } else {
                reason = "weakHorizontalMotion"
            }

            if previous != .indoor {
                recordAssessment(
                    location: currentLocation,
                    motionActivity: motionActivity,
                    environment: .indoor,
                    reason: reason
                )
                NSLog(
                    "NavigationEnvironment: → indoor " +
                    "(reason=\(reason), pressure=\(String(format: "%.1f", currentPressureHPa)) hPa)"
                )
                return .indoor
            }
        }

        recordAssessment(
            location: currentLocation,
            motionActivity: motionActivity,
            environment: .outdoor,
            reason: pendingIndoorReason(
                floorSignal: floorSignal,
                floorConfirmed: floorConfirmed,
                degradedMotionSignal: degradedMotionSignal,
                poorVerticalSignal: poorVerticalSignal,
                grayZoneSignal: grayZoneSignal,
                location: currentLocation,
                motionActivity: motionActivity
            )
        )
        return nil
    }

    /// 即时快照（无防抖），供海拔 Tab 进入时展示。
    func snapshotEnvironment(
        currentLocation: CLLocation,
        motionActivity: CMMotionActivity?
    ) -> NavigationEnvironmentAssessment {
        if shouldSwitchToOutdoor(currentLocation) {
            return recordAndReturn(
                location: currentLocation,
                motionActivity: motionActivity,
                environment: .outdoor,
                reason: "goodGPS"
            )
        }

        if environment == .indoor {
            return recordAndReturn(
                location: currentLocation,
                motionActivity: motionActivity,
                environment: .indoor,
                reason: "latchedIndoor"
            )
        }

        if hasIndoorFloorSignal(currentLocation) {
            return recordAndReturn(
                location: currentLocation,
                motionActivity: motionActivity,
                environment: .indoor,
                reason: "clFloor"
            )
        }

        if hasPoorVerticalMotionSignal(
            currentLocation: currentLocation,
            motionActivity: motionActivity,
            requireDuration: false
        ) {
            return recordAndReturn(
                location: currentLocation,
                motionActivity: motionActivity,
                environment: .indoor,
                reason: "poorVertical"
            )
        }

        if hasGrayZoneMotionSignal(
            currentLocation: currentLocation,
            motionActivity: motionActivity,
            requireDuration: false
        ) {
            return recordAndReturn(
                location: currentLocation,
                motionActivity: motionActivity,
                environment: .indoor,
                reason: "grayZone"
            )
        }

        if hasDegradedHorizontalMotionSignal(
            currentLocation: currentLocation,
            motionActivity: motionActivity,
            requireDuration: false
        ) {
            return recordAndReturn(
                location: currentLocation,
                motionActivity: motionActivity,
                environment: .indoor,
                reason: "weakHorizontalMotion"
            )
        }

        return recordAndReturn(
            location: currentLocation,
            motionActivity: motionActivity,
            environment: .outdoor,
            reason: "noIndoorSignal"
        )
    }

    func adoptIndoorState() {
        environment = .indoor
        indoorFloorSignalCounter = 0
        degradedMotionSince = nil
        poorVerticalMotionSince = nil
    }

    func adoptOutdoorState() {
        environment = .outdoor
        indoorFloorSignalCounter = 0
        degradedMotionSince = nil
        poorVerticalMotionSince = nil
    }

    // MARK: - Private

    private func shouldSwitchToOutdoor(_ location: CLLocation) -> Bool {
        location.horizontalAccuracy > 0
            && location.horizontalAccuracy < Config.outdoorHorizontalThreshold
            && location.verticalAccuracy > 0
            && location.verticalAccuracy < Config.outdoorVerticalThreshold
    }

    private func hasPoorVerticalAccuracy(_ location: CLLocation) -> Bool {
        location.verticalAccuracy <= 0 || location.verticalAccuracy > Config.poorVerticalThreshold
    }

    private func isGrayZoneHorizontal(_ location: CLLocation) -> Bool {
        location.horizontalAccuracy >= Config.outdoorHorizontalThreshold
            && location.horizontalAccuracy <= Config.grayZoneMaxHorizontal
    }

    private func isSlowIndoorSpeed(_ location: CLLocation) -> Bool {
        let speed = location.speed >= 0 ? location.speed : 0
        return speed < Config.indoorSpeedThreshold
    }

    private func isIndoorMotion(_ motionActivity: CMMotionActivity?) -> Bool {
        guard let motionActivity,
              (motionActivity.walking || motionActivity.stationary),
              motionActivity.confidence != .low else {
            return false
        }
        return true
    }

    private func hasIndoorFloorSignal(_ location: CLLocation) -> Bool {
        location.horizontalAccuracy > Config.indoorHorizontalThreshold
            && location.floor != nil
    }

    private func hasDegradedHorizontalMotionSignal(
        currentLocation: CLLocation,
        motionActivity: CMMotionActivity?,
        requireDuration: Bool
    ) -> Bool {
        guard currentLocation.horizontalAccuracy > Config.indoorHorizontalThreshold else {
            if requireDuration { degradedMotionSince = nil }
            return false
        }
        guard isSlowIndoorSpeed(currentLocation), isIndoorMotion(motionActivity) else {
            if requireDuration { degradedMotionSince = nil }
            return false
        }
        return meetsDuration(
            timer: &degradedMotionSince,
            required: Config.degradedMotionDuration,
            requireDuration: requireDuration
        )
    }

    private func hasPoorVerticalMotionSignal(
        currentLocation: CLLocation,
        motionActivity: CMMotionActivity?,
        requireDuration: Bool
    ) -> Bool {
        guard currentLocation.horizontalAccuracy > 0 else {
            if requireDuration { poorVerticalMotionSince = nil }
            return false
        }
        guard hasPoorVerticalAccuracy(currentLocation) else {
            if requireDuration { poorVerticalMotionSince = nil }
            return false
        }
        guard isSlowIndoorSpeed(currentLocation), isIndoorMotion(motionActivity) else {
            if requireDuration { poorVerticalMotionSince = nil }
            return false
        }
        return meetsDuration(
            timer: &poorVerticalMotionSince,
            required: Config.poorVerticalDuration,
            requireDuration: requireDuration
        )
    }

    private func hasGrayZoneMotionSignal(
        currentLocation: CLLocation,
        motionActivity: CMMotionActivity?,
        requireDuration: Bool
    ) -> Bool {
        guard isGrayZoneHorizontal(currentLocation), hasPoorVerticalAccuracy(currentLocation) else {
            return false
        }
        guard isSlowIndoorSpeed(currentLocation), isIndoorMotion(motionActivity) else {
            return false
        }
        if requireDuration {
            return meetsDuration(
                timer: &poorVerticalMotionSince,
                required: Config.poorVerticalDuration,
                requireDuration: true
            )
        }
        return true
    }

    private func meetsDuration(
        timer: inout Date?,
        required: TimeInterval,
        requireDuration: Bool
    ) -> Bool {
        if !requireDuration {
            return true
        }
        if timer == nil {
            timer = Date()
        }
        guard let timer else { return false }
        return Date().timeIntervalSince(timer) >= required
    }

    private func pendingIndoorReason(
        floorSignal: Bool,
        floorConfirmed: Bool,
        degradedMotionSignal: Bool,
        poorVerticalSignal: Bool,
        grayZoneSignal: Bool,
        location: CLLocation,
        motionActivity: CMMotionActivity?
    ) -> String {
        if floorSignal && !floorConfirmed {
            return "pendingClFloor"
        }
        if degradedMotionSignal || poorVerticalSignal || grayZoneSignal {
            return "pendingTimer"
        }
        if hasPoorVerticalAccuracy(location), !isIndoorMotion(motionActivity) {
            return "poorVerticalNoMotion"
        }
        if hasPoorVerticalAccuracy(location), !isSlowIndoorSpeed(location) {
            return "poorVerticalMoving"
        }
        if isGrayZoneHorizontal(location), hasPoorVerticalAccuracy(location) {
            return "pendingGrayZone"
        }
        return "noIndoorSignal"
    }

    @discardableResult
    private func recordAndReturn(
        location: CLLocation,
        motionActivity: CMMotionActivity?,
        environment: NavigationEnvironment,
        reason: String
    ) -> NavigationEnvironmentAssessment {
        recordAssessment(
            location: location,
            motionActivity: motionActivity,
            environment: environment,
            reason: reason
        )
        return lastAssessment
    }

    private func recordAssessment(
        location: CLLocation,
        motionActivity: CMMotionActivity?,
        environment: NavigationEnvironment,
        reason: String
    ) {
        lastAssessment = NavigationEnvironmentAssessment(environment: environment, reason: reason)
        logAssessment(location: location, motionActivity: motionActivity, assessment: lastAssessment)
    }

    private func logAssessment(
        location: CLLocation,
        motionActivity: CMMotionActivity?,
        assessment: NavigationEnvironmentAssessment
    ) {
        let floor = location.floor.map { String($0.level) } ?? "nil"
        let speed = location.speed >= 0 ? location.speed : 0
        let motion = motionLabel(motionActivity)
        let hText = formatAccuracy(location.horizontalAccuracy)
        let vText = formatAccuracy(location.verticalAccuracy)

        NSLog(
            "[TopoLog Env] h=\(hText) v=\(vText) floor=\(floor) " +
            "speed=\(String(format: "%.1f", speed)) motion=\(motion) " +
            "→ \(assessment.environment.rawValue) (reason: \(assessment.reason))"
        )
    }

    private func formatAccuracy(_ value: Double) -> String {
        value >= 0 ? String(format: "%.1f", value) : "invalid"
    }

    private func motionLabel(_ activity: CMMotionActivity?) -> String {
        guard let activity else { return "unknown" }
        if activity.stationary { return "stationary" }
        if activity.walking { return "walking" }
        if activity.running { return "running" }
        if activity.cycling { return "cycling" }
        if activity.automotive { return "automotive" }
        return "other"
    }
}
