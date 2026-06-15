//
//  OLEDMetricCard.swift
//  AltiPin
//

import SwiftUI

struct OLEDMetricCard<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.gray)
                Spacer()
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }

            content
                .font(.system(.title, design: .monospaced))
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}
