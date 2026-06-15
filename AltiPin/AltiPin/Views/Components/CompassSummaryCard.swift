//
//  CompassSummaryCard.swift
//  AltiPin
//

import SwiftUI

struct CompassSummaryCard: View {
    let title: String
    let icon: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.orange)
                Spacer()
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.65))
            }

            Text(value)
                .font(.system(.title3, design: .rounded))
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(white: 0.15))
        )
    }
}

#Preview {
    HStack(spacing: 10) {
        CompassSummaryCard(title: "海拔", icon: "mountain.2.fill", value: "75米")
        CompassSummaryCard(title: "大气压", icon: "gauge.with.dots.needle.67percent", value: "1013 hPa")
        CompassSummaryCard(title: "风向", icon: "wind", value: "西南风")
    }
    .padding()
    .background(Color.black)
}
