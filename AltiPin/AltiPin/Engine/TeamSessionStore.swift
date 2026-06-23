//
//  TeamSessionStore.swift
//  AltiPin
//

import Combine
import CoreLocation
import Foundation

@MainActor
final class TeamSessionStore: ObservableObject {
    @Published private(set) var roomCode: String?
    @Published private(set) var members: [TeamMember] = []
    @Published var visibleMemberIDs: Set<UUID> = []
    @Published private(set) var connectionState: TeamConnectionState = .idle
    @Published private(set) var lastConnectionError: String?
    @Published private(set) var selfLocationSyncNonce = 0
    @Published private(set) var connectionTierRefreshTick = 0
    @Published private(set) var memberMetricsRefreshTick = 0
    @Published private(set) var isRoomCreator = false
    @Published private(set) var pendingSessionSyncAction: TeamSessionSyncAction?
    @Published var showBecameHostAlert = false

    private let relay: TeamRelayClient
    private let maxRecentPoints = 20
    private var selfMemberID: UUID?
    private var hostClientId: String?
    private var roomRefreshTimer: Timer?

    init() {
        self.relay = Self.makeDefaultRelay()
        configureRelayHandlers()
    }

    init(relay: TeamRelayClient) {
        self.relay = relay
        configureRelayHandlers()
    }

    var isInRoom: Bool {
        roomCode != nil
    }

    /// 当前房间内的队员人数（Presence 在房即计入，与位置刷新间隔无关）。
    var onlineMemberCount: Int {
        members.count
    }

    var visibleMembers: [TeamMember] {
        members.filter { visibleMemberIDs.contains($0.id) }
    }

    /// 入队后是否可操控运动会话（仅创建者；加入者只读看数据）。
    var canControlActivitySession: Bool {
        !isInRoom || isRoomCreator
    }

    var leaveButtonTitle: String {
        "退出"
    }

    var leaveConfirmationTitle: String {
        "退出队伍"
    }

    var leaveConfirmationMessage: String {
        if isRoomCreator {
            if members.count > 1 {
                return "退出后房主将自动移交给下一位队员，其余成员可继续组队。"
            }
            return "退出后你将离开房间。"
        }
        return "退出后将离开当前队伍。"
    }

    func createRoom(nickname: String) async {
        let code = Self.generateRoomCode()
        TeamRelayLogger.session("createRoom 请求 nickname=\(nickname) generatedCode=\(code)")
        await joinRoom(code: code, nickname: nickname, isCreator: true)
    }

    func join(roomCode: String, nickname: String) async {
        let normalized = roomCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count == 4, normalized.allSatisfy(\.isNumber) else {
            TeamRelayLogger.session("join 拒绝：无效房间码 raw=\(roomCode)")
            return
        }
        TeamRelayLogger.session("join 请求 room=\(normalized) nickname=\(nickname)")
        await joinRoom(code: normalized, nickname: nickname, isCreator: false)
    }

    func leaveRoom() async {
        let code = roomCode ?? "nil"
        let memberCount = members.count
        let nicknames = members.map(\.nickname).joined(separator: ",")
        TeamRelayLogger.session("leaveRoom room=\(code) members=\(memberCount) [\(nicknames)]")

        if isRoomCreator, memberCount > 1, let nextHost = nextHostMember() {
            let payload = TeamHostTransferPayload(
                newHostClientId: nextHost.clientId,
                newHostNickname: nextHost.nickname,
                previousHostClientId: relay.localClientId,
                issuedAt: Date().timeIntervalSince1970,
                announcePromotion: true
            )
            TeamRelayLogger.session(
                "leaveRoom 转让房主 -> \(nextHost.nickname) clientId=\(nextHost.clientId)"
            )
            await relay.sendHostTransfer(payload)
        }

        abandonRoom()
        TeamRelayLogger.session("leaveRoom 完成 state=idle")
    }

    func acknowledgeBecameHostAlert() {
        showBecameHostAlert = false
    }

    @discardableResult
    func updateSelfNickname(_ rawNickname: String) async -> String? {
        guard isInRoom, let selfID = selfMemberID else { return nil }
        let trimmed = rawNickname.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let index = members.firstIndex(where: { $0.id == selfID }) else { return nil }

        var member = members[index]
        member.nickname = trimmed
        replaceMember(at: index, with: member)

        guard let clientId = relay.localClientId, !clientId.isEmpty else { return trimmed }
        let payload = TeamNicknameUpdatePayload(
            clientId: clientId,
            nickname: trimmed,
            issuedAt: Date().timeIntervalSince1970
        )
        TeamRelayLogger.session("updateSelfNickname -> \(trimmed)")
        await relay.sendNicknameUpdate(payload)
        return trimmed
    }

