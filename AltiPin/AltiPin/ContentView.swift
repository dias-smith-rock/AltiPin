//
//  ContentView.swift
//  AltiPin
//
//  Created by Rock on 15/6/2026.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        MainTabView()
    }
}

#Preview {
    ContentView()
        .modelContainer(for: TripEntity.self, inMemory: true)
}
