//
//  AboutView.swift
//  AltiPin
//

import SwiftUI

struct AboutView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        List {
            Section {
                VStack(spacing: 12) {
                    Image(systemName: "mountain.2.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(AltitudeTheme.accent)
                        .symbolRenderingMode(.hierarchical)

                    Text("AltiPin")
                        .font(.title2.weight(.semibold))

                    Text("户外轨迹与海拔记录工具")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }

            Section {
                infoRow(title: "版本", value: AppLinks.appVersionString)
                infoRow(title: "Bundle ID", value: AppLinks.bundleIdentifier)
            }

            Section {
                Button {
                    openURL(AppLinks.websiteURL)
                } label: {
                    Label("访问官网", systemImage: "globe")
                }
            }

            Section {
                Text("© 2026 GoodCraft")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func infoRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }
}

#Preview {
    NavigationStack {
        AboutView()
    }
    .preferredColorScheme(.dark)
}
