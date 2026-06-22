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
        guard lastFootprint != nil else {
            return FootprintTriggerEvaluation(shouldCommit: true, reason: .seed)
        }

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
}
