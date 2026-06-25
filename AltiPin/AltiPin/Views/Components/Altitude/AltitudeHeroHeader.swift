//
//  AltitudeHeroHeader.swift
//  AltiPin
//

import SwiftUI
import UIKit

struct AltitudeHeroHeader: View {
    let elevationMeters: Double
    let verticalAccuracy: Double
    var navigationEnvironment: NavigationEnvironment = .outdoor
    var estimatedIndoorFloor: Int?
    var isIndoorFloorCalibrated: Bool = false
    var needsFloorCalibration: Bool = false
    var matchedBuildingLabel: String?
    var floorCalibrationSource: FloorCalibrationSource?
    var isManualNavigationOverride: Bool = false
    var isRefreshDisabled: Bool = false
    let onRefresh: () -> Void

    private var isIndoorMode: Bool {
        navigationEnvironment == .indoor
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            heroBackground

            HStack {
                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(isRefreshDisabled ? 0.35 : 0.85))
                }
                .buttonStyle(.plain)
                .disabled(isRefreshDisabled)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(heroSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.85))

                    Text(heroPrimaryValue)
                        .font(.system(size: 48, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)

                    if isIndoorMode {
                        indoorModeBadge
                    }
                }

                Spacer()

                if !isIndoorMode, verticalAccuracy >= 0 {
                    Text(String(format: "±%.2fm", verticalAccuracy))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .frame(height: 220)
    }

    private var heroSubtitle: String {
        guard isIndoorMode else {
            if isManualNavigationOverride { return L10n.t("Current Elevation · Manual Outdoor") }
            return L10n.t("Current Elevation:")
        }
        if needsFloorCalibration { return L10n.t("Indoor Mode · Needs Calibration") }
        if isManualNavigationOverride { return L10n.t("Indoor Mode · Manual") }
        return L10n.t("Barometric Inference:")
    }

    private var heroPrimaryValue: String {
        guard isIndoorMode else {
            return "\(Int(elevationMeters.rounded()))m"
        }
        if needsFloorCalibration {
            return "—"
        }
        if let floor = estimatedIndoorFloor {
            return L10n.format("Floor %lld", floor)
        }
        return L10n.t("Estimating…")
    }

    private var indoorModeBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "building.2.fill")
                .font(.caption2)
            Text(indoorBadgeText)
                .font(.caption)
        }
        .foregroundStyle(.white.opacity(0.7))
        .padding(.top, 2)
    }

    private var indoorBadgeText: String {
        if needsFloorCalibration {
            return L10n.t("Set Current Floor")
        }
        if floorCalibrationSource == .persisted {
            let name = matchedBuildingLabel.map { " \($0)" } ?? ""
            return L10n.format("Restored historical calibration%@", name)
        }
        return L10n.t("Indoor Mode")
    }

    private var heroBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.12, green: 0.28, blue: 0.55),
                    Color(red: 0.05, green: 0.10, blue: 0.22),
                    Color.black,
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            if UIImage(named: "AltitudeHeroMountain") != nil {
                Image("AltitudeHeroMountain")
                    .resizable()
                    .scaledToFill()
                    .opacity(0.85)
            } else {
                Image(systemName: "mountain.2.fill")
                    .font(.system(size: 120))
                    .foregroundStyle(.white.opacity(0.08))
                    .offset(y: -20)
            }

            LinearGradient(
                colors: [.clear, .black.opacity(0.55)],
                startPoint: .center,
                endPoint: .bottom
            )
        }
        .clipped()
    }
}

#Preview("Outdoor") {
    AltitudeHeroHeader(
        elevationMeters: 83,
        verticalAccuracy: 9.88,
        onRefresh: {}
    )
    .background(Color.black)
}

#Preview("Indoor Calibrated") {
    AltitudeHeroHeader(
        elevationMeters: 91,
        verticalAccuracy: -1,
        navigationEnvironment: .indoor,
        estimatedIndoorFloor: 3,
        isIndoorFloorCalibrated: true,
        floorCalibrationSource: .manual,
        onRefresh: {}
    )
    .background(Color.black)
}

#Preview("Indoor Needs Calibration") {
    AltitudeHeroHeader(
        elevationMeters: 72,
        verticalAccuracy: -1,
        navigationEnvironment: .indoor,
        needsFloorCalibration: true,
        onRefresh: {}
    )
    .background(Color.black)
}
