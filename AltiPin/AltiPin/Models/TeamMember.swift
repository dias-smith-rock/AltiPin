//
//  TeamMember.swift
//  AltiPin
//

import CoreLocation
import Foundation
import SwiftUI

struct TeamMember: Identifiable {
    let id: UUID
    var nickname: String
    var color: Color
    var isSelf: Bool
    var recentPoints: [HistoryPoint]
    var currentCoordinate: CLLocationCoordinate2D
    var elevation: Double
    var lastSeen: Date

    var initial: String {
        String(nickname.prefix(1))
    }

    func connectionTier(at now: Date = .now) -> TeamConnectionTier {
        let delta = now.timeIntervalSince(lastSeen)
        if delta <= 30 {
            return .online
        } else if delta <= 180 {
            return .weakSignal
        } else {
            return .disconnected
        }
    }

    func minutesSinceLastSeen(at now: Date = .now) -> Int {
        max(1, Int(now.timeIntervalSince(lastSeen) / 60))
    }
}

enum TeamConnectionState: Equatable {
    case idle
    case connecting
    case connected
    case disconnected
}

extension TeamMember {
    static let memberColors: [Color] = [
        Color(red: 0.95, green: 0.55, blue: 0.12),
        Color(red: 0.31, green: 0.80, blue: 0.77),
        Color(red: 0.61, green: 0.35, blue: 0.71),
        Color(red: 0.97, green: 0.86, blue: 0.44),
        Color(red: 0.40, green: 0.73, blue: 0.42),
        Color(red: 0.95, green: 0.40, blue: 0.45),
    ]

    static func color(for index: Int) -> Color {
        memberColors[index % memberColors.count]
    }
}
