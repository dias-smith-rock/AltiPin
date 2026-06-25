//
//  MemberFilterBar.swift
//  AltiPin
//

import SwiftUI

struct MemberFilterBar: View {
    @ObservedObject var teamSession: TeamSessionStore
    @Binding var activityNickname: String

    @State private var showNicknameEditor = false
    @State private var draftNickname = ""
    @State private var nicknameErrorMessage: String?
    @State private var isSavingNickname = false
    @FocusState private var isNicknameFieldFocused: Bool

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip(
                    title: allSelected ? L10n.t("Deselect All") : L10n.t("Select All"),
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
                        title: member.isSelf ? L10n.format("%@ (Me)", member.nickname) : member.nickname,
                        color: member.color,
                        isSelected: teamSession.visibleMemberIDs.contains(member.id),
                        action: {
                            teamSession.toggleMemberVisibility(member.id)
                        },
                        longPressAction: member.isSelf ? {
                            draftNickname = member.nickname
                            nicknameErrorMessage = nil
                            showNicknameEditor = true
                        } : nil
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(Color.black.opacity(0.82))
        .sheet(isPresented: $showNicknameEditor) {
            nicknameEditorSheet
        }
    }

    private var nicknameEditorSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text("Everyone on the team will see your new nickname.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.65))

                VStack(alignment: .leading, spacing: 8) {
                    Text("My Nickname")
                        .font(.caption)
                        .foregroundStyle(AltitudeTheme.accent)

                    TextField("Hiker", text: $draftNickname)
                        .textFieldStyle(.plain)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white.opacity(0.06))
                        )
                        .foregroundStyle(.white)
                        .focused($isNicknameFieldFocused)
                        .submitLabel(.done)
                        .onSubmit {
                            Task { await saveNickname() }
                        }
                }

                if let nicknameErrorMessage {
                    Text(nicknameErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.red.opacity(0.9))
                }

                Spacer()
            }
            .padding(24)
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Edit Nickname")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showNicknameEditor = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSavingNickname ? "Saving…" : "Save") {
                        Task { await saveNickname() }
                    }
                    .disabled(
                        draftNickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || isSavingNickname
                    )
                }
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium])
        .onAppear {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(100))
                isNicknameFieldFocused = true
            }
        }
    }

    private var allSelected: Bool {
        !teamSession.members.isEmpty
            && teamSession.visibleMemberIDs.count == teamSession.members.count
    }

    private func filterChip(
        title: String,
        color: Color,
        isSelected: Bool,
        action: @escaping () -> Void,
        longPressAction: (() -> Void)? = nil
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
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.45).onEnded { _ in
                longPressAction?()
            }
        )
    }

    private func saveNickname() async {
        let trimmed = draftNickname.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            nicknameErrorMessage = L10n.t("Nickname cannot be empty")
            return
        }

        isSavingNickname = true
        nicknameErrorMessage = nil
        if let saved = await teamSession.updateSelfNickname(trimmed) {
            activityNickname = saved
            showNicknameEditor = false
        } else {
            nicknameErrorMessage = L10n.t("Save failed. Please try again.")
        }
        isSavingNickname = false
    }
}

#Preview {
    MemberFilterBar(
        teamSession: {
            let session = TeamSessionStore()
            Task {
                await session.createRoom(nickname: "Hiker")
            }
            return session
        }(),
        activityNickname: .constant("Hiker")
    )
    .background(Color.black)
}
