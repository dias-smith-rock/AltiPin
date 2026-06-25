//
//  ElevationSessionChart.swift
//  AltiPin
//
//  最近 20 次海拔采样的多段会话截断曲线图。
//

import Charts
import SwiftUI

private struct ChartPlottablePoint: Identifiable {
    let id: UUID
    let slot: Int
    let elevation: Double
    let isIndoor: Bool

    init(from point: HistoryPoint, slot: Int) {
        self.id = point.id
        self.slot = slot
        self.elevation = point.elevation
        self.isIndoor = point.isIndoor
    }
}

struct ElevationSessionChart: View {
    let recentPoints: [HistoryPoint]

    private var windowSize: Int { HistoryPointSessionConfig.slidingWindowCount }

    private var segmentedPoints: [[HistoryPoint]] {
        recentPoints.segmentedPoints
    }

    private var sessionGaps: [(afterSegmentIndex: Int, duration: TimeInterval)] {
        recentPoints.sessionGapDurations
    }

    private var maxElevation: Double? {
        recentPoints.map(\.elevation).max()
    }

    private var minElevation: Double? {
        recentPoints.map(\.elevation).min()
    }

    private var elevationSpan: Double? {
        guard let maxElevation, let minElevation else { return nil }
        return maxElevation - minElevation
    }

    private var yDomain: ClosedRange<Double> {
        guard let minElevation, let maxElevation else { return 0...100 }
        let span = max(maxElevation - minElevation, 5)
        let padding = max(span * 0.15, 2)
        return (minElevation - padding)...(maxElevation + padding)
    }

    private var areaBaseline: Double { yDomain.lowerBound }

    var body: some View {
        VStack(spacing: 8) {
            headerRow

            if recentPoints.isEmpty {
                emptyState
            } else {
                chartCard
            }
        }
        .padding(.bottom, 8)
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack {
            Text(L10n.format("Sampled %lld/%lld · 1 min interval", recentPoints.count, windowSize))
                .font(.caption)
                .foregroundStyle(.white.opacity(0.45))

            Spacer()

            Text(deltaHeaderText)
                .font(.caption)
                .foregroundStyle(AltitudeTheme.accent)
        }
        .padding(.horizontal, 16)
    }

    private var deltaHeaderText: String {
        guard recentPoints.count >= 2, let span = elevationSpan else {
            return "Δ —"
        }
        if span < 0.05 {
            return "Δ —"
        }
        return String(format: "Δ %.1fm", span)
    }

    private var emptyState: some View {
        Text(L10n.t("No elevation session data"))
            .font(.caption)
            .foregroundStyle(.white.opacity(0.45))
            .frame(height: 180)
            .frame(maxWidth: .infinity)
    }

    // MARK: - Chart Card

