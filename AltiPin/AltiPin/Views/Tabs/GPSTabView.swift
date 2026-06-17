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

    var body: some View {
        VStack(spacing: 0) {
            gpsHeader
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 12)

            modePicker
                .padding(.horizontal, 16)
                .padding(.bottom, 12)

            SpeedometerGaugeView(
                currentSpeed: store.speedKmh,
                maxSpeed: selectedMode.maxSpeed,
                majorTickInterval: selectedMode.majorTickInterval
            )
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeOut(duration: 0.25), value: selectedModeRawValue)

            gpsFooter
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        }
        .oledTabBackground()
    }

    // MARK: - Header

    private var gpsHeader: some View {
        HStack {
            Text("GPS测速")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.9))

            Spacer()

            Text(selectedMode.title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AltitudeTheme.accent)
        }
    }

    // MARK: - Mode Picker

    private var modePicker: some View {
        HStack(spacing: 8) {
            ForEach(SpeedometerMode.allCases) { mode in
                modeButton(for: mode)
            }
        }
    }

    private func modeButton(for mode: SpeedometerMode) -> some View {
        let isSelected = selectedMode == mode

        return Button {
            guard selectedMode != mode else { return }
            UISelectionFeedbackGenerator().selectionChanged()
            selectedModeRawValue = mode.rawValue
        } label: {
            VStack(spacing: 6) {
                Image(systemName: mode.icon)
                    .font(.system(size: 15, weight: .semibold))

                Text(mode.title)
                    .font(.caption2.weight(.medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .foregroundStyle(isSelected ? .white : .white.opacity(0.55))
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? AltitudeTheme.accent.opacity(0.22) : Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
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

    // MARK: - Footer

    private var gpsFooter: some View {
        HStack(spacing: 12) {
            accuracyCard(
                title: "水平精度",
                value: store.horizontalAccuracy,
                icon: "arrow.left.and.right"
            )
            accuracyCard(
                title: "垂直精度",
                value: store.verticalAccuracy,
                icon: "arrow.up.and.down"
            )
        }
    }

    @ViewBuilder
    private func accuracyCard(title: String, value: Double, icon: String) -> some View {
        OLEDMetricCard(title: title, icon: icon) {
            if value >= 0 {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text("±")
                    Text(value, format: .number.precision(.fractionLength(0)))
                    Text(" m")
                        .font(.system(.title3, design: .monospaced))
                        .foregroundStyle(.gray)
                }
            } else {
                Text("—")
                    .foregroundStyle(.gray)
            }
        }
    }
}

#Preview {
    GPSTabView(store: OutdoorDashboardStore.preview())
}
