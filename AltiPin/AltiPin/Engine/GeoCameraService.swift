//
//  GeoCameraService.swift
//  AltiPin
//

import AVFoundation
import Combine
import UIKit

enum GeoCameraCaptureMode: String, CaseIterable, Identifiable {
    case photo
    case video

    var id: String { rawValue }

    var title: String {
        switch self {
        case .photo: L10n.t("Photo")
        case .video: L10n.t("Video")
        }
    }
}

@MainActor
final class GeoCameraService: NSObject, ObservableObject {
    @Published private(set) var isSessionRunning = false
    @Published private(set) var isRecording = false
    @Published private(set) var recordingStartedAt: Date?
    @Published private(set) var permissionDenied = false
    @Published private(set) var errorMessage: String?
    @Published var captureMode: GeoCameraCaptureMode = .photo
    @Published private(set) var zoomFactor: CGFloat = 1.0
    @Published private(set) var minZoomFactor: CGFloat = 1.0
    @Published private(set) var maxZoomFactor: CGFloat = 1.0

    let session = AVCaptureSession()

    var onPhotoCaptured: ((UIImage) -> Void)?
    var onVideoCaptured: ((URL, TimeInterval) -> Void)?

    private let photoOutput = AVCapturePhotoOutput()
    private let movieOutput = AVCaptureMovieFileOutput()
    private var videoDeviceInput: AVCaptureDeviceInput?
    private var recordingMetadata: GeoStampMetadata?
    private let sessionQueue = DispatchQueue(label: "com.goodcraft.altipin.geocamera.session")

    func prepare() async {
        let granted = await requestCameraPermission()
        guard granted else {
            permissionDenied = true
            return
        }
        if captureMode == .video {
            _ = await requestMicrophonePermission()
        }
        configureSessionIfNeeded()
        startSession()
    }

    func setCaptureMode(_ mode: GeoCameraCaptureMode) {
        captureMode = mode
        if mode == .video {
            Task { _ = await requestMicrophonePermission() }
        }
    }

