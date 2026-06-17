//
//  SupabaseTeamRelay.swift
//  AltiPin
//

import Foundation
import Supabase

@MainActor
final class SupabaseTeamRelay: TeamRelayClient {
    private(set) var lastError: String?

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
        lastError = nil
        TeamRelayLogger.log("connect 开始 room=\(roomCode) nickname=\(nickname)")

        guard TeamRelayConfiguration.isSupabaseConfigured else {
            lastError = "Supabase 未配置。请在 AltiPin.xcconfig 填写 SUPABASE_PROJECT_REF 与 anon key，并确认 Supabase-Info.plist 已合并进 Info.plist。"
            TeamRelayLogger.log("失败：Supabase 未正确配置")
            onConnectionStateChange?(.disconnected)
            return
        }

        guard let client = SupabaseClientProvider.shared else {
            lastError = "无法初始化 Supabase 客户端，请检查 URL 与 anon key 是否来自同一项目。"
            TeamRelayLogger.log("失败：SupabaseClient 为 nil")
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
        TeamRelayLogger.log("topic=\(topic) clientId=\(presenceKey) isPrivate=false")

        TeamRelayLogger.log("realtimeV2.connect() 前 status=\(client.realtimeV2.status)")
        await client.realtimeV2.connect()
        TeamRelayLogger.log("realtimeV2.connect() 后 status=\(client.realtimeV2.status)")

        guard client.realtimeV2.status == .connected else {
            lastError = "Realtime WebSocket 连接失败，请检查网络与 Supabase 项目状态。"
            TeamRelayLogger.log("失败：WebSocket 未 connected，status=\(client.realtimeV2.status)")
            onConnectionStateChange?(.disconnected)
            return
        }

        let channel = client.realtimeV2.channel(topic) { config in
            config.isPrivate = false
            config.presence.key = presenceKey
            config.broadcast.receiveOwnBroadcasts = false
        }
        self.channel = channel
        TeamRelayLogger.log("channel 已创建，开始注册 broadcast/presence/status 监听")

        broadcastTask = Task { [weak self] in
            TeamRelayLogger.log("broadcast 监听任务启动 event=\(TeamRelayEvents.broadcastUpdate)")
            for await message in channel.broadcastStream(event: TeamRelayEvents.broadcastUpdate) {
                guard let self else { continue }
                TeamRelayLogger.log("收到 broadcast 消息 keys=\(message.keys.sorted())")
                self.handleBroadcastMessage(message)
            }
            TeamRelayLogger.log("broadcast 监听任务结束")
        }

        presenceTask = Task { [weak self] in
            TeamRelayLogger.log("presence 监听任务启动")
            for await action in channel.presenceChange() {
                guard let self else { continue }
                let joinCount = (try? action.decodeJoins(as: TeamPresencePayload.self))?.count ?? 0
                let leaveCount = (try? action.decodeLeaves(as: TeamPresencePayload.self))?.count ?? 0
                TeamRelayLogger.log("presenceChange joins=\(joinCount) leaves=\(leaveCount)")
                self.handlePresenceChange(action)
            }
            TeamRelayLogger.log("presence 监听任务结束")
        }

        statusTask = Task { [weak self] in
            TeamRelayLogger.log("status 监听任务启动")
            for await status in channel.statusChange {
                guard let self else { continue }
                TeamRelayLogger.log("channel.statusChange -> \(status)")
                self.handleStatusChange(status)
            }
            TeamRelayLogger.log("status 监听任务结束")
        }

        TeamRelayLogger.log("subscribeWithError() 开始 channel.status=\(channel.status)")
        do {
            try await channel.subscribeWithError()
            TeamRelayLogger.log("subscribeWithError() 成功 channel.status=\(channel.status)")
        } catch {
            lastError = "频道订阅失败：\(error.localizedDescription)。请在 Supabase SQL Editor 执行 supabase_realtime_policies.sql。"
            TeamRelayLogger.log("失败：subscribeWithError error=\(error)")
            isSubscribed = false
            onConnectionStateChange?(.disconnected)
            await teardownChannel()
            return
        }

        let subscribed = await waitUntilSubscribed(channel: channel, timeoutSeconds: 15)
        TeamRelayLogger.log("waitUntilSubscribed 结果=\(subscribed) 最终 channel.status=\(channel.status)")
        guard subscribed else {
            lastError = "Realtime 频道订阅超时。请确认已执行 supabase_realtime_policies.sql 或开启 Realtime 公共访问。"
            TeamRelayLogger.log("失败：订阅超时")
            isSubscribed = false
            onConnectionStateChange?(.disconnected)
            await teardownChannel()
            return
        }

        do {
            let presence = TeamPresencePayload(
                nickname: nickname,
                clientId: presenceKey
            )
            TeamRelayLogger.log("track(presence) 开始 nickname=\(nickname)")
            try await channel.track(presence)
            isSubscribed = true
            TeamRelayLogger.log("connect 完成 ✅ isSubscribed=true")
            onConnectionStateChange?(.connected)
        } catch {
            lastError = "Presence 上线失败：\(error.localizedDescription)"
            TeamRelayLogger.log("失败：track(presence) error=\(error)")
            isSubscribed = false
            onConnectionStateChange?(.disconnected)
            await teardownChannel()
        }
    }

