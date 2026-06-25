//
//  L10n.swift
//  AltiPin
//

import Foundation

enum L10n {
    static var activeLocale: Locale {
        AppLanguage.persisted.resolvedLocale
    }

    static func t(_ key: String.LocalizationValue, locale: Locale? = nil) -> String {
        String(localized: key, locale: locale ?? activeLocale)
    }

    static func format(_ key: String.LocalizationValue, _ arguments: CVarArg..., locale: Locale? = nil) -> String {
        let resolved = locale ?? activeLocale
        let template = String(localized: key, locale: resolved)
        return String(format: template, locale: resolved, arguments: arguments)
    }
}
