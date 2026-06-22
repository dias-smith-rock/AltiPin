//
//  BuildingCalibrationStore.swift
//  AltiPin
//
//  楼栋楼层校准持久化：按地理围栏匹配与保存。
//

import CoreLocation
import Foundation
import SwiftData

struct BuildingCalibrationMatch: Sendable {
    let record: BuildingCalibrationEntity
    let distanceMeters: Double
}

@MainActor
final class BuildingCalibrationStore {
    static let defaultMatchRadius: CLLocationDistance = 80

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func findMatch(near location: CLLocation, radius: CLLocationDistance = defaultMatchRadius) -> BuildingCalibrationMatch? {
        guard let records = try? modelContext.fetch(FetchDescriptor<BuildingCalibrationEntity>()) else {
            return nil
        }

        var best: BuildingCalibrationMatch?
        for record in records {
            let center = CLLocation(latitude: record.latitude, longitude: record.longitude)
            let effectiveRadius = min(radius, record.matchRadiusMeters)
            let distance = location.distance(from: center)
            guard distance <= effectiveRadius else { continue }

            if let currentBest = best {
                if distance < currentBest.distanceMeters {
                    best = BuildingCalibrationMatch(record: record, distanceMeters: distance)
                } else if distance == currentBest.distanceMeters,
                          record.lastCalibratedAt > currentBest.record.lastCalibratedAt {
                    best = BuildingCalibrationMatch(record: record, distanceMeters: distance)
                }
            } else {
                best = BuildingCalibrationMatch(record: record, distanceMeters: distance)
            }
        }

        if let best {
            NSLog(
                "BuildingCalibrationStore: matched id=\(best.record.id.uuidString.prefix(8)) " +
                "dist=\(String(format: "%.0f", best.distanceMeters))m baseFloor=\(best.record.calibratedBaseFloor)"
            )
        }
        return best
    }

    @discardableResult
    func saveCalibration(
        location: CLLocation,
        floor: Int,
        pressureHPa: Double,
        label: String? = nil,
        radius: CLLocationDistance = defaultMatchRadius
    ) -> BuildingCalibrationEntity {
        if let existing = findMatch(near: location, radius: radius)?.record {
            existing.calibratedBaseFloor = max(1, floor)
            existing.lastBaselinePressureHPa = pressureHPa
            existing.lastCalibratedAt = .now
            existing.useCount += 1
            if let label, !label.isEmpty {
                existing.optionalLabel = label
            }
            existing.latitude = location.coordinate.latitude
            existing.longitude = location.coordinate.longitude
            try? modelContext.save()
            return existing
        }

        let record = BuildingCalibrationEntity(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            calibratedBaseFloor: max(1, floor),
            lastBaselinePressureHPa: pressureHPa,
            optionalLabel: label?.isEmpty == false ? label : nil,
            matchRadiusMeters: radius
        )
        modelContext.insert(record)
        try? modelContext.save()
        NSLog("BuildingCalibrationStore: saved new record baseFloor=\(floor)")
        return record
    }

    func touch(_ record: BuildingCalibrationEntity, baselinePressureHPa: Double? = nil) {
        if let baselinePressureHPa {
            record.lastBaselinePressureHPa = baselinePressureHPa
        }
        record.lastCalibratedAt = .now
        record.useCount += 1
        try? modelContext.save()
    }
}
