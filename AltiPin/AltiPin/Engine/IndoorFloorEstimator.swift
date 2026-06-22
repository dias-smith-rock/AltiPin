//
//  IndoorFloorEstimator.swift
//  AltiPin
//
//  室内楼层推断：地面校准 baseFloor + 气压相对变化追踪。
//

import Foundation

@MainActor
final class IndoorFloorEstimator {
    private(set) var isActive = false
    private(set) var isCalibrated = false
    private(set) var calibratedBaseFloor: Int?
    private(set) var baselinePressureHPa: Double?
    private(set) var estimatedFloor: Int = 1
    private(set) var lastDeltaFloors: Int = 0

    private static let metersPerFloor = 3.0

    func calibrate(baseFloor: Int, pressureHPa: Double) {
        guard pressureHPa > 0 else { return }
        let floor = max(1, baseFloor)
        calibratedBaseFloor = floor
        baselinePressureHPa = pressureHPa
        estimatedFloor = floor
        lastDeltaFloors = 0
        isCalibrated = true
        isActive = true
        NSLog(
            "IndoorFloorEstimator: calibrated baseFloor=\(floor) " +
            "at \(String(format: "%.1f", pressureHPa)) hPa"
        )
    }

    func deactivate() {
        isActive = false
        isCalibrated = false
        calibratedBaseFloor = nil
        baselinePressureHPa = nil
        estimatedFloor = 1
        lastDeltaFloors = 0
        NSLog("IndoorFloorEstimator: deactivated")
    }

    @discardableResult
    func update(currentPressureHPa: Double) -> Int? {
        guard isActive, isCalibrated, currentPressureHPa > 0,
              let baseline = baselinePressureHPa,
              let baseFloor = calibratedBaseFloor else {
            return nil
        }

        let deltaMeters = Self.altitudeDeltaMeters(from: baseline, to: currentPressureHPa)
        let deltaFloors = Int(round(deltaMeters / Self.metersPerFloor))
        lastDeltaFloors = deltaFloors
        estimatedFloor = max(1, baseFloor + deltaFloors)
        return estimatedFloor
    }

    // MARK: - Barometric altitude delta

    private static func altitudeDeltaMeters(from baselineHPa: Double, to currentHPa: Double) -> Double {
        pressureToAltitudeMeters(currentHPa) - pressureToAltitudeMeters(baselineHPa)
    }

    private static func pressureToAltitudeMeters(_ pressureHPa: Double) -> Double {
        guard pressureHPa > 0 else { return 0 }
        return 44330.0 * (1.0 - pow(pressureHPa / 1013.25, 0.1903))
    }
}
