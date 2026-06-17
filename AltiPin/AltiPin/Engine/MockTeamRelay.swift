//
//  MockTeamRelay.swift
//  AltiPin
//

import CoreLocation
import Foundation

@MainActor
final class MockTeamRelay: TeamRelayClient {
    var onMemberUpdate: ((String, TeamLocationPayload) -> Void)?
    var onMemberJoined: ((String) -> Void)?
    var onMemberLeft: ((String) -> Void)?

    private var roomCode: String?
    private var nickname: String?
    private var mockTimer: Timer?
    private var mockMembers: [MockMemberState] = []

    private struct MockMemberState {
        let nickname: String
        var latitude: Double
        var longitude: Double
        var elevation: Double
        var recentPoints: [HistoryPoint]
    }

    func connect(roomCode: String, nickname: String) async {
        self.roomCode = roomCode
        self.nickname = nickname
        seedMockMembers(roomCode: roomCode, excluding: nickname)
        startMockUpdates()
    }

    func disconnect() {
        mockTimer?.invalidate()
        mockTimer = nil
        mockMembers = []
        roomCode = nil
        nickname = nil
    }

    func sendLocationUpdate(_ payload: TeamLocationPayload) {
        // Mock relay accepts self updates silently.
    }

    private func seedMockMembers(roomCode: String, excluding selfNickname: String) {
        let baseLatitude = 22.3678
        let baseLongitude = 114.1817
        let mockNames = ["阿强", "小李", "老王", "Amy"]

        mockMembers = mockNames.enumerated().map { index, name in
            let offset = Double(index + 1) * 0.002
            let startDate = Date().addingTimeInterval(-Double(index + 2) * 60)
            let points = Self.makeTrailPoints(
                startDate: startDate,
                baseLatitude: baseLatitude + offset,
                baseLongitude: baseLongitude + offset,
                index: index
            )
            let last = points.last
            return MockMemberState(
                nickname: name,
                latitude: last?.latitude ?? baseLatitude + offset,
                longitude: last?.longitude ?? baseLongitude + offset,
                elevation: last?.elevation ?? 64,
                recentPoints: points
            )
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self else { return }
            for member in self.mockMembers.prefix(2) {
                self.onMemberJoined?(member.nickname)
                if let last = member.recentPoints.last {
                    self.onMemberUpdate?(
                        member.nickname,
                        TeamLocationPayload(
                            lon: last.longitude,
                            lat: last.latitude,
                            ele: last.elevation,
                            timestamp: last.timestamp.timeIntervalSince1970
                        )
                    )
                }
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self else { return }
            for member in self.mockMembers.dropFirst(2) {
                self.onMemberJoined?(member.nickname)
            }
        }

        _ = roomCode
        _ = selfNickname
    }

    private func startMockUpdates() {
        mockTimer?.invalidate()
        mockTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tickMockMovement()
            }
        }
    }

    private func tickMockMovement() {
        for index in mockMembers.indices {
            let deltaLat = Double.random(in: -0.00015...0.00015)
            let deltaLon = Double.random(in: -0.00015...0.00015)
            let deltaEle = Double.random(in: -0.5...1.2)

            mockMembers[index].latitude += deltaLat
            mockMembers[index].longitude += deltaLon
            mockMembers[index].elevation += deltaEle

            let point = HistoryPoint(
                timestamp: .now,
                latitude: mockMembers[index].latitude,
                longitude: mockMembers[index].longitude,
                elevation: mockMembers[index].elevation
            )
            mockMembers[index].recentPoints.append(point)
            if mockMembers[index].recentPoints.count > 20 {
                mockMembers[index].recentPoints.removeFirst(
                    mockMembers[index].recentPoints.count - 20
                )
            }

            onMemberUpdate?(
                mockMembers[index].nickname,
                TeamLocationPayload(
                    lon: mockMembers[index].longitude,
                    lat: mockMembers[index].latitude,
                    ele: mockMembers[index].elevation,
                    timestamp: point.timestamp.timeIntervalSince1970
                )
            )
        }
    }

    private static func makeTrailPoints(
        startDate: Date,
        baseLatitude: Double,
        baseLongitude: Double,
        index: Int
    ) -> [HistoryPoint] {
        var points: [HistoryPoint] = []
        points.reserveCapacity(8)
        for pointIndex in 0..<8 {
            points.append(
                HistoryPoint(
                    timestamp: startDate.addingTimeInterval(Double(pointIndex) * 15),
                    latitude: baseLatitude + Double(pointIndex) * 0.0008,
                    longitude: baseLongitude + Double(pointIndex) * 0.0006,
                    elevation: 64 + Double(pointIndex) * 2 + Double(index) * 3
                )
            )
        }
        return points
    }
}
