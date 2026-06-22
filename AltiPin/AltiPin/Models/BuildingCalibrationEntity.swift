//
//  BuildingCalibrationEntity.swift
//  AltiPin
//

import Foundation
import SwiftData

@Model
final class BuildingCalibrationEntity {
    @Attribute(.unique) var id: UUID
    var latitude: Double
    var longitude: Double
    var matchRadiusMeters: Double
    var calibratedBaseFloor: Int
    var lastBaselinePressureHPa: Double
    var optionalLabel: String?
    var lastCalibratedAt: Date
    var useCount: Int

    init(
        latitude: Double,
        longitude: Double,
        calibratedBaseFloor: Int,
        lastBaselinePressureHPa: Double,
        optionalLabel: String? = nil,
        matchRadiusMeters: Double = 80,
        lastCalibratedAt: Date = .now,
        useCount: Int = 1
    ) {
        self.id = UUID()
        self.latitude = latitude
        self.longitude = longitude
        self.matchRadiusMeters = matchRadiusMeters
        self.calibratedBaseFloor = calibratedBaseFloor
        self.lastBaselinePressureHPa = lastBaselinePressureHPa
        self.optionalLabel = optionalLabel
        self.lastCalibratedAt = lastCalibratedAt
        self.useCount = useCount
    }
}
