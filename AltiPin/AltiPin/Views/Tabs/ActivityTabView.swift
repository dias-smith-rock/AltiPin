//
//  ActivityTabView.swift
//  AltiPin
//

import SwiftUI

struct ActivityTabView: View {
    @ObservedObject var store: OutdoorDashboardStore
    @StateObject private var teamSession = TeamSessionStore()
    @AppStorage("activityNickname") private var activityNickname = ""

    @State private var showFaceToFaceSheet = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                GroupTrackMapView(
                    members: teamSession.isInRoom ? teamSession.members : [],
                    visibleMemberIDs: teamSession.visibleMemberIDs,
                    selfFallbackPoints: store.recentHistoryPoints
                )

                VStack(spacing: 0) {
                    if teamSession.isInRoom {
                        MemberFilterBar(teamSession: teamSession)
                    }

                    Spacer()

                    metricsOverlay
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                }
            }
            .background(Color.black)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ActivityTeamHeader(
                    teamSession: teamSession,
                    onFaceToFaceTapped: { showFaceToFaceSheet = true },
                    onLeaveTapped: { teamSession.leaveRoom() }
                )
            }
            .sheet(isPresented: $showFaceToFaceSheet) {
                FaceToFaceTeamSheet(
                    teamSession: teamSession,
                    nickname: $activityNickname
                )
            }
            .onAppear {
                ensureNickname()
                syncSelfLocation()
            }
            .onChange(of: store.recentHistoryPoints) { _, _ in
                syncSelfLocation()
            }
            .onChange(of: store.latitude) { _, _ in
                syncSelfLocation()
            }
            .onChange(of: store.longitude) { _, _ in
                syncSelfLocation()
            }
            .onChange(of: teamSession.isInRoom) { _, isInRoom in
                if isInRoom {
                    syncSelfLocation()
                }
            }
        }
    }

    // MARK: - Sync

    private func syncSelfLocation() {
        teamSession.ingestSelfLocation(from: store)
    }

    private func ensureNickname() {
        if activityNickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            activityNickname = "徒步者\(Int.random(in: 100...999))"
        }
    }

    // MARK: - Metrics Overlay

    private var metricsOverlay: some View {
        HStack(spacing: 10) {
            metricPill(
                title: "速度",
                value: String(format: "%.1f", store.speedKmh),
                unit: "km/h"
            )
            metricPill(
                title: "时长",
                value: durationText,
                unit: nil
            )
            metricPill(
                title: "行程",
                value: String(format: "%.1f", store.cumulativeDistanceMeters / 1000),
                unit: "km"
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black.opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }

    private func metricPill(title: String, value: String, unit: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(AltitudeTheme.accent)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                if let unit {
                    Text(unit)
                        .font(.caption2)
                        .foregroundStyle(.gray)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var durationText: String {
        let totalSeconds = max(0, Int(store.sessionDuration.rounded()))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

#Preview {
    ActivityTabView(store: OutdoorDashboardStore.preview())
}
