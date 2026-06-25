//
//  GPXTrackReader.swift
//  AltiPin
//

import Foundation

enum GPXTrackReader {
    static func parse(url: URL) -> [HistoryPoint] {
        guard let parser = XMLParser(contentsOf: url) else { return [] }
        let delegate = GPXHistoryPointParser()
        parser.delegate = delegate
        parser.parse()
        return delegate.points
    }

    static func tracksDirectory() -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("Tracks", isDirectory: true)
    }

    static func fileURL(for fileName: String) -> URL {
        tracksDirectory().appendingPathComponent(fileName)
    }
}

// MARK: - GPX → HistoryPoint

private final class GPXHistoryPointParser: NSObject, XMLParserDelegate {
    private(set) var points: [HistoryPoint] = []
    private var elementStack: [String] = []
    private var textBuffer = ""

    private var currentLatitude: Double?
    private var currentLongitude: Double?
    private var currentElevation: Double?
    private var currentTime: Date?
    private var currentDelta: Double = 0
    private var currentIsIndoor = false

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
            currentLatitude = Double(attributeDict["lat"] ?? "")
            currentLongitude = Double(attributeDict["lon"] ?? "")
            currentElevation = nil
            currentTime = nil
            currentDelta = 0
            currentIsIndoor = false
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
            switch elementName {
            case "ele":
                if let value = Double(trimmed) {
                    currentElevation = value
                }
            case "time":
                currentTime = isoFormatter.date(from: trimmed) ?? isoFormatterFallback.date(from: trimmed)
            case "delta":
                if let value = Double(trimmed) {
                    currentDelta = value
                }
            case "indoor":
                currentIsIndoor = trimmed.lowercased() == "true"
            default:
                break
            }
        }

        if elementName == "trkpt",
           let latitude = currentLatitude,
           let longitude = currentLongitude,
           let elevation = currentElevation,
           let timestamp = currentTime {
            points.append(
                HistoryPoint(
                    timestamp: timestamp,
                    latitude: latitude,
                    longitude: longitude,
                    elevation: elevation,
                    elevationDelta: currentDelta,
                    isIndoor: currentIsIndoor
                )
            )
        }

        _ = elementStack.popLast()
        textBuffer = ""
    }
}
