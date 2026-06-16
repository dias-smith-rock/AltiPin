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
    @Published private(set) var apparentTemperatureCelsius: Double?
    @Published private(set) var humidityPercent: Double?
    @Published private(set) var windSpeedKmh: Double?
    @Published private(set) var windDirectionDegrees: Double?
    @Published private(set) var windDirectionName: String = "—"
    @Published private(set) var windLevel: Int?
    @Published private(set) var conditionName: String = "—"
    @Published private(set) var conditionSymbol: String = "cloud"

    private let weatherService = WeatherService.shared
    private let geocoder = CLGeocoder()
    private var lastRefreshCoordinate: CLLocationCoordinate2D?
    private var hasLoadedWeather = false

    func refresh(for location: CLLocation) async {
        let shouldSkipDueToDistance: Bool
        if let last = lastRefreshCoordinate {
            let previous = CLLocation(latitude: last.latitude, longitude: last.longitude)
            shouldSkipDueToDistance = previous.distance(from: location) < 500
        } else {
            shouldSkipDueToDistance = false
        }

        if shouldSkipDueToDistance && hasLoadedWeather {
            return
        }

        if !shouldSkipDueToDistance {
            lastRefreshCoordinate = location.coordinate
            await refreshLocality(for: location)
        }

        await refreshWeather(for: location)
    }

    func forceRefresh(for location: CLLocation) async {
        lastRefreshCoordinate = nil
        hasLoadedWeather = false
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
        if await refreshWeatherKit(for: location) {
            hasLoadedWeather = true
            return
        }

        if await refreshOpenMeteo(for: location) {
            hasLoadedWeather = true
        }
    }

    private func applyWind(speedMS: Double, directionDegrees: Double) {
        let kmh = speedMS * 3.6
        windSpeedKmh = kmh
        windDirectionDegrees = directionDegrees
        windDirectionName = Self.windDirectionName(for: directionDegrees)
        windLevel = AltitudeCalculations.windLevel(kmh: kmh)
    }

    private func refreshWeatherKit(for location: CLLocation) async -> Bool {
        do {
            let weather = try await weatherService.weather(for: location)
            let current = weather.currentWeather

            temperatureCelsius = current.temperature.converted(to: .celsius).value
            apparentTemperatureCelsius = current.apparentTemperature.converted(to: .celsius).value
            humidityPercent = current.humidity * 100
            applyWind(
                speedMS: current.wind.speed.converted(to: .metersPerSecond).value,
                directionDegrees: current.wind.direction.value
            )
            conditionSymbol = current.symbolName
            conditionName = Self.conditionName(for: current.condition)
            return true
        } catch {
            NSLog("CompassWeatherService: WeatherKit failed — \(error.localizedDescription)")
            return false
        }
    }

    private func refreshOpenMeteo(for location: CLLocation) async -> Bool {
        let coordinate = location.coordinate
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(coordinate.latitude)),
            URLQueryItem(name: "longitude", value: String(coordinate.longitude)),
            URLQueryItem(
                name: "current",
                value: "temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_direction_10m,wind_speed_10m"
            ),
            URLQueryItem(name: "timezone", value: "auto"),
        ]

        guard let url = components.url else { return false }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return false
            }

            let payload = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
            guard let current = payload.current else { return false }

            temperatureCelsius = current.temperature2m
            apparentTemperatureCelsius = current.apparentTemperature2m
            humidityPercent = current.relativeHumidity2m
            if let windDirection = current.windDirection10m, let windSpeed = current.windSpeed10m {
                windSpeedKmh = windSpeed
                windDirectionDegrees = windDirection
                windDirectionName = Self.windDirectionName(for: windDirection)
                windLevel = AltitudeCalculations.windLevel(kmh: windSpeed)
            }
            conditionSymbol = Self.symbol(forWeatherCode: current.weatherCode)
            conditionName = AltitudeCalculations.conditionName(forWeatherCode: current.weatherCode)
            NSLog("CompassWeatherService: using Open-Meteo fallback")
            return true
        } catch {
            NSLog("CompassWeatherService: Open-Meteo failed — \(error.localizedDescription)")
            return false
        }
    }

    static func symbol(forWeatherCode code: Int) -> String {
        switch code {
        case 0:
            return "sun.max.fill"
        case 1, 2:
            return "cloud.sun.fill"
        case 3:
            return "cloud.fill"
        case 45, 48:
            return "cloud.fog.fill"
        case 51, 53, 55, 56, 57, 61, 63, 65, 66, 67, 80, 81, 82:
            return "cloud.rain.fill"
        case 71, 73, 75, 77, 85, 86:
            return "cloud.snow.fill"
        case 95, 96, 99:
            return "cloud.bolt.rain.fill"
        default:
            return "cloud.fill"
        }
    }

    static func windDirectionName(for degrees: Double) -> String {
        let normalized = (degrees.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        let names = ["北风", "东北风", "东风", "东南风", "南风", "西南风", "西风", "西北风"]
        let index = Int((normalized + 22.5) / 45) % 8
        return names[index]
    }

    static func conditionName(for condition: WeatherCondition) -> String {
        switch condition {
        case .clear, .mostlyClear, .hot:
            return "晴"
        case .partlyCloudy:
            return "多云"
        case .mostlyCloudy, .cloudy:
            return "阴"
        case .rain, .heavyRain, .drizzle, .sunShowers:
            return "小雨"
        case .thunderstorms, .isolatedThunderstorms, .scatteredThunderstorms, .strongStorms:
            return "雷雨"
        case .snow, .heavySnow, .flurries, .sunFlurries, .blizzard, .blowingSnow, .sleet, .freezingRain, .wintryMix:
            return "雪"
        case .foggy, .haze, .smoky:
            return "雾"
        case .windy, .breezy:
            return "大风"
        case .hail:
            return "冰雹"
        case .freezingDrizzle:
            return "冻雨"
        case .tropicalStorm, .hurricane:
            return "风暴"
        case .frigid:
            return "严寒"
        case .blowingDust:
            return "沙尘"
        @unknown default:
            return "未知"
        }
    }
}

// MARK: - Open-Meteo

private struct OpenMeteoResponse: Decodable {
    let current: OpenMeteoCurrent?
}

private struct OpenMeteoCurrent: Decodable {
    let temperature2m: Double
    let apparentTemperature2m: Double?
    let relativeHumidity2m: Double?
    let weatherCode: Int
    let windDirection10m: Double?
    let windSpeed10m: Double?

    enum CodingKeys: String, CodingKey {
        case temperature2m = "temperature_2m"
        case apparentTemperature2m = "apparent_temperature"
        case relativeHumidity2m = "relative_humidity_2m"
        case weatherCode = "weather_code"
        case windDirection10m = "wind_direction_10m"
        case windSpeed10m = "wind_speed_10m"
    }
}
