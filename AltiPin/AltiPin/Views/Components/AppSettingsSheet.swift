//
//  AppSettingsSheet.swift
//  AltiPin
//

import SwiftUI

private struct PresentAppSettingsKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    var presentAppSettings: () -> Void {
        get { self[PresentAppSettingsKey.self] }
        set { self[PresentAppSettingsKey.self] = newValue }
    }
}

struct AppTabBarTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.headline)
            .foregroundStyle(.white.opacity(0.9))
    }
}

/// 与指南针 Tab 一致的自定义顶栏：标题左对齐 + 右侧操作，避免 NavigationStack toolbar 截断。
struct AppTabTopBar<Leading: View, Trailing: View>: View {
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing

    init(
        @ViewBuilder leading: @escaping () -> Leading,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.leading = leading
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .center) {
            leading()
            Spacer(minLength: 0)
            trailing()
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }
}

extension AppTabTopBar where Leading == AppTabBarTitle {
    init(title: String, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.leading = { AppTabBarTitle(text: title) }
        self.trailing = trailing
    }
}

extension AppTabTopBar where Leading == AppTabBarTitle, Trailing == AppSettingsButton {
    init(title: String) {
        self.leading = { AppTabBarTitle(text: title) }
        self.trailing = { AppSettingsButton() }
    }
}

struct AppSettingsButton: View {
    var action: (() -> Void)?

    @Environment(\.presentAppSettings) private var presentAppSettings

    var body: some View {
        Button {
            if let action {
                action()
            } else {
                presentAppSettings()
            }
        } label: {
            Image(systemName: "gearshape")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.85))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("设置")
    }
}

struct AppSettingsSheet: View {
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            AppSettingsView()
                .navigationTitle("设置")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("关闭") {
                            onClose()
                        }
                    }
                }
        }
        .preferredColorScheme(.dark)
    }
}

#Preview("Settings Sheet") {
    AppSettingsSheet(onClose: {})
}

#Preview("Settings Button") {
    AppSettingsButton()
        .padding()
        .background(Color.black)
        .environment(\.presentAppSettings) {}
}
