//
//  AltitudeTabView.swift
//  AltiPin
//

import CoreLocation
import SwiftUI

struct AltitudeTabView: View {
    @ObservedObject var store: OutdoorDashboardStore
    @ObservedObject var weatherService: CompassWeatherService
    @ObservedObject private var recentHistoryBuffer = RecentHistoryBuffer.shared

    @State private var showSettings = false
    @State private var showFloorCalibration = false
    @State private var showRecalibrateSheet = false
    @State private var calibrationFloor = 1
    @State private var calibrationLabel = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                AltitudeHeroHeader(
                    elevationMeters: store.elevationMeters,
                    verticalAccuracy: store.verticalAccuracy,
                    navigationEnvironment: store.navigationEnvironment,
                    estimatedIndoorFloor: store.estimatedIndoorFloor,
                    isIndoorFloorCalibrated: store.isIndoorFloorCalibrated,
                    needsFloorCalibration: store.needsFloorCalibration,
                    matchedBuildingLabel: store.matchedBuildingLabel,
                    floorCalibrationSource: store.floorCalibrationSource,
                    isManualNavigationOverride: store.isManualNavigationOverride,
                    onRefresh: refreshAll,
                    onSettings: { showSettings = true }
                )

                environmentModeSection
                sectionDivider

                if store.navigationEnvironment == .indoor {
                    indoorFloorSection
                    sectionDivider
                    #if DEBUG
                    environmentDebugSection
                    sectionDivider
                    #endif
                }

