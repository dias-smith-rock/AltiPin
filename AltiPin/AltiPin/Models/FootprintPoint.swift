//
//  FootprintPoint.swift
//  AltiPin
//
//  脚印驱动型海拔采集的标准 Payload。
//

import CoreLocation
import Foundation

struct FootprintPoint: Identifiable, Equatable {
    let id: UUID
    let coordinate: CLLocationCoordinate2D
    let elevation: Double
    let timestamp: Date
    let isIndoor: Bool

    init(
        id: UUID = UUID(),
        coordinate: CLLocationCoordinate2D,
        elevation: Double,
        timestamp: Date,
        isIndoor: Bool
    ) {
        self.id = id
        self.coordinate = coordinate
        self.elevation = elevation
        self.timestamp = timestamp
        self.isIndoor = isIndoor
    }

    static func == (lhs: FootprintPoint, rhs: FootprintPoint) -> Bool {
        lhs.id == rhs.id
    }
}

enum FootprintConfig {
    static let maxFootprints = 20
    static let verticalThresholdMeters = 3.0
    static let horizontalThresholdMeters = 50.0
    static let timeCapSeconds: TimeInterval = 300
}

extension Array where Element == FootprintPoint {
    /// 固定 20 槽窗口内的 X 轴槽位（0-based），部分填充时从右侧「当前」向左生长。
    func chartSlotIndex(for footprint: FootprintPoint) -> Int? {
        guard let index = firstIndex(where: { $0.id == footprint.id }) else { return nil }
        return (FootprintConfig.maxFootprints - count) + index
    }
}

extension FootprintPoint {
    static var mockFootprints: [FootprintPoint] {
        let now = Date()
        var points: [FootprintPoint] = []
        var lat = 22.3678
        var lon = 114.1817
        var elevation = 64.0

        for index in 0..<8 {
            elevation += 3.0 + Double(index % 3) * 0.5
            lat += 0.0004
            lon += 0.0003
            points.append(
                FootprintPoint(
                    coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                    elevation: elevation,
                    timestamp: now.addingTimeInterval(Double(index - 19) * 180),
                    isIndoor: false
                )
            )
        }

        let indoorSteps: [Double] = [82, 85, 85, 88, 88, 91]
        for (offset, stepElevation) in indoorSteps.enumerated() {
            points.append(
                FootprintPoint(
                    coordinate: CLLocationCoordinate2D(latitude: 22.372, longitude: 114.186),
                    elevation: stepElevation,
                    timestamp: now.addingTimeInterval(Double(offset - 11) * 120),
                    isIndoor: true
                )
            )
        }

        for index in 0..<6 {
            elevation += 3.2
            lat += 0.00035
            lon += 0.00028
            points.append(
                FootprintPoint(
                    coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                    elevation: elevation,
                    timestamp: now.addingTimeInterval(Double(index - 5) * 150),
                    isIndoor: false
                )
            )
        }

        return Array(points.suffix(FootprintConfig.maxFootprints))
    }
}
