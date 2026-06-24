//
//  FootprintHistoryChartView.swift
//  AltiPin
//
//  最近 10 次历史脚印足迹曲线图（等间距 + Scrubbing）。
//

import Charts
import CoreLocation
import SwiftUI
import UIKit

private struct FootprintPlottable: Identifiable {
    let id: UUID
    let slot: Int
    let timestamp: Date
    let elevation: Double
    let isIndoor: Bool
    let footprint: FootprintPoint

    init(footprint: FootprintPoint, slot: Int) {
        self.id = footprint.id
        self.slot = slot
        self.timestamp = footprint.timestamp
        self.elevation = footprint.elevation
        self.isIndoor = footprint.isIndoor
        self.footprint = footprint
    }
}

struct FootprintHistoryChartView: View {
    let footprints: [FootprintPoint]

    @State private var selectedSlot: Int?
    @State private var lastHapticSlot: Int?
    @State private var lastHapticDate: Date?

    private var windowSize: Int { FootprintConfig.effectiveMaxFootprints }

    /// 横轴：左=最早脚印，右=最新脚印。1 点居中；N≥2 时在 0…(windowSize-1) 均匀铺满。
    private func displaySlot(forArrayIndex index: Int) -> Int {
        let count = footprints.count
        let maxSlot = windowSize - 1
        guard count > 1 else {
            return maxSlot / 2
        }
        return Int((Double(index) * Double(maxSlot) / Double(count - 1)).rounded())
    }

    private var plottables: [FootprintPlottable] {
        footprints.enumerated().map { index, footprint in
            FootprintPlottable(footprint: footprint, slot: displaySlot(forArrayIndex: index))
        }
    }

    /// 横轴刻度：最多 5 个，且相邻刻度槽位至少间隔 minSlotGap，避免右侧重叠。
    private var axisTickPlottables: [FootprintPlottable] {
        let all = plottables
        guard all.count > 1 else { return all }

        let maxTicks = min(5, all.count)
        let minSlotGap = max(2, windowSize / 5)

        var candidateIndices = Set([0, all.count - 1])
        if maxTicks > 2 {
            let step = max(1, (all.count - 1) / (maxTicks - 1))
            var index = step
            while index < all.count - 1 {
                candidateIndices.insert(index)
                index += step
            }
        }

        var ticks: [FootprintPlottable] = []
        for index in candidateIndices.sorted() {
            let item = all[index]
            if let last = ticks.last, item.slot - last.slot < minSlotGap {
                if index == all.count - 1 {
                    ticks[ticks.count - 1] = item
                }
                continue
            }
            ticks.append(item)
        }

        if ticks.count == 1, let last = all.last, last.id != ticks[0].id {
            ticks.append(last)
        }

        return ticks
    }

    private var plottableBySlot: [Int: FootprintPlottable] {
        Dictionary(plottables.map { ($0.slot, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private var maxElevation: Double? {
        footprints.map(\.elevation).max()
    }

    private var minElevation: Double? {
        footprints.map(\.elevation).min()
    }

    private var elevationSpan: Double? {
        guard let maxElevation, let minElevation else { return nil }
        return maxElevation - minElevation
    }

    private var yDomain: ClosedRange<Double> {
        guard let minElevation, let maxElevation else { return 0...100 }
        let span = max(maxElevation - minElevation, 5)
        let padding = max(span * 0.15, 2)
        return (minElevation - padding)...(maxElevation + padding * 1.35)
    }

    private var areaBaseline: Double { yDomain.lowerBound }

    private var selectedFootprint: FootprintPoint? {
        guard let selectedSlot else { return footprints.last }
        return footprint(atSlot: selectedSlot)
    }

    var body: some View {
        VStack(spacing: 8) {
            probeHeader
            headerRow

            if footprints.isEmpty {
                emptyState
            } else {
                chartCard
            }
        }
        .padding(.bottom, 8)
    }

    // MARK: - Header

    private var probeHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let footprint = selectedFootprint {
                if selectedSlot != nil {
                    Text(probeText(for: footprint))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.85))
                } else {
                    Text(String(format: "%.0f m", footprint.elevation))
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .foregroundStyle(AltitudeTheme.accent)
                }
            } else {
                Text("等待第一个脚印…")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .frame(minHeight: 36)
    }

    private var headerRow: some View {
        HStack {
            Text("已踩脚印 \(footprints.count)/\(windowSize)")
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
        guard footprints.count >= 2, let span = elevationSpan, span >= 0.05 else {
            return "Δ —"
        }
        return String(format: "Δ %.1fm", span)
    }

    private var emptyState: some View {
        Text("运动中满足位移阈值后将踩下脚印")
            .font(.caption)
            .foregroundStyle(.white.opacity(0.45))
            .frame(height: 200)
            .frame(maxWidth: .infinity)
    }

    // MARK: - Chart

    private var chartCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(white: 0.08))

            chartContent
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 6)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .frame(height: 200)
        .padding(.horizontal, 12)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private static let axisTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let axisDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd"
        return formatter
    }()

