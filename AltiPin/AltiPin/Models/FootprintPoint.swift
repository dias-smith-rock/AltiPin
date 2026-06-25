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
    static let maxFootprints = 10
    static let verticalThresholdMeters = 3.0
    static let horizontalThresholdMeters = 50.0
    static let timeCapSeconds: TimeInterval = 300

    /// 原地更新末条脚印时的持久化节流（与触发阈值分离）。
    static let persistMinIntervalSeconds: TimeInterval = 60
    /// 新增脚印的最小间隔（与 timeCapSeconds 对齐）。
    static let minInsertIntervalSeconds: TimeInterval = 300
    static let persistMinElevationDeltaMeters = 0.3
    static let persistMinHorizontalDeltaMeters = 2.0
    /// 垂直跳变超过此值且水平几乎不变时，视为海拔噪声。
    static let maxVerticalJumpMeters = 30.0
    static let elevationNoiseMaxHorizontalMeters = 5.0
    static let minOutdoorElevationMeters = -100.0

    #if DEBUG
    static let simulatorMockCount = maxFootprints
    #endif

    static var effectiveMaxFootprints: Int { maxFootprints }
}

extension Array where Element == FootprintPoint {
    /// 固定 10 槽窗口内的 X 轴槽位（0-based），部分填充时从右侧「当前」向左生长。
    func chartSlotIndex(for footprint: FootprintPoint) -> Int? {
        guard let index = firstIndex(where: { $0.id == footprint.id }) else { return nil }
        return (FootprintConfig.effectiveMaxFootprints - count) + index
    }
}

extension FootprintPoint {
    #if DEBUG
    static var simulatorMockFootprints: [FootprintPoint] {
        simulatorMockFootprints(count: FootprintConfig.simulatorMockCount)
    }

    static func simulatorMockFootprints(count: Int) -> [FootprintPoint] {
        let now = Date()
        var points: [FootprintPoint] = []
        var lat = 22.3678
        var lon = 114.1817
        var elevation = 64.0

        for index in 0..<count {
            if index >= count * 3 / 5, index <= count * 4 / 5 {
                elevation = 82 + Double(index - count * 3 / 5) * 2.2
                points.append(
                    FootprintPoint(
                        coordinate: CLLocationCoordinate2D(latitude: 22.372, longitude: 114.186),
                        elevation: elevation,
                        timestamp: now.addingTimeInterval(Double(index - count) * 120),
                        isIndoor: true
                    )
                )
            } else {
                elevation += 2.4 + Double(index % 4) * 0.7
                lat += 0.00032
                lon += 0.00026
                points.append(
                    FootprintPoint(
                        coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                        elevation: elevation,
                        timestamp: now.addingTimeInterval(Double(index - count) * 150),
                        isIndoor: false
                    )
                )
            }
        }

        return points
    }
    #endif

    static var mockFootprints: [FootprintPoint] {
        #if DEBUG
        simulatorMockFootprints
        #else
        []
        #endif
    }
}
