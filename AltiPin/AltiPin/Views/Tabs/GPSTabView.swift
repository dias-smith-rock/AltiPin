//
//  GPSTabView.swift
//  AltiPin
//

import SwiftUI

struct GPSTabView: View {
    @ObservedObject var store: OutdoorDashboardStore

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "location.fill")
                    .font(.title)
                    .foregroundStyle(.white.opacity(0.8))

                Text(store.coordinateDMSString)
                    .font(.system(.title3, design: .monospaced))
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                Text(store.coordinateDecimalString)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            VStack(spacing: 12) {
                accuracyRow(
                    title: "水平精度",
                    value: store.horizontalAccuracy,
                    icon: "arrow.left.and.right"
                )
                accuracyRow(
                    title: "垂直精度",
                    value: store.verticalAccuracy,
                    icon: "arrow.up.and.down"
                )
            }
            .padding(.horizontal, 24)

            Spacer()
        }
        .oledTabBackground()
    }

    @ViewBuilder
    private func accuracyRow(title: String, value: Double, icon: String) -> some View {
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
