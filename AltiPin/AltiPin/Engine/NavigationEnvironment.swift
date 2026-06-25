//
//  NavigationEnvironment.swift
//  AltiPin
//

import Foundation

enum NavigationEnvironment: String, Sendable {
    case outdoor
    case indoor
}

enum NavigationEnvironmentControlMode: Equatable, Sendable {
    case automatic
    case manual(NavigationEnvironment)

    var selection: NavigationEnvironmentControlSelection {
        switch self {
        case .automatic:
            return .automatic
        case .manual(.outdoor):
            return .outdoor
        case .manual(.indoor):
            return .indoor
        }
    }

    init(selection: NavigationEnvironmentControlSelection) {
        switch selection {
        case .automatic:
            self = .automatic
        case .outdoor:
            self = .manual(.outdoor)
        case .indoor:
            self = .manual(.indoor)
        }
    }

    var isManual: Bool {
        if case .manual = self { return true }
        return false
    }

    var manualEnvironment: NavigationEnvironment? {
        if case let .manual(environment) = self { return environment }
        return nil
    }
}

enum NavigationEnvironmentControlSelection: String, CaseIterable, Identifiable, Sendable {
    case automatic
    case outdoor
    case indoor

    var id: String { rawValue }

    var label: String {
        switch self {
        case .automatic: return L10n.t("Automatic")
        case .outdoor: return L10n.t("Outdoor")
        case .indoor: return L10n.t("Indoor")
        }
    }
}

@MainActor
enum NavigationEnvironmentOverrideCenter {
    private(set) static var controlMode: NavigationEnvironmentControlMode = .automatic

    static var isManual: Bool { controlMode.isManual }

    static var manualEnvironment: NavigationEnvironment? { controlMode.manualEnvironment }

    static func apply(_ mode: NavigationEnvironmentControlMode) {
        controlMode = mode
    }

    static func reset() {
        controlMode = .automatic
    }
}
