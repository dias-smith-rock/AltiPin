//
//  SpeedometerGaugeView.swift
//  AltiPin
//

import SwiftUI

struct SpeedometerGaugeView: View {
    let currentSpeed: Double
    let maxSpeed: Double
    let majorTickInterval: Double

    private let arcSpanDegrees: Double = 270
    private let arcStartDegrees: Double = 135

    private var clampedSpeed: Double {
        guard maxSpeed > 0 else { return 0 }
        return min(max(currentSpeed, 0), maxSpeed)
    }

    private var speedProgress: Double {
        guard maxSpeed > 0 else { return 0 }
        return clampedSpeed / maxSpeed
    }

    private var majorTickValues: [Double] {
        guard majorTickInterval > 0, maxSpeed >= 0 else { return [0] }
        var values: [Double] = []
        var value = 0.0
        while value <= maxSpeed + 0.0001 {
            values.append(value)
            value += majorTickInterval
        }
        return values
    }

    private var minorTickValues: [Double] {
        guard majorTickInterval > 0 else { return [] }
        let step = majorTickInterval / 5
        var values: [Double] = []
        for major in majorTickValues.dropLast() {
            for index in 1...4 {
                values.append(major + step * Double(index))
            }
        }
        return values
    }

    var body: some View {
        VStack(spacing: 16) {
            gaugeFace
            speedReadout
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("速度表")
        .accessibilityValue("\(clampedSpeed, format: .number.precision(.fractionLength(2))) 公里每小时")
    }

    // MARK: - Gauge Face

    private var gaugeFace: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            let layout = GaugeLayout(size: size)

            ZStack {
                trackArc(layout: layout, progress: 1)
                progressArc(layout: layout)
                minorTicks(layout: layout)
                majorTicks(layout: layout)
                majorLabels(layout: layout)
                needleLayer(layout: layout)
            }
            .frame(width: size, height: size)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func trackArc(layout: GaugeLayout, progress: Double) -> some View {
        GaugeArc(progress: progress)
            .stroke(
                AngularGradient(
                    gradient: Gradient(colors: [
                        Color.white.opacity(0.06),
                        Color.white.opacity(0.14),
                        Color.white.opacity(0.06),
                    ]),
                    center: .center,
                    startAngle: .degrees(layout.swiftStartAngle),
                    endAngle: .degrees(layout.swiftEndAngle)
                ),
                style: StrokeStyle(lineWidth: layout.trackWidth, lineCap: .round)
            )
            .frame(width: layout.diameter, height: layout.diameter)
    }

    private func progressArc(layout: GaugeLayout) -> some View {
        GaugeArc(progress: speedProgress)
            .stroke(
                AngularGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.95, green: 0.55, blue: 0.12).opacity(0.35),
                        Color(red: 0.95, green: 0.55, blue: 0.12),
                        Color(red: 0.98, green: 0.72, blue: 0.18),
                    ]),
                    center: .center,
                    startAngle: .degrees(layout.swiftStartAngle),
                    endAngle: .degrees(layout.swiftEndAngle)
                ),
                style: StrokeStyle(lineWidth: layout.trackWidth, lineCap: .round)
            )
            .frame(width: layout.diameter, height: layout.diameter)
            .animation(.easeOut(duration: 0.25), value: clampedSpeed)
    }

    private func minorTicks(layout: GaugeLayout) -> some View {
        ForEach(minorTickValues, id: \.self) { speed in
            tickMark(
                speed: speed,
                layout: layout,
                width: layout.minorTickWidth,
                length: layout.minorTickLength,
                opacity: 0.28
            )
        }
    }

    private func majorTicks(layout: GaugeLayout) -> some View {
        ForEach(majorTickValues, id: \.self) { speed in
            tickMark(
                speed: speed,
                layout: layout,
                width: layout.majorTickWidth,
                length: layout.majorTickLength,
                opacity: 0.92
            )
        }
    }

    private func majorLabels(layout: GaugeLayout) -> some View {
        ForEach(majorTickValues, id: \.self) { speed in
            Text(labelText(for: speed))
                .font(.system(size: layout.labelFontSize, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.82))
                .offset(y: -layout.labelRadius)
                .rotationEffect(rotation(for: speed))
        }
    }

    private func tickMark(
        speed: Double,
        layout: GaugeLayout,
        width: CGFloat,
        length: CGFloat,
        opacity: Double
    ) -> some View {
        Rectangle()
            .fill(Color.white.opacity(opacity))
            .frame(width: width, height: length)
            .offset(y: -layout.tickRadius)
            .rotationEffect(rotation(for: speed))
    }

    private func needleLayer(layout: GaugeLayout) -> some View {
        ZStack {
            Rectangle()
                .fill(Color.red.opacity(0.95))
                .frame(width: layout.needleWidth, height: layout.needleLength)
                .offset(y: -layout.needleLength / 2)
                .rotationEffect(rotation(for: clampedSpeed))
                .animation(.easeOut(duration: 0.25), value: clampedSpeed)

            Circle()
                .fill(Color.red.opacity(0.95))
                .frame(width: layout.hubSize, height: layout.hubSize)

            Circle()
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
                .frame(width: layout.hubSize + 6, height: layout.hubSize + 6)
        }
    }

    // MARK: - Speed Readout

    private var speedReadout: some View {
        VStack(spacing: 4) {
            Text(clampedSpeed, format: .number.precision(.fractionLength(2)))
                .font(.system(size: 56, weight: .thin, design: .rounded))
                .foregroundStyle(.white)
                .contentTransition(.numericText())
                .animation(.easeOut(duration: 0.25), value: clampedSpeed)

            Text("km/h")
                .font(.subheadline)
                .foregroundStyle(.gray)
        }
    }

    // MARK: - Geometry

    private func rotation(for speed: Double) -> Angle {
        guard maxSpeed > 0 else { return .degrees(-135) }
        let clamped = min(max(speed, 0), maxSpeed)
        return .degrees((clamped / maxSpeed) * arcSpanDegrees - 135)
    }

    private func labelText(for speed: Double) -> String {
        if speed.rounded() == speed {
            return String(format: "%.0f", speed)
        }
        return String(format: "%.1f", speed)
    }
}

