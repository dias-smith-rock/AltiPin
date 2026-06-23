//
//  GroupTrackMapView.swift
//  AltiPin
//

import CoreLocation
import MapKit
import SwiftUI

struct GroupTrackMapView: View {
    let members: [TeamMember]
    let visibleMemberIDs: Set<UUID>
    let selfFallbackPoints: [HistoryPoint]
    let connectionTierRefreshTick: Int
    let memberMetricsRefreshTick: Int

    @State private var cameraPosition: MapCameraPosition = .automatic

    private var visibleMembers: [TeamMember] {
        members.filter { visibleMemberIDs.contains($0.id) }
    }

    private var displayPoints: [HistoryPoint] {
        Array(selfFallbackPoints.suffix(20))
    }

    var body: some View {
        Group {
            if members.isEmpty {
                soloMapView
            } else {
                teamMapView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .onAppear { updateCamera() }
        .onChange(of: members.map(\.id)) { _, _ in updateCamera() }
        .onChange(of: membersSignature) { _, _ in updateCamera() }
        .onChange(of: visibleMemberIDs) { _, _ in updateCamera() }
        .onChange(of: connectionTierRefreshTick) { _, _ in }
        .onChange(of: memberMetricsRefreshTick) { _, _ in }
    }

    private var membersSignature: String {
        members.map {
            "\($0.id.uuidString):\($0.currentCoordinate.latitude):\($0.currentCoordinate.longitude):\($0.recentPoints.count):\($0.sessionDuration)"
        }
        .joined(separator: "|")
    }

    // MARK: - Solo Fallback

    private var soloMapView: some View {
        Map(position: $cameraPosition) {
            if !displayPoints.isEmpty {
                MapPolyline(coordinates: displayPoints.map(\.coordinate))
                    .stroke(AltitudeTheme.accent, lineWidth: 4)

                if let start = displayPoints.first {
                    Annotation("起点", coordinate: start.coordinate, anchor: .center) {
                        Image(systemName: "play.circle.fill")
                            .font(.title3)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, AltitudeTheme.accent)
                    }
                }

                if let end = displayPoints.last {
                    Annotation("当前位置", coordinate: end.coordinate, anchor: .center) {
                        Image(systemName: "location.north.flash.fill")
                            .font(.title3)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(AltitudeTheme.accent, .white.opacity(0.9))
                    }
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic, emphasis: .muted))
        .mapControlVisibility(.hidden)
    }

    // MARK: - Team Map

    private var teamMapView: some View {
        Map(position: $cameraPosition) {
            ForEach(visibleMembers) { member in
                if member.hasValidCoordinate {
                    if member.recentPoints.count >= 2 {
                        MapPolyline(coordinates: member.recentPoints.map(\.coordinate))
                            .stroke(member.color, lineWidth: member.isSelf ? 5 : 3.5)
                    }

                    if let start = member.recentPoints.first, member.recentPoints.count >= 2 {
                        Annotation("\(member.nickname) 起点", coordinate: start.coordinate, anchor: .center) {
                            Image(systemName: "play.circle.fill")
                                .font(.caption)
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, member.color.opacity(0.9))
                        }
                    }

                    Annotation(member.nickname, coordinate: member.currentCoordinate, anchor: .top) {
                        memberMarkerStack(member)
                    }
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic, emphasis: .muted))
        .mapControlVisibility(.hidden)
    }

    @ViewBuilder
    private func memberMarkerStack(_ member: TeamMember) -> some View {
        VStack(spacing: 4) {
            memberAvatar(member)
            memberMetricsBadge(member)
        }
    }

    @ViewBuilder
    private func memberAvatar(_ member: TeamMember) -> some View {
        let tier = member.connectionTier()

        ZStack {
            Circle()
                .fill(tier == .disconnected ? Color.gray : member.color)
                .frame(width: member.isSelf ? 40 : 34, height: member.isSelf ? 40 : 34)
                .overlay {
                    Text(member.initial)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                }
                .overlay {
                    Circle()
                        .strokeBorder(Color.white.opacity(0.85), lineWidth: member.isSelf ? 2 : 1)
                }
        }
        .opacity(markerOpacity(for: tier))
        .grayscale(tier == .disconnected ? 1 : 0)
    }

    private func memberMetricsBadge(_ member: TeamMember) -> some View {
        VStack(spacing: 2) {
            Text(String(format: "%.1f km/h", member.speedKmh))
            Text(member.formattedDuration)
            Text(String(format: "%.1f km", member.distanceMeters / 1000))
        }
        .font(.system(size: 9, weight: .semibold, design: .rounded))
        .monospacedDigit()
        .foregroundStyle(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black.opacity(0.78))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(member.color.opacity(0.65), lineWidth: 1)
        )
    }

    private func markerOpacity(for tier: TeamConnectionTier) -> Double {
        switch tier {
        case .online: 1.0
        case .weakSignal: 0.55
        case .disconnected: 0.35
        }
    }

    // MARK: - Camera

    private func updateCamera() {
        let coordinates: [CLLocationCoordinate2D]
        if members.isEmpty {
            coordinates = displayPoints.map(\.coordinate)
        } else {
            coordinates = visibleMembers.flatMap { member -> [CLLocationCoordinate2D] in
                guard member.hasValidCoordinate else { return [] }
                return member.recentPoints.map(\.coordinate) + [member.currentCoordinate]
            }
        }
        guard !coordinates.isEmpty else { return }
        cameraPosition = Self.cameraPosition(for: coordinates)
    }

    private static func cameraPosition(for coordinates: [CLLocationCoordinate2D]) -> MapCameraPosition {
        guard !coordinates.isEmpty else { return .automatic }

        if coordinates.count == 1, let coordinate = coordinates.first {
            return .region(
                MKCoordinateRegion(
                    center: coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.004, longitudeDelta: 0.004)
                )
            )
        }

        var rect = MKMapRect.null
        for coordinate in coordinates {
            let point = MKMapPoint(coordinate)
            rect = rect.union(MKMapRect(x: point.x, y: point.y, width: 1, height: 1))
        }

        let paddingFactor = 0.35
        return .rect(
            rect.insetBy(
                dx: -rect.size.width * paddingFactor,
                dy: -rect.size.height * paddingFactor
            )
        )
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        GroupTrackMapView(
            members: [],
            visibleMemberIDs: [],
            selfFallbackPoints: HistoryPoint.mockPoints,
            connectionTierRefreshTick: 0,
            memberMetricsRefreshTick: 0
        )
    }
}
