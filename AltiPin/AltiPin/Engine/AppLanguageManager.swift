//
//  AppLanguageManager.swift
//  AltiPin
//

import Combine
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case en
    case zhHans = "zh-Hans"
    case zhHant = "zh-Hant"
    case ja
    case es
    case ptBR = "pt-BR"
    case ar
    case hi
    case fr

    var id: String { rawValue }

    var resolvedLocale: Locale {
        switch self {
        case .system:
            return .autoupdatingCurrent
        case .en:
            return Locale(identifier: "en")
        case .zhHans:
            return Locale(identifier: "zh-Hans")
        case .zhHant:
            return Locale(identifier: "zh-Hant")
        case .ja:
            return Locale(identifier: "ja")
        case .es:
            return Locale(identifier: "es")
        case .ptBR:
            return Locale(identifier: "pt-BR")
        case .ar:
            return Locale(identifier: "ar")
        case .hi:
            return Locale(identifier: "hi")
        case .fr:
            return Locale(identifier: "fr")
        }
    }

    /// Autonym shown in the language picker.
    var displayName: String {
        switch self {
        case .system:
            return L10n.t("System Default", locale: resolvedLocaleForPicker)
        case .en:
            return "English"
        case .zhHans:
            return "简体中文"
        case .zhHant:
            return "繁體中文"
        case .ja:
            return "日本語"
        case .es:
            return "Español"
        case .ptBR:
            return "Português"
        case .ar:
            return "العربية"
        case .hi:
            return "हिन्दी"
        case .fr:
            return "Français"
        }
    }

    private var resolvedLocaleForPicker: Locale {
        self == .system ? .autoupdatingCurrent : resolvedLocale
    }

    static var persisted: AppLanguage {
        let raw = UserDefaults.standard.string(forKey: storageKey) ?? AppLanguage.system.rawValue
        return AppLanguage(rawValue: raw) ?? .system
    }

    static var storageKey: String { "appLanguage" }
}

@MainActor
final class AppLanguageManager: ObservableObject {
    @Published var selected: AppLanguage {
        didSet {
            UserDefaults.standard.set(selected.rawValue, forKey: AppLanguage.storageKey)
        }
    }

    var locale: Locale { selected.resolvedLocale }

    var layoutDirection: LayoutDirection {
        locale.language.languageCode?.identifier == "ar" ? .rightToLeft : .leftToRight
    }

    var refreshToken: String { selected.rawValue }

    init() {
        selected = AppLanguage.persisted
    }

    func select(_ language: AppLanguage) {
        selected = language
    }
}
