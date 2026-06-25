//
//  GeoMediaGalleryView.swift
//  AltiPin
//

import AVFoundation
import AVKit
import SwiftData
import SwiftUI

struct GeoMediaGalleryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \GeoMediaEntity.capturedAt, order: .reverse) private var mediaItems: [GeoMediaEntity]

    @State private var isSelecting = false
    @State private var selectedIDs: Set<UUID> = []
    @State private var sortOrder: GeoMediaSortOrder = .newestFirst
    @State private var showDeleteConfirmation = false
    @State private var showShareSheet = false
    @State private var shareItems: [Any] = []
    @State private var statusMessage: String?
    @State private var previewLaunch: GeoMediaPreviewLaunch?

    private var mediaStore: GeoMediaStore {
        GeoMediaStore(modelContext: modelContext)
    }

    private var displayedItems: [GeoMediaEntity] {
        switch sortOrder {
        case .newestFirst:
            mediaItems.sorted { $0.capturedAt > $1.capturedAt }
        case .oldestFirst:
            mediaItems.sorted { $0.capturedAt < $1.capturedAt }
        }
    }

    private var selectedEntities: [GeoMediaEntity] {
        displayedItems.filter { selectedIDs.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            galleryToolbar

            if displayedItems.isEmpty {
                ContentUnavailableView(
                    "暂无拍摄",
                    systemImage: "photo.on.rectangle.angled",
                    description: Text("拍照或录像后会显示在这里")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 108), spacing: 8)],
                        spacing: 8
                    ) {
                        ForEach(displayedItems) { item in
                            galleryCell(item)
                        }
                    }
                    .padding(12)
                }
            }
        }
        .background(Color.black)
        .confirmationDialog(
            "删除所选媒体？",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                deleteSelected()
            }
            Button("取消", role: .cancel) {}
        }
        .sheet(isPresented: $showShareSheet) {
            GeoMediaShareSheet(items: shareItems)
        }
        .fullScreenCover(item: $previewLaunch) { launch in
            GeoMediaPreviewScreen(
                items: launch.items,
                initialID: launch.id,
                mediaStore: mediaStore,
                onClose: { previewLaunch = nil }
            )
        }
        .overlay(alignment: .bottom) {
            if let statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.white.opacity(0.15)))
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private var galleryToolbar: some View {
        HStack(spacing: 12) {
            Menu {
                Picker("排序", selection: $sortOrder) {
                    ForEach(GeoMediaSortOrder.allCases) { order in
                        Text(order.title).tag(order)
                    }
                }
            } label: {
                Label(sortOrder.title, systemImage: "arrow.up.arrow.down")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.85))
            }

            Spacer()

            if isSelecting {
                Text("已选 \(selectedIDs.count)")
                    .font(.subheadline)
                    .foregroundStyle(AltitudeTheme.accent)

                Button("分享") { shareSelected() }
                    .font(.subheadline.weight(.medium))
                    .disabled(selectedIDs.isEmpty)

                Button("保存") {
                    Task { await saveSelectedToLibrary() }
                }
                .font(.subheadline.weight(.medium))
                .disabled(selectedIDs.isEmpty)

                Button("删除", role: .destructive) {
                    showDeleteConfirmation = true
                }
                .font(.subheadline.weight(.medium))
                .disabled(selectedIDs.isEmpty)
            }

            Button(isSelecting ? "完成" : "选择") {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isSelecting.toggle()
                    if !isSelecting {
                        selectedIDs.removeAll()
                    }
                }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(AltitudeTheme.accent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.92))
    }

    private func galleryCell(_ item: GeoMediaEntity) -> some View {
        let isSelected = selectedIDs.contains(item.id)

        return ZStack(alignment: .topTrailing) {
            thumbnailView(for: item)
                .frame(height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(isSelected ? AltitudeTheme.accent : Color.white.opacity(0.08), lineWidth: isSelected ? 2 : 1)
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    if isSelecting {
                        toggleSelection(item.id)
                    } else {
                        previewLaunch = GeoMediaPreviewLaunch(id: item.id, items: displayedItems)
                    }
                }
                .onLongPressGesture {
                    if !isSelecting {
                        isSelecting = true
                    }
                    toggleSelection(item.id)
                }

            if item.mediaType == .video {
                Image(systemName: "play.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }

            if isSelecting {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? AltitudeTheme.accent : .white.opacity(0.7))
                    .padding(8)
            }
        }
    }

    @ViewBuilder
    private func thumbnailView(for item: GeoMediaEntity) -> some View {
        if let thumbURL = mediaStore.thumbnailURL(for: item),
           let image = UIImage(contentsOfFile: thumbURL.path) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else if item.mediaType == .photo,
                  let image = UIImage(contentsOfFile: mediaStore.fileURL(for: item).path) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .overlay {
                    Image(systemName: item.mediaType == .video ? "video.fill" : "photo.fill")
                        .foregroundStyle(.white.opacity(0.35))
                }
        }
    }

    private func toggleSelection(_ id: UUID) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    private func deleteSelected() {
        do {
            try mediaStore.delete(selectedEntities)
            selectedIDs.removeAll()
            isSelecting = false
            flashStatus("已删除")
        } catch {
            flashStatus(error.localizedDescription)
        }
    }

    private func shareSelected() {
        shareItems = GeoMediaLibrary.shareURLs(for: selectedEntities, store: mediaStore)
        showShareSheet = true
    }

    private func saveSelectedToLibrary() async {
        do {
            try await GeoMediaLibrary.saveToPhotoLibrary(entities: selectedEntities, store: mediaStore)
            flashStatus("已保存到相册")
        } catch {
            flashStatus(error.localizedDescription)
        }
    }

    private func flashStatus(_ message: String) {
        withAnimation {
            statusMessage = message
        }
        Task {
            try? await Task.sleep(for: .seconds(2))
            await MainActor.run {
                withAnimation {
                    statusMessage = nil
                }
            }
        }
    }
}

