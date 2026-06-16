//
//  MainTabView.swift
//  AltiPin
//

import SwiftUI
import SwiftData

struct MainTabView: View {
    @StateObject private var store = OutdoorDashboardStore()
    @StateObject private var weatherService = CompassWeatherService()

    var body: some View {
        TabView {
            CompassTabView(store: store, weatherService: weatherService)
                .tabItem {
                    Label("指南针", systemImage: "location.north.line.fill")
                }

            AltitudeTabView(store: store, weatherService: weatherService)
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
