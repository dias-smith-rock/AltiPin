//
//  GeoCameraCaptureScreen.swift
//  AltiPin
//

import Combine
import SwiftData
import SwiftUI
import UIKit

struct GeoCameraCaptureScreen: View {
    @ObservedObject var store: OutdoorDashboardStore
    @ObservedObject var weatherService: CompassWeatherService
    let onClose: () -> Void
    let onStatus: (String) -> Void

    @Environment(\.modelContext) private var modelContext
    @StateObject private var cameraService = GeoCameraService()
    @State private var isProcessing = false
    @State private var recordingMetadata: GeoStampMetadata?
    @State private var pinchAnchorZoom: CGFloat = 1.0
    @State private var shutterFlashOpacity: Double = 0
    @State private var recordingDotOpacity: Double = 1

    private var mediaStore: GeoMediaStore {
        GeoMediaStore(modelContext: modelContext)
    }

    private var liveMetadata: GeoStampMetadata {
        GeoStampMetadata.capture(from: store, weather: weatherService)
    }

    var body: some View {
        NavigationStack {
            captureContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.ignoresSafeArea())
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.black, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbarColorScheme(.dark, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close", action: closeCapture)
                    }
                    ToolbarItem(placement: .principal) {
                        captureModePicker
                    }
                }
        }
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled(cameraService.isRecording)
        .task {
            wireCameraCallbacks()
            await cameraService.prepare()
            await refreshWeatherIfNeeded()
        }
        .onDisappear {
            cameraService.stopSession()
        }
        .onChange(of: store.latitude) { _, _ in
            Task { await refreshWeatherIfNeeded() }
        }
        .onChange(of: store.longitude) { _, _ in
            Task { await refreshWeatherIfNeeded() }
        }
        .onChange(of: cameraService.captureMode) { _, newMode in
            cameraService.setCaptureMode(newMode)
        }
        .onChange(of: cameraService.zoomFactor) { _, factor in
            pinchAnchorZoom = factor
        }
        .onChange(of: cameraService.isRecording) { _, isRecording in
            if isRecording {
                recordingDotOpacity = 1
                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                    recordingDotOpacity = 0.25
                }
            } else {
                withAnimation(.default) {
                    recordingDotOpacity = 1
                }
            }
        }
        .onChange(of: cameraService.errorMessage) { _, message in
            guard let message else { return }
            onStatus(message)
        }
    }

    private var captureZoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { scale in
                cameraService.setZoomFactor(pinchAnchorZoom * scale)
            }
            .onEnded { _ in
                pinchAnchorZoom = cameraService.zoomFactor
            }
    }

    private var captureContent: some View {
        ZStack {
            if cameraService.permissionDenied {
                permissionPlaceholder
            } else {
                GeoCameraPreviewView(session: cameraService.session)
            }

            VStack {
                Spacer()
                LinearGradient(
                    colors: [.clear, Color.black.opacity(0.75)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 220)
            }
            .allowsHitTesting(false)

            VStack(spacing: 10) {
                if cameraService.isRecording {
                    recordingIndicator
                        .padding(.top, 8)
                }

                if abs(cameraService.zoomFactor - 1.0) > 0.01 {
                    HStack {
                        Spacer()
                        Text(String(format: "%.1f×", cameraService.zoomFactor))
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.black.opacity(0.45)))
                    }
                    .padding(.top, cameraService.isRecording ? 0 : 8)
                }

                Spacer()

                GeoStampOverlayView(metadata: liveMetadata)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                captureControls
                    .padding(.bottom, 4)
            }
            .padding(.horizontal, 12)

            Color.white
                .opacity(shutterFlashOpacity)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        .simultaneousGesture(captureZoomGesture)
    }

    private static func formatRecordingTime(_ elapsed: TimeInterval) -> String {
        let total = max(0, Int(elapsed))
        let minutes = total / 60
        let seconds = total % 60
        if minutes > 0 {
            return String(format: "%d:%02d", minutes, seconds)
        }
        return String(format: "0:%02d", seconds)
    }

    private var recordingIndicator: some View {
        TimelineView(.periodic(from: .now, by: 0.2)) { context in
            let elapsed = cameraService.recordingStartedAt
                .map { context.date.timeIntervalSince($0) } ?? 0

            HStack(spacing: 8) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 9, height: 9)
                    .opacity(recordingDotOpacity)

                Text(Self.formatRecordingTime(elapsed))
                    .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.black.opacity(0.55))
            )
            .frame(maxWidth: .infinity)
        }
    }

    private var captureModePicker: some View {
        Picker("Capture Mode", selection: $cameraService.captureMode) {
            ForEach(GeoCameraCaptureMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 220)
        .padding(4)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private var permissionPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.fill")
                .font(.largeTitle)
                .foregroundStyle(.white.opacity(0.35))
            Text("Camera access is required to capture")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.65))
            Text("Allow AltiPin to access the camera and microphone in Settings.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.45))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var captureControls: some View {
        HStack {
            Button {
                pinchAnchorZoom = 1.0
                cameraService.flipCamera()
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath.camera")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 48, height: 48)
            }
            .buttonStyle(.plain)
            .disabled(cameraService.permissionDenied || isProcessing)

            Spacer()

            Button {
                handleCaptureTap()
            } label: {
                ZStack {
                    Circle()
                        .strokeBorder(.white.opacity(0.9), lineWidth: 4)
                        .frame(width: 74, height: 74)
                    if cameraService.captureMode == .video {
                        RoundedRectangle(cornerRadius: cameraService.isRecording ? 8 : 34, style: .continuous)
                            .fill(cameraService.isRecording ? .red : .red.opacity(0.9))
                            .frame(
                                width: cameraService.isRecording ? 30 : 58,
                                height: cameraService.isRecording ? 30 : 58
                            )
                            .animation(.easeInOut(duration: 0.2), value: cameraService.isRecording)
                    } else {
                        Circle()
                            .fill(.white)
                            .frame(width: 58, height: 58)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(cameraService.permissionDenied || isProcessing)

            Spacer()

            if isProcessing {
                ProgressView()
                    .tint(AltitudeTheme.accent)
                    .frame(width: 48, height: 48)
            } else {
                Color.clear.frame(width: 48, height: 48)
            }
        }
    }

    private func closeCapture() {
        if cameraService.isRecording {
            cameraService.toggleRecording(metadata: recordingMetadata ?? liveMetadata)
        }
        onClose()
    }

    private func wireCameraCallbacks() {
        cameraService.onPhotoCaptured = { image in
            Task { await savePhoto(image) }
        }
        cameraService.onVideoCaptured = { url, duration in
            Task { await saveVideo(url: url, duration: duration) }
        }
    }

    private func handleCaptureTap() {
        switch cameraService.captureMode {
        case .photo:
            playShutterFeedback()
            cameraService.capturePhoto()
        case .video:
            if cameraService.isRecording {
                cameraService.toggleRecording(metadata: recordingMetadata ?? liveMetadata)
            } else {
                recordingMetadata = liveMetadata
                cameraService.toggleRecording(metadata: recordingMetadata!)
            }
        }
    }

    private func savePhoto(_ image: UIImage) async {
        isProcessing = true
        defer { isProcessing = false }
        let metadata = liveMetadata
        do {
            _ = try mediaStore.insertPhoto(image: image, metadata: metadata)
            onStatus(L10n.t("Photo saved"))
        } catch {
            onStatus(error.localizedDescription)
        }
    }

    private func saveVideo(url: URL, duration: TimeInterval) async {
        isProcessing = true
        defer {
            isProcessing = false
            recordingMetadata = nil
        }
        let metadata = recordingMetadata ?? liveMetadata
        do {
            _ = try await mediaStore.insertVideo(from: url, metadata: metadata, duration: duration)
            try? FileManager.default.removeItem(at: url)
            onStatus(L10n.t("Video saved"))
        } catch {
            onStatus(error.localizedDescription)
        }
    }

    private func playShutterFeedback() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        shutterFlashOpacity = 0.92
        withAnimation(.easeOut(duration: 0.32)) {
            shutterFlashOpacity = 0
        }
    }

    private func refreshWeatherIfNeeded() async {
        guard let location = store.currentLocation else { return }
        await weatherService.refresh(for: location)
    }
}