    func disconnect() {
        TeamRelayLogger.log("disconnect room=\(roomCode ?? "nil")")
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
            await SupabaseClientProvider.shared?.realtimeV2.disconnect()
            TeamRelayLogger.log("disconnect 完成")
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
            do {
                try await channel.broadcast(
                    event: TeamRelayEvents.broadcastUpdate,
                    message: envelope
                )
                TeamRelayLogger.log("broadcast 发送成功 lat=\(payload.lat) lon=\(payload.lon)")
            } catch {
                TeamRelayLogger.log("broadcast 发送失败 error=\(error)")
            }
        }
    }

    // MARK: - Private

    private func waitUntilSubscribed(channel: RealtimeChannelV2, timeoutSeconds: TimeInterval) async -> Bool {
        if channel.status == .subscribed {
            return true
        }

        let deadline = Date().addingTimeInterval(timeoutSeconds)
        var pollCount = 0
        while Date() < deadline {
            pollCount += 1
            if channel.status == .subscribed {
                TeamRelayLogger.log("waitUntilSubscribed 在第 \(pollCount) 次轮询时 subscribed")
                return true
            }
            if channel.status == .unsubscribed {
                TeamRelayLogger.log("waitUntilSubscribed 在第 \(pollCount) 次轮询时 unsubscribed，提前退出")
                return false
            }
            if pollCount % 10 == 0 {
                TeamRelayLogger.log("waitUntilSubscribed 轮询 #\(pollCount) status=\(channel.status)")
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return channel.status == .subscribed
    }

    private func handleBroadcastMessage(_ message: JSONObject) {
        if let envelope = try? message["payload"]?.decode(as: TeamBroadcastEnvelope.self) {
            TeamRelayLogger.log("解析 broadcast envelope from=\(envelope.nickname)")
            onMemberUpdate?(envelope.nickname, envelope.data)
            return
        }

        if let payload = try? message["payload"]?.decode(as: TeamLocationPayload.self),
           let sender = message["from"]?.stringValue ?? nickname {
            TeamRelayLogger.log("解析 broadcast payload from=\(sender)")
            onMemberUpdate?(sender, payload)
        } else {
            TeamRelayLogger.log("无法解析 broadcast 消息")
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
        TeamRelayLogger.log("成员加入 nickname=\(member.nickname) clientId=\(member.clientId)")
        onMemberJoined?(member.nickname)
    }

    private func registerMemberLeave(_ member: TeamPresencePayload) {
        guard knownMemberClientIDs.remove(member.clientId) != nil else { return }
        TeamRelayLogger.log("成员离开 nickname=\(member.nickname)")
        onMemberLeft?(member.nickname)
    }

    private func handleStatusChange(_ status: RealtimeChannelStatus) {
        switch status {
        case .subscribed:
            isSubscribed = true
            onConnectionStateChange?(.connected)
        case .unsubscribed:
            isSubscribed = false
            if lastError == nil {
                lastError = "Realtime 连接已断开"
            }
            TeamRelayLogger.log("channel 变为 unsubscribed lastError=\(lastError ?? "nil")")
            onConnectionStateChange?(.disconnected)
        case .subscribing, .unsubscribing:
            onConnectionStateChange?(.connecting)
        }
    }

    private func teardownChannel() async {
        TeamRelayLogger.log("teardownChannel 开始")
        broadcastTask?.cancel()
        presenceTask?.cancel()
        statusTask?.cancel()
        broadcastTask = nil
        presenceTask = nil
        statusTask = nil

        await channel?.untrack()
        await channel?.unsubscribe()
        channel = nil
        TeamRelayLogger.log("teardownChannel 完成")
    }
}
