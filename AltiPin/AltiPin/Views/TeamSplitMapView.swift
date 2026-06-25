//
//  TeamSplitMapView.swift
//  AltiPin
//
//  多人群组实时大盘：50/50 地图雷达 + 海拔错落曲线
//

import Charts
import CoreLocation
import MapKit
import SwiftUI

// MARK: - Team User Model

struct TeamUser: Identifiable {
    let id: UUID
    let nickname: String
    let color: Color
    var coordinate: CLLocationCoordinate2D
    var elevation: Double
    var lastSeen: Date

    var initial: String {
        String(nickname.prefix(1))
    }

    func secondsSinceLastSeen(at now: Date = .now) -> TimeInterval {
        now.timeIntervalSince(lastSeen)
    }

    func minutesSinceLastSeen(at now: Date = .now) -> Int {
        max(1, Int(secondsSinceLastSeen(at: now) / 60))
    }

    func connectionTier(at now: Date = .now) -> TeamConnectionTier {
        let delta = secondsSinceLastSeen(at: now)
        if delta <= 30 {
            return .online
        } else if delta <= 180 {
            return .weakSignal
        } else {
            return .disconnected
        }
    }
}

enum TeamConnectionTier {
    case online
    case weakSignal
    case disconnected
}

// MARK: - Terrain Sample

struct TerrainSample: Identifiable {
    let id = UUID()
    let distanceKm: Double
    let elevation: Double
}

struct UserElevationMarker: Identifiable {
    let id: UUID
    let nickname: String
    let color: Color
    let distanceKm: Double
    let elevation: Double
    let tier: TeamConnectionTier
}

// MARK: - Team Split Map View

struct TeamSplitMapView: View {
    @State private var users: [TeamUser]
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var selectedUserID: UUID?
    @State private var pulseRing = false

    private let terrainSamples: [TerrainSample]

