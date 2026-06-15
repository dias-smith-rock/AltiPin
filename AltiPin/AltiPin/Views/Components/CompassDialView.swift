//
//  CompassDialView.swift
//  AltiPin
//

import SwiftUI

struct CompassDialView: View {
    let heading: Double
    var directionName: String = ""

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                .frame(width: 260, height: 260)

            Circle()
                .stroke(Color.white.opacity(0.06), lineWidth: 12)
                .frame(width: 220, height: 220)

            ZStack {
                ForEach(0..<12, id: \.self) { index in
                    let angle = Double(index) * 30
                    VStack(spacing: 6) {
                        Text(tickLabel(for: angle))
                            .font(.system(.caption2, design: .monospaced))
                            .fontWeight(angle == 0 ? .bold : .regular)
                            .foregroundStyle(angle == 0 ? .white : .gray)

                        Rectangle()
                            .fill(angle == 0 ? Color.white : Color.gray.opacity(0.55))
                            .frame(width: angle == 0 ? 2 : 1, height: angle == 0 ? 18 : 12)
                    }
                    .offset(y: -118)
                    .rotationEffect(.degrees(angle))
                }

                Capsule()
                    .fill(Color.red)
                    .frame(width: 3, height: 28)
                    .offset(y: -96)
            }
            .rotationEffect(.degrees(-heading))

            Circle()
                .fill(Color.white)
                .frame(width: 8, height: 8)

            Image(systemName: "triangle.fill")
                .font(.caption)
                .foregroundStyle(.red)
                .rotationEffect(.degrees(180))
                .offset(y: -138)
        }
        .frame(width: 280, height: 280)
        .accessibilityLabel("数字罗盘")
        .accessibilityValue("\(directionName) \(Int(heading.rounded()))度")
    }

    private func tickLabel(for angle: Double) -> String {
        switch Int(angle) {
        case 0: "N"
        case 90: "E"
        case 180: "S"
        case 270: "W"
        default: "\(Int(angle))"
        }
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        CompassDialView(heading: 61, directionName: "东北")
    }
}
