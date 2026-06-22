//
//  FootprintTrackingEngine.swift
//  AltiPin
//
//  脚印驱动型海拔采集引擎：双重位移阈值 + FIFO 20 窗口。
//

import Combine
import CoreLocation
import CoreMotion
import Foundation
import SwiftData

@MainActor
final class FootprintTrackingEngine: ObservableObject {
    static let shared = FootprintTrackingEngine()

    @Published private(set) var recentFootprints: [FootprintPoint] = []

    private var footprintStore: FootprintStore?
    private var lastFootprintCommittedAt: Date?
    private var isMotionGateOpen = false
    private var isConfigured = false

    private init() {}

    func configure(modelContext: ModelContext) {
        guard !isConfigured else { return }
        isConfigured = true
        footprintStore = FootprintStore(modelContext: modelContext)
        reloadFromStore()
    }

    /// 从 SwiftData 重载最近脚印窗口。
    func reloadFromStore() {
        guard let footprintStore else { return }

        let loaded = footprintStore.loadRecent()
        recentFootprints = loaded
        lastFootprintCommittedAt = loaded.last?.timestamp

        NSLog("FootprintTrackingEngine: reload count=\(loaded.count)")
    }

    /// 脚印不足时，将 RecentHistoryBuffer / GPX 历史采样回灌为脚印并持久化。
    func backfillFromHistoryIfNeeded(historyPoints: [HistoryPoint]) {
        guard recentFootprints.count <= 1 else { return }
        guard historyPoints.count >= 2 else { return }

        let converted = historyPoints.map { point in
            FootprintPoint(
                id: point.id,
                coordinate: point.coordinate,
                elevation: point.elevation,
                timestamp: point.timestamp,
                isIndoor: point.isIndoor
            )
        }

        let footprints = deduplicatedFootprints(Array(converted.suffix(FootprintConfig.maxFootprints)))
        guard footprints.count >= 2 else { return }

        footprintStore?.replaceAll(with: footprints)
        recentFootprints = footprints
        lastFootprintCommittedAt = footprints.last?.timestamp

        NSLog("FootprintTrackingEngine: backfill from history \(footprints.count) points")
    }

    func reset() {
        recentFootprints = []
        lastFootprintCommittedAt = nil
        isMotionGateOpen = false

        if let footprintStore {
            footprintStore.replaceAll(with: [])
        }
    }

    /// 无脚印时，将当前位置海拔作为首个种子脚印（不依赖运动门控）。
    func seedInitialFootprintIfNeeded(
        location: CLLocation,
        elevation: Double,
        isIndoor: Bool
    ) {
        guard recentFootprints.isEmpty else { return }
        guard location.horizontalAccuracy >= 0 else { return }

        commitFootprint(
            location: location,
            elevation: elevation,
            isIndoor: isIndoor,
            reason: .seed
        )
    }

    /// 接收融合后的定位/海拔/运动状态，判定是否踩下新脚印。
    func ingest(
        location: CLLocation,
        elevation: Double,
        isIndoor: Bool,
        motionActivity: CMMotionActivity?
    ) {
        let motionActive = FootprintTriggerEvaluator.isQualifyingMotion(motionActivity)

        guard motionActive else {
            isMotionGateOpen = false
            return
        }

        isMotionGateOpen = true

        let evaluation = FootprintTriggerEvaluator.evaluate(
            currentLocation: location,
            currentElevation: elevation,
            lastFootprint: recentFootprints.last,
            lastFootprintCommittedAt: lastFootprintCommittedAt
        )

        guard evaluation.shouldCommit else { return }

        commitFootprint(
            location: location,
            elevation: elevation,
            isIndoor: isIndoor,
            reason: evaluation.reason ?? .seed
        )
    }

    // MARK: - Private

    private func deduplicatedFootprints(_ footprints: [FootprintPoint]) -> [FootprintPoint] {
        guard footprints.count >= 2 else { return footprints }

        var result: [FootprintPoint] = []
        for footprint in footprints {
            if let last = result.last,
               footprint.timestamp.timeIntervalSince(last.timestamp) < 60,
               abs(footprint.elevation - last.elevation) < 0.3 {
                result[result.count - 1] = footprint
            } else {
                result.append(footprint)
            }
        }
        return result
    }

    private func commitFootprint(
        location: CLLocation,
        elevation: Double,
        isIndoor: Bool,
        reason: FootprintTriggerReason
    ) {
        let footprint = FootprintPoint(
            coordinate: location.coordinate,
            elevation: elevation,
            timestamp: location.timestamp,
            isIndoor: isIndoor
        )

        recentFootprints.append(footprint)
        if recentFootprints.count > FootprintConfig.maxFootprints {
            recentFootprints.removeFirst(recentFootprints.count - FootprintConfig.maxFootprints)
        }

        lastFootprintCommittedAt = footprint.timestamp
        footprintStore?.save(footprint)

        NSLog(
            "FootprintTrackingEngine: committed \(reason.rawValue) " +
            "ele=\(String(format: "%.1f", elevation))m count=\(recentFootprints.count)"
        )
    }
}
