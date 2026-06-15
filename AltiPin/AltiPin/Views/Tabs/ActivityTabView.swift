//
//  ActivityTabView.swift
//  AltiPin
//

import SwiftUI

struct ActivityTabView: View {
    @ObservedObject var store: OutdoorDashboardStore
    @State private var showTeamDashboard = false

    private let gridColumns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: gridColumns, spacing: 16) {
                    speedCard
                    durationCard
                    distanceCard
                }
                .padding(20)
            }
            .oledTabBackground()
            .navigationTitle("运动")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("临时组队") {
                        showTeamDashboard = true
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.accentColor, in: Capsule())
                }
            }
            .sheet(isPresented: $showTeamDashboard) {
                NavigationStack {
                    TeamSplitMapView()
                        .navigationTitle("临时探险队")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("关闭") {
                                    showTeamDashboard = false
                                }
                            }
                        }
                }
            }
        }
    }

    private var speedCard: some View {
        OLEDMetricCard(title: "移动速度", icon: "speedometer") {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(store.speedKmh, format: .number.precision(.fractionLength(2)))
                Text(" km/h")
                    .font(.system(.title3, design: .monospaced))
                    .foregroundStyle(.gray)
            }
        }
    }

    private var durationCard: some View {
        OLEDMetricCard(title: "持续时间", icon: "clock") {
            Text(
                Duration.seconds(store.sessionDuration),
                format: .time(pattern: .hourMinute(padHourToLength: 2))
            )
        }
    }

    private var distanceCard: some View {
        OLEDMetricCard(title: "累计行程", icon: "figure.walk") {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(store.cumulativeDistanceMeters / 1000, format: .number.precision(.fractionLength(1)))
                Text(" km")
                    .font(.system(.title3, design: .monospaced))
                    .foregroundStyle(.gray)
            }
        }
        .gridCellColumns(2)
    }
}

#Preview {
    ActivityTabView(store: OutdoorDashboardStore.preview())
}
