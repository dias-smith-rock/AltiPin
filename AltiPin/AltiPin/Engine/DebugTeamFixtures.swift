//
//  DebugTeamFixtures.swift
//  AltiPin
//
//  模拟器 Debug：香港大围附近组队测试数据。
//

#if DEBUG
import CoreLocation
import Foundation

enum DebugTeamFixtures {
    static let roomCode = "8866"
    static let taiWaiCenter = CLLocationCoordinate2D(latitude: 22.3709, longitude: 114.1781)

    static func taiWaiMockTrack(now: Date = .now) -> [HistoryPoint] {
        let samples: [(lat: Double, lon: Double, ele: Double, offsetMinutes: Double)] = [
            (22.3698, 114.1768, 11, -8),
            (22.3704, 114.1776, 13, -6),
            (22.3709, 114.1781, 15, -4),
            (22.3714, 114.1789, 17, -2),
            (22.3720, 114.1794, 19, 0),
        ]

        return samples.map { sample in
            HistoryPoint(
                timestamp: now.addingTimeInterval(sample.offsetMinutes * 60),
                latitude: sample.lat,
                longitude: sample.lon,
                elevation: sample.ele
            )
        }
    }
}
#endif