// MARK: - Layout

private struct GaugeLayout {
    let size: CGFloat

    var diameter: CGFloat { size * 0.92 }
    var trackWidth: CGFloat { size * 0.028 }
    var tickRadius: CGFloat { size * 0.36 }
    var labelRadius: CGFloat { size * 0.28 }
    var majorTickLength: CGFloat { size * 0.045 }
    var minorTickLength: CGFloat { size * 0.024 }
    var majorTickWidth: CGFloat { max(1.5, size * 0.0045) }
    var minorTickWidth: CGFloat { max(1, size * 0.0025) }
    var labelFontSize: CGFloat { size * 0.052 }
    var needleLength: CGFloat { size * 0.30 }
    var needleWidth: CGFloat { max(1.5, size * 0.006) }
    var hubSize: CGFloat { size * 0.028 }

    var swiftStartAngle: Double { 135 - 90 }
    var swiftEndAngle: Double { 135 + 270 - 90 }
}

// MARK: - Arc Shape

private struct GaugeArc: Shape {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let clampedProgress = min(max(progress, 0), 1)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let startAngle = Angle.degrees(135 - 90)
        let endAngle = Angle.degrees(135 - 90 + 270 * clampedProgress)

        var path = Path()
        path.addArc(
            center: center,
            radius: radius,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: true
        )
        return path
    }
}

// MARK: - Previews

#Preview("Driving 320") {
    ZStack {
        Color.black.ignoresSafeArea()
        SpeedometerGaugeView(
            currentSpeed: 128,
            maxSpeed: 320,
            majorTickInterval: 40
        )
        .padding()
    }
}

#Preview("Cycling 80") {
    ZStack {
        Color.black.ignoresSafeArea()
        SpeedometerGaugeView(
            currentSpeed: 24.5,
            maxSpeed: 80,
            majorTickInterval: 10
        )
        .padding()
    }
}

#Preview("Running 40") {
    ZStack {
        Color.black.ignoresSafeArea()
        SpeedometerGaugeView(
            currentSpeed: 8.75,
            maxSpeed: 40,
            majorTickInterval: 2
        )
        .padding()
    }
}

#Preview("Walking 16") {
    ZStack {
        Color.black.ignoresSafeArea()
        SpeedometerGaugeView(
            currentSpeed: 4.2,
            maxSpeed: 16,
            majorTickInterval: 2
        )
        .padding()
    }
}
