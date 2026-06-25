//
//  AppSettingsView.swift
//  AltiPin
//

import StoreKit
import SwiftUI

struct AppSettingsView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.requestReview) private var requestReview

    @State private var showMailComposer = false
    @State private var safariSheet: SafariLinkSheet?

    var body: some View {
        List {
            if AppLinks.showProUpgrade {
                Section {
                    Button {
                        // TODO: Present Pro paywall when StoreKit is integrated
                    } label: {
                        SettingsRowLabel(
                            title: "升级 Pro 版本",
                            systemImage: "star.fill",
                            iconColor: AltitudeTheme.accent
                        )
                    }
                }
            }

            Section {
                Button {
                    openFeedback()
                } label: {
                    SettingsRowLabel(title: "Feedback", systemImage: "envelope")
                }

                Button {
                    requestSupport()
                } label: {
                    SettingsRowLabel(title: "Support us", systemImage: "heart")
                }
            }

            Section {
                Button {
                    safariSheet = SafariLinkSheet(url: AppLinks.privacyPolicyURL, title: "隐私")
                } label: {
                    SettingsRowLabel(title: "隐私", systemImage: "hand.raised")
                }

                Button {
                    safariSheet = SafariLinkSheet(url: AppLinks.termsOfUseURL, title: "使用协议")
                } label: {
                    SettingsRowLabel(title: "使用协议", systemImage: "doc.text")
                }
            }

            Section {
                NavigationLink {
                    AboutView()
                } label: {
                    SettingsRowLabel(title: "About", systemImage: "info.circle", showsChevron: false)
                }
            }
        }
        .listStyle(.insetGrouped)
        .sheet(isPresented: $showMailComposer) {
            MailComposeView(
                recipients: [AppLinks.feedbackEmail],
                subject: AppLinks.feedbackSubject,
                body: AppLinks.feedbackBodyTemplate
            )
            .ignoresSafeArea()
        }
        .sheet(item: $safariSheet) { sheet in
            NavigationStack {
                SafariView(url: sheet.url)
                    .ignoresSafeArea()
                    .navigationTitle(sheet.title)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("完成") {
                                safariSheet = nil
                            }
                        }
                    }
            }
            .preferredColorScheme(.dark)
        }
    }

    private func openFeedback() {
        if MailComposeView.canSendMail {
            showMailComposer = true
        } else if !FeedbackMailPresenter.open(from: openURL) {
            // mailto: also unavailable — nothing more to do
        }
    }

    private func requestSupport() {
        requestReview()
    }
}

private struct SettingsRowLabel: View {
    let title: String
    let systemImage: String
    var iconColor: Color = AltitudeTheme.accent
    var showsChevron: Bool = true

    var body: some View {
        HStack {
            Label {
                Text(title)
            } icon: {
                Image(systemName: systemImage)
                    .foregroundStyle(iconColor)
            }

            Spacer(minLength: 0)

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

#Preview {
    NavigationStack {
        AppSettingsView()
            .navigationTitle("设置")
    }
    .preferredColorScheme(.dark)
}
