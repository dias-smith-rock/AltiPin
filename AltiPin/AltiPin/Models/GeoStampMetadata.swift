//
//  GeoStampMetadata.swift
//  AltiPin
//

import CoreLocation
import Foundation

struct GeoStampMetadata: Equatable, Sendable {
    let capturedAt: Date
    let latitude: Double
    let longitude: Double
    let elevation: Double
    let locality: String
    let weatherCondition: String
    let temperatureCelsius: Double?
    let coordinateLabel: String
    let usesAppleWeatherData: Bool
    let weatherAttributionLabel: String?

    @MainActor
    static func capture(
        from store: OutdoorDashboardStore,
        weather: CompassWeatherService,
        at date: Date = .now
    ) -> GeoStampMetadata {
        let location = store.currentLocation
        let latitude = location?.coordinate.latitude ?? store.latitude
        let longitude = location?.coordinate.longitude ?? store.longitude
        let elevation: Double
        if let location {
            elevation = store.resolvedElevation(for: location)
        } else {
            elevation = store.elevationMeters
        }

        return GeoStampMetadata(
            capturedAt: date,
            latitude: latitude,
            longitude: longitude,
            elevation: elevation,
            locality: weather.localityName,
            weatherCondition: weather.conditionName,
            temperatureCelsius: weather.temperatureCelsius,
            coordinateLabel: store.coordinateDMSString,
            usesAppleWeatherData: weather.usesAppleWeatherData,
            weatherAttributionLabel: weather.weatherAttributionLabel
        )
    }

    var overlayLines: [String] {
        var lines: [String] = []
        lines.append(coordinateLabel)
        lines.append(L10n.format("Elevation %.0f m", elevation))
        if !locality.isEmpty, locality != "—" {
            lines.append(locality)
        }
        lines.append(Self.formattedDateTime(capturedAt))
        var weatherLine = weatherCondition
        if let temperatureCelsius {
            weatherLine += String(format: " %.0f°C", temperatureCelsius)
        }
        lines.append(weatherLine)
        if usesAppleWeatherData {
            lines.append(weatherAttributionLabel ?? L10n.t("Weather"))
        }
        return lines
    }

    static func formattedDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }
}
