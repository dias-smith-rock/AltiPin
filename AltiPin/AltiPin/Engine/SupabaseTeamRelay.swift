//
//  SupabaseTeamRelay.swift
//  AltiPin
//

import Foundation
import Supabase

@MainActor
final class SupabaseTeamRelay: TeamRelayClient {
    var onMemberUpdate: ((String, TeamLocationPayload) -> Void)?
    var onMemberJoined: ((String) -> Void)?
    var onMemberLeft: ((String) -> Void)?
    var onConnectionStateChange: ((TeamConnectionState) -> Void)?

    private var channel: RealtimeChannelV2?
    private var clientId: UUID?
    private var nickname: String?
    private var roomCode: String?
    private var broadcastTask: Task<Void, Never>?
    private var presenceTask: Task<Void, Never>?
    private var statusTask: Task<Void, Never>?
    private var lastSentAt: Date?
    private var isSubscribed = false
    private var knownMemberClientIDs = Set<String>()

    func connect(roomCode: String, nickname: String) async {
        guard let client = SupabaseClientProvider.shared else {
            onConnectionStateChange?(.disconnected)
            return
        }

        self.roomCode = roomCode
        self.nickname = nickname
        self.clientId = UUID()
        knownMemberClientIDs.removeAll()
        isSubscribed = false
        onConnectionStateChange?(.connecting)

        let topic = TeamRelayConfiguration.channelTopic(roomID: roomCode)
        let presenceKey = clientId!.uuidString

        let channel = client.realtimeV2.channel(topic) { config in
            config.presence.key = presenceKey
            config.broadcast.receiveOwnBroadcasts = false
        }
        self.channel = channel

        broadcastTask = Task { [weak self] in
            for await message in channel.broadcastStream(event: TeamRelayEvents.broadcastUpdate) {
                guard let self else { continue }
                self.handleBroadcastMessage(message)
            }
        }

        presenceTask = Task { [weak self] in
            for await action in channel.presenceChange() {
                guard let self else { continue }
                self.handlePresenceChange(action)
            }
        }

        statusTask = Task { [weak self] in
            for await status in channel.statusChange {
                guard let self else { continue }
                self.handleStatusChange(status)
            }
        }

        await channel.subscribe()

        do {
            let presence = TeamPresencePayload(
                nickname: nickname,
                clientId: presenceKey
            )
            try await channel.track(presence)
            isSubscribed = true
            onConnectionStateChange?(.connected)
        } catch {
            isSubscribed = false
            onConnectionStateChange?(.disconnected)
            await teardownChannel()
        }
    }

    func disconnect() {
        isSubscribed = false
        broadcastTask?.cancel()
        presenceTask?.cancel()
        statusTask?.cancel()
        broadcastTask = nil
        presenceTask = nil
        statusTask = nil

        let activeChannel = channel
        channel = nil
        clientId = nil
        nickname = nil
        roomCode = nil
        lastSentAt = nil
        knownMemberClientIDs.removeAll()

        Task {
            await activeChannel?.untrack()
            await activeChannel?.unsubscribe()
        }
    }

    func sendLocationUpdate(_ payload: TeamLocationPayload) {
        guard isSubscribed,
              let channel,
              let nickname else {
            return
        }

        let now = Date()
        if let lastSentAt,
           now.timeIntervalSince(lastSentAt) < TeamRelayConfiguration.locationUpdateInterval {
            return
        }
        lastSentAt = now

        var outbound = payload
        if outbound.timestamp == nil {
            outbound.timestamp = now.timeIntervalSince1970
        }

        let envelope = TeamBroadcastEnvelope(nickname: nickname, data: outbound)

        Task {
            try? await channel.broadcast(
                event: TeamRelayEvents.broadcastUpdate,
                message: envelope
            )
        }
    }

    // MARK: - Private

    private func handleBroadcastMessage(_ message: JSONObject) {
        if let envelope = try? message["payload"]?.decode(as: TeamBroadcastEnvelope.self) {
            onMemberUpdate?(envelope.nickname, envelope.data)
            return
        }

        if let payload = try? message["payload"]?.decode(as: TeamLocationPayload.self),
           let sender = message["from"]?.stringValue ?? nickname {
            onMemberUpdate?(sender, payload)
        }
    }

    private func handlePresenceChange(_ action: any PresenceAction) {
        if let joins = try? action.decodeJoins(as: TeamPresencePayload.self) {
            for member in joins {
                registerMemberJoin(member)
            }
        }

        if let leaves = try? action.decodeLeaves(as: TeamPresencePayload.self) {
            for member in leaves {
                registerMemberLeave(member)
            }
        }
    }

    private func registerMemberJoin(_ member: TeamPresencePayload) {
        guard member.clientId != clientId?.uuidString else { return }
        guard knownMemberClientIDs.insert(member.clientId).inserted else { return }
        onMemberJoined?(member.nickname)
    }

    private func registerMemberLeave(_ member: TeamPresencePayload) {
        guard knownMemberClientIDs.remove(member.clientId) != nil else { return }
        onMemberLeft?(member.nickname)
    }

    private func handleStatusChange(_ status: RealtimeChannelStatus) {
        switch status {
        case .subscribed:
            isSubscribed = true
            onConnectionStateChange?(.connected)
        case .unsubscribed:
            isSubscribed = false
            onConnectionStateChange?(.disconnected)
        case .subscribing, .unsubscribing:
            onConnectionStateChange?(.connecting)
        }
    }

    private func teardownChannel() async {
        broadcastTask?.cancel()
        presenceTask?.cancel()
        statusTask?.cancel()
        broadcastTask = nil
        presenceTask = nil
        statusTask = nil

        await channel?.untrack()
        await channel?.unsubscribe()
        channel = nil
    }
}
