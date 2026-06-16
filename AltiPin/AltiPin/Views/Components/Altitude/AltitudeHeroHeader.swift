//
//  AltitudeHeroHeader.swift
//  AltiPin
//

import SwiftUI
import UIKit

struct AltitudeHeroHeader: View {
    let elevationMeters: Double
    let verticalAccuracy: Double
    let onRefresh: () -> Void
    let onSettings: () -> Void

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
                    Text("当前海拔:")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.85))

                    Text("\(Int(elevationMeters.rounded()))m")
                        .font(.system(size: 48, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                }

                Spacer()

                if verticalAccuracy >= 0 {
                    Text(String(format: "±%.2fm", verticalAccuracy))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .frame(height: 200)
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

#Preview {
    AltitudeHeroHeader(
        elevationMeters: 83,
        verticalAccuracy: 9.88,
        onRefresh: {},
        onSettings: {}
    )
    .background(Color.black)
}