    func ingestSelfSnapshot(from store: OutdoorDashboardStore) {
        guard isInRoom, let selfID = selfMemberID,
              let index = members.firstIndex(where: { $0.id == selfID }) else {
            return
        }

        var member = members[index]
        let points = store.recentHistoryPoints
        if !points.isEmpty {
            member.recentPoints = Array(points.suffix(maxRecentPoints))
        }

        member.speedKmh = store.speedKmh
        member.sessionDuration = store.sessionDuration
        member.distanceMeters = store.cumulativeDistanceMeters
        member.activityPhase = store.activitySessionPhase

        let payload = makeLocationPayload(from: store)

        if store.latitude != 0 || store.longitude != 0 {
            member.currentCoordinate = CLLocationCoordinate2D(
                latitude: store.latitude,
                longitude: store.longitude
            )
            member.elevation = store.elevationMeters
            member.lastSeen = .now
            replaceMember(at: index, with: member)
            relay.sendLocationUpdate(payload)
        } else if let last = member.recentPoints.last {
            member.currentCoordinate = last.coordinate
            member.elevation = last.elevation
            member.lastSeen = .now
            replaceMember(at: index, with: member)
            relay.sendLocationUpdate(payload)
        } else {
            replaceMember(at: index, with: member)
            relay.sendLocationUpdate(payload)
        }
    }

    func broadcastSessionSync(_ action: TeamSessionSyncAction, nickname: String) {
        guard isInRoom, isRoomCreator else { return }
        let payload = TeamSessionSyncPayload(
            action: action,
            nickname: nickname,
            clientId: relay.localClientId,
            issuedAt: Date().timeIntervalSince1970
        )
        TeamRelayLogger.session("broadcastSessionSync action=\(action.rawValue)")
        relay.sendSessionSync(payload)
    }

    func acknowledgeSessionSync() {
        pendingSessionSyncAction = nil
    }

    private func makeLocationPayload(from store: OutdoorDashboardStore) -> TeamLocationPayload {
        let lat = store.latitude != 0 || store.longitude != 0
            ? store.latitude
            : (members.first(where: { $0.isSelf })?.currentCoordinate.latitude ?? 0)
        let lon = store.latitude != 0 || store.longitude != 0
            ? store.longitude
            : (members.first(where: { $0.isSelf })?.currentCoordinate.longitude ?? 0)
        let ele = store.latitude != 0 || store.longitude != 0
            ? store.elevationMeters
            : (members.first(where: { $0.isSelf })?.elevation ?? 0)

        return TeamLocationPayload(
            lon: lon,
            lat: lat,
            ele: ele,
            timestamp: Date().timeIntervalSince1970,
            speedKmh: store.speedKmh,
            sessionDuration: store.sessionDuration,
            distanceMeters: store.cumulativeDistanceMeters,
            activityPhase: store.activitySessionPhase.rawValue
        )
    }

    /// 保留旧名以兼容调用方。
    func ingestSelfLocation(from store: OutdoorDashboardStore) {
        ingestSelfSnapshot(from: store)
    }

    func toggleMemberVisibility(_ memberID: UUID) {
        if visibleMemberIDs.contains(memberID) {
            visibleMemberIDs.remove(memberID)
        } else {
            visibleMemberIDs.insert(memberID)
        }
    }

    func selectAll() {
        visibleMemberIDs = Set(members.map(\.id))
    }

    func deselectAll() {
        visibleMemberIDs = []
    }

    #if DEBUG
    /// 模拟器 Debug：本地 mock 宿主房间（不连接 Supabase），定位香港大围附近。
    func configureDebugSimulatorHostIfNeeded(nickname: String) {
        #if targetEnvironment(simulator)
        guard !isInRoom else { return }

        let track = DebugTeamFixtures.taiWaiMockTrack()
        guard let latest = track.last else { return }

        let selfMember = TeamMember(
            id: UUID(),
            clientId: "debug-simulator-host",
            nickname: nickname,
            color: TeamMember.color(for: 0),
            isSelf: true,
            recentPoints: track,
            currentCoordinate: latest.coordinate,
            elevation: latest.elevation,
            lastSeen: .now
        )

        selfMemberID = selfMember.id
        roomCode = DebugTeamFixtures.roomCode
        isRoomCreator = true
        hostClientId = selfMember.clientId
        members = [selfMember]
        visibleMemberIDs = [selfMember.id]
        connectionState = .connected
        lastConnectionError = nil
        startRoomRefreshTimers()

        TeamRelayLogger.session(
            "debug simulator host mock room=\(DebugTeamFixtures.roomCode) " +
            "nickname=\(nickname) " +
            TeamRelayLogger.formatCoordinate(lat: latest.latitude, lon: latest.longitude, ele: latest.elevation)
        )
        #endif
    }
    #endif

