//
//  CompassDialView.swift
//  AltiPin
//

import SwiftUI

struct CompassDialView: View {
    let heading: Double
    var directionName: String = ""
    var levelOffsetX: Double = 0
    var levelOffsetY: Double = 0

    private let dialSize: CGFloat = 320
    private let outerRadius: CGFloat = 148
    private let innerRadius: CGFloat = 100
    private let levelTravel: CGFloat = 36

    var body: some View {
        ZStack {
            rotatingDial

            fixedHeadingIndicator

            levelCrosshair
        }
        .frame(width: dialSize, height: dialSize)
        .accessibilityLabel("数字罗盘")
        .accessibilityValue("\(directionName) \(Int(heading.rounded()))度")
    }

    // MARK: - Rotating Dial

    private var rotatingDial: some View {
        ZStack {
            ForEach(0..<360, id: \.self) { degree in
                tickMark(for: degree)
            }

            ForEach(0..<12, id: \.self) { index in
                let angle = Double(index) * 30
                Text("\(Int(angle))")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85))
                    .offset(y: -outerRadius + 14)
                    .rotationEffect(.degrees(angle))
            }

            Circle()
                .fill(Color.white.opacity(0.06))
                .frame(width: innerRadius * 2, height: innerRadius * 2)

            ForEach(cardinalDirections, id: \.label) { item in
                Text(item.label)
                    .font(.system(size: 18, weight: item.label == "北" ? .bold : .regular))
                    .foregroundStyle(item.label == "北" ? .white : .white.opacity(0.75))
                    .offset(y: -innerRadius + 24)
                    .rotationEffect(.degrees(item.angle))
            }

            Image(systemName: "triangle.fill")
                .font(.system(size: 10))
                .foregroundStyle(.red)
                .rotationEffect(.degrees(180))
                .offset(y: -innerRadius + 8)
        }
        .rotationEffect(.degrees(-heading))
    }

    // MARK: - Fixed Overlay

    private var fixedHeadingIndicator: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.white)
                .frame(width: 2, height: 24)
            Spacer()
        }
        .frame(height: dialSize)
    }

    private var levelCrosshair: some View {
        ZStack {
            Rectangle()
                .fill(Color.white.opacity(0.35))
                .frame(width: 44, height: 1)
            Rectangle()
                .fill(Color.white.opacity(0.35))
                .frame(width: 1, height: 44)

            Circle()
                .stroke(Color.white.opacity(0.25), lineWidth: 1)
                .frame(width: 10, height: 10)

            levelBubbleCluster
        }
    }

    private var levelBubbleCluster: some View {
        let x = levelOffsetX * levelTravel
        let y = levelOffsetY * levelTravel

        return ZStack {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color.orange)
                    .frame(width: 8, height: 8)
                    .offset(
                        x: x + CGFloat(index - 1) * 3,
                        y: y + CGFloat(index - 1) * 2
                    )
            }
        }
        .animation(.interactiveSpring(response: 0.25, dampingFraction: 0.82), value: levelOffsetX)
        .animation(.interactiveSpring(response: 0.25, dampingFraction: 0.82), value: levelOffsetY)
    }

    // MARK: - Helpers

    private var cardinalDirections: [(label: String, angle: Double)] {
        [
            ("北", 0),
            ("东", 90),
            ("南", 180),
            ("西", 270),
        ]
    }

    @ViewBuilder
    private func tickMark(for degree: Int) -> some View {
        let isMajor = degree % 30 == 0
        let isMedium = degree % 5 == 0

        Rectangle()
            .fill(Color.white.opacity(isMajor ? 0.9 : (isMedium ? 0.55 : 0.25)))
            .frame(
                width: isMajor ? 1.5 : 1,
                height: isMajor ? 16 : (isMedium ? 10 : 5)
            )
            .offset(y: -outerRadius + (isMajor ? 8 : 4))
            .rotationEffect(.degrees(Double(degree)))
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        CompassDialView(
            heading: 33,
            directionName: "东北",
            levelOffsetX: 0.2,
            levelOffsetY: -0.1
        )
    }
}
