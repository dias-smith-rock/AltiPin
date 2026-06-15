//
//  AltiPinApp.swift
//  AltiPin
//
//  Created by Rock on 15/6/2026.
//

import SwiftUI
import SwiftData

@main
struct AltiPinApp: App {
    @Environment(\.scenePhase) private var scenePhase

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            TripEntity.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    init() {
        TrackingEngine.shared.configure()
        TrackingEngine.shared.delegate = AppTrackingDelegate.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    bootstrapTrackingEngine()
                }
        }
        .modelContainer(sharedModelContainer)
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                bootstrapTrackingEngine()
            case .background:
                TrackingEngine.shared.handleBackgroundWake()
            default:
                break
            }
        }
    }

    private func bootstrapTrackingEngine() {
        TrackingEngine.shared.requestPermissions()
        TrackingEngine.shared.start()
    }
}

// MARK: - TrackingEngineDelegate（日志占位，后续接入 TripEntity）

@MainActor
private final class AppTrackingDelegate: TrackingEngineDelegate {
    static let shared = AppTrackingDelegate()
    private init() {}

    func trackingEngine(_ engine: TrackingEngine, didAppend point: TrackPoint) {
        NSLog("TrackingEngine: point lat=\(point.latitude) lon=\(point.longitude) ele=\(point.elevation)")
    }

    func trackingEngine(_ engine: TrackingEngine, didFinalizeDay fileName: String, pointCount: Int) {
        NSLog("TrackingEngine: finalized day \(fileName) — \(pointCount) points")
    }
}