    init(
        users: [TeamUser] = TeamSplitMapView.mockUsers,
        terrainSamples: [TerrainSample] = TeamSplitMapView.mockTerrain
    ) {
        _users = State(initialValue: users)
        self.terrainSamples = terrainSamples
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                mapSection
                    .frame(height: geometry.size.height * 0.5)

                Divider()

                elevationChartSection
                    .frame(height: geometry.size.height * 0.5)
            }
        }
        .background(Color(.systemBackground))
        .onAppear {
            fitCameraToUsers()
            pulseRing = true
        }
    }

    // MARK: - Map Section

    private var mapSection: some View {
        Map(position: $cameraPosition) {
            ForEach(users) { user in
                Annotation(user.nickname, coordinate: user.coordinate) {
                    userMapMarker(user)
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic))
    }

    @ViewBuilder
    private func userMapMarker(_ user: TeamUser) -> some View {
        let tier = user.connectionTier()

        Button {
            if tier == .disconnected {
                selectedUserID = user.id
            }
        } label: {
            ZStack {
                if tier == .online {
                    Circle()
                        .stroke(user.color.opacity(0.55), lineWidth: 3)
                        .frame(width: 50, height: 50)
                        .scaleEffect(pulseRing ? 1.22 : 1.0)
                        .opacity(pulseRing ? 0.25 : 0.75)
                        .animation(
                            .easeInOut(duration: 1.35).repeatForever(autoreverses: true),
                            value: pulseRing
                        )
                }

                Circle()
                    .fill(tier == .disconnected ? Color.gray : user.color)
                    .frame(width: 38, height: 38)
                    .overlay {
                        Text(user.initial)
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                    }
                    .overlay {
                        Circle()
                            .strokeBorder(
                                tier == .disconnected ? Color.gray.opacity(0.5) : user.color,
                                lineWidth: tier == .online ? 2.5 : 1
                            )
                    }
            }
            .opacity(mapMarkerOpacity(for: tier))
            .grayscale(tier == .disconnected ? 1.0 : 0.0)
        }
        .buttonStyle(.plain)
        .popover(
            isPresented: Binding(
                get: { selectedUserID == user.id && tier == .disconnected },
                set: { if !$0 { selectedUserID = nil } }
            ),
            arrowEdge: .top
        ) {
            Text(L10n.format("Poor signal — last online %lld min ago", user.minutesSinceLastSeen()))
                .font(.subheadline)
                .foregroundStyle(.primary)
                .padding()
                .presentationCompactAdaptation(.popover)
        }
    }

    private func mapMarkerOpacity(for tier: TeamConnectionTier) -> Double {
        switch tier {
        case .online: 1.0
        case .weakSignal: 0.5
        case .disconnected: 0.3
        }
    }

    // MARK: - Elevation Chart Section

    private var elevationChartSection: some View {
        let markers = userElevationMarkers

        return VStack(alignment: .leading, spacing: 10) {
            Text("Team Elevation Alignment")
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.top, 12)

            Chart {
                ForEach(terrainSamples) { sample in
                    AreaMark(
                        x: .value("Distance", sample.distanceKm),
                        y: .value("Elevation", sample.elevation)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color(red: 0.95, green: 0.76, blue: 0.18).opacity(0.72),
                                Color(red: 0.95, green: 0.76, blue: 0.18).opacity(0.04),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)

                    LineMark(
                        x: .value("Distance", sample.distanceKm),
                        y: .value("Elevation", sample.elevation)
                    )
                    .foregroundStyle(Color(red: 0.92, green: 0.72, blue: 0.12))
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.catmullRom)
                }

                ForEach(markers) { marker in
                    PointMark(
                        x: .value("Distance", marker.distanceKm),
                        y: .value("Elevation", marker.elevation)
                    )
                    .foregroundStyle(marker.color)
                    .symbolSize(marker.tier == .disconnected ? 90 : 150)
                    .annotation(position: .top, spacing: 6) {
                        Text("\(marker.nickname) · \(Int(marker.elevation))m")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(marker.color)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.ultraThinMaterial, in: Capsule())
                            .opacity(marker.tier == .disconnected ? 0.35 : 1.0)
                    }
                }
            }
            .chartXAxisLabel("Relative Distance (km)")
            .chartYAxisLabel("Elevation (m)")
            .chartYScale(domain: chartYDomain)
            .chartXScale(domain: chartXDomain)
            .padding(.horizontal, 12)
            .padding(.bottom, 14)
        }
        .background(Color(.secondarySystemBackground))
    }

    private var userElevationMarkers: [UserElevationMarker] {
        users.map { user in
            UserElevationMarker(
                id: user.id,
                nickname: user.nickname,
                color: user.color,
                distanceKm: projectedDistanceKm(for: user),
                elevation: user.elevation,
                tier: user.connectionTier()
            )
        }
    }

    private var chartYDomain: ClosedRange<Double> {
        let elevations = terrainSamples.map(\.elevation) + users.map(\.elevation)
        let minValue = (elevations.min() ?? 0) - 60
        let maxValue = (elevations.max() ?? 1000) + 60
        return minValue...maxValue
    }

    private var chartXDomain: ClosedRange<Double> {
        let maxDistance = terrainSamples.last?.distanceKm ?? 10
        return 0...(maxDistance * 1.05)
    }

    private func projectedDistanceKm(for user: TeamUser) -> Double {
        let maxDistance = terrainSamples.last?.distanceKm ?? 10
        guard users.count > 1 else { return maxDistance * 0.5 }

        let latitudes = users.map(\.coordinate.latitude)
        let longitudes = users.map(\.coordinate.longitude)

        let minLat = latitudes.min() ?? user.coordinate.latitude
        let maxLat = latitudes.max() ?? user.coordinate.latitude
        let minLon = longitudes.min() ?? user.coordinate.longitude
        let maxLon = longitudes.max() ?? user.coordinate.longitude

        let latSpan = max(maxLat - minLat, 0.000_01)
        let lonSpan = max(maxLon - minLon, 0.000_01)

        let latProgress = (user.coordinate.latitude - minLat) / latSpan
        let lonProgress = (user.coordinate.longitude - minLon) / lonSpan
        let blended = (latProgress * 0.55) + (lonProgress * 0.45)

        return blended * maxDistance * 0.92 + maxDistance * 0.04
    }

    // MARK: - Camera

    private func fitCameraToUsers() {
        guard !users.isEmpty else { return }

        let latitudes = users.map(\.coordinate.latitude)
        let longitudes = users.map(\.coordinate.longitude)

        let center = CLLocationCoordinate2D(
            latitude: (latitudes.min()! + latitudes.max()!) / 2,
            longitude: (longitudes.min()! + longitudes.max()!) / 2
        )

        let latDelta = max((latitudes.max()! - latitudes.min()!) * 2.0, 0.018)
        let lonDelta = max((longitudes.max()! - longitudes.min()!) * 2.0, 0.018)

        cameraPosition = .region(
            MKCoordinateRegion(
                center: center,
                span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta)
            )
        )
    }

    // MARK: - Mock Data

    static let mockUsers: [TeamUser] = [
        TeamUser(
            id: UUID(),
            nickname: "阿强",
            color: Color(red: 1.0, green: 0.42, blue: 0.21),
            coordinate: CLLocationCoordinate2D(latitude: 49.2827, longitude: -123.1207),
            elevation: 1240,
            lastSeen: Date().addingTimeInterval(-8)
        ),
        TeamUser(
            id: UUID(),
            nickname: "小李",
            color: Color(red: 0.31, green: 0.80, blue: 0.77),
            coordinate: CLLocationCoordinate2D(latitude: 49.2788, longitude: -123.1158),
            elevation: 1180,
            lastSeen: Date().addingTimeInterval(-68)
        ),
        TeamUser(
            id: UUID(),
            nickname: "老王",
            color: Color(red: 0.61, green: 0.35, blue: 0.71),
            coordinate: CLLocationCoordinate2D(latitude: 49.2754, longitude: -123.1096),
            elevation: 1050,
            lastSeen: Date().addingTimeInterval(-245)
        ),
        TeamUser(
            id: UUID(),
            nickname: "Amy",
            color: Color(red: 0.97, green: 0.86, blue: 0.44),
            coordinate: CLLocationCoordinate2D(latitude: 49.2716, longitude: -123.1038),
            elevation: 980,
            lastSeen: Date().addingTimeInterval(-4)
        ),
    ]

    static let mockTerrain: [TerrainSample] = [
        TerrainSample(distanceKm: 0.0, elevation: 900),
        TerrainSample(distanceKm: 1.0, elevation: 940),
        TerrainSample(distanceKm: 2.1, elevation: 1010),
        TerrainSample(distanceKm: 3.3, elevation: 1080),
        TerrainSample(distanceKm: 4.6, elevation: 1140),
        TerrainSample(distanceKm: 5.8, elevation: 1190),
        TerrainSample(distanceKm: 7.0, elevation: 1230),
        TerrainSample(distanceKm: 8.2, elevation: 1265),
        TerrainSample(distanceKm: 9.5, elevation: 1290),
        TerrainSample(distanceKm: 10.0, elevation: 1305),
    ]
}

// MARK: - Preview

#Preview {
    TeamSplitMapView()
}
