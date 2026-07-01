//
//  AltitudeTabView.swift
//  AltiPin
//

import CoreLocation
import SwiftUI

struct AltitudeTabView: View {
    @ObservedObject var store: OutdoorDashboardStore
    @ObservedObject var weatherService: CompassWeatherService
    @ObservedObject private var footprintEngine = FootprintTrackingEngine.shared

    @State private var showFloorCalibration = false
    @State private var showRecalibrateSheet = false
    @State private var calibrationFloor = 1
    @State private var calibrationLabel = ""
    @State private var isRefreshingData = false

    var body: some View {
        NavigationStack {
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
                        isBlackboxModeActive: store.isBlackboxElevationModeActive,
                        isRefreshDisabled: isRefreshingData,
                        onRefresh: refreshAll
                    )

                    environmentModeSection
                    sectionDivider

                    FootprintHistoryChartView(footprints: footprintEngine.recentFootprints)

                    sectionDivider

                    if store.navigationEnvironment == .indoor {
                        indoorFloorSection
                        sectionDivider
                        #if DEBUG
                        environmentDebugSection
                        sectionDivider
                        #endif
                    }

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
            .ignoresSafeArea(edges: .top)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    AppSettingsButton()
                }
            }
        }
        .overlay {
            if isRefreshingData {
                dataRefreshOverlay
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isRefreshingData)
        .onAppear {
            store.refreshNavigationEnvironmentForAltitudeTab()
            Task { @MainActor in
                bootstrapFootprintHistory()
            }
            refreshWeatherIfNeeded()
        }
        .onChange(of: store.latitude) { _, _ in
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
    }

    // MARK: - Sections

    private var environmentModeSection: some View {
        VStack(spacing: 0) {
            AltitudeSectionHeader(
                icon: "arrow.triangle.branch",
                title: "Environment Mode",
                trailingText: store.isManualNavigationOverride ? L10n.t("Manual") : L10n.t("Auto")
            )

            Picker("Environment Mode", selection: environmentModeSelection) {
                ForEach(NavigationEnvironmentControlSelection.allCases) { option in
                    Text(environmentControlLabel(option)).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            if store.isManualNavigationOverride {
                Text("Auto detection paused. Switch indoor/outdoor manually.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            } else {
                Text("Automatically detects indoor/outdoor from GPS and motion.")
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
                title: "Indoor Floor",
                trailingText: store.isIndoorFloorCalibrated ? L10n.t("Calibrated") : L10n.t("Needs Calibration")
            )

            if store.needsFloorCalibration {
                Button {
                    calibrationFloor = 1
                    calibrationLabel = store.matchedBuildingLabel ?? ""
                    showFloorCalibration = true
                } label: {
                    HStack {
                        Image(systemName: "slider.horizontal.3")
                        Text("Set Current Floor")
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
                        Text("Recalibrate Floor")
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
            AltitudeMetricItem(label: "Inferred Floor", value: indoorFloorText),
            AltitudeMetricItem(label: "Baseline Pressure", value: indoorBaselinePressureText),
            AltitudeMetricItem(label: "Current Pressure", value: currentPressureText),
            AltitudeMetricItem(label: "Location Accuracy", value: indoorAccuracyText),
        ]

        if let source = store.floorCalibrationSource {
            items.append(AltitudeMetricItem(label: "Calibration Source", value: calibrationSourceText(source)))
        }
        if let label = store.matchedBuildingLabel, !label.isEmpty {
            items.append(AltitudeMetricItem(label: "Building", value: label))
        }

        return items
    }

    private func calibrationSourceText(_ source: FloorCalibrationSource) -> String {
        switch source {
        case .persisted: return L10n.t("History")
        case .clFloor: return L10n.t("System Floor")
        case .manual: return L10n.t("Manually Set")
        }
    }

    @ViewBuilder
    private func floorCalibrationSheet(isRecalibrate: Bool) -> some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $calibrationFloor, in: 1...99) {
                        Text(L10n.format("Current floor: Floor %lld", calibrationFloor))
                    }
                } header: {
                    Text("Floor")
                } footer: {
                    Text("Set your actual floor. Future floor changes will be inferred from air pressure.")
                }

                Section("Building Name (Optional)") {
                    TextField("e.g. Office Building", text: $calibrationLabel)
                }

                if store.elevationMeters > 0 {
                    Section {
                        LabeledContent("Reference Elevation", value: "\(Int(store.elevationMeters.rounded())) m")
                    }
                }
            }
            .navigationTitle(isRecalibrate ? "Recalibrate Floor" : "Set Current Floor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if isRecalibrate {
                            showRecalibrateSheet = false
                        } else {
                            showFloorCalibration = false
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Confirm") {
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
        if store.needsFloorCalibration { return L10n.t("Not Set") }
        guard let floor = store.estimatedIndoorFloor else { return L10n.t("Estimating…") }
        return L10n.format("Floor %lld", floor)
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
            AltitudeSectionHeader(icon: "ant.fill", title: "Environment Diagnosis (DEBUG)")

            AltitudeMetricGrid(items: [
                AltitudeMetricItem(label: "Detection", value: store.navigationEnvironmentDiagnostic),
                AltitudeMetricItem(
                    label: "Horizontal Accuracy",
                    value: store.horizontalAccuracy >= 0
                        ? String(format: "%.1fm", store.horizontalAccuracy) : "—"
                ),
                AltitudeMetricItem(
                    label: "Vertical Accuracy",
                    value: store.verticalAccuracy >= 0
                        ? String(format: "%.1fm", store.verticalAccuracy) : "invalid"
                ),
                AltitudeMetricItem(label: "Summary", value: store.navigationEnvironmentDebugSummary),
            ])
        }
    }
    #endif

    private var coordinatesSection: some View {
        VStack(spacing: 0) {
            AltitudeSectionHeader(
                icon: "globe.asia.australia.fill",
                title: "Coordinates",
                trailingText: horizontalAccuracyText
            )

            HStack(spacing: 0) {
                coordinateColumn(title: "East Longitude", value: store.longitudeDMS)
                coordinateColumn(title: "North Latitude", value: store.latitudeDMS)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
    }

    private var airDataSection: some View {
        VStack(spacing: 0) {
            AltitudeSectionHeader(icon: "cloud.fill", title: "Air Data")

            AltitudeMetricGrid(items: [
                AltitudeMetricItem(
                    label: "Oxygen Content",
                    value: String(format: "%.2f g/m³", oxygenContent)
                ),
                AltitudeMetricItem(
                    label: "Oxygen Ratio",
                    value: String(format: "%.1f%%", oxygenRatio)
                ),
            ])
        }
    }

    private var magneticFieldSection: some View {
        VStack(spacing: 0) {
            AltitudeSectionHeader(icon: "location.north.fill", title: "Magnetic Field")

            AltitudeMetricGrid(items: [
                AltitudeMetricItem(
                    label: "Magnetic Flux Density",
                    value: String(format: "%.1f μT", store.magneticFieldStrength)
                ),
                AltitudeMetricItem(label: "X-axis", value: String(format: "%.1f", store.magneticFieldX)),
                AltitudeMetricItem(label: "Y-axis", value: String(format: "%.1f", store.magneticFieldY)),
                AltitudeMetricItem(label: "Z-axis", value: String(format: "%.1f", store.magneticFieldZ)),
            ])
        }
    }

    private var pressureSection: some View {
        VStack(spacing: 0) {
            AltitudeSectionHeader(icon: "gauge.with.needle", title: "Air Pressure")

            AltitudeMetricGrid(items: [
                AltitudeMetricItem(
                    label: "Millimeters of Mercury",
                    value: pressureMmHgText
                ),
            ])
        }
    }

    private var boilingPointSection: some View {
        VStack(spacing: 0) {
            AltitudeSectionHeader(icon: "cup.and.saucer.fill", title: "Boiling Point of Water")

            AltitudeMetricGrid(items: [
                AltitudeMetricItem(
                    label: "Celsius",
                    value: String(format: "%.2f°C", boilingPointCelsius)
                ),
                AltitudeMetricItem(
                    label: "Fahrenheit",
                    value: String(format: "%.2f°F", boilingPointFahrenheit)
                ),
            ])
        }
    }

    private var weatherSection: some View {
        VStack(spacing: 0) {
            AltitudeSectionHeader(icon: "cloud.sun.fill", title: "Weather")

            AltitudeMetricGrid(items: [
                AltitudeMetricItem(label: "Temperature", value: temperatureText),
                AltitudeMetricItem(label: "Feels Like", value: apparentTemperatureText),
                AltitudeMetricItem(label: "Conditions", value: weatherService.conditionName),
                AltitudeMetricItem(label: "Humidity", value: humidityText),
                AltitudeMetricItem(label: "Wind Direction", value: weatherService.windDirectionName),
                AltitudeMetricItem(label: "Wind Scale", value: windLevelText),
                AltitudeMetricItem(label: "Wind Speed", value: windSpeedText),
                AltitudeMetricItem(label: "Wind Direction Angle", value: windDirectionDegreesText),
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

    private func environmentControlLabel(_ option: NavigationEnvironmentControlSelection) -> String {
        switch option {
        case .automatic: L10n.t("Automatic")
        case .outdoor: L10n.t("Outdoor")
        case .indoor: L10n.t("Indoor")
        }
    }

    private func coordinateColumn(title: LocalizedStringKey, value: String) -> some View {
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

    private func bootstrapFootprintHistory() {
        footprintEngine.reloadFromStore()

        let elevation = store.elevationMeters > 0
            ? store.elevationMeters
            : (store.currentLocation.map { store.resolvedElevation(for: $0) } ?? 0)

        RecentHistoryBuffer.shared.bootstrapIfNeeded(
            elevation: elevation,
            latitude: store.latitude,
            longitude: store.longitude,
            isIndoor: store.navigationEnvironment == .indoor
        )

        footprintEngine.backfillFromHistoryIfNeeded(
            historyPoints: RecentHistoryBuffer.shared.points
        )
        #if DEBUG
        footprintEngine.seedSimulatorMockFootprintsIfNeeded()
        #endif
        seedFootprintIfNeeded()
    }

    private func seedFootprintIfNeeded() {
        guard footprintEngine.recentFootprints.isEmpty else { return }
        guard let location = store.currentLocation else { return }

        footprintEngine.persistCurrentFootprintIfNeeded(
            location: location,
            elevation: store.resolvedElevation(for: location),
            isIndoor: store.navigationEnvironment == .indoor
        )
    }

    private var dataRefreshOverlay: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                ProgressView()
                    .tint(AltitudeTheme.accent)
                    .scaleEffect(1.15)

                Text("Fetching data…")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(white: 0.14))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
        }
        .transition(.opacity)
    }

    private func refreshAll() {
        guard !isRefreshingData else { return }

        isRefreshingData = true
        Task {
            let location = await store.forceRefreshForAltitudeTab() ?? store.currentLocation
            if let location {
                await weatherService.forceRefresh(for: location)
            }
            isRefreshingData = false
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
