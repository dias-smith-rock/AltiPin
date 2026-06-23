//
//  SupabaseTeamRelay.swift
//  AltiPin
//

import Foundation
import Supabase

@MainActor
final class SupabaseTeamRelay: TeamRelayClient {
    private(set) var lastError: String?
    var localClientId: String? { clientId?.uuidString }

    var onMemberUpdate: ((TeamBroadcastEnvelope) -> Void)?
    var onMemberJoined: ((TeamPresencePayload) -> Void)?
    var onMemberLeft: ((String) -> Void)?
    var onSessionSync: ((TeamSessionSyncPayload) -> Void)?
    var onHostTransfer: ((TeamHostTransferPayload) -> Void)?
    var onConnectionStateChange: ((TeamConnectionState) -> Void)?

    private var channel: RealtimeChannelV2?
    private var clientId: UUID?
    private var nickname: String?
    private var roomCode: String?
    private var broadcastTask: Task<Void, Never>?
    private var presenceTask: Task<Void, Never>?
    private var statusTask: Task<Void, Never>?
    private var sessionSyncTask: Task<Void, Never>?
    private var hostTransferTask: Task<Void, Never>?
    private var lastSentAt: Date?
    private var isSubscribed = false
    private var knownMemberClientIDs = Set<String>()
    private var pendingLocationPayload: TeamLocationPayload?

