//
//  HistoryPoint.swift
//  AltiPin
//

import CoreLocation
import Foundation

struct HistoryPoint: Identifiable, Equatable {
    let id: UUID
    let timestamp: Date
    let latitude: Double
    let longitude: Double
    let elevation: Double

    init(
        id: UUID = UUID(),
        timestamp: Date,
        latitude: Double,
        longitude: Double,
        elevation: Double
    ) {
        self.id = id
        self.timestamp = timestamp
        self.latitude = latitude
        self.longitude = longitude
        self.elevation = elevation
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

extension HistoryPoint {
    static var mockPoints: [HistoryPoint] {
        let startDate = Date().addingTimeInterval(-19 * 12)
        let baseLatitude = 22.3678
        let baseLongitude = 114.1817

        return (0..<20).map { index in
            let progress = Double(index) / 19.0
            let wave = sin(progress * .pi * 1.6)
            let latitude = baseLatitude + progress * 0.012 + wave * 0.0015
            let longitude = baseLongitude + progress * 0.009 + cos(progress * .pi * 2) * 0.0012
            let elevation = 64 + progress * 28 + sin(progress * .pi * 3) * 6

            return HistoryPoint(
                timestamp: startDate.addingTimeInterval(Double(index) * 12),
                latitude: latitude,
                longitude: longitude,
                elevation: elevation
            )
        }
    }
}
