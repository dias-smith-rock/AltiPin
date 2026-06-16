//
//  AltitudeHistoryChart.swift
//  AltiPin
//

import Charts
import SwiftUI

struct AltitudeHistoryChart: View {
    let samples: [ElevationSample]
    let maxElevation: Double?
    let minElevation: Double?

    private var axisTimeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH':00'"
        return formatter
    }

    private var axisDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd"
        return formatter
    }

    var body: some View {
        VStack(spacing: 8) {
            if let maxElevation, let minElevation, !samples.isEmpty {
                HStack {
                    Text("最高 \(String(format: "%.1f", maxElevation))m")
                    Spacer()
                    Text("最低 \(String(format: "%.1f", minElevation))m")
                }
                .font(.caption)
                .foregroundStyle(AltitudeTheme.accent)
                .padding(.horizontal, 16)
            }

            if samples.isEmpty {
                Text("暂无海拔历史数据")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.45))
                    .frame(height: 160)
                    .frame(maxWidth: .infinity)
            } else {
                Chart {
                    ForEach(samples) { sample in
                        AreaMark(
                            x: .value("时间", sample.date),
                            y: .value("海拔", sample.elevation)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [AltitudeTheme.chartGradientTop, AltitudeTheme.chartGradientBottom],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.catmullRom)

                        LineMark(
                            x: .value("时间", sample.date),
                            y: .value("海拔", sample.elevation)
                        )
                        .foregroundStyle(AltitudeTheme.chartLine)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.catmullRom)
                    }

                    if let maxSample = samples.max(by: { $0.elevation < $1.elevation }) {
                        PointMark(
                            x: .value("时间", maxSample.date),
                            y: .value("海拔", maxSample.elevation)
                        )
                        .foregroundStyle(.clear)
                        .annotation(position: .top, spacing: 4) {
                            Text(String(format: "%.1f", maxSample.elevation))
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.85))
                        }
                    }

                    if let minSample = samples.min(by: { $0.elevation < $1.elevation }),
                       minSample.id != samples.max(by: { $0.elevation < $1.elevation })?.id {
                        PointMark(
                            x: .value("时间", minSample.date),
                            y: .value("海拔", minSample.elevation)
                        )
                        .foregroundStyle(.clear)
                        .annotation(position: .bottom, spacing: 4) {
                            Text(String(format: "%.1f", minSample.elevation))
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.85))
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) { value in
                        if let date = value.as(Date.self) {
                            AxisValueLabel {
                                VStack(spacing: 2) {
                                    Text(axisTimeFormatter.string(from: date))
                                    Text(axisDateFormatter.string(from: date))
                                }
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.45))
                            }
                        }
                    }
                }
                .chartYAxis(.hidden)
                .frame(height: 160)
                .padding(.horizontal, 8)
            }
        }
        .padding(.bottom, 8)
    }
}

#Preview {
    let now = Date()
    let samples = [
        ElevationSample(date: now.addingTimeInterval(-86400 * 2), elevation: 72.4),
        ElevationSample(date: now.addingTimeInterval(-86400), elevation: 73.8),
        ElevationSample(date: now.addingTimeInterval(-3600), elevation: 5.8),
        ElevationSample(date: now, elevation: 83.7),
    ]
    AltitudeHistoryChart(samples: samples, maxElevation: 83.7, minElevation: 5.8)
        .background(Color.black)
}
