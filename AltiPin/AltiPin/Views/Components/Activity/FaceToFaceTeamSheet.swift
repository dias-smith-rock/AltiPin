//
//  FaceToFaceTeamSheet.swift
//  AltiPin
//

import SwiftUI

struct FaceToFaceTeamSheet: View {
    @ObservedObject var teamSession: TeamSessionStore
    @Binding var nickname: String
    @Environment(\.dismiss) private var dismiss

    @State private var mode: Mode = .choose
    @State private var joinCode = ""
    @State private var createdCode = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    @FocusState private var isJoinCodeFocused: Bool

    enum Mode {
        case choose
        case create
        case join
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                switch mode {
                case .choose:
                    chooseView
                case .create:
                    createView
                case .join:
                    joinView
                }

                Spacer()
            }
            .padding(24)
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("面对面组队")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            TeamRelayLogger.ui("FaceToFaceTeamSheet 打开 mode=\(mode)")
            TeamRelayLogger.logConfigDiagnostics()
        }
        .onChange(of: mode) { _, newMode in
            if newMode == .join {
                focusJoinCodeField()
            } else {
                isJoinCodeFocused = false
            }
        }
    }

    // MARK: - Choose

    private var chooseView: some View {
        VStack(spacing: 20) {
            Text("和身边的人输入相同 4 位数字，即可进入同一队伍。")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.65))
                .multilineTextAlignment(.center)

            nicknameField

            Button {
                mode = .create
                createdCode = ""
                Task { await startCreate() }
            } label: {
                modeButton(title: "创建队伍", subtitle: "生成随机密码")
            }

            Button {
                mode = .join
                joinCode = ""
                errorMessage = nil
            } label: {
                modeButton(title: "加入队伍", subtitle: "输入 4 位密码")
            }
        }
    }

    // MARK: - Create

    private var createView: some View {
        VStack(spacing: 20) {
            Text("让队友输入以下数字")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.65))

            Text(createdCode.isEmpty ? "····" : createdCode)
                .font(.system(size: 56, weight: .thin, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(AltitudeTheme.accent)
                .tracking(8)

            if isWorking {
                ProgressView()
                    .tint(AltitudeTheme.accent)
            } else if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red.opacity(0.9))
            } else {
                Text("等待队友加入…")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.45))
            }

            Button("完成") {
                dismiss()
            }
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(AltitudeTheme.accent.opacity(0.9), in: RoundedRectangle(cornerRadius: 14))
            .padding(.top, 8)
        }
    }

    // MARK: - Join

    private var joinView: some View {
        VStack(spacing: 20) {
            Text("输入队伍密码")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.65))

            nicknameField

            TextField("0000", text: $joinCode)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(.system(size: 44, weight: .thin, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.white.opacity(0.06))
                )
                .focused($isJoinCodeFocused)
                .onChange(of: joinCode) { _, newValue in
                    joinCode = String(newValue.filter(\.isNumber).prefix(4))
                }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red.opacity(0.9))
            }

            Button {
                Task { await startJoin() }
            } label: {
                Text(isWorking ? "加入中…" : "加入队伍")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        joinCode.count == 4 ? AltitudeTheme.accent.opacity(0.9) : Color.white.opacity(0.15),
                        in: RoundedRectangle(cornerRadius: 14)
                    )
            }
            .disabled(joinCode.count != 4 || isWorking)
            .buttonStyle(.plain)
        }
        .onAppear {
            focusJoinCodeField()
        }
    }

    private var nicknameField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("我的昵称")
                .font(.caption)
                .foregroundStyle(AltitudeTheme.accent)

            TextField("徒步者", text: $nickname)
                .textFieldStyle(.plain)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.06))
                )
                .foregroundStyle(.white)
        }
    }

    private func modeButton(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }

    private func startCreate() async {
        isWorking = true
        errorMessage = nil
        let trimmed = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty ? defaultNickname() : trimmed
        nickname = name
        TeamRelayLogger.ui("startCreate nickname=\(name)")
        await teamSession.createRoom(nickname: name)
        createdCode = teamSession.roomCode ?? ""
        if teamSession.roomCode == nil {
            errorMessage = teamSession.lastConnectionError ?? "创建队伍失败"
            TeamRelayLogger.ui("startCreate 失败 error=\(errorMessage ?? "nil")")
        } else {
            TeamRelayLogger.ui("startCreate 成功 room=\(createdCode)")
        }
        isWorking = false
    }

    private func startJoin() async {
        guard joinCode.count == 4 else {
            errorMessage = "请输入 4 位数字"
            TeamRelayLogger.ui("startJoin 拒绝：房间码长度=\(joinCode.count)")
            return
        }
        isWorking = true
        errorMessage = nil
        let trimmed = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty ? defaultNickname() : trimmed
        nickname = name
        TeamRelayLogger.ui("startJoin room=\(joinCode) nickname=\(name)")
        await teamSession.join(roomCode: joinCode, nickname: name)
        isWorking = false
        if teamSession.isInRoom {
            TeamRelayLogger.ui("startJoin 成功 room=\(joinCode) 关闭 sheet")
            dismiss()
        } else {
            errorMessage = teamSession.lastConnectionError ?? "加入队伍失败"
            TeamRelayLogger.ui("startJoin 失败 error=\(errorMessage ?? "nil")")
        }
    }

    private func defaultNickname() -> String {
        "徒步者\(Int.random(in: 100...999))"
    }

    private func focusJoinCodeField() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            isJoinCodeFocused = true
        }
    }
}

#Preview {
    FaceToFaceTeamSheet(
        teamSession: TeamSessionStore(),
        nickname: .constant("徒步者")
    )
}
