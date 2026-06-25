//
//  TripRecordStore.swift
//  AltiPin
//

import CoreLocation
import Foundation
import SwiftData

enum TripRecordError: LocalizedError {
    case trackTooShort
    case gpxWriteFailed
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .trackTooShort:
            return "轨迹太短，未保存"
        case .gpxWriteFailed:
            return "轨迹文件写入失败"
        case .saveFailed:
            return "轨迹保存失败"
        }
    }
}

@MainActor
final class TripRecordStore {
    static let minimumDistanceMeters = 10.0

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func saveSession(
        points: [HistoryPoint],
        duration: TimeInterval,
        distanceMeters: Double,
        startTime: Date,
        endTime: Date
    ) throws -> TripEntity {
        guard points.count >= 2, distanceMeters >= Self.minimumDistanceMeters else {
            throw TripRecordError.trackTooShort
        }

        let fileName = "Session_\(UUID().uuidString).gpx"
        let fileURL = GPXTrackReader.fileURL(for: fileName)

        do {
            try SessionGPXWriter.write(points: points, to: fileURL)
        } catch {
            throw TripRecordError.gpxWriteFailed
        }

        let stats = Self.computeStats(from: points, distanceMeters: distanceMeters)
        let entity = TripEntity(
            title: Self.makeTitle(for: startTime),
            subGpxFileNames: [fileName],
            startTime: startTime,
            endTime: endTime,
            totalDistance: stats.distance,
            totalAscent: stats.ascent,
            maxElevation: stats.maxElevation
        )

        modelContext.insert(entity)
        do {
            try modelContext.save()
        } catch {
            try? FileManager.default.removeItem(at: fileURL)
            throw TripRecordError.saveFailed
        }

        return entity
    }

    func loadTrackPoints(for trip: TripEntity) -> [HistoryPoint] {
        var allPoints: [HistoryPoint] = []
        for fileName in trip.subGpxFileNames {
            let url = GPXTrackReader.fileURL(for: fileName)
            allPoints.append(contentsOf: GPXTrackReader.parse(url: url))
        }
        return allPoints.sorted { $0.timestamp < $1.timestamp }
    }

    func delete(_ trips: [TripEntity]) throws {
        guard !trips.isEmpty else { return }

        for trip in trips {
            for fileName in trip.subGpxFileNames {
                let url = GPXTrackReader.fileURL(for: fileName)
                try? FileManager.default.removeItem(at: url)
            }
            modelContext.delete(trip)
        }

        try modelContext.save()
    }

    private static func makeTitle(for startTime: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 运动"
        return formatter.string(from: startTime)
    }

    private static func computeStats(
        from points: [HistoryPoint],
        distanceMeters: Double
    ) -> (distance: Double, ascent: Double, maxElevation: Double) {
        var ascent = 0.0
        var maxElevation = 0.0

        for point in points {
            if point.elevationDelta > 0 {
                ascent += point.elevationDelta
            }
            maxElevation = max(maxElevation, point.elevation)
        }

        let computedDistance = trackDistanceMeters(from: points)
        let distance = distanceMeters > 0 ? distanceMeters : computedDistance

        return (distance, ascent, maxElevation)
    }

    private static func trackDistanceMeters(from points: [HistoryPoint]) -> Double {
        guard points.count >= 2 else { return 0 }
        var total = 0.0
        for index in 1..<points.count {
            let previous = CLLocation(latitude: points[index - 1].latitude, longitude: points[index - 1].longitude)
            let current = CLLocation(latitude: points[index].latitude, longitude: points[index].longitude)
            total += current.distance(from: previous)
        }
        return total
    }
}

// MARK: - Session GPX Writer

private enum SessionGPXWriter {
    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func write(points: [HistoryPoint], to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }

        guard let startTime = points.first?.timestamp else { return }

        var content = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="AltiPin"
             xmlns="http://www.topografix.com/GPX/1/1"
             xmlns:altipin="https://altipin.app/gpx">
          <metadata>
            <time>\(isoFormatter.string(from: startTime))</time>
          </metadata>
          <trk>
            <name>AltiPin Session</name>
            <trkseg>

        """

        for point in points {
            let timeString = isoFormatter.string(from: point.timestamp)
            let indoorValue = point.isIndoor ? "true" : "false"
            content += """
                <trkpt lat="\(point.latitude)" lon="\(point.longitude)">
                  <ele>\(String(format: "%.1f", point.elevation))</ele>
                  <time>\(timeString)</time>
                  <extensions>
                    <altipin:delta>\(String(format: "%.2f", point.elevationDelta))</altipin:delta>
                    <altipin:indoor>\(indoorValue)</altipin:indoor>
                  </extensions>
                </trkpt>

            """
        }

        content += """
            </trkseg>
          </trk>
        </gpx>
        """

        try content.write(to: url, atomically: true, encoding: .utf8)
    }
}
