//
//  AltitudeWakeMonitor.swift
//  AltiPin
//
//  气压高度唤醒 / 静止睡眠判定辅助。
//

import Foundation

struct AltitudeWakeMonitor {
    private struct Sample {
        let relativeMeters: Double
        let date: Date
    }

    private var samples: [Sample] = []

    let windowSeconds: TimeInterval
    let wakeThresholdMeters: Double

    init(windowSeconds: TimeInterval = 30, wakeThresholdMeters: Double = 2.0) {
        self.windowSeconds = windowSeconds
        self.wakeThresholdMeters = wakeThresholdMeters
    }

    mutating func reset() {
        samples.removeAll()
    }

    /// 30 秒内绝对高度变化 ≥ 2m 时返回 true。
    mutating func ingest(relativeMeters: Double, date: Date = .now) -> Bool {
        samples.append(Sample(relativeMeters: relativeMeters, date: date))
        samples.removeAll { date.timeIntervalSince($0.date) > windowSeconds }

        guard samples.count >= 2 else { return false }

        let values = samples.map(\.relativeMeters)
        guard let minValue = values.min(), let maxValue = values.max() else { return false }
        return maxValue - minValue >= wakeThresholdMeters
    }
}

struct StationaryAltitudeMonitor {
    private struct Sample {
        let relativeMeters: Double
        let date: Date
    }

    private var samples: [Sample] = []

    let windowSeconds: TimeInterval
    let maxVariationMeters: Double

    init(windowSeconds: TimeInterval = 600, maxVariationMeters: Double = 0.5) {
        self.windowSeconds = windowSeconds
        self.maxVariationMeters = maxVariationMeters
    }

    mutating func reset() {
        samples.removeAll()
    }

    mutating func ingest(relativeMeters: Double, date: Date = .now) {
        samples.append(Sample(relativeMeters: relativeMeters, date: date))
        samples.removeAll { date.timeIntervalSince($0.date) > windowSeconds }
    }

    /// 连续窗口内海拔波动 < 0.5m 且样本覆盖足够时长。
    var isAltitudeStable: Bool {
        guard samples.count >= 2 else { return false }

        guard let oldest = samples.map(\.date).min(),
              Date().timeIntervalSince(oldest) >= windowSeconds * 0.9 else {
            return false
        }

        let values = samples.map(\.relativeMeters)
        guard let minValue = values.min(), let maxValue = values.max() else { return false }
        return maxValue - minValue < maxVariationMeters
    }

    var peakToPeakMeters: Double {
        let values = samples.map(\.relativeMeters)
        guard let minValue = values.min(), let maxValue = values.max() else { return 0 }
        return maxValue - minValue
    }
}
