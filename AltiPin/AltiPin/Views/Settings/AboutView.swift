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

                    Text("TopoLog")
                        .font(.title2.weight(.semibold))

                    Text("Outdoor track and altitude recorder")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }

            Section {
                infoRow(title: "Version", value: AppLinks.appVersionString)
            }

            Section {
                Button {
                    openURL(AppLinks.websiteURL)
                } label: {
                    Label("Visit Website", systemImage: "globe")
                }
            }

            Section {
                Text("© 2026 TopoLog")
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

    private func infoRow(title: LocalizedStringKey, value: String) -> some View {
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
