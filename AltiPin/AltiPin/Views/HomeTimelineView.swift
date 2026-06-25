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
    @State private var showDeleteConfirmation = false
    @State private var mergeTitle = ""

    private var tripStore: TripRecordStore {
        TripRecordStore(modelContext: modelContext)
    }

    private var isAllSelected: Bool {
        !trips.isEmpty && selectedTripIDs.count == trips.count
    }

    private var monthSections: [(title: String, trips: [TripEntity])] {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = L10n.activeLocale
        formatter.setLocalizedDateFormatFromTemplate("yyyyMMMM")

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
            VStack(spacing: 0) {
                timelineTopBar

                ZStack {
                    List {
                        if trips.isEmpty {
                            ContentUnavailableView(
                                "No Tracks Yet",
                                systemImage: "map",
                                description: Text("Tracks appear here after you start an activity.")
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

                    if isEditMode {
                        VStack {
                            Spacer()
                            editModeBottomBar
                                .padding(.horizontal, 24)
                                .padding(.bottom, 28)
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .animation(.easeInOut(duration: 0.25), value: isEditMode)
            .animation(.easeInOut(duration: 0.25), value: selectedTripIDs.count)
            .toolbar(.hidden, for: .navigationBar)
            .confirmationDialog(
                "Delete Selected Tracks?",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    performDelete()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(L10n.format("This will permanently delete %lld tracks and their GPX files.", selectedTripIDs.count))
            }
            .alert("Merge as Memory", isPresented: $showMergeAlert) {
                TextField("e.g. Canada Trip", text: $mergeTitle)
                Button("Confirm Merge") {
                    performMerge()
                }
                Button("Cancel", role: .cancel) {
                    mergeTitle = ""
                }
            } message: {
                Text(L10n.format("Merge %lld tracks into one memory. Enter a new name.", selectedTripIDs.count))
            }
        }
    }

    // MARK: - Top Bar

    private var timelineTopBar: some View {
        AppTabTopBar {
            if isEditMode, !trips.isEmpty {
                Button(isAllSelected ? "Deselect All" : "Select All") {
                    withAnimation {
                        if isAllSelected {
                            deselectAll()
                        } else {
                            selectAll()
                        }
                    }
                }
                .font(.subheadline)
            } else {
                AppTabBarTitle(text: "Track History")
            }
        } trailing: {
            if isEditMode {
                Button("Cancel") {
                    withAnimation {
                        isEditMode.toggle()
                        if !isEditMode {
                            selectedTripIDs.removeAll()
                        }
                    }
                }
                .font(.subheadline)
            } else {
                HStack(spacing: 12) {
                    Button("Select") {
                        withAnimation {
                            isEditMode.toggle()
                            if !isEditMode {
                                selectedTripIDs.removeAll()
                            }
                        }
                    }
                    .font(.subheadline)

                    AppSettingsButton()
                }
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

    // MARK: - Edit Mode Bottom Bar

    private var editModeBottomBar: some View {
        HStack(spacing: 12) {
            Button {
                showDeleteConfirmation = true
            } label: {
                Text(L10n.format("Delete (%lld)", selectedTripIDs.count))
                    .font(.headline)
                    .foregroundStyle(selectedTripIDs.isEmpty ? Color.white.opacity(0.35) : .white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        selectedTripIDs.isEmpty ? Color.white.opacity(0.08) : Color.red.opacity(0.85),
                        in: Capsule()
                    )
            }
            .disabled(selectedTripIDs.isEmpty)

            Button {
                mergeTitle = suggestedMergeTitle
                showMergeAlert = true
            } label: {
                Text(L10n.format("Merge (%lld)", selectedTripIDs.count))
                    .font(.headline)
                    .foregroundStyle(selectedTripIDs.isEmpty ? Color.white.opacity(0.35) : .white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        selectedTripIDs.isEmpty ? Color.white.opacity(0.08) : Color.accentColor,
                        in: Capsule()
                    )
                    .shadow(color: selectedTripIDs.isEmpty ? .clear : .black.opacity(0.18), radius: 12, y: 6)
            }
            .disabled(selectedTripIDs.isEmpty)
        }
    }

    // MARK: - Actions

    private func selectAll() {
        selectedTripIDs = Set(trips.map(\.id))
    }

    private func deselectAll() {
        selectedTripIDs.removeAll()
    }

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
            return L10n.t("Merged Tracks")
        }
        let formatter = DateFormatter()
        formatter.locale = L10n.activeLocale
        formatter.dateFormat = "yyyy-MM-dd"
        return L10n.format("%@ Memory", formatter.string(from: earliest.startTime))
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

    private func performDelete() {
        let ids = selectedTripIDs
        guard !ids.isEmpty else { return }

        let toDelete = trips.filter { ids.contains($0.id) }
        let willBeEmpty = toDelete.count >= trips.count

        do {
            try tripStore.delete(toDelete)
        } catch {
            NSLog("HomeTimelineView: delete failed — \(error.localizedDescription)")
            return
        }

        withAnimation {
            selectedTripIDs.removeAll()
            if willBeEmpty {
                isEditMode = false
            }
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
                    Text("Merged")
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
        String(format: "%.0f m %@", meters, L10n.t("Highest"))
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