    // MARK: - Private

    private static func makeDefaultRelay() -> TeamRelayClient {
        SupabaseTeamRelay()
    }

    private func joinRoom(code: String, nickname: String, isCreator: Bool) async {
        lastConnectionError = nil
        connectionState = .connecting
        roomCode = code
        isRoomCreator = isCreator

        TeamRelayLogger.session("joinRoom 开始 code=\(code) nickname=\(nickname) isCreator=\(isCreator)")

        let selfMember = TeamMember(
            id: UUID(),
            clientId: "",
            nickname: nickname,
            color: TeamMember.color(for: 0),
            isSelf: true,
            recentPoints: [],
            currentCoordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            elevation: 0,
            lastSeen: .now
        )
        selfMemberID = selfMember.id
        members = [selfMember]
        visibleMemberIDs = [selfMember.id]
        TeamRelayLogger.session("joinRoom 本地成员已创建 selfId=\(selfMember.id.uuidString.prefix(8))")

        await relay.connect(roomCode: code, nickname: nickname)

        TeamRelayLogger.session(
            "joinRoom relay.connect 返回 state=\(connectionState) " +
            "relayError=\(relay.lastError ?? "nil")"
        )

        if connectionState != .connected {
            lastConnectionError = relay.lastError
                ?? (TeamRelayConfiguration.isSupabaseConfigured
                    ? "无法连接组队服务，请检查网络后重试"
                    : "Supabase 未正确配置，请检查 AltiPin.xcconfig 中的 SUPABASE_PROJECT_REF")
            TeamRelayLogger.session("joinRoom 失败，即将 abandonRoom error=\(lastConnectionError ?? "nil")")
            abandonRoom()
        } else {
            applyLocalClientIdToSelfMember()
            if isCreator, let clientId = relay.localClientId {
                hostClientId = clientId
            }
            startRoomRefreshTimers()
            requestSelfLocationSync()
            TeamRelayLogger.session("joinRoom 成功 ✅ room=\(roomCode ?? "nil") members=\(members.count)")
        }
    }

    private func configureRelayHandlers() {
        relay.onConnectionStateChange = { [weak self] state in
            TeamRelayLogger.session("connectionState 变更 -> \(state)")
            self?.connectionState = state
        }

        relay.onMemberJoined = { [weak self] presence in
            TeamRelayLogger.presence(
                "onMemberJoined 回调 nickname=\(presence.nickname) clientId=\(presence.clientId)"
            )
            self?.addRemoteMemberIfNeeded(presence: presence)
            self?.requestSelfLocationSync()
            if self?.isRoomCreator == true {
                self?.broadcastHostState(announcePromotion: false)
            }
        }

        relay.onMemberUpdate = { [weak self] envelope in
            self?.applyRemoteUpdate(envelope: envelope)
        }

        relay.onMemberLeft = { [weak self] clientId in
            TeamRelayLogger.presence("onMemberLeft 回调 clientId=\(clientId)")
            self?.removeMember(clientId: clientId)
        }

        relay.onHostTransfer = { [weak self] payload in
            self?.applyHostTransfer(payload)
        }

        relay.onNicknameUpdate = { [weak self] payload in
            guard let self else { return }
            if let localId = relay.localClientId, payload.clientId == localId { return }
            applyRemoteNicknameUpdate(clientId: payload.clientId, nickname: payload.nickname)
        }

        relay.onSessionSync = { [weak self] payload in
            guard let self else { return }
            if let localId = relay.localClientId, payload.clientId == localId { return }
            TeamRelayLogger.session(
                "onSessionSync action=\(payload.action.rawValue) from=\(payload.nickname)"
            )
            pendingSessionSyncAction = payload.action
        }
    }

