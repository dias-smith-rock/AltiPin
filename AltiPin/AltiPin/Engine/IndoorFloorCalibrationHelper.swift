//
//  IndoorFloorCalibrationHelper.swift
//  AltiPin
//

import CoreLocation
import Foundation

enum FloorCalibrationSource: String, Sendable {
    case persisted
    case clFloor
    case manual
}

enum FloorCalibrationOutcome: Sendable {
    case calibrated(
        baseFloor: Int,
        baselinePressureHPa: Double?,
        source: FloorCalibrationSource,
        label: String?
    )
    case needsManual
}

enum IndoorFloorCalibrationHelper {
    static func resolve(
        location: CLLocation,
        buildingStore: BuildingCalibrationStore?
    ) -> FloorCalibrationOutcome {
        if let store = buildingStore, let match = store.findMatch(near: location) {
            let storedBaseline = match.record.lastBaselinePressureHPa
            return .calibrated(
                baseFloor: match.record.calibratedBaseFloor,
                baselinePressureHPa: storedBaseline > 0 ? storedBaseline : nil,
                source: .persisted,
                label: match.record.optionalLabel
            )
        }

        if let floor = location.floor?.level {
            return .calibrated(
                baseFloor: max(1, floor),
                baselinePressureHPa: nil,
                source: .clFloor,
                label: nil
            )
        }

        return .needsManual
    }
}
