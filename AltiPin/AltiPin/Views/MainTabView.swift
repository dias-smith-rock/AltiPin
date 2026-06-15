//
//  MainTabView.swift
//  AltiPin
//

import SwiftUI
import SwiftData

struct MainTabView: View {
    @StateObject private var store = OutdoorDashboardStore()

    var body: some View {
        TabView {
            CompassTabView(store: store)
                .tabItem {
                    Label("指南针", systemImage: "location.north.line.fill")
                }

            AltitudeTabView(store: store)
                .tabItem {
                    Label("海拔", systemImage: "mountain.2.fill")
                }

            GPSTabView(store: store)
                .tabItem {
                    Label("GPS", systemImage: "location.fill")
                }

            ActivityTabView(store: store)
                .tabItem {
                    Label("运动", systemImage: "figure.walk")
                }

            HomeTimelineView()
                .tabItem {
                    Label("记录", systemImage: "list.bullet")
                }
        }
        .onAppear {
            store.startMonitoring()
        }
    }
}

#Preview {
    MainTabView()
        .modelContainer(for: TripEntity.self, inMemory: true)
}
