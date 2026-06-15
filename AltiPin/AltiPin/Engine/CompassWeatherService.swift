//
//  CompassWeatherService.swift
//  AltiPin
//

import Combine
import CoreLocation
import Foundation
import WeatherKit

@MainActor
final class CompassWeatherService: ObservableObject {
    @Published private(set) var localityName: String = "—"
    @Published private(set) var temperatureCelsius: Double?
    @Published private(set) var windDirectionName: String = "—"
    @Published private(set) var conditionSymbol: String = "cloud"

    private let weatherService = WeatherService.shared
    private let geocoder = CLGeocoder()
    private var lastRefreshCoordinate: CLLocationCoordinate2D?

    func refresh(for location: CLLocation) async {
        if let last = lastRefreshCoordinate {
            let previous = CLLocation(latitude: last.latitude, longitude: last.longitude)
            if previous.distance(from: location) < 500 {
                return
            }
        }
        lastRefreshCoordinate = location.coordinate

        await refreshLocality(for: location)
        await refreshWeather(for: location)
    }

    func forceRefresh(for location: CLLocation) async {
        lastRefreshCoordinate = nil
        await refresh(for: location)
    }

    // MARK: - Private

    private func refreshLocality(for location: CLLocation) async {
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            if let placemark = placemarks.first {
                localityName = placemark.subLocality
                    ?? placemark.locality
                    ?? placemark.administrativeArea
                    ?? "—"
            }
        } catch {
            NSLog("CompassWeatherService: geocode failed — \(error.localizedDescription)")
        }
    }

    private func refreshWeather(for location: CLLocation) async {
        do {
            let weather = try await weatherService.weather(for: location)
            let current = weather.currentWeather

            temperatureCelsius = current.temperature.converted(to: .celsius).value
            windDirectionName = Self.windDirectionName(for: current.wind.direction.value)
            conditionSymbol = Self.symbol(for: current.condition)
        } catch {
            NSLog("CompassWeatherService: weather failed — \(error.localizedDescription)")
        }
    }

    static func windDirectionName(for degrees: Double) -> String {
        let normalized = (degrees.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        let names = ["北风", "东北风", "东风", "东南风", "南风", "西南风", "西风", "西北风"]
        let index = Int((normalized + 22.5) / 45) % 8
        return names[index]
    }

    static func symbol(for condition: WeatherCondition) -> String {
        switch condition {
        case .clear, .mostlyClear, .hot:
            return "sun.max.fill"
        case .partlyCloudy, .mostlyCloudy, .cloudy:
            return "cloud.fill"
        case .rain, .heavyRain, .drizzle, .sunShowers:
            return "cloud.rain.fill"
        case .thunderstorms, .isolatedThunderstorms, .scatteredThunderstorms, .strongStorms:
            return "cloud.bolt.rain.fill"
        case .snow, .heavySnow, .flurries, .sunFlurries, .blizzard, .blowingSnow, .sleet, .freezingRain, .wintryMix:
            return "cloud.snow.fill"
        case .foggy, .haze, .smoky:
            return "cloud.fog.fill"
        case .windy, .breezy:
            return "wind"
        case .hail, .frigid:
            return "cloud.hail.fill"
        case .blowingDust:
            return "sun.dust.fill"
        case .freezingDrizzle:
            return "cloud.sleet.fill"
        case .tropicalStorm, .hurricane:
            return "hurricane"
        @unknown default:
            return "cloud"
        }
    }
}
