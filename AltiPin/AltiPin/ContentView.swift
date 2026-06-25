//
//  ContentView.swift
//  AltiPin
//
//  Created by Rock on 15/6/2026.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @StateObject private var languageManager = AppLanguageManager()

    var body: some View {
        MainTabView()
            .environmentObject(languageManager)
            .environment(\.locale, languageManager.locale)
            .environment(\.layoutDirection, languageManager.layoutDirection)
            .id(languageManager.refreshGeneration)
            .onChange(of: languageManager.selected) { _, _ in
                L10n.updateActiveLocale(languageManager.locale)
            }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppLanguageManager())
        .modelContainer(for: TripEntity.self, inMemory: true)
}
