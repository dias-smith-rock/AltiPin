//
//  ActivityTopBar.swift
//  AltiPin
//

import SwiftUI

struct ActivityTopBar: View {
    @ObservedObject var teamSession: TeamSessionStore
    let onFaceToFaceTapped: () -> Void
    let onLeaveTapped: () -> Void

    var body: some View {
        AppTabTopBar {
            leadingTitle
        } trailing: {
            HStack(spacing: 12) {
                if teamSession.isInRoom {
                    Button(teamSession.leaveButtonTitle, action: onLeaveTapped)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.red.opacity(0.9))
                } else {
                    faceToFaceButton
                }

                AppSettingsButton()
            }
        }
    }

    @ViewBuilder
    private var leadingTitle: some View {
        if teamSession.isInRoom, let roomCode = teamSession.roomCode {
            VStack(alignment: .leading, spacing: 2) {
                AppTabBarTitle(text: "队伍 \(roomCode)")

                Text(subtitleText)
                    .font(.caption2)
                    .foregroundStyle(subtitleColor)
            }
            .id("team-header-\(teamSession.members.count)-\(teamSession.connectionTierRefreshTick)")
        } else {
            AppTabBarTitle(text: "运动")
        }
    }

    private var faceToFaceButton: some View {
        Button(action: onFaceToFaceTapped) {
            Text("面对面组队")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule(style: .continuous)
                        .fill(AltitudeTheme.accent.opacity(0.22))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(AltitudeTheme.accent.opacity(0.85), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var subtitleText: String {
        switch teamSession.connectionState {
        case .disconnected:
            "连接中断"
        case .connecting:
            "连接中…"
        default:
            "\(teamSession.onlineMemberCount) 人在线"
        }
    }

    private var subtitleColor: Color {
        teamSession.connectionState == .disconnected ? .red.opacity(0.85) : AltitudeTheme.accent
    }
}
