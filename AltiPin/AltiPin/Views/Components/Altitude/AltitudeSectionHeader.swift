//
//  AltitudeSectionHeader.swift
//  AltiPin
//

import SwiftUI

struct AltitudeSectionHeader: View {
    let icon: String
    let title: String
    var trailingText: String?

    var body: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(AltitudeTheme.accent)
                .frame(width: 3, height: 18)

            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(AltitudeTheme.accent)

            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.9))

            Spacer()

            if let trailingText {
                Text(trailingText)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

#Preview {
    AltitudeSectionHeader(icon: "globe.asia.australia.fill", title: L10n.t("Coordinates"), trailingText: "±6.10m")
        .background(Color.black)
}