    private func addRemoteMemberIfNeeded(presence: TeamPresencePayload) {
        guard !members.contains(where: { $0.clientId == presence.clientId && !$0.isSelf }) else {
            TeamRelayLogger.presence("addRemoteMember 跳过：已存在 clientId=\(presence.clientId)")
            return
        }

        let memberIndex = members.count
        let member = TeamMember(
            id: UUID(),
            clientId: presence.clientId,
            nickname: presence.nickname,
            color: TeamMember.color(for: memberIndex),
            isSelf: false,
            recentPoints: [],
            currentCoordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            elevation: 0,
            lastSeen: .now
        )
        members.append(member)
        visibleMemberIDs.insert(member.id)
        TeamRelayLogger.presence(
            "addRemoteMember 成功 nickname=\(presence.nickname) clientId=\(presence.clientId) " +
            "id=\(member.id.uuidString.prefix(8)) totalMembers=\(members.count)"
        )
    }

    private func applyRemoteUpdate(envelope: TeamBroadcastEnvelope) {
        let clientId = envelope.clientId ?? ""
        let nickname = envelope.nickname
        let payload = envelope.data

        if let index = memberIndex(forRemoteClientId: clientId, nickname: nickname) {
            updateMember(at: index, payload: payload)
            return
        }

        if !clientId.isEmpty || !members.contains(where: { $0.nickname == nickname && !$0.isSelf }) {
            TeamRelayLogger.location(
                "remote 更新时自动建成员 nickname=\(nickname) clientId=\(clientId.isEmpty ? "nil" : clientId)"
            )
            let memberIndex = members.count
            let member = TeamMember(
                id: UUID(),
                clientId: clientId.isEmpty ? "unknown-\(UUID().uuidString)" : clientId,
                nickname: nickname,
                color: TeamMember.color(for: memberIndex),
                isSelf: false,
                recentPoints: [],
                currentCoordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                elevation: 0,
                lastSeen: .now
            )
            members.append(member)
            visibleMemberIDs.insert(member.id)
            updateMember(at: members.count - 1, payload: payload)
        }
    }

    private func memberIndex(forRemoteClientId clientId: String, nickname: String) -> Int? {
        if !clientId.isEmpty,
           let index = members.firstIndex(where: { $0.clientId == clientId && !$0.isSelf }) {
            return index
        }
        return members.firstIndex(where: { $0.nickname == nickname && !$0.isSelf })
    }

    private func updateMember(at index: Int, payload: TeamLocationPayload) {
        var member = members[index]
        let nickname = member.nickname
        let pointCountBefore = member.recentPoints.count

        let locationChanged = abs(member.currentCoordinate.latitude - payload.lat) > 0.000_01
            || abs(member.currentCoordinate.longitude - payload.lon) > 0.000_01
            || !member.hasValidCoordinate

        if locationChanged {
            let point = HistoryPoint(
                timestamp: Date(timeIntervalSince1970: payload.timestamp ?? Date().timeIntervalSince1970),
                latitude: payload.lat,
                longitude: payload.lon,
                elevation: payload.ele
            )
            member.currentCoordinate = point.coordinate
            member.elevation = payload.ele
            member.recentPoints.append(point)
            if member.recentPoints.count > maxRecentPoints {
                member.recentPoints.removeFirst(member.recentPoints.count - maxRecentPoints)
            }
        }

        if let speedKmh = payload.speedKmh { member.speedKmh = speedKmh }
        if let sessionDuration = payload.sessionDuration { member.sessionDuration = sessionDuration }
        if let distanceMeters = payload.distanceMeters { member.distanceMeters = distanceMeters }
        if let phaseRaw = payload.activityPhase,
           let phase = ActivitySessionPhase(rawValue: phaseRaw) {
            member.activityPhase = phase
        }
        member.lastSeen = .now
        replaceMember(at: index, with: member)
        TeamRelayLogger.location(
            "remote 更新 nickname=\(nickname) " +
            "speed=\(String(format: "%.1f", member.speedKmh))km/h " +
            "dur=\(member.formattedDuration) " +
            "dist=\(String(format: "%.1f", member.distanceMeters / 1000))km " +
            "points=\(pointCountBefore)->\(member.recentPoints.count)",
            throttleKey: "remote-location-\(member.clientId)",
            throttleSeconds: 5
        )
    }

    private func removeMember(clientId: String) {
        let departingWasHost = clientId == hostClientId
        guard let member = members.first(where: { $0.clientId == clientId && !$0.isSelf }) else {
            TeamRelayLogger.presence("removeMember 跳过：未找到 clientId=\(clientId)")
            if departingWasHost {
                promoteNextHostAfterDeparture(announcePromotion: true)
            }
            return
        }
        visibleMemberIDs.remove(member.id)
        members.removeAll { $0.id == member.id }
        TeamRelayLogger.presence(
            "removeMember 成功 nickname=\(member.nickname) clientId=\(clientId) remaining=\(members.count)"
        )
        if departingWasHost {
            promoteNextHostAfterDeparture(announcePromotion: true)
        }
    }

