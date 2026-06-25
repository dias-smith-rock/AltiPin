//
//  RecentHistoryBuffer.swift
//  AltiPin
//
//  最近 20 次海拔采样滑动窗口（1 分钟间隔），供图表与 UI 共享。
//

import Combine
import Foundation

@MainActor
final class RecentHistoryBuffer: ObservableObject {
    static let shared = RecentHistoryBuffer()

    @Published private(set) var points: [HistoryPoint] = []

    private var lastRecordedPoint: HistoryPoint?
    private var lastSampleDate: Date?
    private var didBootstrapFromGPX = false

    private var tracksDirectory: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("Tracks", isDirectory: true)
    }

    private init() {}

    func reset() {
        points = []
        lastRecordedPoint = nil
        lastSampleDate = nil
        didBootstrapFromGPX = false
    }

    /// Tab 进入时：GPX 回灌 + 当前海拔种子点。
    func bootstrapIfNeeded(
        elevation: Double,
        latitude: Double,
        longitude: Double,
        isIndoor: Bool
    ) {
        if !didBootstrapFromGPX {
            backfillFromGPX(maxPoints: HistoryPointSessionConfig.slidingWindowCount)
            didBootstrapFromGPX = true
        }

        _ = appendIfNeeded(
            timestamp: .now,
            latitude: latitude,
            longitude: longitude,
            elevation: elevation,
            isIndoor: isIndoor,
            force: points.isEmpty
        )
    }

    /// 从本地 GPX 读取最近 N 个轨迹点注入滑动窗口。
    func backfillFromGPX(maxPoints: Int = HistoryPointSessionConfig.slidingWindowCount) {
        let gpxPoints = Self.loadRecentHistoryPoints(from: tracksDirectory, maxPoints: maxPoints)
        guard !gpxPoints.isEmpty else { return }

        if points.isEmpty {
            points = gpxPoints
            lastRecordedPoint = gpxPoints.last
            lastSampleDate = gpxPoints.last?.timestamp
            return
        }

        // 缓冲区内样本不足时，用 GPX 历史前缀补齐
        if points.count < maxPoints {
            let merged = mergeGPXPrefix(gpxPoints, withLive: points, maxPoints: maxPoints)
            points = merged
            lastRecordedPoint = merged.last
            lastSampleDate = merged.last?.timestamp
        }
    }

    /// 按 1 分钟节流写入滑动窗口；60 秒内原地更新末点。
    @discardableResult
    func appendIfNeeded(
        timestamp: Date = .now,
        latitude: Double,
        longitude: Double,
        elevation: Double,
        isIndoor: Bool,
        force: Bool = false
    ) -> HistoryPoint? {
        if !force,
           let lastSampleDate,
           timestamp.timeIntervalSince(lastSampleDate) < HistoryPointSessionConfig.samplingInterval {
            return updateLastPoint(
                timestamp: timestamp,
                latitude: latitude,
                longitude: longitude,
                elevation: elevation,
                isIndoor: isIndoor
            )
        }

        let delta: Double
        if let lastRecordedPoint {
            delta = elevation - lastRecordedPoint.elevation
        } else {
            delta = 0
        }

        let point = HistoryPoint(
            timestamp: timestamp,
            latitude: latitude,
            longitude: longitude,
            elevation: elevation,
            elevationDelta: delta,
            isIndoor: isIndoor
        )

        points.append(point)
        trimToWindowLimit()

        lastRecordedPoint = point
        lastSampleDate = timestamp
        return point
    }

    /// GPX 精确打点同步进滑动窗口（不受 1 分钟节流，但去重相近时间戳）。
    @discardableResult
    func ingestRecordedPoint(_ point: HistoryPoint) -> HistoryPoint {
        if let last = points.last,
           point.timestamp.timeIntervalSince(last.timestamp) < 5,
           abs(point.elevation - last.elevation) < 0.3 {
            return last
        }

        var adjusted = point
        if let lastRecordedPoint, point.elevationDelta == 0 {
            adjusted = HistoryPoint(
                id: point.id,
                timestamp: point.timestamp,
                latitude: point.latitude,
                longitude: point.longitude,
                elevation: point.elevation,
                elevationDelta: point.elevation - lastRecordedPoint.elevation,
                isIndoor: point.isIndoor
            )
        }

        points.append(adjusted)
        trimToWindowLimit()

        lastRecordedPoint = adjusted
        lastSampleDate = adjusted.timestamp
        return adjusted
    }

    // MARK: - Private

    @discardableResult
    private func updateLastPoint(
        timestamp: Date,
        latitude: Double,
        longitude: Double,
        elevation: Double,
        isIndoor: Bool
    ) -> HistoryPoint? {
        guard !points.isEmpty else { return nil }

        let lastIndex = points.count - 1
        let previousElevation = lastIndex > 0 ? points[lastIndex - 1].elevation : elevation
        let existing = points[lastIndex]
        let updated = HistoryPoint(
            id: existing.id,
            timestamp: timestamp,
            latitude: latitude,
            longitude: longitude,
            elevation: elevation,
            elevationDelta: elevation - previousElevation,
            isIndoor: isIndoor
        )

        points[lastIndex] = updated
        lastRecordedPoint = updated
        return updated
    }

    private func trimToWindowLimit() {
        let limit = HistoryPointSessionConfig.slidingWindowCount
        if points.count > limit {
            points.removeFirst(points.count - limit)
        }
    }

    private func mergeGPXPrefix(
        _ gpxPoints: [HistoryPoint],
        withLive livePoints: [HistoryPoint],
        maxPoints: Int
    ) -> [HistoryPoint] {
        guard let liveFirst = livePoints.first?.timestamp else { return gpxPoints }

        let prefix = gpxPoints.filter { $0.timestamp < liveFirst }
        let combined = prefix + livePoints
        if combined.count <= maxPoints {
            return combined
        }
        return Array(combined.suffix(maxPoints))
    }

    private static func loadRecentHistoryPoints(from directory: URL, maxPoints: Int) -> [HistoryPoint] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else {
            return []
        }

        let gpxFiles = files
            .filter { $0.pathExtension.lowercased() == "gpx" }
            .sorted { lhs, rhs in
                let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                return lhsDate > rhsDate
            }

        var allPoints: [HistoryPoint] = []
        for file in gpxFiles {
            allPoints.append(contentsOf: GPXTrackReader.parse(url: file))
        }

        allPoints.sort { $0.timestamp < $1.timestamp }
        if allPoints.count <= maxPoints {
            return allPoints
        }
        return Array(allPoints.suffix(maxPoints))
    }
}
