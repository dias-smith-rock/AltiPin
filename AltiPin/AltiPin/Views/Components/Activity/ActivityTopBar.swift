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
                Text(L10n.format("Team %@", roomCode))
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.9))

                Text(subtitleText)
                    .font(.caption2)
                    .foregroundStyle(subtitleColor)
            }
            .id("team-header-\(teamSession.members.count)-\(teamSession.connectionTierRefreshTick)")
        } else {
            AppTabBarTitle(text: "Activity")
        }
    }

    private var faceToFaceButton: some View {
        Button(action: onFaceToFaceTapped) {
            Text("Face to Face Team Up")
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
            L10n.t("Disconnected")
        case .connecting:
            L10n.t("Connecting…")
        default:
            L10n.format("%lld online", teamSession.onlineMemberCount)
        }
    }

    private var subtitleColor: Color {
        teamSession.connectionState == .disconnected ? .red.opacity(0.85) : AltitudeTheme.accent
    }
}
