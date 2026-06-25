//
//  MainTabView.swift
//  AltiPin
//

import SwiftUI
import SwiftData

struct MainTabView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var languageManager: AppLanguageManager
    @StateObject private var store = OutdoorDashboardStore()
    @StateObject private var weatherService = CompassWeatherService()
    @State private var selectedTab: AppTab = .compass
    @State private var isTabBarHidden = false
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch selectedTab {
                case .compass:
                    CompassTabView(store: store, weatherService: weatherService)
                case .altitude:
                    AltitudeTabView(store: store, weatherService: weatherService)
                case .gps:
                    GPSTabView(store: store)
                case .activity:
                    ActivityTabView(store: store)
                case .geoCamera:
                    GeoCameraTabView(store: store, weatherService: weatherService)
                case .timeline:
                    HomeTimelineView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if !isTabBarHidden {
                AppTabBar(selectedTab: $selectedTab)
            }
        }
        .preferredColorScheme(.dark)
        .environment(\.presentAppSettings) {
            showSettings = true
        }
        .sheet(isPresented: $showSettings) {
            AppSettingsSheet(onClose: { showSettings = false })
                .environmentObject(languageManager)
        }
        .onPreferenceChange(TabBarHiddenPreferenceKey.self) { isTabBarHidden = $0 }
        .onAppear {
            store.configure(modelContext: modelContext)
            store.startMonitoring()
        }
        .onChange(of: selectedTab) { _, tab in
            if tab != .activity {
                isTabBarHidden = false
            }
            if tab == .altitude {
                store.refreshNavigationEnvironmentForAltitudeTab()
            }
        }
    }
}

#Preview {
    MainTabView()
        .environmentObject(AppLanguageManager())
        .modelContainer(for: [TripEntity.self, BuildingCalibrationEntity.self, FootprintEntity.self, GeoMediaEntity.self], inMemory: true)
}