    private var chartContent: some View {
        Chart {
            footprintMarks
            scrubRuleMark
        }
        .chartXScale(domain: 0...(windowSize - 1))
        .chartYScale(domain: yDomain)
        .chartXSelection(value: $selectedSlot)
        .chartXAxis {
            AxisMarks(position: .bottom, values: axisTickPlottables.map(\.slot)) { value in
                AxisValueLabel(anchor: xAxisLabelAnchor(for: value.as(Int.self))) {
                    if let slot = value.as(Int.self),
                       let item = plottableBySlot[slot] {
                        axisLabel(for: item.timestamp)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                    .foregroundStyle(.white.opacity(0.08))
            }
        }
        .chartPlotStyle { plot in
            plot.background(.clear)
        }
        .chartLegend(.hidden)
        .onChange(of: selectedSlot) { _, newSlot in
            handleScrubSelectionChange(newSlot)
        }
    }

    @ChartContentBuilder
    private var footprintMarks: some ChartContent {
        if plottables.count == 1, let only = plottables.first {
            singlePointMarks(for: only)
        } else {
            if plottables.count >= 3 {
                ForEach(plottables) { item in
                    AreaMark(
                        x: .value("槽位", item.slot),
                        yStart: .value("基线", areaBaseline),
                        yEnd: .value("海拔", item.elevation),
                        series: .value("脚印", "area")
                    )
                    .foregroundStyle(areaGradient)
                    .interpolationMethod(.linear)
                }
            }

            ForEach(plottables) { item in
                LineMark(
                    x: .value("槽位", item.slot),
                    y: .value("海拔", item.elevation),
                    series: .value("脚印", "line")
                )
                .foregroundStyle(AltitudeTheme.chartLine)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .interpolationMethod(.linear)
            }

            ForEach(plottables) { item in
                elevationAnnotatedPoint(for: item, symbolSize: pointSymbolSize)
            }
        }
    }

    @ChartContentBuilder
    private var scrubRuleMark: some ChartContent {
        if let selectedSlot {
            RuleMark(x: .value("选中", selectedSlot))
                .foregroundStyle(AltitudeTheme.accent.opacity(0.75))
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
        }
    }

    @ChartContentBuilder
    private func singlePointMarks(for item: FootprintPlottable) -> some ChartContent {
        RuleMark(
            x: .value("槽位", item.slot),
            yStart: .value("基线", areaBaseline),
            yEnd: .value("海拔", item.elevation)
        )
        .foregroundStyle(AltitudeTheme.chartLine.opacity(0.35))
        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))

        PointMark(
            x: .value("槽位", item.slot),
            y: .value("海拔", item.elevation)
        )
        .foregroundStyle(AltitudeTheme.chartLine)
        .symbolSize(64)
        .annotation(position: .top, spacing: 4) {
            elevationLabel(for: item.elevation)
        }
    }

    private var pointSymbolSize: CGFloat {
        switch plottables.count {
        case ...4: 36
        case ...10: 28
        default: 20
        }
    }

