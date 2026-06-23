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

    private let relay: TeamRelayClient
    private let maxRecentPoints = 20
    private var selfMemberID: UUID?

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

    var onlineMemberCount: Int {
        members.filter { $0.connectionTier() == .online }.count
    }

    var visibleMembers: [TeamMember] {
        members.filter { visibleMemberIDs.contains($0.id) }
    }

    func createRoom(nickname: String) async {
        let code = Self.generateRoomCode()
        await joinRoom(code: code, nickname: nickname, isCreator: true)
    }

    func join(roomCode: String, nickname: String) async {
        let normalized = roomCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count == 4, normalized.allSatisfy(\.isNumber) else { return }
        await joinRoom(code: normalized, nickname: nickname, isCreator: false)
    }

    func leaveRoom() {
        relay.disconnect()
        roomCode = nil
        members = []
        visibleMemberIDs = []
        selfMemberID = nil
        connectionState = .idle
        lastConnectionError = nil
    }

    func ingestSelfLocation(from store: OutdoorDashboardStore) {
        guard isInRoom, let selfID = selfMemberID,
              let index = members.firstIndex(where: { $0.id == selfID }) else { return }

        let points = store.recentHistoryPoints
        if !points.isEmpty {
            members[index].recentPoints = Array(points.suffix(maxRecentPoints))
        }

        if store.latitude != 0 || store.longitude != 0 {
            members[index].currentCoordinate = CLLocationCoordinate2D(
                latitude: store.latitude,
                longitude: store.longitude
            )
            members[index].elevation = store.elevationMeters
            members[index].lastSeen = .now

            relay.sendLocationUpdate(
                TeamLocationPayload(
                    lon: store.longitude,
                    lat: store.latitude,
                    ele: store.elevationMeters,
                    timestamp: Date().timeIntervalSince1970
                )
            )
        } else if let last = members[index].recentPoints.last {
            members[index].currentCoordinate = last.coordinate
            members[index].elevation = last.elevation
            members[index].lastSeen = .now
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

        TeamRelayLogger.log(
            "debug simulator host mock room=\(DebugTeamFixtures.roomCode) " +
            "at \(String(format: "%.4f", latest.latitude)),\(String(format: "%.4f", latest.longitude))"
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

        TeamRelayLogger.log("joinRoom 开始 code=\(code) nickname=\(nickname) isCreator=\(isCreator)")

        let selfMember = TeamMember(
            id: UUID(),
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

        await relay.connect(roomCode: code, nickname: nickname)

        TeamRelayLogger.log("joinRoom relay.connect 返回 connectionState=\(connectionState) relay.lastError=\(relay.lastError ?? "nil")")

        if connectionState != .connected {
            lastConnectionError = relay.lastError
                ?? (TeamRelayConfiguration.isSupabaseConfigured
                    ? "无法连接组队服务，请检查网络后重试"
                    : "Supabase 未正确配置，请检查 AltiPin.xcconfig 中的 SUPABASE_PROJECT_REF")
            TeamRelayLogger.log("joinRoom 失败，即将 leaveRoom error=\(lastConnectionError ?? "nil")")
            leaveRoom()
        } else {
            TeamRelayLogger.log("joinRoom 成功 ✅ roomCode=\(roomCode ?? "nil") members=\(members.count)")
        }

        _ = isCreator
    }

    private func configureRelayHandlers() {
        relay.onConnectionStateChange = { [weak self] state in
            TeamRelayLogger.log("connectionState 变更 -> \(state)")
            self?.connectionState = state
        }

        relay.onMemberJoined = { [weak self] nickname in
            self?.addRemoteMemberIfNeeded(nickname: nickname)
        }

        relay.onMemberUpdate = { [weak self] nickname, payload in
            self?.applyRemoteUpdate(nickname: nickname, payload: payload)
        }

        relay.onMemberLeft = { [weak self] nickname in
            self?.removeMember(nickname: nickname)
        }
    }

    private func addRemoteMemberIfNeeded(nickname: String) {
        guard !members.contains(where: { $0.nickname == nickname }) else { return }

        let memberIndex = members.count
        let member = TeamMember(
            id: UUID(),
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
    }

    private func applyRemoteUpdate(nickname: String, payload: TeamLocationPayload) {
        guard let index = members.firstIndex(where: { $0.nickname == nickname && !$0.isSelf }) else {
            if !members.contains(where: { $0.nickname == nickname }) {
                addRemoteMemberIfNeeded(nickname: nickname)
            }
            guard let idx = members.firstIndex(where: { $0.nickname == nickname }) else { return }
            updateMember(at: idx, payload: payload)
            return
        }
        updateMember(at: index, payload: payload)
    }

    private func updateMember(at index: Int, payload: TeamLocationPayload) {
        let point = HistoryPoint(
            timestamp: Date(timeIntervalSince1970: payload.timestamp ?? Date().timeIntervalSince1970),
            latitude: payload.lat,
            longitude: payload.lon,
            elevation: payload.ele
        )
        members[index].currentCoordinate = point.coordinate
        members[index].elevation = payload.ele
        members[index].lastSeen = .now
        members[index].recentPoints.append(point)
        if members[index].recentPoints.count > maxRecentPoints {
            members[index].recentPoints.removeFirst(members[index].recentPoints.count - maxRecentPoints)
        }
    }

    private func removeMember(nickname: String) {
        guard let member = members.first(where: { $0.nickname == nickname && !$0.isSelf }) else { return }
        visibleMemberIDs.remove(member.id)
        members.removeAll { $0.id == member.id }
    }

    private static func generateRoomCode() -> String {
        String(format: "%04d", Int.random(in: 0...9999))
    }
}
