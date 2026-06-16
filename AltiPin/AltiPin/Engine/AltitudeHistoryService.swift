//
//  AltitudeHistoryService.swift
//  AltiPin
//

import Combine
import Foundation

struct ElevationSample: Identifiable, Equatable {
    let id: UUID
    let date: Date
    let elevation: Double

    init(id: UUID = UUID(), date: Date, elevation: Double) {
        self.id = id
        self.date = date
        self.elevation = elevation
    }
}

@MainActor
final class AltitudeHistoryService: ObservableObject {
    @Published private(set) var chartSamples: [ElevationSample] = []
    @Published private(set) var maxElevation: Double?
    @Published private(set) var minElevation: Double?

    private var gpxSamples: [ElevationSample] = []
    private var liveSamples: [ElevationSample] = []
    private var lastLiveSampleDate: Date?
    private let liveSampleInterval: TimeInterval = 30

    private var tracksDirectory: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("Tracks", isDirectory: true)
    }

    func reloadFromGPX() {
        gpxSamples = Self.loadSamples(from: tracksDirectory)
        rebuildChart()
    }

    func appendLiveSample(elevation: Double, date: Date = .now) {
        if let last = lastLiveSampleDate, date.timeIntervalSince(last) < liveSampleInterval {
            if let latest = liveSamples.last {
                liveSamples[liveSamples.count - 1] = ElevationSample(
                    id: latest.id,
                    date: date,
                    elevation: elevation
                )
                rebuildChart()
            }
            return
        }

        lastLiveSampleDate = date
        liveSamples.append(ElevationSample(date: date, elevation: elevation))
        rebuildChart()
    }

    // MARK: - Private

    private func rebuildChart() {
        let merged = (gpxSamples + liveSamples).sorted { $0.date < $1.date }
        chartSamples = Self.downsample(merged, targetCount: 30)
        maxElevation = merged.map(\.elevation).max()
        minElevation = merged.map(\.elevation).min()
    }

    private static func loadSamples(from directory: URL) -> [ElevationSample] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }

        var samples: [ElevationSample] = []
        for file in files where file.pathExtension.lowercased() == "gpx" {
            samples.append(contentsOf: GPXElevationParser.parse(url: file))
        }
        return samples.sorted { $0.date < $1.date }
    }

    private static func downsample(_ samples: [ElevationSample], targetCount: Int) -> [ElevationSample] {
        guard samples.count > targetCount else { return samples }

        var result = Set<UUID>()
        var output: [ElevationSample] = []

        if let maxSample = samples.max(by: { $0.elevation < $1.elevation }) {
            result.insert(maxSample.id)
            output.append(maxSample)
        }
        if let minSample = samples.min(by: { $0.elevation < $1.elevation }) {
            if !result.contains(minSample.id) {
                result.insert(minSample.id)
                output.append(minSample)
            }
        }

        let step = Double(samples.count - 1) / Double(targetCount - 1)
        for index in 0..<targetCount {
            let sourceIndex = Int((Double(index) * step).rounded())
            let clampedIndex = min(max(sourceIndex, 0), samples.count - 1)
            let sample = samples[clampedIndex]
            if !result.contains(sample.id) {
                result.insert(sample.id)
                output.append(sample)
            }
        }

        return output.sorted { $0.date < $1.date }
    }
}

// MARK: - GPX Parser

private final class GPXElevationParser: NSObject, XMLParserDelegate {
    private var samples: [ElevationSample] = []
    private var elementStack: [String] = []
    private var textBuffer = ""
    private var currentElevation: Double?
    private var currentTime: Date?

    private let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private let isoFormatterFallback: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func parse(url: URL) -> [ElevationSample] {
        guard let parser = XMLParser(contentsOf: url) else { return [] }
        let delegate = GPXElevationParser()
        parser.delegate = delegate
        parser.parse()
        return delegate.samples
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        elementStack.append(elementName)
        textBuffer = ""
        if elementName == "trkpt" {
            currentElevation = nil
            currentTime = nil
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        textBuffer += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?
    ) {
        let trimmed = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        let insideTrackPoint = elementStack.contains("trkpt")

        if insideTrackPoint {
            if elementName == "ele", let value = Double(trimmed) {
                currentElevation = value
            } else if elementName == "time" {
                currentTime = isoFormatter.date(from: trimmed) ?? isoFormatterFallback.date(from: trimmed)
            }
        }

        if elementName == "trkpt", let elevation = currentElevation, let date = currentTime {
            samples.append(ElevationSample(date: date, elevation: elevation))
        }

        _ = elementStack.popLast()
        textBuffer = ""
    }
}
