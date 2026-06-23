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
    var speedKmh: Double?
    var sessionDuration: TimeInterval?
    var distanceMeters: Double?
    var activityPhase: String?

    init(
        lon: Double,
        lat: Double,
        ele: Double,
        timestamp: TimeInterval? = nil,
        speedKmh: Double? = nil,
        sessionDuration: TimeInterval? = nil,
        distanceMeters: Double? = nil,
        activityPhase: String? = nil
    ) {
        self.lon = lon
        self.lat = lat
        self.ele = ele
        self.timestamp = timestamp
        self.speedKmh = speedKmh
        self.sessionDuration = sessionDuration
        self.distanceMeters = distanceMeters
        self.activityPhase = activityPhase
    }
}

struct TeamPresencePayload: Codable, Equatable {
    let nickname: String
    let clientId: String
}

struct TeamBroadcastEnvelope: Codable, Equatable {
    let nickname: String
    let clientId: String?
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
    static let sessionSync = TeamRelayConfiguration.sessionSyncEvent
    static let hostTransfer = TeamRelayConfiguration.hostTransferEvent
}

struct TeamHostTransferPayload: Codable, Equatable, Sendable {
    let newHostClientId: String
    let newHostNickname: String
    let previousHostClientId: String?
    let issuedAt: TimeInterval
    /// 为 false 时仅同步房主身份，不弹窗（例如新成员入队时房主广播当前状态）。
    let announcePromotion: Bool
}

enum TeamSessionSyncAction: String, Codable, Sendable {
    case start
    case pause
    case reset
}

struct TeamSessionSyncPayload: Codable, Equatable, Sendable {
    let action: TeamSessionSyncAction
    let nickname: String
    let clientId: String?
    let issuedAt: TimeInterval
}

// MARK: - Relay Client Protocol

@MainActor
protocol TeamRelayClient: AnyObject {
    var lastError: String? { get }
    var localClientId: String? { get }
    var onMemberUpdate: ((TeamBroadcastEnvelope) -> Void)? { get set }
    var onMemberJoined: ((TeamPresencePayload) -> Void)? { get set }
    var onMemberLeft: ((String) -> Void)? { get set }
    var onSessionSync: ((TeamSessionSyncPayload) -> Void)? { get set }
    var onHostTransfer: ((TeamHostTransferPayload) -> Void)? { get set }
    var onConnectionStateChange: ((TeamConnectionState) -> Void)? { get set }

    func connect(roomCode: String, nickname: String) async
    func disconnect()
    func sendLocationUpdate(_ payload: TeamLocationPayload)
    func sendSessionSync(_ payload: TeamSessionSyncPayload)
    func sendHostTransfer(_ payload: TeamHostTransferPayload) async
}

extension TeamRelayClient {
    var lastError: String? { nil }
    var localClientId: String? { nil }
    var onSessionSync: ((TeamSessionSyncPayload) -> Void)? {
        get { nil }
        set { _ = newValue }
    }

    func sendSessionSync(_ payload: TeamSessionSyncPayload) {}

    var onHostTransfer: ((TeamHostTransferPayload) -> Void)? {
        get { nil }
        set { _ = newValue }
    }

    func sendHostTransfer(_ payload: TeamHostTransferPayload) async {}

    var onConnectionStateChange: ((TeamConnectionState) -> Void)? {
        get { nil }
        set { _ = newValue }
    }
}
