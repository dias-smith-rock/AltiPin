//
//  GPSTabView.swift
//  AltiPin
//

import SwiftUI
import UIKit

struct GPSTabView: View {
    @ObservedObject var store: OutdoorDashboardStore

    @AppStorage("gpsSpeedometerMode")
    private var selectedModeRawValue = SpeedometerMode.driving.rawValue

    private var selectedMode: SpeedometerMode {
        SpeedometerMode(rawValue: selectedModeRawValue) ?? .driving
    }

    private var hasSessionStats: Bool {
        store.isSpeedSessionActive
            || store.speedSessionDuration > 0
            || store.speedSessionDistanceMeters > 0
    }

    /// 停止测速后表盘与读数归零；测速进行中显示实时 GPS 速度。
    private var gaugeSpeed: Double {
        store.isSpeedSessionActive ? store.speedKmh : 0
    }

    var body: some View {
        VStack(spacing: 0) {
            AppTabTopBar(title: "Speed")

            if store.isSpeedSessionActive {
                gpsHeader
                    .padding(.horizontal, 20)
                    .padding(.bottom, 10)
            }

            modePicker
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)

                SpeedometerGaugeView(
                    currentSpeed: gaugeSpeed,
                    maxSpeed: selectedMode.maxSpeed,
                    majorTickInterval: selectedMode.majorTickInterval
                )
                .padding(.horizontal, 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(2)
                .animation(.easeOut(duration: 0.25), value: selectedModeRawValue)

                sessionControlButton
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 10)

                sessionStatsPanel
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        }
        .oledTabBackground()
    }

    // MARK: - Header

    private var gpsHeader: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 7, height: 7)
                    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: store.isSpeedSessionActive)

                Text("Speed Test Active")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red.opacity(0.9))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.red.opacity(0.12))
            )

            Spacer()
        }
    }

    // MARK: - Mode Picker

    private var modePicker: some View {
        HStack(spacing: 8) {
            ForEach(SpeedometerMode.allCases) { mode in
                modeButton(for: mode)
            }
        }
        .disabled(store.isSpeedSessionActive)
        .opacity(store.isSpeedSessionActive ? 0.45 : 1)
    }

    private func modeButton(for mode: SpeedometerMode) -> some View {
        let isSelected = selectedMode == mode

        return Button {
            guard selectedMode != mode else { return }
            UISelectionFeedbackGenerator().selectionChanged()
            selectedModeRawValue = mode.rawValue
        } label: {
            VStack(spacing: 5) {
                Image(systemName: mode.icon)
                    .font(.system(size: 14, weight: .semibold))

                Text(mode.title)
                    .font(.caption2.weight(.medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .foregroundStyle(isSelected ? .white : .white.opacity(0.55))
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? AltitudeTheme.accent.opacity(0.22) : Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        isSelected ? AltitudeTheme.accent.opacity(0.85) : Color.white.opacity(0.08),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mode.title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: - Session Control

    private var sessionControlButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            store.toggleSpeedSession()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: store.isSpeedSessionActive ? "stop.fill" : "play.fill")
                    .font(.body.weight(.semibold))

                Text(store.isSpeedSessionActive ? "Stop Speed Test" : "Start Speed Test")
                    .font(.headline.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(.white)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        store.isSpeedSessionActive
                            ? Color.red.opacity(0.88)
                            : AltitudeTheme.accent.opacity(0.92)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(store.isSpeedSessionActive ? "Stop Speed Test" : "Start Speed Test")
    }

    // MARK: - Session Stats

    private var sessionStatsPanel: some View {
        VStack(spacing: 0) {
            HStack {
                Text("This Session")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.45))

                Spacer()

                if hasSessionStats {
                    Text(durationText(store.speedSessionDuration))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(store.isSpeedSessionActive ? AltitudeTheme.accent : .white.opacity(0.55))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 4)

            AltitudeMetricGrid(
                items: [
                    AltitudeMetricItem(label: "Duration", value: statDurationText),
                    AltitudeMetricItem(label: "Average Speed", value: statAverageSpeedText),
                    AltitudeMetricItem(label: "Distance", value: statDistanceText),
                    AltitudeMetricItem(label: "Max Speed", value: statMaxSpeedText),
                    AltitudeMetricItem(label: "Elevation Gain", value: statElevationGainText),
                ],
                columns: 3
            )
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var statDurationText: String {
        guard hasSessionStats else { return "—" }
        return durationText(store.speedSessionDuration)
    }

    private var statAverageSpeedText: String {
        guard hasSessionStats, store.speedSessionAverageSpeedKmh > 0 else { return "—" }
        return String(format: "%.1fkm/h", store.speedSessionAverageSpeedKmh)
    }

    private var statDistanceText: String {
        guard hasSessionStats, store.speedSessionDistanceMeters > 0 else {
            return hasSessionStats ? "0m" : "—"
        }
        if store.speedSessionDistanceMeters >= 1000 {
            return String(format: "%.2fkm", store.speedSessionDistanceMeters / 1000)
        }
        return String(format: "%.0fm", store.speedSessionDistanceMeters)
    }

    private var statMaxSpeedText: String {
        guard hasSessionStats, store.speedSessionMaxSpeedKmh > 0 else { return "—" }
        return String(format: "%.1fkm/h", store.speedSessionMaxSpeedKmh)
    }

    private var statElevationGainText: String {
        guard hasSessionStats, store.speedSessionElevationGainMeters > 0 else {
            return hasSessionStats ? "0m" : "—"
        }
        return String(format: "%.0fm", store.speedSessionElevationGainMeters)
    }

    private func durationText(_ interval: TimeInterval) -> String {
        let totalSeconds = max(0, Int(interval.rounded()))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

#Preview("Active Session") {
    GPSTabView(store: OutdoorDashboardStore.preview())
}

#Preview("Idle") {
    GPSTabView(store: OutdoorDashboardStore.previewIdle())
}
