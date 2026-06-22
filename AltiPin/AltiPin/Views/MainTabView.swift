//
//  MainTabView.swift
//  AltiPin
//

import SwiftUI
import SwiftData

private enum AppTab: Hashable {
    case compass
    case altitude
    case gps
    case activity
    case timeline
}

struct MainTabView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var store = OutdoorDashboardStore()
    @StateObject private var weatherService = CompassWeatherService()
    @State private var selectedTab: AppTab = .compass

    var body: some View {
        TabView(selection: $selectedTab) {
            CompassTabView(store: store, weatherService: weatherService)
                .tabItem {
                    Label("指南针", systemImage: "location.north.line.fill")
                }
                .tag(AppTab.compass)

            AltitudeTabView(store: store, weatherService: weatherService)
                .tabItem {
                    Label("海拔", systemImage: "mountain.2.fill")
                }
                .tag(AppTab.altitude)

            GPSTabView(store: store)
                .tabItem {
                    Label("GPS", systemImage: "location.fill")
                }
                .tag(AppTab.gps)

            ActivityTabView(store: store)
                .tabItem {
                    Label("运动", systemImage: "figure.walk")
                }
                .tag(AppTab.activity)

            HomeTimelineView()
                .tabItem {
                    Label("记录", systemImage: "list.bullet")
                }
                .tag(AppTab.timeline)
        }
        .onAppear {
            store.configure(modelContext: modelContext)
            store.startMonitoring()
        }
        .onChange(of: selectedTab) { _, tab in
            if tab == .altitude {
                store.refreshNavigationEnvironmentForAltitudeTab()
            }
        }
    }
}

#Preview {
    MainTabView()
        .modelContainer(for: [TripEntity.self, BuildingCalibrationEntity.self, FootprintEntity.self], inMemory: true)
}
