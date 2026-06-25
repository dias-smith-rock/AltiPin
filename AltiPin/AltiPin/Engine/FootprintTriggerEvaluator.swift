//
//  FootprintTriggerEvaluator.swift
//  AltiPin
//
//  脚印双重位移阈值 + 时间安全上限判定（纯函数）。
//

import CoreLocation
import CoreMotion
import Foundation

enum FootprintTriggerReason: String, Sendable {
    case seed
    case verticalDisplacement
    case horizontalDisplacement
    case timeCap
}

struct FootprintTriggerEvaluation: Sendable {
    let shouldCommit: Bool
    let reason: FootprintTriggerReason?
}

enum FootprintTriggerEvaluator {
    static func isQualifyingMotion(_ activity: CMMotionActivity?) -> Bool {
        guard let activity else { return false }
        return (activity.walking || activity.running || activity.cycling)
            && activity.confidence != .low
    }

    static func evaluate(
        currentLocation: CLLocation,
        currentElevation: Double,
        lastFootprint: FootprintPoint?,
        lastFootprintCommittedAt: Date?,
        now: Date = .now
    ) -> FootprintTriggerEvaluation {
        guard let lastFootprint else {
            return FootprintTriggerEvaluation(shouldCommit: false, reason: nil)
        }

        let verticalDelta = abs(currentElevation - lastFootprint.elevation)
        if verticalDelta >= FootprintConfig.verticalThresholdMeters {
            return FootprintTriggerEvaluation(shouldCommit: true, reason: .verticalDisplacement)
        }

        let lastLocation = CLLocation(
            latitude: lastFootprint.coordinate.latitude,
            longitude: lastFootprint.coordinate.longitude
        )
        let horizontalDelta = currentLocation.distance(from: lastLocation)
        if horizontalDelta >= FootprintConfig.horizontalThresholdMeters {
            return FootprintTriggerEvaluation(shouldCommit: true, reason: .horizontalDisplacement)
        }

        if let lastFootprintCommittedAt,
           now.timeIntervalSince(lastFootprintCommittedAt) >= FootprintConfig.timeCapSeconds {
            return FootprintTriggerEvaluation(shouldCommit: true, reason: .timeCap)
        }

        return FootprintTriggerEvaluation(shouldCommit: false, reason: nil)
    }

    /// 水平与垂直偏移均未超阈时，可原地更新末条脚印而非新增。
    static func isWithinUpsertThresholds(
        currentLocation: CLLocation,
        currentElevation: Double,
        lastFootprint: FootprintPoint
    ) -> Bool {
        let verticalDelta = abs(currentElevation - lastFootprint.elevation)
        let lastLocation = CLLocation(
            latitude: lastFootprint.coordinate.latitude,
            longitude: lastFootprint.coordinate.longitude
        )
        let horizontalDelta = currentLocation.distance(from: lastLocation)
        return verticalDelta < FootprintConfig.verticalThresholdMeters
            && horizontalDelta < FootprintConfig.horizontalThresholdMeters
    }

    /// 末条脚印 upsert 前判定：是否有必要写入 DB（有意义变化或到达刷新间隔）。
    static func shouldPersistUpdate(
        candidate: FootprintPoint,
        lastPersisted: FootprintPoint?,
        lastPersistedAt: Date?,
        now: Date = .now
    ) -> Bool {
        guard let lastPersisted else { return true }

        if candidate.isIndoor != lastPersisted.isIndoor {
            return true
        }

        let elevationDelta = abs(candidate.elevation - lastPersisted.elevation)
        if elevationDelta >= FootprintConfig.persistMinElevationDeltaMeters {
            return true
        }

        let lastLocation = CLLocation(
            latitude: lastPersisted.coordinate.latitude,
            longitude: lastPersisted.coordinate.longitude
        )
        let candidateLocation = CLLocation(
            latitude: candidate.coordinate.latitude,
            longitude: candidate.coordinate.longitude
        )
        if candidateLocation.distance(from: lastLocation) >= FootprintConfig.persistMinHorizontalDeltaMeters {
            return true
        }

        if let lastPersistedAt,
           now.timeIntervalSince(lastPersistedAt) >= FootprintConfig.persistMinIntervalSeconds {
            return true
        }

        return false
    }

    /// 距上一条 commit 不足最小 insert 间隔时不允许新增脚印。
    static func shouldBlockInsert(
        lastFootprintCommittedAt: Date?,
        now: Date = .now
    ) -> Bool {
        guard let lastFootprintCommittedAt else { return false }
        return now.timeIntervalSince(lastFootprintCommittedAt) < FootprintConfig.minInsertIntervalSeconds
    }

    /// 垂直大幅跳变但水平几乎不动，视为 GPS/融合海拔噪声。
    static func isElevationNoise(
        currentLocation: CLLocation,
        currentElevation: Double,
        lastFootprint: FootprintPoint
    ) -> Bool {
        let verticalDelta = abs(currentElevation - lastFootprint.elevation)
        let lastLocation = CLLocation(
            latitude: lastFootprint.coordinate.latitude,
            longitude: lastFootprint.coordinate.longitude
        )
        let horizontalDelta = currentLocation.distance(from: lastLocation)
        return verticalDelta >= FootprintConfig.maxVerticalJumpMeters
            && horizontalDelta < FootprintConfig.elevationNoiseMaxHorizontalMeters
    }
}