    func connect(roomCode: String, nickname: String) async {
        lastError = nil
        TeamRelayLogger.relay("connect 开始 room=\(roomCode) nickname=\(nickname)")

        guard TeamRelayConfiguration.isSupabaseConfigured else {
            lastError = "Supabase 未配置。请在 AltiPin.xcconfig 填写 SUPABASE_PROJECT_REF 与 anon key，并确认 Supabase-Info.plist 已合并进 Info.plist。"
            TeamRelayLogger.relay("失败：Supabase 未正确配置")
            onConnectionStateChange?(.disconnected)
            return
        }

        guard let client = SupabaseClientProvider.shared else {
            lastError = "无法初始化 Supabase 客户端，请检查 URL 与 anon key 是否来自同一项目。"
            TeamRelayLogger.relay("失败：SupabaseClient 为 nil")
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
        TeamRelayLogger.relay("topic=\(topic) clientId=\(presenceKey) isPrivate=false")

        TeamRelayLogger.relay("realtimeV2.connect() 前 status=\(client.realtimeV2.status)")
        await client.realtimeV2.connect()
        TeamRelayLogger.relay("realtimeV2.connect() 后 status=\(client.realtimeV2.status)")

        guard client.realtimeV2.status == .connected else {
            lastError = "Realtime WebSocket 连接失败，请检查网络与 Supabase 项目状态。"
            TeamRelayLogger.relay("失败：WebSocket 未 connected，status=\(client.realtimeV2.status)")
            onConnectionStateChange?(.disconnected)
            return
        }

        let channel = client.realtimeV2.channel(topic) { config in
            config.isPrivate = false
            config.presence.key = presenceKey
            config.broadcast.receiveOwnBroadcasts = false
        }
        self.channel = channel
        TeamRelayLogger.relay("channel 已创建，开始注册 broadcast/presence/status 监听")

        // 必须在 subscribe 之前同步创建 stream（注册回调），否则 presence 不会在 phx_join 中启用。
        let broadcastStream = channel.broadcastStream(event: TeamRelayEvents.broadcastUpdate)
        let presenceStream = channel.presenceChange()
        let statusStream = channel.statusChange
        let sessionSyncStream = channel.broadcastStream(event: TeamRelayEvents.sessionSync)
        let hostTransferStream = channel.broadcastStream(event: TeamRelayEvents.hostTransfer)

        broadcastTask = Task { [weak self] in
            TeamRelayLogger.relay("broadcast 监听任务启动 event=\(TeamRelayEvents.broadcastUpdate)")
            for await message in broadcastStream {
                guard let self else { continue }
                TeamRelayLogger.relay("收到 broadcast 消息 keys=\(message.keys.sorted())")
                self.handleBroadcastMessage(message)
            }
            TeamRelayLogger.relay("broadcast 监听任务结束")
        }

        presenceTask = Task { [weak self] in
            TeamRelayLogger.relay("presence 监听任务启动")
            for await action in presenceStream {
                guard let self else { continue }
                self.handlePresenceChange(action)
            }
            TeamRelayLogger.relay("presence 监听任务结束")
        }

        statusTask = Task { [weak self] in
            TeamRelayLogger.relay("status 监听任务启动")
            for await status in statusStream {
                guard let self else { continue }
                TeamRelayLogger.relay("channel.statusChange -> \(status)")
                self.handleStatusChange(status)
            }
            TeamRelayLogger.relay("status 监听任务结束")
        }

        sessionSyncTask = Task { [weak self] in
            TeamRelayLogger.relay("sessionSync 监听任务启动 event=\(TeamRelayEvents.sessionSync)")
            for await message in sessionSyncStream {
                guard let self else { continue }
                self.handleSessionSyncMessage(message)
            }
            TeamRelayLogger.relay("sessionSync 监听任务结束")
        }

        hostTransferTask = Task { [weak self] in
            TeamRelayLogger.relay("hostTransfer 监听任务启动 event=\(TeamRelayEvents.hostTransfer)")
            for await message in hostTransferStream {
                guard let self else { continue }
                self.handleHostTransferMessage(message)
            }
            TeamRelayLogger.relay("hostTransfer 监听任务结束")
        }

        TeamRelayLogger.relay("subscribeWithError() 开始 channel.status=\(channel.status)")
        do {
            try await channel.subscribeWithError()
            TeamRelayLogger.relay("subscribeWithError() 成功 channel.status=\(channel.status)")
        } catch {
            lastError = "频道订阅失败：\(error.localizedDescription)。请在 Supabase SQL Editor 执行 supabase_realtime_policies.sql。"
            TeamRelayLogger.relay("失败：subscribeWithError error=\(error)")
            isSubscribed = false
            onConnectionStateChange?(.disconnected)
            await teardownChannel()
            return
        }

        let subscribed = await waitUntilSubscribed(channel: channel, timeoutSeconds: 15)
        TeamRelayLogger.relay("waitUntilSubscribed 结果=\(subscribed) 最终 channel.status=\(channel.status)")
        guard subscribed else {
            lastError = "Realtime 频道订阅超时。请确认已执行 supabase_realtime_policies.sql 或开启 Realtime 公共访问。"
            TeamRelayLogger.relay("失败：订阅超时")
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
            TeamRelayLogger.relay("track(presence) 开始 nickname=\(nickname)")
            try await channel.track(presence)
            isSubscribed = true
            lastError = nil
            TeamRelayLogger.relay("connect 完成 ✅ isSubscribed=true")
            onConnectionStateChange?(.connected)
            flushPendingLocationIfNeeded()
        } catch {
            lastError = "Presence 上线失败：\(error.localizedDescription)"
            TeamRelayLogger.relay("失败：track(presence) error=\(error)")
            isSubscribed = false
            onConnectionStateChange?(.disconnected)
            await teardownChannel()
        }
    }

    func disconnect() {
        TeamRelayLogger.relay("disconnect room=\(roomCode ?? "nil")")
        isSubscribed = false
        broadcastTask?.cancel()
        presenceTask?.cancel()
        statusTask?.cancel()
        sessionSyncTask?.cancel()
        hostTransferTask?.cancel()
        broadcastTask = nil
        presenceTask = nil
        statusTask = nil
        sessionSyncTask = nil
        hostTransferTask = nil

        let activeChannel = channel
        channel = nil
        clientId = nil
        nickname = nil
        roomCode = nil
        lastSentAt = nil
        pendingLocationPayload = nil
        knownMemberClientIDs.removeAll()

        Task {
            await activeChannel?.untrack()
            await activeChannel?.unsubscribe()
            await SupabaseClientProvider.shared?.realtimeV2.disconnect()
            TeamRelayLogger.relay("disconnect 完成")
        }
    }

    func sendLocationUpdate(_ payload: TeamLocationPayload) {
        guard isSubscribed,
              let channel,
              let nickname else {
            pendingLocationPayload = payload
            TeamRelayLogger.location(
                "broadcast 跳过：未订阅 room=\(roomCode ?? "nil")，已缓存待发送",
                throttleKey: "broadcast-skip-not-subscribed",
                throttleSeconds: 10
            )
            return
        }

        sendLocationUpdateNow(payload, channel: channel, nickname: nickname)
    }

    func sendSessionSync(_ payload: TeamSessionSyncPayload) {
        guard isSubscribed, let channel else { return }
        Task {
            do {
                try await channel.broadcast(
                    event: TeamRelayEvents.sessionSync,
                    message: payload
                )
                TeamRelayLogger.session("sessionSync 发送成功 action=\(payload.action.rawValue)")
            } catch {
                TeamRelayLogger.relay("sessionSync 发送失败 error=\(error)")
            }
        }
    }

    func sendHostTransfer(_ payload: TeamHostTransferPayload) async {
        guard isSubscribed, let channel else { return }
        do {
            try await channel.broadcast(
                event: TeamRelayEvents.hostTransfer,
                message: payload
            )
            TeamRelayLogger.session(
                "hostTransfer 发送成功 newHost=\(payload.newHostNickname) " +
                "clientId=\(payload.newHostClientId) announce=\(payload.announcePromotion)"
            )
        } catch {
            TeamRelayLogger.relay("hostTransfer 发送失败 error=\(error)")
        }
    }

    private func sendLocationUpdateNow(
        _ payload: TeamLocationPayload,
        channel: RealtimeChannelV2,
        nickname: String
    ) {
        let now = Date()
        if let lastSentAt,
           now.timeIntervalSince(lastSentAt) < TeamRelayConfiguration.metricsUpdateInterval {
            return
        }
        lastSentAt = now

        var outbound = payload
        if outbound.timestamp == nil {
            outbound.timestamp = now.timeIntervalSince1970
        }

        let envelope = TeamBroadcastEnvelope(
            nickname: nickname,
            clientId: clientId?.uuidString,
            data: outbound
        )

        Task {
            do {
                try await channel.broadcast(
                    event: TeamRelayEvents.broadcastUpdate,
                    message: envelope
                )
                TeamRelayLogger.location(
                    "broadcast 发送成功 from=\(nickname) \(TeamRelayLogger.formatCoordinate(lat: payload.lat, lon: payload.lon, ele: payload.ele))",
                    throttleKey: "broadcast-sent-\(roomCode ?? "")",
                    throttleSeconds: 5
                )
            } catch {
                TeamRelayLogger.relay("broadcast 发送失败 error=\(error)")
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
                TeamRelayLogger.relay("waitUntilSubscribed 在第 \(pollCount) 次轮询时 subscribed")
                return true
            }
            if channel.status == .unsubscribed {
                TeamRelayLogger.relay("waitUntilSubscribed 在第 \(pollCount) 次轮询时 unsubscribed，提前退出")
                return false
            }
            if pollCount % 10 == 0 {
                TeamRelayLogger.relay("waitUntilSubscribed 轮询 #\(pollCount) status=\(channel.status)")
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return channel.status == .subscribed
    }

    private func handleBroadcastMessage(_ message: JSONObject) {
        if let envelope = try? message["payload"]?.decode(as: TeamBroadcastEnvelope.self) {
            TeamRelayLogger.relay("解析 broadcast envelope from=\(envelope.nickname) clientId=\(envelope.clientId ?? "nil")")
            onMemberUpdate?(envelope)
            return
        }

        if let payload = try? message["payload"]?.decode(as: TeamLocationPayload.self),
           let sender = message["from"]?.stringValue ?? nickname {
            TeamRelayLogger.relay("解析 broadcast payload from=\(sender)")
            onMemberUpdate?(
                TeamBroadcastEnvelope(nickname: sender, clientId: nil, data: payload)
            )
        } else {
            TeamRelayLogger.relay("无法解析 broadcast 消息")
        }
    }

    private func handleSessionSyncMessage(_ message: JSONObject) {
        if let payload = try? message["payload"]?.decode(as: TeamSessionSyncPayload.self) {
            TeamRelayLogger.session("收到 sessionSync action=\(payload.action.rawValue) from=\(payload.nickname)")
            onSessionSync?(payload)
            return
        }
        if let payload = try? message.decode(as: TeamSessionSyncPayload.self) {
            onSessionSync?(payload)
        } else {
            TeamRelayLogger.relay("无法解析 sessionSync 消息")
        }
    }

    private func handleHostTransferMessage(_ message: JSONObject) {
        if let payload = try? message["payload"]?.decode(as: TeamHostTransferPayload.self) {
            TeamRelayLogger.session(
                "收到 hostTransfer newHost=\(payload.newHostNickname) " +
                "clientId=\(payload.newHostClientId) announce=\(payload.announcePromotion)"
            )
            onHostTransfer?(payload)
            return
        }
        if let payload = try? message.decode(as: TeamHostTransferPayload.self) {
            onHostTransfer?(payload)
        } else {
            TeamRelayLogger.relay("无法解析 hostTransfer 消息")
        }
    }

    private func handlePresenceChange(_ action: any PresenceAction) {
        let rawJoinCount = action.joins.count
        let rawLeaveCount = action.leaves.count
        TeamRelayLogger.relay("presenceChange raw joins=\(rawJoinCount) leaves=\(rawLeaveCount)")

        if let joins = try? action.decodeJoins(as: TeamPresencePayload.self) {
            TeamRelayLogger.relay("presenceChange decoded joins=\(joins.count)")
            for member in joins {
                registerMemberJoin(member)
            }
        } else {
            TeamRelayLogger.relay("presence decodeJoins 失败，尝试逐个解析")
            for presence in action.joins.values {
                if let member = try? presence.decodeState(as: TeamPresencePayload.self) {
                    registerMemberJoin(member)
                }
            }
        }

        if let leaves = try? action.decodeLeaves(as: TeamPresencePayload.self) {
            for member in leaves {
                registerMemberLeave(member)
            }
        } else {
            for presence in action.leaves.values {
                if let member = try? presence.decodeState(as: TeamPresencePayload.self) {
                    registerMemberLeave(member)
                }
            }
        }
    }

    private func registerMemberJoin(_ member: TeamPresencePayload) {
        guard member.clientId != clientId?.uuidString else { return }
        guard knownMemberClientIDs.insert(member.clientId).inserted else { return }
        TeamRelayLogger.presence("成员加入 nickname=\(member.nickname) clientId=\(member.clientId)")
        onMemberJoined?(member)
    }

    private func registerMemberLeave(_ member: TeamPresencePayload) {
        guard knownMemberClientIDs.remove(member.clientId) != nil else { return }
        TeamRelayLogger.presence("成员离开 nickname=\(member.nickname) clientId=\(member.clientId)")
        onMemberLeft?(member.clientId)
    }

    private func handleStatusChange(_ status: RealtimeChannelStatus) {
        switch status {
        case .subscribed:
            isSubscribed = true
            onConnectionStateChange?(.connected)
        case .unsubscribed:
            let wasLive = isSubscribed
            isSubscribed = false
            if wasLive {
                if lastError == nil {
                    lastError = "Realtime 连接已断开"
                }
                TeamRelayLogger.relay("channel 变为 unsubscribed lastError=\(lastError ?? "nil")")
                onConnectionStateChange?(.disconnected)
            } else {
                TeamRelayLogger.relay("channel 初始/过渡状态 unsubscribed（忽略）")
            }
        case .subscribing, .unsubscribing:
            onConnectionStateChange?(.connecting)
        }
    }

    private func teardownChannel() async {
        TeamRelayLogger.relay("teardownChannel 开始")
        broadcastTask?.cancel()
        presenceTask?.cancel()
        statusTask?.cancel()
        sessionSyncTask?.cancel()
        hostTransferTask?.cancel()
        broadcastTask = nil
        presenceTask = nil
        statusTask = nil
        sessionSyncTask = nil
        hostTransferTask = nil

        await channel?.untrack()
        await channel?.unsubscribe()
        channel = nil
        TeamRelayLogger.relay("teardownChannel 完成")
    }

    private func flushPendingLocationIfNeeded() {
        guard let pendingLocationPayload,
              let channel,
              let nickname else {
            return
        }
        self.pendingLocationPayload = nil
        lastSentAt = nil
        TeamRelayLogger.location("broadcast 刷新缓存的待发送位置")
        sendLocationUpdateNow(pendingLocationPayload, channel: channel, nickname: nickname)
    }
}
