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
    let onRefresh: () -> Void
    let onSettings: () -> Void

    private var isIndoorMode: Bool {
        navigationEnvironment == .indoor
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            heroBackground

            HStack {
                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(width: 36, height: 36)
                }

                Spacer()

                Button(action: onSettings) {
                    Image(systemName: "gearshape")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(width: 36, height: 36)
                }
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
        .frame(height: isIndoorMode ? 220 : 200)
    }

    private var heroSubtitle: String {
        guard isIndoorMode else {
            if isManualNavigationOverride { return "当前海拔 · 手动室外" }
            return "当前海拔:"
        }
        if needsFloorCalibration { return "室内模式 · 待校准" }
        if isManualNavigationOverride { return "室内模式 · 手动" }
        return "室内气压推断:"
    }

    private var heroPrimaryValue: String {
        guard isIndoorMode else {
            return "\(Int(elevationMeters.rounded()))m"
        }
        if needsFloorCalibration {
            return "—"
        }
        if let floor = estimatedIndoorFloor {
            return "\(floor) 楼"
        }
        return "推算中…"
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
            return "请设定当前楼层 · 参考海拔 \(Int(elevationMeters.rounded()))m"
        }
        if floorCalibrationSource == .persisted {
            let name = matchedBuildingLabel.map { " \($0)" } ?? ""
            return "已恢复历史校准\(name) · 参考海拔 \(Int(elevationMeters.rounded()))m"
        }
        if isIndoorFloorCalibrated {
            return "室内模式 · 参考海拔 \(Int(elevationMeters.rounded()))m"
        }
        return "室内模式 · 参考海拔 \(Int(elevationMeters.rounded()))m"
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
        onRefresh: {},
        onSettings: {}
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
        onRefresh: {},
        onSettings: {}
    )
    .background(Color.black)
}

#Preview("Indoor Needs Calibration") {
    AltitudeHeroHeader(
        elevationMeters: 72,
        verticalAccuracy: -1,
        navigationEnvironment: .indoor,
        needsFloorCalibration: true,
        onRefresh: {},
        onSettings: {}
    )
    .background(Color.black)
}
