//
//  AppLanguageSettingsView.swift
//  AltiPin
//

import SwiftUI

struct AppLanguageSettingsView: View {
    @EnvironmentObject private var languageManager: AppLanguageManager

    var body: some View {
        List {
            ForEach(AppLanguage.allCases) { language in
                Button {
                    languageManager.select(language)
                } label: {
                    HStack {
                        Text(language.displayName)
                            .foregroundStyle(.primary)
                        Spacer()
                        if languageManager.selected == language {
                            Image(systemName: "checkmark")
                                .foregroundStyle(AltitudeTheme.accent)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Language")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        AppLanguageSettingsView()
            .environmentObject(AppLanguageManager())
    }
    .preferredColorScheme(.dark)
}
