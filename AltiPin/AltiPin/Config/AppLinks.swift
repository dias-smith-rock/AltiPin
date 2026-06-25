//
//  AppLinks.swift
//  AltiPin
//

import Foundation

enum AppLinks {
    static let feedbackEmail = "support@altipin.app"
    static let feedbackSubject = "AltiPin Feedback"

    static let privacyPolicyURL = URL(string: "https://altipin.app/privacy")!
    static let termsOfUseURL = URL(string: "https://altipin.app/terms")!
    static let websiteURL = URL(string: "https://altipin.app")!

    /// 上线前替换为真实 App Store ID
    static let appStoreReviewURL = URL(string: "https://apps.apple.com/app/id0000000000?action=write-review")!

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