private struct GeoMediaPreviewLaunch: Identifiable {
    let id: UUID
    let items: [GeoMediaEntity]
}

private struct GeoMediaPreviewScreen: View {
    let items: [GeoMediaEntity]
    let mediaStore: GeoMediaStore
    let onClose: () -> Void

    @State private var currentID: UUID

    init(
        items: [GeoMediaEntity],
        initialID: UUID,
        mediaStore: GeoMediaStore,
        onClose: @escaping () -> Void
    ) {
        self.items = items
        self.mediaStore = mediaStore
        self.onClose = onClose
        _currentID = State(initialValue: initialID)
    }

    private var currentIndex: Int {
        items.firstIndex(where: { $0.id == currentID }) ?? 0
    }

    private var currentEntity: GeoMediaEntity? {
        items.first(where: { $0.id == currentID })
    }

    var body: some View {
        NavigationStack {
            TabView(selection: $currentID) {
                ForEach(items, id: \.id) { item in
                    GeoMediaPreviewPage(
                        entity: item,
                        mediaStore: mediaStore,
                        isActive: item.id == currentID
                    )
                    .tag(item.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .background(Color.black)
            .navigationTitle(currentEntity.map { GeoStampMetadata.formattedDateTime($0.capturedAt) } ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭", action: onClose)
                }
                if items.count > 1 {
                    ToolbarItem(placement: .topBarTrailing) {
                        Text("\(currentIndex + 1)/\(items.count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

private struct GeoMediaPreviewPage: View {
    let entity: GeoMediaEntity
    let mediaStore: GeoMediaStore
    let isActive: Bool

    @State private var player: AVPlayer?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch entity.mediaType {
            case .photo:
                if let image = UIImage(contentsOfFile: mediaStore.fileURL(for: entity).path) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                }
            case .video:
                if let player {
                    VideoPlayer(player: player)
                }
            }
        }
        .onAppear {
            if isActive { startPlaybackIfNeeded() }
        }
        .onDisappear { stopPlayback() }
        .onChange(of: isActive) { _, active in
            if active {
                startPlaybackIfNeeded()
            } else {
                stopPlayback()
            }
        }
    }

    private func startPlaybackIfNeeded() {
        guard entity.mediaType == .video, player == nil else { return }
        let newPlayer = AVPlayer(url: mediaStore.fileURL(for: entity))
        player = newPlayer
        newPlayer.play()
    }

    private func stopPlayback() {
        player?.pause()
        player = nil
    }
}
