//
//  GeoMediaEntity.swift
//  AltiPin
//

import Foundation
import SwiftData

enum GeoMediaType: String, Codable, CaseIterable {
    case photo
    case video
}

@Model
final class GeoMediaEntity {
    @Attribute(.unique) var id: UUID
    var capturedAt: Date
    var mediaTypeRaw: String
    var fileName: String
    var thumbnailFileName: String?
    var latitude: Double
    var longitude: Double
    var elevation: Double
    var locality: String
    var weatherCondition: String
    var temperatureCelsius: Double?
    var coordinateLabel: String
    var durationSeconds: Double?

    init(
        id: UUID = UUID(),
        capturedAt: Date,
        mediaType: GeoMediaType,
        fileName: String,
        thumbnailFileName: String? = nil,
        latitude: Double,
        longitude: Double,
        elevation: Double,
        locality: String,
        weatherCondition: String,
        temperatureCelsius: Double?,
        coordinateLabel: String,
        durationSeconds: Double? = nil
    ) {
        self.id = id
        self.capturedAt = capturedAt
        self.mediaTypeRaw = mediaType.rawValue
        self.fileName = fileName
        self.thumbnailFileName = thumbnailFileName
        self.latitude = latitude
        self.longitude = longitude
        self.elevation = elevation
        self.locality = locality
        self.weatherCondition = weatherCondition
        self.temperatureCelsius = temperatureCelsius
        self.coordinateLabel = coordinateLabel
        self.durationSeconds = durationSeconds
    }

    var mediaType: GeoMediaType {
        get { GeoMediaType(rawValue: mediaTypeRaw) ?? .photo }
        set { mediaTypeRaw = newValue.rawValue }
    }
}
