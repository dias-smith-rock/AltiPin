//
//  GeoMediaLibrary.swift
//  AltiPin
//

import Photos
import SwiftUI
import UIKit

enum GeoMediaLibrary {
    static func requestAddOnlyAuthorization() async -> Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        switch status {
        case .authorized, .limited:
            return true
        case .notDetermined:
            let newStatus = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            return newStatus == .authorized || newStatus == .limited
        default:
            return false
        }
    }

    @MainActor
    static func saveToPhotoLibrary(entities: [GeoMediaEntity], store: GeoMediaStore) async throws {
        guard await requestAddOnlyAuthorization() else {
            throw GeoMediaLibraryError.permissionDenied
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                for entity in entities {
                    let fileURL = store.fileURL(for: entity)
                    switch entity.mediaType {
                    case .photo:
                        PHAssetCreationRequest.forAsset().addResource(with: .photo, fileURL: fileURL, options: nil)
                    case .video:
                        PHAssetCreationRequest.forAsset().addResource(with: .video, fileURL: fileURL, options: nil)
                    }
                }
            } completionHandler: { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: GeoMediaLibraryError.saveFailed)
                }
            }
        }
    }

    @MainActor
    static func shareURLs(for entities: [GeoMediaEntity], store: GeoMediaStore) -> [URL] {
        entities.map { store.fileURL(for: $0) }
    }
}

enum GeoMediaLibraryError: LocalizedError {
    case permissionDenied
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .permissionDenied: "没有相册写入权限"
        case .saveFailed: "保存到相册失败"
        }
    }
}

struct GeoMediaShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
