//
//  AltitudeTabView.swift
//  AltiPin
//

import SwiftUI

struct AltitudeTabView: View {
    @ObservedObject var store: OutdoorDashboardStore

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 8) {
                Text("实时海拔")
                    .font(.caption)
                    .foregroundStyle(.gray)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(store.elevationMeters, format: .number.precision(.fractionLength(0)))
                        .font(.system(size: 72, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white)
                    Text("m")
                        .font(.system(.title, design: .monospaced))
                        .foregroundStyle(.gray)
                }
            }

            OLEDMetricCard(title: "当前气压", icon: "gauge.with.needle") {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(store.pressureHPa, format: .number.precision(.fractionLength(1)))
                    Text(" hPa")
                        .font(.system(.title3, design: .monospaced))
                        .foregroundStyle(.gray)
                }
            }
            .padding(.horizontal, 24)

            Text("GPS + 气压计融合校准")
                .font(.caption)
                .foregroundStyle(.gray.opacity(0.8))

            Spacer()
        }
        .oledTabBackground()
    }
}

#Preview {
    AltitudeTabView(store: OutdoorDashboardStore.preview())
}
