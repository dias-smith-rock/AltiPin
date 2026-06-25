//
//  L10n.swift
//  AltiPin
//

import Foundation

enum L10n {
    private(set) static var activeLocale: Locale = AppLanguage.persisted.resolvedLocale

    static func updateActiveLocale(_ locale: Locale) {
        activeLocale = locale
    }

    static func localizedBundle(for locale: Locale) -> Bundle {
        var candidates: [String] = []

        let identifier = locale.identifier.replacingOccurrences(of: "_", with: "-")
        if !identifier.isEmpty {
            candidates.append(identifier)
        }

        if let languageCode = locale.language.languageCode?.identifier, !languageCode.isEmpty {
            candidates.append(languageCode)
        }

        if identifier.hasPrefix("zh-Hans") || identifier == "zh-CN" {
            candidates.append("zh-Hans")
        } else if identifier.hasPrefix("zh-Hant") || identifier == "zh-TW" || identifier == "zh-HK" {
            candidates.append("zh-Hant")
        } else if identifier.hasPrefix("pt") {
            candidates.append("pt-BR")
        }

        for candidate in candidates {
            if let path = Bundle.main.path(forResource: candidate, ofType: "lproj"),
               let bundle = Bundle(path: path) {
                return bundle
            }
        }

        return .main
    }

    static func t(_ key: String.LocalizationValue, locale: Locale? = nil) -> String {
        let resolved = locale ?? activeLocale
        return String(localized: key, bundle: localizedBundle(for: resolved))
    }

    static func format(_ key: String.LocalizationValue, _ arguments: CVarArg..., locale: Locale? = nil) -> String {
        let resolved = locale ?? activeLocale
        let bundle = localizedBundle(for: resolved)
        let template = String(localized: key, bundle: bundle)
        return String(format: template, locale: resolved, arguments: arguments)
    }
}
