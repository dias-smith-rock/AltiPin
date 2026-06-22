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
    private var lastPersistedFootprint: FootprintPoint?
    private var lastPersistedAt: Date?
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
        syncPersistState(from: loaded.last)

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
        syncPersistState(from: footprints.last)

        NSLog("FootprintTrackingEngine: backfill from history \(footprints.count) points")
    }

    func reset() {
        recentFootprints = []
        lastFootprintCommittedAt = nil
        lastPersistedFootprint = nil
        lastPersistedAt = nil
        isMotionGateOpen = false

        if let footprintStore {
            footprintStore.replaceAll(with: [])
        }
    }

    /// 将当前位置/海拔写入脚印库：阈值内更新末条，超阈或空库则新增（不依赖运动门控）。
    func persistCurrentFootprintIfNeeded(
        location: CLLocation,
        elevation: Double,
        isIndoor: Bool
    ) {
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

    private enum FootprintWriteMode {
        case inserted
        case updated
        case skipped
    }

    private func syncPersistState(from footprint: FootprintPoint?) {
        lastPersistedFootprint = footprint
        lastPersistedAt = footprint?.timestamp
    }

    private func markPersisted(_ footprint: FootprintPoint) {
        lastPersistedFootprint = footprint
        lastPersistedAt = Date()
    }

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

    @discardableResult
    private func commitFootprint(
        location: CLLocation,
        elevation: Double,
        isIndoor: Bool,
        reason: FootprintTriggerReason
    ) -> FootprintWriteMode {
        if let last = recentFootprints.last,
           FootprintTriggerEvaluator.isWithinUpsertThresholds(
               currentLocation: location,
               currentElevation: elevation,
               lastFootprint: last
           ) {
            let updated = FootprintPoint(
                id: last.id,
                coordinate: location.coordinate,
                elevation: elevation,
                timestamp: location.timestamp,
                isIndoor: isIndoor
            )

            guard FootprintTriggerEvaluator.shouldPersistUpdate(
                candidate: updated,
                lastPersisted: lastPersistedFootprint,
                lastPersistedAt: lastPersistedAt
            ) else {
                return .skipped
            }

            recentFootprints[recentFootprints.count - 1] = updated
            lastFootprintCommittedAt = updated.timestamp
            footprintStore?.update(updated)
            markPersisted(updated)

            NSLog(
                "FootprintTrackingEngine: updated \(reason.rawValue) " +
                "ele=\(String(format: "%.1f", elevation))m count=\(recentFootprints.count)"
            )
            return .updated
        }

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
        markPersisted(footprint)

        NSLog(
            "FootprintTrackingEngine: inserted \(reason.rawValue) " +
            "ele=\(String(format: "%.1f", elevation))m count=\(recentFootprints.count)"
        )
        return .inserted
    }
}
