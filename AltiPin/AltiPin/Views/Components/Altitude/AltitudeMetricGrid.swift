//
//  AltitudeMetricGrid.swift
//  AltiPin
//

import SwiftUI

struct AltitudeMetricItem: Identifiable {
    let id = UUID()
    let label: LocalizedStringKey
    let value: String
}

struct AltitudeMetricGrid: View {
    let items: [AltitudeMetricItem]
    var columns: Int = 2

    var body: some View {
        let rows = stride(from: 0, to: items.count, by: columns).map { start in
            Array(items[start..<min(start + columns, items.count)])
        }

        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                HStack(spacing: 0) {
                    ForEach(row) { item in
                        metricCell(item)
                    }

                    if row.count < columns {
                        Spacer(minLength: 0)
                            .frame(maxWidth: .infinity)
                    }
                }

                if index < rows.count - 1 {
                    Divider()
                        .background(Color.white.opacity(0.08))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private func metricCell(_ item: AltitudeMetricItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.label)
                .font(.caption)
                .foregroundStyle(AltitudeTheme.accent)

            Text(item.value)
                .font(.system(.title3, design: .rounded))
                .fontWeight(.medium)
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
    }
}

#Preview {
    AltitudeMetricGrid(items: [
        AltitudeMetricItem(label: "Celsius", value: "99.69°C"),
        AltitudeMetricItem(label: "Fahrenheit", value: "211.44°F"),
    ])
    .background(Color.black)
}
