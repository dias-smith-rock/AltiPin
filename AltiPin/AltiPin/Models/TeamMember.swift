//
//  TeamMember.swift
//  AltiPin
//

import CoreLocation
import Foundation
import SwiftUI

struct TeamMember: Identifiable {
    let id: UUID
    var clientId: String
    var nickname: String
    var color: Color
    var isSelf: Bool
    var recentPoints: [HistoryPoint]
    var currentCoordinate: CLLocationCoordinate2D
    var elevation: Double
    var lastSeen: Date
    var speedKmh: Double
    var sessionDuration: TimeInterval
    var distanceMeters: Double
    var activityPhase: ActivitySessionPhase

    init(
        id: UUID,
        clientId: String,
        nickname: String,
        color: Color,
        isSelf: Bool,
        recentPoints: [HistoryPoint],
        currentCoordinate: CLLocationCoordinate2D,
        elevation: Double,
        lastSeen: Date,
        speedKmh: Double = 0,
        sessionDuration: TimeInterval = 0,
        distanceMeters: Double = 0,
        activityPhase: ActivitySessionPhase = .idle
    ) {
        self.id = id
        self.clientId = clientId
        self.nickname = nickname
        self.color = color
        self.isSelf = isSelf
        self.recentPoints = recentPoints
        self.currentCoordinate = currentCoordinate
        self.elevation = elevation
        self.lastSeen = lastSeen
        self.speedKmh = speedKmh
        self.sessionDuration = sessionDuration
        self.distanceMeters = distanceMeters
        self.activityPhase = activityPhase
    }

    var initial: String {
        String(nickname.prefix(1))
    }

    var hasValidCoordinate: Bool {
        abs(currentCoordinate.latitude) > 0.000_001 || abs(currentCoordinate.longitude) > 0.000_001
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

    var formattedDuration: String {
        Self.formatDuration(sessionDuration)
    }

    static func formatDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = max(0, Int(duration.rounded()))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
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
