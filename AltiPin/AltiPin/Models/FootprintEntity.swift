//
//  FootprintEntity.swift
//  AltiPin
//

import CoreLocation
import Foundation
import SwiftData

@Model
final class FootprintEntity {
    @Attribute(.unique) var id: UUID
    var latitude: Double
    var longitude: Double
    var elevation: Double
    var timestamp: Date
    var isIndoor: Bool

    init(
        id: UUID = UUID(),
        latitude: Double,
        longitude: Double,
        elevation: Double,
        timestamp: Date,
        isIndoor: Bool
    ) {
        self.id = id
        self.latitude = latitude
        self.longitude = longitude
        self.elevation = elevation
        self.timestamp = timestamp
        self.isIndoor = isIndoor
    }

    convenience init(from point: FootprintPoint) {
        self.init(
            id: point.id,
            latitude: point.coordinate.latitude,
            longitude: point.coordinate.longitude,
            elevation: point.elevation,
            timestamp: point.timestamp,
            isIndoor: point.isIndoor
        )
    }

    var asFootprintPoint: FootprintPoint {
        FootprintPoint(
            id: id,
            coordinate: .init(latitude: latitude, longitude: longitude),
            elevation: elevation,
            timestamp: timestamp,
            isIndoor: isIndoor
        )
    }
}
