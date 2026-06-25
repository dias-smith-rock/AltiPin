//
//  AppTabBar.swift
//  AltiPin
//

import SwiftUI

enum AppTab: Hashable, CaseIterable {
    case compass
    case altitude
    case gps
    case activity
    case geoCamera
    case timeline

    var icon: String {
        switch self {
        case .compass: "location.north.line.fill"
        case .altitude: "mountain.2.fill"
        case .gps: "speedometer"
        case .activity: "figure.walk"
        case .geoCamera: "camera.viewfinder"
        case .timeline: "list.bullet"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .compass: L10n.t("Compass")
        case .altitude: L10n.t("Altitude")
        case .gps: L10n.t("Speed")
        case .activity: L10n.t("Activity")
        case .geoCamera: L10n.t("Geo Camera")
        case .timeline: L10n.t("History")
        }
    }
}

struct TabBarHiddenPreferenceKey: PreferenceKey {
    static var defaultValue = false

    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

struct AppTabBar: View {
    @Binding var selectedTab: AppTab

    var body: some View {
        VStack(spacing: 0) {
            Divider()
                .overlay(Color.white.opacity(0.12))

            HStack(spacing: 0) {
                ForEach(AppTab.allCases, id: \.self) { tab in
                    tabButton(tab)
                }
            }
            .frame(height: 49)
            .padding(.horizontal, 4)
        }
        .background(Color.black.ignoresSafeArea(edges: .bottom))
    }

    private func tabButton(_ tab: AppTab) -> some View {
        let isSelected = selectedTab == tab

        return Button {
            selectedTab = tab
        } label: {
            Image(systemName: tab.icon)
                .font(.system(size: 22, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? AltitudeTheme.accent : Color.white.opacity(0.45))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isSelected ? AltitudeTheme.accent.opacity(0.12) : Color.clear)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 2)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.accessibilityLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
