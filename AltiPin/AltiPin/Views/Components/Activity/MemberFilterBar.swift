//
//  MemberFilterBar.swift
//  AltiPin
//

import SwiftUI

struct MemberFilterBar: View {
    @ObservedObject var teamSession: TeamSessionStore

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip(
                    title: allSelected ? "全不选" : "全选",
                    color: .white.opacity(0.6),
                    isSelected: allSelected,
                    action: {
                        if allSelected {
                            teamSession.deselectAll()
                        } else {
                            teamSession.selectAll()
                        }
                    }
                )

                ForEach(teamSession.members) { member in
                    filterChip(
                        title: member.isSelf ? "\(member.nickname)(我)" : member.nickname,
                        color: member.color,
                        isSelected: teamSession.visibleMemberIDs.contains(member.id),
                        action: {
                            teamSession.toggleMemberVisibility(member.id)
                        }
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(Color.black.opacity(0.82))
    }

    private var allSelected: Bool {
        !teamSession.members.isEmpty
            && teamSession.visibleMemberIDs.count == teamSession.members.count
    }

    private func filterChip(
        title: String,
        color: Color,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)

                Text(title)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .foregroundStyle(isSelected ? .white : .white.opacity(0.55))
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? color.opacity(0.22) : Color.white.opacity(0.06))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(isSelected ? color.opacity(0.75) : Color.white.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    MemberFilterBar(teamSession: {
        let session = TeamSessionStore()
        Task {
            await session.createRoom(nickname: "徒步者")
        }
        return session
    }())
    .background(Color.black)
}
