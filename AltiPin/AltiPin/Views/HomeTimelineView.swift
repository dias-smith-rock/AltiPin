//
//  HomeTimelineView.swift
//  AltiPin
//

import SwiftUI
import SwiftData
import UIKit

struct HomeTimelineView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TripEntity.dateCreated, order: .reverse) private var trips: [TripEntity]

    @State private var isEditMode = false
    @State private var selectedTripIDs: Set<UUID> = []
    @State private var showMergeAlert = false
    @State private var mergeTitle = ""

    private var monthSections: [(title: String, trips: [TripEntity])] {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年MM月"

        var grouped: [String: [TripEntity]] = [:]
        var order: [String] = []

        for trip in trips {
            let key = formatter.string(from: trip.dateCreated)
            if grouped[key] == nil {
                order.append(key)
                grouped[key] = []
            }
            grouped[key]?.append(trip)
        }

        return order.map { key in
            (title: key, trips: grouped[key] ?? [])
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                List {
                    if trips.isEmpty {
                        ContentUnavailableView(
                            "暂无轨迹",
                            systemImage: "map",
                            description: Text("开始运动后，轨迹将自动出现在这里")
                        )
                    } else {
                        ForEach(monthSections, id: \.title) { section in
                            Section(header: Text(section.title)) {
                                ForEach(section.trips) { trip in
                                    tripRow(trip)
                                }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .environment(\.editMode, .constant(isEditMode ? .active : .inactive))

                if isEditMode, !selectedTripIDs.isEmpty {
                    VStack {
                        Spacer()
                        mergeFloatingButton
                            .padding(.horizontal, 24)
                            .padding(.bottom, 28)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.25), value: isEditMode)
            .animation(.easeInOut(duration: 0.25), value: selectedTripIDs.count)
            .navigationTitle("轨迹记录")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isEditMode ? "取消" : "选择") {
                        withAnimation {
                            isEditMode.toggle()
                            if !isEditMode {
                                selectedTripIDs.removeAll()
                            }
                        }
                    }
                }
            }
            .alert("打包合并为回忆", isPresented: $showMergeAlert) {
                TextField("例如：加拿大旅游", text: $mergeTitle)
                Button("确认合并") {
                    performMerge()
                }
                Button("取消", role: .cancel) {
                    mergeTitle = ""
                }
            } message: {
                Text("将 \(selectedTripIDs.count) 条轨迹合并为一条回忆，请输入新名称。")
            }
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func tripRow(_ trip: TripEntity) -> some View {
        if isEditMode {
            editModeRow(trip)
        } else {
            normalModeRow(trip)
        }
    }

    private func normalModeRow(_ trip: TripEntity) -> some View {
        NavigationLink {
            TripDetailView(trip: trip)
        } label: {
            TripRowContent(trip: trip)
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()
                withAnimation {
                    isEditMode = true
                    selectedTripIDs.insert(trip.id)
                }
            }
        )
    }

    private func editModeRow(_ trip: TripEntity) -> some View {
        Button {
            toggleSelection(for: trip.id)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: selectedTripIDs.contains(trip.id) ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(selectedTripIDs.contains(trip.id) ? Color.accentColor : .secondary)

                TripRowContent(trip: trip)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Merge Button

    private var mergeFloatingButton: some View {
        Button {
            mergeTitle = suggestedMergeTitle
            showMergeAlert = true
        } label: {
            Text("打包合并为回忆 (\(selectedTripIDs.count))")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.accentColor, in: Capsule())
                .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
        }
    }

    // MARK: - Actions

    private func toggleSelection(for id: UUID) {
        withAnimation(.easeInOut(duration: 0.15)) {
            if selectedTripIDs.contains(id) {
                selectedTripIDs.remove(id)
            } else {
                selectedTripIDs.insert(id)
            }
        }
    }

    private var suggestedMergeTitle: String {
        let selected = trips.filter { selectedTripIDs.contains($0.id) }
        guard let earliest = selected.min(by: { $0.startTime < $1.startTime }) else {
            return "合并轨迹"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return "\(formatter.string(from: earliest.startTime)) 回忆"
    }

    private func performMerge() {
        let ids = selectedTripIDs
        let title = mergeTitle.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !ids.isEmpty, !title.isEmpty else { return }

        // TODO: 调用 GPX 合并算法（读取、拼接 trkseg、重算统计量、写入 Merged_UUID.gpx）
        NSLog("HomeTimelineView: merge \(ids.count) trips into '\(title)'")

        withAnimation {
            isEditMode = false
            selectedTripIDs.removeAll()
            mergeTitle = ""
        }
    }
}

// MARK: - Trip Row Content

private struct TripRowContent: View {
    let trip: TripEntity

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(trip.title)
                    .font(.headline)
                    .foregroundStyle(.primary)

                if trip.isMerged {
                    Text("已合并")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.15), in: Capsule())
                        .foregroundStyle(Color.accentColor)
                }
            }

            HStack(spacing: 16) {
                Label(formatDistance(trip.totalDistance), systemImage: "arrow.left.and.right")
                Label(formatAscent(trip.totalAscent), systemImage: "arrow.up.right")
                Label(formatElevation(trip.maxElevation), systemImage: "mountain.2")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func formatDistance(_ meters: Double) -> String {
        if meters >= 1000 {
            return String(format: "%.1f km", meters / 1000)
        }
        return String(format: "%.0f m", meters)
    }

    private func formatAscent(_ meters: Double) -> String {
        String(format: "%.0f m ↑", meters)
    }

    private func formatElevation(_ meters: Double) -> String {
        String(format: "%.0f m 最高", meters)
    }
}

// MARK: - Preview

#Preview {
    let container = try! ModelContainer(
        for: TripEntity.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )

    let context = container.mainContext
    context.insert(TripEntity(
        title: "2026-06-13 轨迹",
        subGpxFileNames: ["20260613.gpx"],
        startTime: Date(),
        endTime: Date(),
        totalDistance: 12_400,
        totalAscent: 680,
        maxElevation: 1240
    ))
    context.insert(TripEntity(
        title: "2026-06-10 轨迹",
        subGpxFileNames: ["20260610.gpx"],
        startTime: Calendar.current.date(byAdding: .day, value: -3, to: Date())!,
        endTime: Date(),
        totalDistance: 8_200,
        totalAscent: 420,
        maxElevation: 980
    ))

    return HomeTimelineView()
        .modelContainer(container)
}