    private func replaceMember(at index: Int, with member: TeamMember) {
        var updated = members
        updated[index] = member
        members = updated
    }

    private func applyLocalClientIdToSelfMember() {
        guard let clientId = relay.localClientId,
              let selfID = selfMemberID,
              let index = members.firstIndex(where: { $0.id == selfID }) else {
            return
        }
        var member = members[index]
        member.clientId = clientId
        replaceMember(at: index, with: member)
    }

    private func requestSelfLocationSync() {
        selfLocationSyncNonce += 1
    }

    private func startRoomRefreshTimers() {
        stopRoomRefreshTimers()
        var tierTick = 0
        roomRefreshTimer = Timer.scheduledTimer(
            withTimeInterval: TeamRelayConfiguration.metricsUpdateInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                memberMetricsRefreshTick += 1
                tierTick += 1
                if tierTick >= 20 {
                    tierTick = 0
                    connectionTierRefreshTick += 1
                }
            }
        }
    }

    private func stopRoomRefreshTimers() {
        roomRefreshTimer?.invalidate()
        roomRefreshTimer = nil
        connectionTierRefreshTick = 0
        memberMetricsRefreshTick = 0
    }

    private func abandonRoom() {
        stopRoomRefreshTimers()
        relay.disconnect()
        roomCode = nil
        members = []
        visibleMemberIDs = []
        selfMemberID = nil
        hostClientId = nil
        isRoomCreator = false
        connectionState = .idle
        lastConnectionError = nil
        showBecameHostAlert = false
    }

    private func nextHostMember() -> TeamMember? {
        members.first(where: { !$0.isSelf && !$0.clientId.isEmpty })
    }

    private func broadcastHostState(announcePromotion: Bool) {
        guard isInRoom, isRoomCreator,
              let clientId = relay.localClientId,
              let selfMember = members.first(where: \.isSelf) else {
            return
        }
        let payload = TeamHostTransferPayload(
            newHostClientId: clientId,
            newHostNickname: selfMember.nickname,
            previousHostClientId: clientId,
            issuedAt: Date().timeIntervalSince1970,
            announcePromotion: announcePromotion
        )
        Task {
            await relay.sendHostTransfer(payload)
        }
    }

    private func applyHostTransfer(_ payload: TeamHostTransferPayload) {
        guard isInRoom else { return }
        let wasAlreadyHost = isRoomCreator && relay.localClientId == payload.newHostClientId
        hostClientId = payload.newHostClientId
        let becameHost = relay.localClientId == payload.newHostClientId
        isRoomCreator = becameHost
        TeamRelayLogger.session(
            "applyHostTransfer newHost=\(payload.newHostNickname) " +
            "becameHost=\(becameHost) announce=\(payload.announcePromotion)"
        )
        if becameHost, payload.announcePromotion, !wasAlreadyHost {
            showBecameHostAlert = true
        }
    }

    private func applyRemoteNicknameUpdate(clientId: String, nickname: String) {
        guard let index = members.firstIndex(where: { $0.clientId == clientId }) else {
            TeamRelayLogger.session("applyRemoteNicknameUpdate 跳过：未找到 clientId=\(clientId)")
            return
        }
        var member = members[index]
        member.nickname = nickname
        replaceMember(at: index, with: member)
        TeamRelayLogger.session(
            "applyRemoteNicknameUpdate clientId=\(clientId) nickname=\(nickname)"
        )
    }

    private func promoteNextHostAfterDeparture(announcePromotion: Bool) {
        guard isInRoom, let nextHost = nextHostMember() else {
            hostClientId = nil
            isRoomCreator = false
            return
        }
        let wasAlreadyHost = isRoomCreator && relay.localClientId == nextHost.clientId
        hostClientId = nextHost.clientId
        let becameHost = relay.localClientId == nextHost.clientId
        isRoomCreator = becameHost
        TeamRelayLogger.session(
            "promoteNextHostAfterDeparture -> \(nextHost.nickname) becameHost=\(becameHost)"
        )
        if becameHost, announcePromotion, !wasAlreadyHost {
            showBecameHostAlert = true
        }
    }

    private static func generateRoomCode() -> String {
        String(format: "%04d", Int.random(in: 0...9999))
    }
}
