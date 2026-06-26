//
//  AppLinks.swift
//  AltiPin
//

import Foundation

enum AppLinks {
    static let feedbackEmail = "music.player.250617@gmail.com"
    static let feedbackSubject = "AltiPin Feedback"

    static let privacyPolicyURL = URL(string: "http://www.compass.sryze.cc/privacy/?lang=en")!
    static let termsOfUseURL = URL(string: "http://www.compass.sryze.cc/terms/?lang=en")!
    static let websiteURL = URL(string: "https://compass.sryze.cc")!

    static let appStoreURL = URL(string: "https://apps.apple.com/app/id6780429432")!
    static let appStoreReviewURL = URL(string: "https://apps.apple.com/app/id6780429432?action=write-review")!

    /// 后续接入 StoreKit Paywall 时改为 true
    static let showProUpgrade = false

    static var appVersionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }

    static var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "—"
    }

    static var feedbackBodyTemplate: String {
        """
        
        
        ---
        App: AltiPin \(appVersionString)
        Device: \(deviceDescription)
        iOS: \(systemVersion)
        """
    }

    static var mailtoFallbackURL: URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = feedbackEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: feedbackSubject),
            URLQueryItem(name: "body", value: feedbackBodyTemplate),
        ]
        return components.url
    }

    private static var deviceDescription: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let identifier = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingUTF8: $0) ?? "Unknown"
            }
        }
        return identifier
    }

    private static var systemVersion: String {
        ProcessInfo.processInfo.operatingSystemVersionString
    }
}