    private var chartCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(white: 0.08))

            chartContent
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .frame(height: 180)
        .padding(.horizontal, 12)
        .clipped()
    }

    private var chartContent: some View {
        Chart {
            sessionMarks
            gapAnnotations
            endpointPointMarks
        }
        .chartXScale(domain: 0...(windowSize - 1))
        .chartYScale(domain: yDomain)
        .chartXAxis {
            AxisMarks(values: [0, windowSize - 1]) { value in
                AxisValueLabel(anchor: xAxisLabelAnchor(for: value.as(Int.self))) {
                    if let index = value.as(Int.self) {
                        Text(index == 0 ? L10n.t("20 samples ago") : L10n.t("Current"))
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.45))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                if let elevation = value.as(Double.self) {
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                        .foregroundStyle(.white.opacity(0.08))
                    AxisValueLabel {
                        Text("\(Int(elevation.rounded()))m")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.35))
                    }
                }
            }
        }
        .chartPlotStyle { plot in
            plot.background(.clear)
        }
        .chartLegend(.hidden)
    }

    private func xAxisLabelAnchor(for index: Int?) -> UnitPoint {
        guard let index else { return .center }
        return index == 0 ? .topLeading : .topTrailing
    }

    // MARK: - Session Marks

    @ChartContentBuilder
    private var sessionMarks: some ChartContent {
        ForEach(segmentedPoints.indices, id: \.self) { segmentIndex in
            let session = segmentedPoints[segmentIndex]
            let plottables = plottablePoints(for: session)
            let interpolation = interpolationMethod(for: session)
            let seriesID = "session-\(segmentIndex)"

            if session.count == 1, let only = plottables.first {
                singlePointMarks(for: only)
            } else {
                // AreaMark 必须成组绘制，不能与 LineMark 交错，否则每点独立填充成竖条
                if session.count >= 3 {
                    ForEach(plottables) { item in
                        AreaMark(
                            x: .value(L10n.t("Order"), item.slot),
                            yStart: .value(L10n.t("Baseline"), areaBaseline),
                            yEnd: .value(L10n.t("Elevation"), item.elevation),
                            series: .value(L10n.t("Session"), seriesID)
                        )
                        .foregroundStyle(AltitudeTheme.chartLine.opacity(0.22))
                        .interpolationMethod(interpolation)
                    }
                }

                ForEach(plottables) { item in
                    LineMark(
                        x: .value(L10n.t("Order"), item.slot),
                        y: .value(L10n.t("Elevation"), item.elevation),
                        series: .value(L10n.t("Session"), seriesID)
                    )
                    .foregroundStyle(AltitudeTheme.chartLine)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(interpolation)
                }
            }
        }
    }

    @ChartContentBuilder
    private func singlePointMarks(for item: ChartPlottablePoint) -> some ChartContent {
        RuleMark(
            x: .value(L10n.t("Order"), item.slot),
            yStart: .value(L10n.t("Baseline"), areaBaseline),
            yEnd: .value(L10n.t("Elevation"), item.elevation)
        )
        .foregroundStyle(AltitudeTheme.chartLine.opacity(0.35))
        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))

        PointMark(
            x: .value(L10n.t("Order"), item.slot),
            y: .value(L10n.t("Elevation"), item.elevation)
        )
        .foregroundStyle(AltitudeTheme.chartLine)
        .symbolSize(64)
    }

    /// 2 点或少变化时，在端点叠加圆点便于辨认
    @ChartContentBuilder
    private var endpointPointMarks: some ChartContent {
        if recentPoints.count >= 2, recentPoints.count < 5 {
            ForEach(recentPoints) { point in
                if let slot = recentPoints.chartSlotIndex(for: point) {
                    PointMark(
                        x: .value(L10n.t("Order"), slot),
                        y: .value(L10n.t("Elevation"), point.elevation)
                    )
                    .foregroundStyle(AltitudeTheme.chartLine)
                    .symbolSize(36)
                }
            }
        }
    }

    private func plottablePoints(for session: [HistoryPoint]) -> [ChartPlottablePoint] {
        session.compactMap { point in
            guard let slot = recentPoints.chartSlotIndex(for: point) else { return nil }
            return ChartPlottablePoint(from: point, slot: slot)
        }
    }

    private func interpolationMethod(for session: [HistoryPoint]) -> InterpolationMethod {
        if session.contains(where: \.isIndoor) {
            return .stepCenter
        }
        switch session.count {
        case 0, 1, 2:
            return .linear
        default:
            return .catmullRom
        }
    }

    @ChartContentBuilder
    private var gapAnnotations: some ChartContent {
        ForEach(sessionGaps, id: \.afterSegmentIndex) { gap in
            if let midpoint = gapMidpointSlot(for: gap) {
                RuleMark(x: .value(L10n.t("Gap"), midpoint))
                    .foregroundStyle(.white.opacity(0.06))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 5]))
                    .annotation(position: .overlay, alignment: .center) {
                        Text(L10n.format("System sleep %@", Self.formatGapDuration(gap.duration)))
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.32))
                            .multilineTextAlignment(.center)
                            .fixedSize()
                    }
            }
        }
    }

    private func gapMidpointSlot(for gap: (afterSegmentIndex: Int, duration: TimeInterval)) -> Double? {
        let leftSegment = segmentedPoints[gap.afterSegmentIndex]
        let rightSegment = segmentedPoints[gap.afterSegmentIndex + 1]
        guard let leftLast = leftSegment.last,
              let rightFirst = rightSegment.first,
              let leftSlot = recentPoints.chartSlotIndex(for: leftLast),
              let rightSlot = recentPoints.chartSlotIndex(for: rightFirst) else {
            return nil
        }
        return Double(leftSlot + rightSlot) / 2.0
    }

    private static func formatGapDuration(_ interval: TimeInterval) -> String {
        guard interval.isFinite, interval > 0 else { return "—" }
        if interval >= 3600 {
            let hours = interval / 3600
            return hours >= 10
                ? L10n.format("%.0f hr", hours)
                : L10n.format("%.1f hr", hours)
        }
        let minutes = max(1, Int((interval / 60).rounded()))
        return L10n.format("%lld min", minutes)
    }
}

#Preview("Multi-Session") {
    ElevationSessionChart(recentPoints: HistoryPoint.mockPoints)
        .padding(.vertical, 12)
        .background(Color.black)
}

#Preview("Two Points Flat") {
    let now = Date()
    let points = [
        HistoryPoint(
            timestamp: now.addingTimeInterval(-60),
            latitude: 22.37,
            longitude: 114.18,
            elevation: 78,
            elevationDelta: 0,
            isIndoor: false
        ),
        HistoryPoint(
            timestamp: now,
            latitude: 22.37,
            longitude: 114.18,
            elevation: 78,
            elevationDelta: 0,
            isIndoor: false
        ),
    ]
    ElevationSessionChart(recentPoints: points)
        .padding(.vertical, 12)
        .background(Color.black)
}

#Preview("Single Point") {
    let point = HistoryPoint(
        timestamp: .now,
        latitude: 22.37,
        longitude: 114.18,
        elevation: 71,
        elevationDelta: 0,
        isIndoor: false
    )
    ElevationSessionChart(recentPoints: [point])
        .padding(.vertical, 12)
        .background(Color.black)
}

#Preview("Empty") {
    ElevationSessionChart(recentPoints: [])
        .background(Color.black)
}
