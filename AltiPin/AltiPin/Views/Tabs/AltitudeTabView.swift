//
//  AltitudeTabView.swift
//  AltiPin
//

import SwiftUI

struct AltitudeTabView: View {
    @ObservedObject var store: OutdoorDashboardStore
    @ObservedObject var weatherService: CompassWeatherService
    @StateObject private var historyService = AltitudeHistoryService()

    @State private var showSettings = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                AltitudeHeroHeader(
                    elevationMeters: store.elevationMeters,
                    verticalAccuracy: store.verticalAccuracy,
                    onRefresh: refreshAll,
                    onSettings: { showSettings = true }
                )

                AltitudeHistoryChart(
                    samples: historyService.chartSamples,
                    maxElevation: historyService.maxElevation,
                    minElevation: historyService.minElevation
                )

                sectionDivider

                coordinatesSection
                sectionDivider

                airDataSection
                sectionDivider

                magneticFieldSection
                sectionDivider

                pressureSection
                sectionDivider

                boilingPointSection
                sectionDivider

                weatherSection
            }
            .padding(.bottom, 24)
        }
        .oledTabBackground()
        .onAppear {
            historyService.reloadFromGPX()
            historyService.appendLiveSample(elevation: store.elevationMeters)
            refreshWeatherIfNeeded()
        }
        .onChange(of: store.elevationMeters) { _, newValue in
            historyService.appendLiveSample(elevation: newValue)
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

    // MARK: - Sections

    private var coordinatesSection: some View {
        VStack(spacing: 0) {
            AltitudeSectionHeader(
                icon: "globe.asia.australia.fill",
                title: "经纬度",
                trailingText: horizontalAccuracyText
            )

            HStack(spacing: 0) {
                coordinateColumn(title: "东经", value: store.longitudeDMS)
                coordinateColumn(title: "北纬", value: store.latitudeDMS)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
    }

    private var airDataSection: some View {
        VStack(spacing: 0) {
            AltitudeSectionHeader(icon: "cloud.fill", title: "空气数据")

            AltitudeMetricGrid(items: [
                AltitudeMetricItem(
                    label: "含氧量",
                    value: String(format: "%.2f g/m³", oxygenContent)
                ),
                AltitudeMetricItem(
                    label: "含氧比",
                    value: String(format: "%.1f%%", oxygenRatio)
                ),
            ])
        }
    }

    private var magneticFieldSection: some View {
        VStack(spacing: 0) {
            AltitudeSectionHeader(icon: "location.north.fill", title: "磁场")

            AltitudeMetricGrid(items: [
                AltitudeMetricItem(
                    label: "磁感应强度",
                    value: String(format: "%.1f μT", store.magneticFieldStrength)
                ),
                AltitudeMetricItem(label: "x轴", value: String(format: "%.1f", store.magneticFieldX)),
                AltitudeMetricItem(label: "y轴", value: String(format: "%.1f", store.magneticFieldY)),
                AltitudeMetricItem(label: "z轴", value: String(format: "%.1f", store.magneticFieldZ)),
            ])
        }
    }

    private var pressureSection: some View {
        VStack(spacing: 0) {
            AltitudeSectionHeader(icon: "gauge.with.needle", title: "大气压")

            AltitudeMetricGrid(items: [
                AltitudeMetricItem(
                    label: "毫米汞柱",
                    value: pressureMmHgText
                ),
            ])
        }
    }

    private var boilingPointSection: some View {
        VStack(spacing: 0) {
            AltitudeSectionHeader(icon: "cup.and.saucer.fill", title: "水的沸点")

            AltitudeMetricGrid(items: [
                AltitudeMetricItem(
                    label: "摄氏度",
                    value: String(format: "%.2f°C", boilingPointCelsius)
                ),
                AltitudeMetricItem(
                    label: "华氏度",
                    value: String(format: "%.2f°F", boilingPointFahrenheit)
                ),
            ])
        }
    }

    private var weatherSection: some View {
        VStack(spacing: 0) {
            AltitudeSectionHeader(icon: "cloud.sun.fill", title: "天气")

            AltitudeMetricGrid(items: [
                AltitudeMetricItem(label: "温度", value: temperatureText),
                AltitudeMetricItem(label: "体感温度", value: apparentTemperatureText),
                AltitudeMetricItem(label: "天气状态", value: weatherService.conditionName),
                AltitudeMetricItem(label: "湿度", value: humidityText),
                AltitudeMetricItem(label: "风向", value: weatherService.windDirectionName),
                AltitudeMetricItem(label: "风力等级", value: windLevelText),
                AltitudeMetricItem(label: "风速", value: windSpeedText),
                AltitudeMetricItem(label: "风向角度", value: windDirectionDegreesText),
            ])
        }
    }

    private var sectionDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.06))
            .frame(height: 1)
            .padding(.horizontal, 16)
    }

    // MARK: - Helpers

    private func coordinateColumn(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(AltitudeTheme.accent)

            Text(value)
                .font(.system(.title2, design: .rounded))
                .fontWeight(.medium)
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    private var horizontalAccuracyText: String? {
        guard store.horizontalAccuracy >= 0 else { return nil }
        return String(format: "±%.2fm", store.horizontalAccuracy)
    }

    private var oxygenContent: Double {
        AltitudeCalculations.oxygenContentGramsPerCubicMeter(
            elevationMeters: store.elevationMeters,
            pressureHPa: store.pressureHPa,
            temperatureCelsius: weatherService.temperatureCelsius ?? 15
        )
    }

    private var oxygenRatio: Double {
        AltitudeCalculations.oxygenRatio(
            elevationMeters: store.elevationMeters,
            pressureHPa: store.pressureHPa
        )
    }

    private var pressureMmHgText: String {
        guard store.pressureHPa > 0 else { return "—" }
        return String(
            format: "%.2f mmHg",
            AltitudeCalculations.pressureMmHg(fromHPa: store.pressureHPa)
        )
    }

    private var boilingPointCelsius: Double {
        AltitudeCalculations.boilingPointCelsius(pressureHPa: store.pressureHPa)
    }

    private var boilingPointFahrenheit: Double {
        AltitudeCalculations.boilingPointFahrenheit(pressureHPa: store.pressureHPa)
    }

    private var temperatureText: String {
        guard let temp = weatherService.temperatureCelsius else { return "—" }
        return "\(Int(temp.rounded()))°C"
    }

    private var apparentTemperatureText: String {
        guard let temp = weatherService.apparentTemperatureCelsius else { return "—" }
        return "\(Int(temp.rounded()))°C"
    }

    private var humidityText: String {
        guard let humidity = weatherService.humidityPercent else { return "—" }
        return "\(Int(humidity.rounded()))%"
    }

    private var windLevelText: String {
        guard let level = weatherService.windLevel else { return "—" }
        return "\(level)"
    }

    private var windSpeedText: String {
        guard let speed = weatherService.windSpeedKmh else { return "—" }
        return "\(Int(speed.rounded()))km/h"
    }

    private var windDirectionDegreesText: String {
        guard let degrees = weatherService.windDirectionDegrees else { return "—" }
        return "\(Int(degrees.rounded()))°"
    }

    private func refreshAll() {
        historyService.reloadFromGPX()
        historyService.appendLiveSample(elevation: store.elevationMeters)
        guard let location = store.currentLocation else { return }
        Task {
            await weatherService.forceRefresh(for: location)
        }
    }

    private func refreshWeatherIfNeeded() {
        guard let location = store.currentLocation else { return }
        Task {
            await weatherService.refresh(for: location)
        }
    }
}

#Preview {
    AltitudeTabView(
        store: OutdoorDashboardStore.preview(),
        weatherService: CompassWeatherService()
    )
}
