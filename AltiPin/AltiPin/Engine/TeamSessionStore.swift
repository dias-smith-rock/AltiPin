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

    private let relay: TeamRelayClient
    private let maxRecentPoints = 20
    private var selfMemberID: UUID?

    init() {
        self.relay = MockTeamRelay()
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
    }

    func ingestSelfLocation(from store: OutdoorDashboardStore) {
        guard isInRoom, let selfID = selfMemberID,
              let index = members.firstIndex(where: { $0.id == selfID }) else { return }

        let points = store.recentHistoryPoints
        if !points.isEmpty {
            members[index].recentPoints = Array(points.suffix(maxRecentPoints))
        } else if members[index].recentPoints.isEmpty {
            #if DEBUG
            #if targetEnvironment(simulator)
            members[index].recentPoints = HistoryPoint.mockPoints
            #endif
            #endif
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

    // MARK: - Private

    private func joinRoom(code: String, nickname: String, isCreator: Bool) async {
        connectionState = .connecting
        roomCode = code

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
        connectionState = .connected

        _ = isCreator
    }

    private func configureRelayHandlers() {
        relay.onMemberJoined = { [weak self] nickname in
            self?.addMockMemberIfNeeded(nickname: nickname)
        }

        relay.onMemberUpdate = { [weak self] nickname, payload in
            self?.applyRemoteUpdate(nickname: nickname, payload: payload)
        }

        relay.onMemberLeft = { [weak self] nickname in
            self?.removeMember(nickname: nickname)
        }
    }

    private func addMockMemberIfNeeded(nickname: String) {
        guard !members.contains(where: { $0.nickname == nickname }) else { return }

        let memberIndex = members.count
        let baseLatitude = 22.3678 + Double(memberIndex) * 0.002
        let baseLongitude = 114.1817 + Double(memberIndex) * 0.002
        let points = Self.makeMemberTrailPoints(
            baseLatitude: baseLatitude,
            baseLongitude: baseLongitude
        )
        let lastPoint = points.last
        let fallbackCoordinate = CLLocationCoordinate2D(
            latitude: baseLatitude,
            longitude: baseLongitude
        )

        let member = TeamMember(
            id: UUID(),
            nickname: nickname,
            color: TeamMember.color(for: memberIndex),
            isSelf: false,
            recentPoints: points,
            currentCoordinate: lastPoint?.coordinate ?? fallbackCoordinate,
            elevation: lastPoint?.elevation ?? 60,
            lastSeen: .now
        )
        members.append(member)
        visibleMemberIDs.insert(member.id)
    }

    private func applyRemoteUpdate(nickname: String, payload: TeamLocationPayload) {
        guard let index = members.firstIndex(where: { $0.nickname == nickname && !$0.isSelf }) else {
            if !members.contains(where: { $0.nickname == nickname }) {
                addMockMemberIfNeeded(nickname: nickname)
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

    private static func makeMemberTrailPoints(
        baseLatitude: Double,
        baseLongitude: Double
    ) -> [HistoryPoint] {
        var points: [HistoryPoint] = []
        points.reserveCapacity(6)
        for index in 0..<6 {
            points.append(
                HistoryPoint(
                    timestamp: Date().addingTimeInterval(Double(index - 6) * 20),
                    latitude: baseLatitude + Double(index) * 0.0005,
                    longitude: baseLongitude + Double(index) * 0.0004,
                    elevation: 60 + Double(index) * 3
                )
            )
        }
        return points
    }
}
