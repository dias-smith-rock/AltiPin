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

    private let relay: TeamRelayClient
    private let maxRecentPoints = 20
    private var selfMemberID: UUID?
    private var tierRefreshTimer: Timer?

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

    func leaveRoom() {
        let code = roomCode ?? "nil"
        let memberCount = members.count
        let nicknames = members.map(\.nickname).joined(separator: ",")
        TeamRelayLogger.session("leaveRoom room=\(code) members=\(memberCount) [\(nicknames)]")
        stopConnectionTierRefresh()
        relay.disconnect()
        roomCode = nil
        members = []
        visibleMemberIDs = []
        selfMemberID = nil
        connectionState = .idle
        lastConnectionError = nil
        TeamRelayLogger.session("leaveRoom 完成 state=idle")
    }

    func ingestSelfLocation(from store: OutdoorDashboardStore) {
        guard isInRoom, let selfID = selfMemberID,
              let index = members.firstIndex(where: { $0.id == selfID }) else {
            return
        }

        var member = members[index]
        let points = store.recentHistoryPoints
        if !points.isEmpty {
            member.recentPoints = Array(points.suffix(maxRecentPoints))
        }

        if store.latitude != 0 || store.longitude != 0 {
            member.currentCoordinate = CLLocationCoordinate2D(
                latitude: store.latitude,
                longitude: store.longitude
            )
            member.elevation = store.elevationMeters
            member.lastSeen = .now

            let payload = TeamLocationPayload(
                lon: store.longitude,
                lat: store.latitude,
                ele: store.elevationMeters,
                timestamp: Date().timeIntervalSince1970
            )
            TeamRelayLogger.location(
                "self 上报 room=\(roomCode ?? "nil") \(TeamRelayLogger.formatCoordinate(lat: payload.lat, lon: payload.lon, ele: payload.ele))",
                throttleKey: "self-location-\(roomCode ?? "")",
                throttleSeconds: 5
            )
            replaceMember(at: index, with: member)
            relay.sendLocationUpdate(payload)
        } else if let last = member.recentPoints.last {
            member.currentCoordinate = last.coordinate
            member.elevation = last.elevation
            member.lastSeen = .now
            TeamRelayLogger.location(
                "self 无 GPS，使用末条历史点 \(TeamRelayLogger.formatCoordinate(lat: last.latitude, lon: last.longitude, ele: last.elevation))",
                throttleKey: "self-fallback-\(roomCode ?? "")",
                throttleSeconds: 10
            )
            replaceMember(at: index, with: member)
        } else if !points.isEmpty {
            replaceMember(at: index, with: member)
        }
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
        members = [selfMember]
        visibleMemberIDs = [selfMember.id]
        connectionState = .connected
        lastConnectionError = nil
        startConnectionTierRefresh()

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
            TeamRelayLogger.session("joinRoom 失败，即将 leaveRoom error=\(lastConnectionError ?? "nil")")
            leaveRoom()
        } else {
            applyLocalClientIdToSelfMember()
            startConnectionTierRefresh()
            requestSelfLocationSync()
            TeamRelayLogger.session("joinRoom 成功 ✅ room=\(roomCode ?? "nil") members=\(members.count)")
        }

        _ = isCreator
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
        }

        relay.onMemberUpdate = { [weak self] envelope in
            self?.applyRemoteUpdate(envelope: envelope)
        }

        relay.onMemberLeft = { [weak self] clientId in
            TeamRelayLogger.presence("onMemberLeft 回调 clientId=\(clientId)")
            self?.removeMember(clientId: clientId)
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
        let point = HistoryPoint(
            timestamp: Date(timeIntervalSince1970: payload.timestamp ?? Date().timeIntervalSince1970),
            latitude: payload.lat,
            longitude: payload.lon,
            elevation: payload.ele
        )
        member.currentCoordinate = point.coordinate
        member.elevation = payload.ele
        member.lastSeen = .now
        member.recentPoints.append(point)
        if member.recentPoints.count > maxRecentPoints {
            member.recentPoints.removeFirst(member.recentPoints.count - maxRecentPoints)
        }
        replaceMember(at: index, with: member)
        TeamRelayLogger.location(
            "remote 更新 nickname=\(nickname) \(TeamRelayLogger.formatCoordinate(lat: payload.lat, lon: payload.lon, ele: payload.ele)) " +
            "points=\(pointCountBefore)->\(member.recentPoints.count)",
            throttleKey: "remote-location-\(member.clientId)",
            throttleSeconds: 5
        )
    }

    private func removeMember(clientId: String) {
        guard let member = members.first(where: { $0.clientId == clientId && !$0.isSelf }) else {
            TeamRelayLogger.presence("removeMember 跳过：未找到 clientId=\(clientId)")
            return
        }
        visibleMemberIDs.remove(member.id)
        members.removeAll { $0.id == member.id }
        TeamRelayLogger.presence(
            "removeMember 成功 nickname=\(member.nickname) clientId=\(clientId) remaining=\(members.count)"
        )
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

    private func startConnectionTierRefresh() {
        stopConnectionTierRefresh()
        tierRefreshTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.connectionTierRefreshTick += 1
            }
        }
    }

    private func stopConnectionTierRefresh() {
        tierRefreshTimer?.invalidate()
        tierRefreshTimer = nil
        connectionTierRefreshTick = 0
    }

    private static func generateRoomCode() -> String {
        String(format: "%04d", Int.random(in: 0...9999))
    }
}
