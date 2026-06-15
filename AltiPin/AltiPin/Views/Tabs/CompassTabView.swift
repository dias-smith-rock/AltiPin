//
//  CompassTabView.swift
//  AltiPin
//

import SwiftUI

struct CompassTabView: View {
    @ObservedObject var store: OutdoorDashboardStore
    @StateObject private var weatherService = CompassWeatherService()

    @State private var heading: Double = 0
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            compassHeader
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 12)

            headingSection
                .padding(.bottom, 8)

            CompassDialView(
                heading: heading,
                directionName: store.compassDirectionName,
                levelOffsetX: store.levelOffsetX,
                levelOffsetY: store.levelOffsetY
            )
            .frame(maxHeight: .infinity)

            bottomSummaryCards
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        }
        .oledTabBackground()
        .onAppear {
            heading = store.heading
            refreshWeatherIfNeeded()
        }
        .onChange(of: store.heading) { oldValue, newValue in
            let delta = Self.shortestAngleDelta(from: oldValue, to: newValue)
            withAnimation(.interactiveSpring(response: 0.32, dampingFraction: 0.86)) {
                heading += delta
            }
        }
        .onChange(of: store.latitude) { _, _ in
            refreshWeatherIfNeeded()
        }
        .onChange(of: store.longitude) { _, _ in
            refreshWeatherIfNeeded()
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                ContentUnavailableView(
                    "设置",
                    systemImage: "gearshape",
                    description: Text("设置功能即将推出")
                )
                .navigationTitle("设置")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("关闭") {
                            showSettings = false
                        }
                    }
                }
            }
            .preferredColorScheme(.dark)
        }
    }

    // MARK: - Header

    private var compassHeader: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: weatherService.conditionSymbol)
                    .font(.subheadline)
                    .symbolRenderingMode(.multicolor)
                    .contentTransition(.symbolEffect(.replace))
                VStack(alignment: .leading, spacing: 2) {
                    Text(weatherService.localityName)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.85))
                    Text(temperatureText)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.65))
                }
            }

            Spacer()

            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
    }

    private var temperatureText: String {
        guard let temp = weatherService.temperatureCelsius else { return "—" }
        return "\(Int(temp.rounded()))°C"
    }

    // MARK: - Heading

    private var headingSection: some View {
        VStack(spacing: 8) {
            Text("\(store.compassDirectionName) \(Int(store.heading.rounded()))°")
                .font(.system(size: 36, weight: .thin))
                .foregroundStyle(.white)

            Text(store.coordinateDMSString)
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(.white.opacity(0.65))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
    }

    // MARK: - Bottom Cards

    private var bottomSummaryCards: some View {
        HStack(spacing: 10) {
            CompassSummaryCard(
                title: "海拔",
                icon: "mountain.2.fill",
                value: "\(Int(store.elevationMeters.rounded()))米"
            )
            CompassSummaryCard(
                title: "大气压",
                icon: "gauge.with.dots.needle.67percent",
                value: pressureText
            )
            CompassSummaryCard(
                title: "风向",
                icon: "wind",
                value: weatherService.windDirectionName
            )
        }
    }

    private var pressureText: String {
        guard store.pressureHPa > 0 else { return "—" }
        return String(format: "%.0f hPa", store.pressureHPa)
    }

    private func refreshWeatherIfNeeded() {
        guard let location = store.currentLocation else { return }
        Task {
            await weatherService.refresh(for: location)
        }
    }

    private static func shortestAngleDelta(from: Double, to: Double) -> Double {
        var delta = (to - from).truncatingRemainder(dividingBy: 360)
        if delta > 180 { delta -= 360 }
        if delta < -180 { delta += 360 }
        return delta
    }
}

#Preview {
    CompassTabView(store: OutdoorDashboardStore.preview())
}
