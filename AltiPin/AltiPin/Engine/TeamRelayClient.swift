//
//  TeamRelayClient.swift
//  AltiPin
//

import Foundation

// MARK: - Wire Messages (PRD Module 3 + Supabase Realtime extensions)

struct TeamLocationPayload: Codable, Equatable {
    let lon: Double
    let lat: Double
    let ele: Double
    var timestamp: TimeInterval?

    init(lon: Double, lat: Double, ele: Double, timestamp: TimeInterval? = nil) {
        self.lon = lon
        self.lat = lat
        self.ele = ele
        self.timestamp = timestamp
    }
}

struct TeamPresencePayload: Codable, Equatable {
    let nickname: String
    let clientId: String
}

struct TeamBroadcastEnvelope: Codable, Equatable {
    let nickname: String
    let data: TeamLocationPayload
}

struct TeamRosterMember: Codable, Equatable {
    let nickname: String
    let clientId: String
}

enum TeamRelayOutboundAction: String, Codable {
    case join
    case update
    case leave
}

struct TeamJoinMessage: Encodable {
    let action = TeamRelayOutboundAction.join
    let roomID: String
    let nickname: String
}

struct TeamUpdateMessage: Encodable {
    let action = TeamRelayOutboundAction.update
    let roomID: String
    let data: TeamLocationPayload
}

struct TeamLeaveMessage: Encodable {
    let action = TeamRelayOutboundAction.leave
    let roomID: String
    let nickname: String
}

struct TeamBroadcastUpdate: Codable {
    let event: String
    let from: String
    let data: TeamLocationPayload
}

enum TeamRelayEvents {
    static let broadcastUpdate = TeamRelayConfiguration.broadcastEvent
}

// MARK: - Relay Client Protocol

@MainActor
protocol TeamRelayClient: AnyObject {
    var onMemberUpdate: ((String, TeamLocationPayload) -> Void)? { get set }
    var onMemberJoined: ((String) -> Void)? { get set }
    var onMemberLeft: ((String) -> Void)? { get set }
    var onConnectionStateChange: ((TeamConnectionState) -> Void)? { get set }

    func connect(roomCode: String, nickname: String) async
    func disconnect()
    func sendLocationUpdate(_ payload: TeamLocationPayload)
}

extension TeamRelayClient {
    var onConnectionStateChange: ((TeamConnectionState) -> Void)? {
        get { nil }
        set { _ = newValue }
    }
}
