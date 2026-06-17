//
//  ActivityTeamHeader.swift
//  AltiPin
//

import SwiftUI

struct ActivityTeamHeader: ToolbarContent {
    @ObservedObject var teamSession: TeamSessionStore
    let onFaceToFaceTapped: () -> Void
    let onLeaveTapped: () -> Void

    var body: some ToolbarContent {
        if teamSession.isInRoom, let roomCode = teamSession.roomCode {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 2) {
                    Text("队伍 \(roomCode)")
                        .font(.headline)
                        .foregroundStyle(.white)

                    Text(subtitleText)
                        .font(.caption2)
                        .foregroundStyle(subtitleColor)
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button("退出", action: onLeaveTapped)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.red.opacity(0.9))
            }
        } else {
            ToolbarItem(placement: .principal) {
                Text("运动")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.9))
            }

            ToolbarItem(placement: .topBarTrailing) {
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
        }
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
