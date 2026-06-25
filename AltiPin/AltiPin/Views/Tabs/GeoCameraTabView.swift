//
//  GeoCameraTabView.swift
//  AltiPin
//

import SwiftData
import SwiftUI

struct GeoCameraTabView: View {
    @ObservedObject var store: OutdoorDashboardStore
    @ObservedObject var weatherService: CompassWeatherService

    @State private var showCapture = false
    @State private var statusMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            AppTabTopBar(title: "Geo Camera")

            GeoMediaGalleryView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.black.ignoresSafeArea())
        .overlay(alignment: .bottomTrailing) {
            captureFAB
        }
        .overlay(alignment: .bottom) {
            if let statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.white.opacity(0.15)))
                    .padding(.bottom, 88)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .preferredColorScheme(.dark)
        .fullScreenCover(isPresented: $showCapture) {
            GeoCameraCaptureScreen(
                store: store,
                weatherService: weatherService,
                onClose: { showCapture = false },
                onStatus: flashStatus
            )
        }
    }

    private var captureFAB: some View {
        Button {
            showCapture = true
        } label: {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(
                    Circle()
                        .fill(AltitudeTheme.accent)
                        .shadow(color: AltitudeTheme.accent.opacity(0.35), radius: 8, y: 4)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Capture")
        .padding(.trailing, 20)
        .padding(.bottom, 72)
    }

    private func flashStatus(_ message: String) {
        withAnimation {
            statusMessage = message
        }
        Task {
            try? await Task.sleep(for: .seconds(2))
            await MainActor.run {
                withAnimation {
                    statusMessage = nil
                }
            }
        }
    }
}

#Preview {
    GeoCameraTabView(
        store: OutdoorDashboardStore.preview(),
        weatherService: CompassWeatherService()
    )
    .modelContainer(for: GeoMediaEntity.self, inMemory: true)
}
