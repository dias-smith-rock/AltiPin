//
//  GeoStampRenderer.swift
//  AltiPin
//

import AVFoundation
import CoreGraphics
import UIKit

enum GeoStampRenderer {
    static func stampedImage(from image: UIImage, metadata: GeoStampMetadata) -> UIImage {
        let normalized = image.normalizedOrientation()
        let size = normalized.size
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            normalized.draw(in: CGRect(origin: .zero, size: size))
            drawOverlay(metadata: metadata, in: context.cgContext, canvasSize: size)
        }
    }

    static func makeThumbnail(from image: UIImage, maxDimension: CGFloat = 320) -> UIImage? {
        let normalized = image.normalizedOrientation()
        let size = normalized.size
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = min(maxDimension / size.width, maxDimension / size.height, 1)
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: target)
        return renderer.image { _ in
            normalized.draw(in: CGRect(origin: .zero, size: target))
        }
    }

    static func makeVideoThumbnail(url: URL) async -> UIImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let time = CMTime(seconds: 0.2, preferredTimescale: 600)
        return await withCheckedContinuation { continuation in
            generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) { _, image, _, _, _ in
                if let image {
                    continuation.resume(returning: UIImage(cgImage: image))
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    static func stampedVideo(
        inputURL: URL,
        metadata: GeoStampMetadata,
        outputURL: URL
    ) async throws -> URL {
        let asset = AVURLAsset(url: inputURL)
        let videoComposition = try await makeStampedVideoComposition(for: asset, metadata: metadata)

        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw GeoMediaStoreError.exportFailed
        }

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.videoComposition = videoComposition
        exportSession.shouldOptimizeForNetworkUse = true

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            exportSession.exportAsynchronously {
                switch exportSession.status {
                case .completed:
                    continuation.resume()
                case .failed, .cancelled:
                    continuation.resume(throwing: exportSession.error ?? GeoMediaStoreError.exportFailed)
                default:
                    continuation.resume(throwing: GeoMediaStoreError.exportFailed)
                }
            }
        }

        return outputURL
    }

    static func drawOverlay(
        metadata: GeoStampMetadata,
        in context: CGContext,
        canvasSize: CGSize
    ) {
        let lines = metadata.overlayLines
        let padding = max(canvasSize.width, canvasSize.height) * 0.02
        let fontSize = max(12, min(canvasSize.width, canvasSize.height) * 0.028)
        let lineSpacing = fontSize * 0.35
        let textHeight = CGFloat(lines.count) * fontSize + CGFloat(lines.count - 1) * lineSpacing
        let barHeight = textHeight + padding * 2
        let barRect = CGRect(
            x: 0,
            y: canvasSize.height - barHeight,
            width: canvasSize.width,
            height: barHeight
        )

        context.setFillColor(UIColor.black.withAlphaComponent(0.55).cgColor)
        context.fill(barRect)

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .left

        var y = barRect.minY + padding
        for (index, line) in lines.enumerated() {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: fontSize, weight: index == 0 ? .semibold : .regular),
                .foregroundColor: index == 0 ? UIColor(red: 0.95, green: 0.55, blue: 0.12, alpha: 1) : UIColor.white,
                .paragraphStyle: paragraph,
            ]
            let rect = CGRect(
                x: padding,
                y: y,
                width: barRect.width - padding * 2,
                height: fontSize * 1.2
            )
            (line as NSString).draw(in: rect, withAttributes: attributes)
            y += fontSize + lineSpacing
        }
    }

    private static func makeStampedVideoComposition(
        for asset: AVURLAsset,
        metadata: GeoStampMetadata
    ) async throws -> AVMutableVideoComposition {
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = videoTracks.first else {
            throw GeoMediaStoreError.exportFailed
        }

        let naturalSize = try await videoTrack.load(.naturalSize)
        let preferredTransform = try await videoTrack.load(.preferredTransform)
        let transformedSize = naturalSize.applying(preferredTransform)
        let renderSize = CGSize(width: abs(transformedSize.width), height: abs(transformedSize.height))
        guard renderSize.width > 0, renderSize.height > 0 else {
            throw GeoMediaStoreError.exportFailed
        }

        let duration = try await asset.load(.duration)
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)

        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
        layerInstruction.setTransform(preferredTransform, at: .zero)
        instruction.layerInstructions = [layerInstruction]

        let videoLayer = CALayer()
        videoLayer.frame = CGRect(origin: .zero, size: renderSize)

        let overlayLayer = makeOverlayLayer(metadata: metadata, canvasSize: renderSize)
        overlayLayer.frame = CGRect(origin: .zero, size: renderSize)

        let parentLayer = CALayer()
        parentLayer.frame = CGRect(origin: .zero, size: renderSize)
        parentLayer.isGeometryFlipped = true
        parentLayer.addSublayer(videoLayer)
        parentLayer.addSublayer(overlayLayer)

        let composition = AVMutableVideoComposition()
        composition.renderSize = renderSize
        composition.frameDuration = CMTime(value: 1, timescale: 30)
        composition.instructions = [instruction]
        composition.animationTool = AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer,
            in: parentLayer
        )

        return composition
    }

    private static func makeOverlayLayer(metadata: GeoStampMetadata, canvasSize: CGSize) -> CALayer {
        let renderer = UIGraphicsImageRenderer(size: canvasSize)
        let overlayImage = renderer.image { context in
            drawOverlay(metadata: metadata, in: context.cgContext, canvasSize: canvasSize)
        }
        let layer = CALayer()
        layer.frame = CGRect(origin: .zero, size: canvasSize)
        layer.contents = overlayImage.cgImage
        return layer
    }
}

private extension UIImage {
    func normalizedOrientation() -> UIImage {
        guard imageOrientation != .up else { return self }
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
