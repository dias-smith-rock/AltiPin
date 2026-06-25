//
//  SpeedometerMode.swift
//  AltiPin
//

import Foundation

enum SpeedometerMode: String, CaseIterable, Identifiable {
    case driving
    case cycling
    case running
    case walking

    var id: String { rawValue }

    var title: String {
        switch self {
        case .driving: L10n.t("Driving")
        case .cycling: L10n.t("Cycling")
        case .running: L10n.t("Running")
        case .walking: L10n.t("Walking")
        }
    }

    var icon: String {
        switch self {
        case .driving: "car.fill"
        case .cycling: "bicycle"
        case .running: "figure.run"
        case .walking: "figure.walk"
        }
    }

    var maxSpeed: Double {
        switch self {
        case .driving: 320
        case .cycling: 80
        case .running: 40
        case .walking: 16
        }
    }

    var majorTickInterval: Double {
        switch self {
        case .driving: 40
        case .cycling: 10
        case .running: 5
        case .walking: 2
        }
    }
}
