//
//  HistoryPoint.swift
//  AltiPin
//
//  高度驱动记录引擎的标准 Payload：服务于海拔变化追踪。
//

import CoreLocation
import Foundation

struct HistoryPoint: Identifiable, Equatable, Sendable {
    let id: UUID
    let timestamp: Date
    let latitude: Double
    let longitude: Double
    let elevation: Double
    let elevationDelta: Double
    let isIndoor: Bool

    init(
        id: UUID = UUID(),
        timestamp: Date,
        latitude: Double,
        longitude: Double,
        elevation: Double,
        elevationDelta: Double = 0,
        isIndoor: Bool = false
    ) {
        self.id = id
        self.timestamp = timestamp
        self.latitude = latitude
        self.longitude = longitude
        self.elevation = elevation
        self.elevationDelta = elevationDelta
        self.isIndoor = isIndoor
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

// MARK: - 多段会话截断

extension Array where Element == HistoryPoint {
    /// 按 5 分钟时间断层切分为多个连续运动会话。
    var segmentedPoints: [[HistoryPoint]] {
        guard !isEmpty else { return [] }

        var segments: [[HistoryPoint]] = []
        var currentSegment: [HistoryPoint] = [self[0]]

        for index in 1..<count {
            let gap = self[index].timestamp.timeIntervalSince(self[index - 1].timestamp)
            if gap > HistoryPointSessionConfig.gapThreshold {
                segments.append(currentSegment)
                currentSegment = [self[index]]
            } else {
                currentSegment.append(self[index])
            }
        }

        segments.append(currentSegment)
        return segments
    }

    /// 相邻会话之间的休眠时长（秒），索引对应前一段 session 的下标。
    var sessionGapDurations: [(afterSegmentIndex: Int, duration: TimeInterval)] {
        let segments = segmentedPoints
        guard segments.count > 1 else { return [] }

        var gaps: [(Int, TimeInterval)] = []
        for index in 0..<(segments.count - 1) {
            guard let segmentEnd = segments[index].last?.timestamp,
                  let nextStart = segments[index + 1].first?.timestamp else {
                continue
            }
            gaps.append((index, nextStart.timeIntervalSince(segmentEnd)))
        }
        return gaps
    }

    func orderIndex(for point: HistoryPoint) -> Int? {
        firstIndex(where: { $0.id == point.id })
    }

    /// 固定 20 槽窗口内的 X 轴次序：部分填充时从右侧「当前」向左生长。
    func chartSlotIndex(for point: HistoryPoint) -> Int? {
        guard let index = orderIndex(for: point) else { return nil }
        let windowSize = HistoryPointSessionConfig.slidingWindowCount
        return (windowSize - count) + index
    }
}

enum HistoryPointSessionConfig {
    static let gapThreshold: TimeInterval = 300
    static let slidingWindowCount = 20
    static let samplingInterval: TimeInterval = 60
}

extension HistoryPoint {
    static var mockPoints: [HistoryPoint] {
        let now = Date()
        var points: [HistoryPoint] = []

        // Session 1: 8 个室外点，平滑山体起伏
        let session1Start = now.addingTimeInterval(-19 * 60)
        var lastElevation = 64.0
        for index in 0..<8 {
            let progress = Double(index) / 7.0
            let elevation = 64 + progress * 18 + sin(progress * .pi * 2) * 4
            let delta = elevation - lastElevation
            lastElevation = elevation
            points.append(
                HistoryPoint(
                    timestamp: session1Start.addingTimeInterval(Double(index) * 60),
                    latitude: 22.3678 + progress * 0.004,
                    longitude: 114.1817 + progress * 0.003,
                    elevation: elevation,
                    elevationDelta: delta,
                    isIndoor: false
                )
            )
        }

        // Session 2: 断层 12 分钟后，室内阶梯 + 室外恢复
        let session2Start = session1Start.addingTimeInterval(8 * 60 + 720)
        let indoorElevations: [Double] = [82, 82, 85, 85, 88, 88, 91, 91, 93, 93, 95, 95]
        for (index, elevation) in indoorElevations.enumerated() {
            let previous = index == 0 ? lastElevation : indoorElevations[index - 1]
            let isIndoor = index < 6
            points.append(
                HistoryPoint(
                    timestamp: session2Start.addingTimeInterval(Double(index) * 60),
                    latitude: 22.372,
                    longitude: 114.186,
                    elevation: elevation,
                    elevationDelta: elevation - previous,
                    isIndoor: isIndoor
                )
            )
        }

        return Array(points.suffix(HistoryPointSessionConfig.slidingWindowCount))
    }
}