    func flipCamera() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            let nextPosition: AVCaptureDevice.Position
            switch videoDeviceInput?.device.position {
            case .back: nextPosition = .front
            default: nextPosition = .back
            }
            guard let device = Self.bestVideoDevice(for: nextPosition),
                  let input = try? AVCaptureDeviceInput(device: device) else {
                return
            }
            session.beginConfiguration()
            if let currentInput = videoDeviceInput {
                session.removeInput(currentInput)
            }
            if session.canAddInput(input) {
                session.addInput(input)
                videoDeviceInput = input
            }
            session.commitConfiguration()
            configureMovieOutputConnections()
            resetZoomOnDevice(device)
        }
    }

    func setZoomFactor(_ factor: CGFloat) {
        sessionQueue.async { [weak self] in
            self?.applyZoomFactor(factor)
        }
    }

    func resetZoom() {
        setZoomFactor(1.0)
    }

    func capturePhoto() {
        guard captureMode == .photo, !isRecording else { return }
        let settings = AVCapturePhotoSettings()
        if photoOutput.supportedFlashModes.contains(.auto) {
            settings.flashMode = .auto
        }
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    func toggleRecording(metadata: GeoStampMetadata) {
        switch captureMode {
        case .photo:
            break
        case .video:
            sessionQueue.async { [weak self] in
                self?.toggleRecordingOnQueue(metadata: metadata)
            }
        }
    }

    func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self, session.isRunning else { return }
            session.stopRunning()
            Task { @MainActor in
                self.isSessionRunning = false
            }
        }
    }

    private func startSession() {
        sessionQueue.async { [weak self] in
            guard let self, !session.isRunning else { return }
            session.startRunning()
            Task { @MainActor in
                self.isSessionRunning = true
            }
        }
    }

    private func configureSessionIfNeeded() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard session.inputs.isEmpty else { return }

            session.beginConfiguration()
            session.sessionPreset = .high

            guard let camera = Self.bestVideoDevice(for: .back),
                  let videoInput = try? AVCaptureDeviceInput(device: camera),
                  session.canAddInput(videoInput) else {
                session.commitConfiguration()
                Task { @MainActor in
                    self.errorMessage = L10n.t("Cannot access camera")
                }
                return
            }
            session.addInput(videoInput)
            videoDeviceInput = videoInput

            if let audioDevice = AVCaptureDevice.default(for: .audio),
               let audioInput = try? AVCaptureDeviceInput(device: audioDevice),
               session.canAddInput(audioInput) {
                session.addInput(audioInput)
            }

            if session.canAddOutput(photoOutput) {
                session.addOutput(photoOutput)
            }
            if session.canAddOutput(movieOutput) {
                session.addOutput(movieOutput)
            }

            configureMovieOutputConnections()

            session.commitConfiguration()
            refreshZoomLimits(for: camera)
            applyZoomFactor(1.0)
        }
    }

    private func configureMovieOutputConnections() {
        guard let connection = movieOutput.connection(with: .video) else { return }
        if connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
        if connection.isVideoStabilizationSupported {
            connection.preferredVideoStabilizationMode = .auto
        }
    }

    private func applyZoomFactor(_ factor: CGFloat) {
        guard let device = videoDeviceInput?.device else { return }
        let minZoom = device.minAvailableVideoZoomFactor
        let maxZoom = min(device.maxAvailableVideoZoomFactor, 10.0)
        let clamped = min(max(factor, minZoom), maxZoom)

        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = clamped
            device.unlockForConfiguration()
            Task { @MainActor in
                self.zoomFactor = clamped
                self.minZoomFactor = minZoom
                self.maxZoomFactor = maxZoom
            }
        } catch {
            Task { @MainActor in
                self.errorMessage = L10n.t("Zoom failed")
            }
        }
    }

    private func resetZoomOnDevice(_ device: AVCaptureDevice) {
        refreshZoomLimits(for: device)
        applyZoomFactor(1.0)
    }

    private func refreshZoomLimits(for device: AVCaptureDevice) {
        let minZoom = device.minAvailableVideoZoomFactor
        let maxZoom = min(device.maxAvailableVideoZoomFactor, 10.0)
        Task { @MainActor in
            minZoomFactor = minZoom
            maxZoomFactor = maxZoom
            zoomFactor = min(max(zoomFactor, minZoom), maxZoom)
        }
    }

    /// Prefers virtual multi-camera devices on the back camera so ultra-wide 0.5× zoom is available.
    private static func bestVideoDevice(for position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        if position == .back {
            let preferredTypes: [AVCaptureDevice.DeviceType] = [
                .builtInTripleCamera,
                .builtInDualWideCamera,
                .builtInDualCamera,
                .builtInWideAngleCamera,
            ]
            let discoverySession = AVCaptureDevice.DiscoverySession(
                deviceTypes: preferredTypes,
                mediaType: .video,
                position: .back
            )
            for type in preferredTypes {
                if let device = discoverySession.devices.first(where: { $0.deviceType == type }) {
                    return device
                }
            }
        }
        return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
    }

    private func toggleRecordingOnQueue(metadata: GeoStampMetadata) {
        if movieOutput.isRecording {
            stopRecordingOnQueue()
        } else {
            startRecordingOnQueue(metadata: metadata)
        }
    }

    private func startRecordingOnQueue(metadata: GeoStampMetadata) {
        #if targetEnvironment(simulator)
        publishError(L10n.t("Recording is not supported in Simulator. Use a physical device."))
        return
        #endif

        guard session.isRunning else {
            publishError(L10n.t("Camera not ready. Please try again."))
            return
        }

        guard !movieOutput.isRecording else { return }

        configureMovieOutputConnections()

        guard isMovieOutputReadyForRecording else {
            publishError(L10n.t("Cannot start recording. Check camera and microphone permissions."))
            return
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).mov")

        Task { @MainActor in
            recordingStartedAt = Date()
            recordingMetadata = metadata
            isRecording = true
        }

        movieOutput.startRecording(to: tempURL, recordingDelegate: self)
    }

    private func stopRecordingOnQueue() {
        guard movieOutput.isRecording else { return }
        movieOutput.stopRecording()
    }

    private var isMovieOutputReadyForRecording: Bool {
        guard session.outputs.contains(movieOutput) else { return false }
        guard let connection = movieOutput.connection(with: .video) else { return false }
        return connection.isEnabled && connection.isActive
    }

    private func publishError(_ message: String) {
        Task { @MainActor in
            errorMessage = message
        }
    }

    private func requestCameraPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        default:
            return false
        }
    }

    private func requestMicrophonePermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        default:
            return false
        }
    }
}

extension GeoCameraService: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        guard error == nil,
              let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else {
            Task { @MainActor in
                self.errorMessage = error?.localizedDescription ?? L10n.t("Photo capture failed")
            }
            return
        }
        Task { @MainActor in
            self.onPhotoCaptured?(image)
        }
    }
}

extension GeoCameraService: AVCaptureFileOutputRecordingDelegate {
    nonisolated func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        Task { @MainActor in
            let duration = Date().timeIntervalSince(self.recordingStartedAt ?? Date())
            self.isRecording = false
            self.recordingStartedAt = nil
            if let error {
                self.errorMessage = error.localizedDescription
                return
            }
            self.onVideoCaptured?(outputFileURL, duration)
            self.recordingMetadata = nil
        }
    }
}
