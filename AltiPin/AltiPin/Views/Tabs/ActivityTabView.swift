//
//  ActivityTabView.swift
//  AltiPin
//

import Combine
import SwiftUI
import UIKit

struct ActivityTabView: View {
    @ObservedObject var store: OutdoorDashboardStore
    @StateObject private var teamSession = TeamSessionStore()
    @AppStorage("activityNickname") private var activityNickname = ""

    @State private var showFaceToFaceSheet = false
    @State private var isMapFullscreen = false
    @State private var showResetConfirmation = false
    @State private var showLeaveConfirmation = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                GroupTrackMapView(
                    members: teamSession.isInRoom ? teamSession.members : [],
                    visibleMemberIDs: teamSession.visibleMemberIDs,
                    selfFallbackPoints: store.recentHistoryPoints,
                    connectionTierRefreshTick: teamSession.connectionTierRefreshTick,
                    memberMetricsRefreshTick: teamSession.memberMetricsRefreshTick
                )
                .ignoresSafeArea(edges: isMapFullscreen ? [.top, .bottom] : [])
                .simultaneousGesture(
                    TapGesture().onEnded {
                        toggleMapFullscreen()
                    }
                )

                if !isMapFullscreen {
                    VStack(spacing: 0) {
                        if teamSession.isInRoom {
                            MemberFilterBar(
                                teamSession: teamSession,
                                activityNickname: $activityNickname
                            )
                        }

                        Spacer()

                        VStack(spacing: 10) {
                            if !teamSession.isInRoom {
                                metricsOverlay
                            }
                            if teamSession.canControlActivitySession {
                                sessionControlBar
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                    }
                    .transition(.opacity)
                }
            }
            .background(Color.black)
            .animation(.easeInOut(duration: 0.22), value: isMapFullscreen)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(isMapFullscreen ? .hidden : .visible, for: .navigationBar)
            .toolbar(isMapFullscreen ? .hidden : .visible, for: .tabBar)
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarBackground(isMapFullscreen ? .hidden : .visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                if !isMapFullscreen {
                    ActivityTeamHeader(
                        teamSession: teamSession,
                        onFaceToFaceTapped: {
                            TeamRelayLogger.ui("点击「面对面组队」")
                            showFaceToFaceSheet = true
                        },
                        onLeaveTapped: {
                            TeamRelayLogger.ui(
                                "点击「\(teamSession.leaveButtonTitle)」room=\(teamSession.roomCode ?? "nil")"
                            )
                            showLeaveConfirmation = true
                        }
                    )
                }
            }
            .confirmationDialog(
                teamSession.leaveConfirmationTitle,
                isPresented: $showLeaveConfirmation,
                titleVisibility: .visible
            ) {
                Button(teamSession.leaveButtonTitle, role: .destructive) {
                    TeamRelayLogger.ui(
                        "确认\(teamSession.leaveButtonTitle) room=\(teamSession.roomCode ?? "nil")"
                    )
                    Task {
                        await teamSession.leaveRoom()
                    }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text(teamSession.leaveConfirmationMessage)
            }
            .alert("你自动成为房主", isPresented: $teamSession.showBecameHostAlert) {
                Button("好的", role: .cancel) {
                    teamSession.acknowledgeBecameHostAlert()
                }
            } message: {
                Text("原房主已退出，你已接管队伍控制。")
            }
            .confirmationDialog(
                "重置运动会话",
                isPresented: $showResetConfirmation,
                titleVisibility: .visible
            ) {
                Button("重置", role: .destructive) {
                    resetTeamActivity()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("将同步重置所有成员的速度、时长与行程数据。")
            }
            .sheet(isPresented: $showFaceToFaceSheet) {
                FaceToFaceTeamSheet(
                    teamSession: teamSession,
                    nickname: $activityNickname
                )
            }
            .onAppear {
                ensureNickname()
                #if DEBUG
                applyDebugSimulatorSetupIfNeeded()
                #endif
                syncSelfSnapshot()
            }
            .onDisappear {
                isMapFullscreen = false
            }
            .onChange(of: store.recentHistoryPoints) { _, _ in
                syncSelfSnapshot()
            }
            .onChange(of: store.latitude) { _, _ in
                syncSelfSnapshot()
            }
            .onChange(of: store.longitude) { _, _ in
                syncSelfSnapshot()
            }
            .onChange(of: teamSession.isInRoom) { _, isInRoom in
                TeamRelayLogger.ui("isInRoom 变更 -> \(isInRoom) room=\(teamSession.roomCode ?? "nil")")
                if isInRoom {
                    syncSelfSnapshot()
                }
            }
            .onChange(of: teamSession.selfLocationSyncNonce) { _, _ in
                syncSelfSnapshot()
            }
            .onChange(of: teamSession.pendingSessionSyncAction) { _, action in
                guard let action else { return }
                applyRemoteSessionSync(action)
                teamSession.acknowledgeSessionSync()
            }
            .onReceive(
                Timer.publish(
                    every: TeamRelayConfiguration.metricsUpdateInterval,
                    on: .main,
                    in: .common
                ).autoconnect()
            ) { _ in
                guard teamSession.isInRoom else { return }
                syncSelfSnapshot()
            }
        }
    }

    // MARK: - Sync

    private func syncSelfSnapshot() {
        teamSession.ingestSelfSnapshot(from: store)
    }

    private func applyRemoteSessionSync(_ action: TeamSessionSyncAction) {
        switch action {
        case .start:
            store.startActivitySession()
        case .pause:
            store.pauseActivitySession()
        case .reset:
            store.resetActivitySession()
        }
    }

    private func startTeamActivity() {
        store.startActivitySession()
        if teamSession.isInRoom, teamSession.isRoomCreator {
            teamSession.broadcastSessionSync(.start, nickname: activityNickname)
        }
    }

    private func pauseTeamActivity() {
        store.pauseActivitySession()
        if teamSession.isInRoom, teamSession.isRoomCreator {
            teamSession.broadcastSessionSync(.pause, nickname: activityNickname)
        }
    }

    private func resetTeamActivity() {
        store.resetActivitySession()
        if teamSession.isInRoom, teamSession.isRoomCreator {
            teamSession.broadcastSessionSync(.reset, nickname: activityNickname)
        }
    }

    private func ensureNickname() {
        if activityNickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            activityNickname = "徒步者\(Int.random(in: 100...999))"
        }
    }

