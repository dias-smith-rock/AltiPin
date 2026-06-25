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
            .id(languageManager.refreshToken)
    }
}

#Preview {
    ContentView()
        .environmentObject(AppLanguageManager())
        .modelContainer(for: TripEntity.self, inMemory: true)
}
