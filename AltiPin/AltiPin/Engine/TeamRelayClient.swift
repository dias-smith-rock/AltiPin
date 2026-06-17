//
//  TeamRelayClient.swift
//  AltiPin
//

import Foundation

// MARK: - Wire Messages (PRD Module 3)

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

struct TeamJoinMessage: Codable {
    let action: String = "join"
    let roomID: String
    let nickname: String
}

struct TeamUpdateMessage: Codable {
    let action: String = "update"
    let roomID: String
    let data: TeamLocationPayload
}

struct TeamBroadcastUpdate: Codable {
    let event: String
    let from: String
    let data: TeamLocationPayload
}

// MARK: - Relay Client Protocol

@MainActor
protocol TeamRelayClient: AnyObject {
    var onMemberUpdate: ((String, TeamLocationPayload) -> Void)? { get set }
    var onMemberJoined: ((String) -> Void)? { get set }
    var onMemberLeft: ((String) -> Void)? { get set }

    func connect(roomCode: String, nickname: String) async
    func disconnect()
    func sendLocationUpdate(_ payload: TeamLocationPayload)
}

// WebSocketTeamRelay: 后续替换 MockTeamRelay，对接 PRD 中转服务