                ElevationSessionChart(recentPoints: recentHistoryBuffer.points)

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
            store.refreshNavigationEnvironmentForAltitudeTab()
            bootstrapChartSamples()
            refreshWeatherIfNeeded()
        }
        .onChange(of: store.elevationMeters) { _, newValue in
            appendLiveChartSample(elevation: newValue)
        }
        .onChange(of: store.latitude) { _, _ in
            if recentHistoryBuffer.points.isEmpty {
                bootstrapChartSamples()
            }
            refreshWeatherIfNeeded()
        }
        .onChange(of: store.longitude) { _, _ in
            refreshWeatherIfNeeded()
        }
        .onChange(of: store.needsFloorCalibration) { _, needs in
            if needs, store.navigationEnvironment == .indoor {
                calibrationFloor = 1
                calibrationLabel = ""
                showFloorCalibration = true
            }
        }
        .sheet(isPresented: $showFloorCalibration) {
            floorCalibrationSheet(isRecalibrate: false)
        }
        .sheet(isPresented: $showRecalibrateSheet) {
            floorCalibrationSheet(isRecalibrate: true)
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

    private var environmentModeSection: some View {
        VStack(spacing: 0) {
            AltitudeSectionHeader(
                icon: "arrow.triangle.branch",
                title: "环境模式",
                trailingText: store.isManualNavigationOverride ? "手动" : "自动"
            )

            Picker("环境模式", selection: environmentModeSelection) {
                ForEach(NavigationEnvironmentControlSelection.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            if store.isManualNavigationOverride {
                Text("已暂停自动判定，可手动切换室内外。")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            } else {
                Text("根据 GPS 与运动状态自动识别室内外。")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }
        }
    }

    private var environmentModeSelection: Binding<NavigationEnvironmentControlSelection> {
        Binding(
            get: { store.navigationEnvironmentControlMode.selection },
            set: { store.setNavigationEnvironmentControlMode(NavigationEnvironmentControlMode(selection: $0)) }
        )
    }

    private var indoorFloorSection: some View {
        VStack(spacing: 0) {
            AltitudeSectionHeader(
                icon: "building.2.fill",
                title: "室内楼层",
                trailingText: store.isIndoorFloorCalibrated ? "已校准" : "待校准"
            )

            if store.needsFloorCalibration {
                Button {
                    calibrationFloor = 1
                    calibrationLabel = store.matchedBuildingLabel ?? ""
                    showFloorCalibration = true
                } label: {
                    HStack {
                        Image(systemName: "slider.horizontal.3")
                        Text("设定当前楼层")
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AltitudeTheme.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            } else if store.isIndoorFloorCalibrated {
                Button {
                    calibrationFloor = store.estimatedIndoorFloor ?? 1
                    calibrationLabel = store.matchedBuildingLabel ?? ""
                    showRecalibrateSheet = true
                } label: {
                    HStack {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text("重新校准楼层")
                    }
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }

            AltitudeMetricGrid(items: indoorFloorMetrics)
        }
    }

    private var indoorFloorMetrics: [AltitudeMetricItem] {
        var items: [AltitudeMetricItem] = [
            AltitudeMetricItem(label: "推断楼层", value: indoorFloorText),
            AltitudeMetricItem(label: "基准气压", value: indoorBaselinePressureText),
            AltitudeMetricItem(label: "当前气压", value: currentPressureText),
            AltitudeMetricItem(label: "定位精度", value: indoorAccuracyText),
        ]

        if let source = store.floorCalibrationSource {
            items.append(AltitudeMetricItem(label: "校准来源", value: calibrationSourceText(source)))
        }
        if let label = store.matchedBuildingLabel, !label.isEmpty {
            items.append(AltitudeMetricItem(label: "楼栋", value: label))
        }

        return items
    }

    private func calibrationSourceText(_ source: FloorCalibrationSource) -> String {
        switch source {
        case .persisted: return "历史记录"
        case .clFloor: return "系统楼层"
        case .manual: return "手动设定"
        }
    }

    @ViewBuilder
    private func floorCalibrationSheet(isRecalibrate: Bool) -> some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $calibrationFloor, in: 1...99) {
                        Text("当前楼层：\(calibrationFloor) 楼")
                    }
                } header: {
                    Text("楼层")
                } footer: {
                    Text("设定你此刻所在的真实楼层。之后将用气压变化推算上下楼。")
                }

                Section("楼栋名称（可选）") {
                    TextField("例如：公司大楼", text: $calibrationLabel)
                }

                if store.elevationMeters > 0 {
                    Section {
                        LabeledContent("参考海拔", value: "\(Int(store.elevationMeters.rounded())) m")
                    }
                }
            }
            .navigationTitle(isRecalibrate ? "重新校准楼层" : "设定当前楼层")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        if isRecalibrate {
                            showRecalibrateSheet = false
                        } else {
                            showFloorCalibration = false
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确认") {
                        let label = calibrationLabel.trimmingCharacters(in: .whitespacesAndNewlines)
                        if isRecalibrate {
                            store.recalibrateIndoorFloor(
                                to: calibrationFloor,
                                label: label.isEmpty ? nil : label
                            )
                            showRecalibrateSheet = false
                        } else {
                            store.confirmFloorCalibration(
                                floor: calibrationFloor,
                                label: label.isEmpty ? nil : label
                            )
                            showFloorCalibration = false
                        }
                    }
                    .disabled(store.pressureHPa <= 0)
                }
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium])
    }

    private var indoorFloorText: String {
        if store.needsFloorCalibration { return "待设定" }
        guard let floor = store.estimatedIndoorFloor else { return "推算中…" }
        return "\(floor) 楼"
    }

    private var indoorBaselinePressureText: String {
        guard let baseline = store.indoorBaselinePressureHPa, baseline > 0 else { return "—" }
        return String(format: "%.1f hPa", baseline)
    }

    private var currentPressureText: String {
        guard store.pressureHPa > 0 else { return "—" }
        return String(format: "%.1f hPa", store.pressureHPa)
    }

    private var indoorAccuracyText: String {
        guard store.horizontalAccuracy > 0 else { return "—" }
        return String(format: "±%.0fm", store.horizontalAccuracy)
    }

    #if DEBUG
    private var environmentDebugSection: some View {
        VStack(spacing: 0) {
            AltitudeSectionHeader(icon: "ant.fill", title: "环境诊断 (DEBUG)")

            AltitudeMetricGrid(items: [
                AltitudeMetricItem(label: "判定", value: store.navigationEnvironmentDiagnostic),
                AltitudeMetricItem(
                    label: "水平精度",
                    value: store.horizontalAccuracy >= 0
                        ? String(format: "%.1fm", store.horizontalAccuracy) : "—"
                ),
                AltitudeMetricItem(
                    label: "垂直精度",
                    value: store.verticalAccuracy >= 0
                        ? String(format: "%.1fm", store.verticalAccuracy) : "invalid"
                ),
                AltitudeMetricItem(label: "摘要", value: store.navigationEnvironmentDebugSummary),
            ])
        }
    }
    #endif

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

    private func bootstrapChartSamples() {
        guard store.horizontalAccuracy >= 0 else { return }
        RecentHistoryBuffer.shared.bootstrapIfNeeded(
            elevation: store.elevationMeters,
            latitude: store.latitude,
            longitude: store.longitude,
            isIndoor: store.navigationEnvironment == .indoor
        )
    }

    private func appendLiveChartSample(elevation: Double) {
        guard store.horizontalAccuracy >= 0 else { return }
        RecentHistoryBuffer.shared.appendIfNeeded(
            timestamp: .now,
            latitude: store.latitude,
            longitude: store.longitude,
            elevation: elevation,
            isIndoor: store.navigationEnvironment == .indoor
        )
    }

    private func refreshAll() {
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
