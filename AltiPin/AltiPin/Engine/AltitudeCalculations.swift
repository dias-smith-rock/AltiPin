//
//  AltitudeCalculations.swift
//  AltiPin
//

import Foundation

enum AltitudeCalculations {
    static func pressureMmHg(fromHPa hPa: Double) -> Double {
        hPa * 0.750062
    }

    static func boilingPointCelsius(pressureHPa: Double) -> Double {
        guard pressureHPa > 0 else { return 100 }
        let ratio = pressureHPa / 1013.25
        return 100 * pow(ratio, 0.1903)
    }

    static func boilingPointFahrenheit(pressureHPa: Double) -> Double {
        let celsius = boilingPointCelsius(pressureHPa: pressureHPa)
        return celsius * 9 / 5 + 32
    }

    /// 含氧量：O₂ 体积密度相对海平面的百分比
    static func oxygenRatio(elevationMeters: Double, pressureHPa: Double) -> Double {
        let pressureFactor = pressureHPa > 0 ? pressureHPa / 1013.25 : exp(-elevationMeters / 8500)
        return max(0, min(100, pressureFactor * 100))
    }

    /// 含氧比：每立方米空气中 O₂ 质量（g/m³）近似
    static func oxygenContentGramsPerCubicMeter(
        elevationMeters: Double,
        pressureHPa: Double,
        temperatureCelsius: Double = 15
    ) -> Double {
        let pressurePa = pressureHPa > 0 ? pressureHPa * 100 : 101325 * exp(-elevationMeters / 8500)
        let temperatureK = temperatureCelsius + 273.15
        let o2MolarMass = 32.0
        let gasConstant = 8.314
        let o2MoleFraction = 0.2095
        return (pressurePa * o2MoleFraction * o2MolarMass) / (gasConstant * temperatureK)
    }

    static func windLevel(kmh: Double) -> Int {
        switch kmh {
        case ..<1: return 0
        case ..<6: return 1
        case ..<12: return 2
        case ..<20: return 3
        case ..<29: return 4
        case ..<39: return 5
        case ..<50: return 6
        case ..<62: return 7
        case ..<75: return 8
        case ..<89: return 9
        case ..<103: return 10
        case ..<117: return 11
        default: return 12
        }
    }

    static func conditionName(forWeatherCode code: Int) -> String {
        switch code {
        case 0: return "晴"
        case 1, 2: return "多云"
        case 3: return "阴"
        case 45, 48: return "雾"
        case 51, 53, 55: return "毛毛雨"
        case 56, 57: return "冻毛毛雨"
        case 61, 63, 65, 80, 81, 82: return "小雨"
        case 66, 67: return "冻雨"
        case 71, 73, 75, 77, 85, 86: return "雪"
        case 95: return "雷雨"
        case 96, 99: return "冰雹雷雨"
        default: return "未知"
        }
    }
}
