//
//  GeoMediaStore.swift
//  AltiPin
//

import AVFoundation
import Foundation
import SwiftData
import UIKit

enum GeoMediaSortOrder: String, CaseIterable, Identifiable {
    case newestFirst
    case oldestFirst

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newestFirst: "最新优先"
        case .oldestFirst: "最早优先"
        }
    }

    var sortDescriptors: [SortDescriptor<GeoMediaEntity>] {
        switch self {
        case .newestFirst:
            [SortDescriptor(\.capturedAt, order: .reverse)]
        case .oldestFirst:
            [SortDescriptor(\.capturedAt, order: .forward)]
        }
    }
}

@MainActor
final class GeoMediaStore {
    static let folderName = "GeoMedia"

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        ensureMediaDirectory()
    }

    var mediaDirectory: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent(Self.folderName, isDirectory: true)
    }

    func fileURL(for entity: GeoMediaEntity) -> URL {
        mediaDirectory.appendingPathComponent(entity.fileName)
    }

    func thumbnailURL(for entity: GeoMediaEntity) -> URL? {
        guard let thumbnailFileName = entity.thumbnailFileName else { return nil }
        return mediaDirectory.appendingPathComponent(thumbnailFileName)
    }

    func insertPhoto(image: UIImage, metadata: GeoStampMetadata) throws -> GeoMediaEntity {
        let id = UUID()
        let fileName = "\(id.uuidString).jpg"
        let thumbnailFileName = "\(id.uuidString)_thumb.jpg"
        let stamped = GeoStampRenderer.stampedImage(from: image, metadata: metadata)

        guard let data = stamped.jpegData(compressionQuality: 0.92) else {
            throw GeoMediaStoreError.encodingFailed
        }

        let fileURL = mediaDirectory.appendingPathComponent(fileName)
        try data.write(to: fileURL, options: .atomic)

        if let thumbData = GeoStampRenderer.makeThumbnail(from: stamped)?.jpegData(compressionQuality: 0.8) {
            let thumbURL = mediaDirectory.appendingPathComponent(thumbnailFileName)
            try thumbData.write(to: thumbURL, options: .atomic)
        }

        let entity = GeoMediaEntity(
            id: id,
            capturedAt: metadata.capturedAt,
            mediaType: .photo,
            fileName: fileName,
            thumbnailFileName: thumbnailFileName,
            latitude: metadata.latitude,
            longitude: metadata.longitude,
            elevation: metadata.elevation,
            locality: metadata.locality,
            weatherCondition: metadata.weatherCondition,
            temperatureCelsius: metadata.temperatureCelsius,
            coordinateLabel: metadata.coordinateLabel
        )
        modelContext.insert(entity)
        try modelContext.save()
        return entity
    }

    func insertVideo(
        from sourceURL: URL,
        metadata: GeoStampMetadata,
        duration: TimeInterval
    ) async throws -> GeoMediaEntity {
        let id = UUID()
        let fileName = "\(id.uuidString).mp4"
        let thumbnailFileName = "\(id.uuidString)_thumb.jpg"
        let destinationURL = mediaDirectory.appendingPathComponent(fileName)

        let stampedURL = try await GeoStampRenderer.stampedVideo(
            inputURL: sourceURL,
            metadata: metadata,
            outputURL: mediaDirectory.appendingPathComponent("\(id.uuidString)_raw.mp4")
        )

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.moveItem(at: stampedURL, to: destinationURL)

        if let thumbnail = await GeoStampRenderer.makeVideoThumbnail(url: destinationURL),
           let thumbData = thumbnail.jpegData(compressionQuality: 0.8) {
            let thumbURL = mediaDirectory.appendingPathComponent(thumbnailFileName)
            try thumbData.write(to: thumbURL, options: .atomic)
        }

        let entity = GeoMediaEntity(
            id: id,
            capturedAt: metadata.capturedAt,
            mediaType: .video,
            fileName: fileName,
            thumbnailFileName: thumbnailFileName,
            latitude: metadata.latitude,
            longitude: metadata.longitude,
            elevation: metadata.elevation,
            locality: metadata.locality,
            weatherCondition: metadata.weatherCondition,
            temperatureCelsius: metadata.temperatureCelsius,
            coordinateLabel: metadata.coordinateLabel,
            durationSeconds: duration
        )
        modelContext.insert(entity)
        try modelContext.save()
        return entity
    }

    func delete(_ entities: [GeoMediaEntity]) throws {
        for entity in entities {
            let fileURL = fileURL(for: entity)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try? FileManager.default.removeItem(at: fileURL)
            }
            if let thumbURL = thumbnailURL(for: entity),
               FileManager.default.fileExists(atPath: thumbURL.path) {
                try? FileManager.default.removeItem(at: thumbURL)
            }
            modelContext.delete(entity)
        }
        try modelContext.save()
    }

    private func ensureMediaDirectory() {
        let url = mediaDirectory
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }
}

enum GeoMediaStoreError: LocalizedError {
    case encodingFailed
    case exportFailed

    var errorDescription: String? {
        switch self {
        case .encodingFailed: "无法编码照片"
        case .exportFailed: "视频导出失败"
        }
    }
}