    private func toggleMapFullscreen() {
        UISelectionFeedbackGenerator().selectionChanged()
        isMapFullscreen.toggle()
    }

    #if DEBUG
    private func applyDebugSimulatorSetupIfNeeded() {
        #if targetEnvironment(simulator)
        // 仅注入模拟 GPS，不自动创建本地假房间（假房间不走 Supabase，队友无法收到位置广播）。
        store.applyDebugSimulatorTeamLocationIfNeeded()
        #endif
    }
    #endif

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

    private var sessionControlBar: some View {
        HStack(spacing: 10) {
            sessionButton(
                title: startButtonTitle,
                systemImage: "play.fill",
                isEnabled: store.activitySessionPhase != .running,
                fill: AltitudeTheme.accent.opacity(0.92)
            ) {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                startTeamActivity()
            }

            if showsPauseControl {
                sessionButton(
                    title: "暂停",
                    systemImage: "pause.fill",
                    isEnabled: store.activitySessionPhase == .running,
                    fill: Color.orange.opacity(0.88)
                ) {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    pauseTeamActivity()
                }
            }

            sessionButton(
                title: "重置",
                systemImage: "arrow.counterclockwise",
                isEnabled: canResetActivitySession,
                fill: Color.white.opacity(0.14)
            ) {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                if teamSession.isInRoom, teamSession.isRoomCreator {
                    showResetConfirmation = true
                } else {
                    resetTeamActivity()
                }
            }
        }
    }

    private var showsPauseControl: Bool {
        !teamSession.isInRoom || !teamSession.isRoomCreator
    }

    private var startButtonTitle: String {
        if showsPauseControl, store.activitySessionPhase == .paused {
            return "继续"
        }
        return "开始"
    }

    private var canResetActivitySession: Bool {
        store.activitySessionPhase != .idle
            || store.sessionDuration > 0
            || store.cumulativeDistanceMeters > 0
    }

    private func sessionButton(
        title: String,
        systemImage: String,
        isEnabled: Bool,
        fill: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.semibold))
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .foregroundStyle(isEnabled ? .white : .white.opacity(0.35))
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isEnabled ? fill : Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(isEnabled ? 0.12 : 0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
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