    @ChartContentBuilder
    private func elevationAnnotatedPoint(for item: FootprintPlottable, symbolSize: CGFloat) -> some ChartContent {
        PointMark(
            x: .value("槽位", item.slot),
            y: .value("海拔", item.elevation)
        )
        .foregroundStyle(AltitudeTheme.chartLine)
        .symbolSize(symbolSize)
        .annotation(position: .top, spacing: 3) {
            elevationLabel(for: item.elevation)
        }
    }

    private func elevationLabel(for elevation: Double) -> some View {
        Group {
            if elevation.isFinite {
                Text("\(Int(elevation.rounded()))m")
            } else {
                Text("—")
            }
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(AltitudeTheme.accent)
    }

    // MARK: - Helpers

    private var areaGradient: LinearGradient {
        LinearGradient(
            colors: [AltitudeTheme.chartGradientTop, AltitudeTheme.chartGradientBottom],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func axisLabel(for timestamp: Date) -> some View {
        let time = Self.axisTimeFormatter.string(from: timestamp)
        let date = Self.axisDateFormatter.string(from: timestamp)
        return Text("\(time)\n\(date)")
            .font(.caption2)
            .foregroundStyle(.white.opacity(0.45))
            .multilineTextAlignment(.center)
    }

    private func xAxisLabelAnchor(for slot: Int?) -> UnitPoint {
        guard let slot else { return .center }
        let ticks = axisTickPlottables
        guard ticks.count > 1,
              let first = ticks.first?.slot,
              let last = ticks.last?.slot else {
            return .top
        }
        if footprints.count <= 2 {
            if slot == first { return .topLeading }
            if slot == last { return .topTrailing }
            return .top
        }
        if slot == first { return .topLeading }
        if slot == last { return .topTrailing }
        return .top
    }

    private func footprint(atSlot slot: Int) -> FootprintPoint? {
        guard !footprints.isEmpty else { return nil }

        var bestIndex = 0
        var bestDistance = Int.max
        for index in footprints.indices {
            let distance = abs(displaySlot(forArrayIndex: index) - slot)
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }
        return footprints[bestIndex]
    }

    private func probeText(for footprint: FootprintPoint) -> String {
        let date = Self.axisDateFormatter.string(from: footprint.timestamp)
        let time = Self.axisTimeFormatter.string(from: footprint.timestamp)
        return "\(date) \(time) · 海拔 \(String(format: "%.0f", footprint.elevation))m"
    }

    private func handleScrubSelectionChange(_ newSlot: Int?) {
        guard let newSlot, newSlot != lastHapticSlot else { return }

        let now = Date()
        if let lastHapticDate, now.timeIntervalSince(lastHapticDate) < 0.08 {
            return
        }

        guard footprint(atSlot: newSlot) != nil else { return }

        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred()

        lastHapticSlot = newSlot
        lastHapticDate = now
    }
}

#Preview("Full") {
    FootprintHistoryChartView(footprints: FootprintPoint.mockFootprints)
        .padding(.vertical, 12)
        .background(Color.black)
}

#Preview("Sparse") {
    let now = Date()
    let footprints = [
        FootprintPoint(
            coordinate: CLLocationCoordinate2D(latitude: 22.37, longitude: 114.18),
            elevation: 78,
            timestamp: now.addingTimeInterval(-120),
            isIndoor: false
        ),
        FootprintPoint(
            coordinate: CLLocationCoordinate2D(latitude: 22.371, longitude: 114.181),
            elevation: 81,
            timestamp: now,
            isIndoor: false
        ),
    ]
    FootprintHistoryChartView(footprints: footprints)
        .padding(.vertical, 12)
        .background(Color.black)
}

#Preview("Single") {
    FootprintHistoryChartView(
        footprints: [
            FootprintPoint(
                coordinate: CLLocationCoordinate2D(latitude: 22.37, longitude: 114.18),
                elevation: 72,
                timestamp: .now,
                isIndoor: false
            ),
        ]
    )
    .padding(.vertical, 12)
    .background(Color.black)
}

#Preview("Empty") {
    FootprintHistoryChartView(footprints: [])
        .background(Color.black)
}
