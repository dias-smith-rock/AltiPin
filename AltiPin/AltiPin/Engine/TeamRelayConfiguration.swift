//
//  TeamRelayConfiguration.swift
//  AltiPin
//

import Foundation

enum TeamRelayConfiguration {
    static let broadcastEvent = "broadcast_update"
    static let sessionSyncEvent = "session_sync"
    static let hostTransferEvent = "host_transfer"
    static let locationUpdateInterval: TimeInterval = 4
    static let metricsUpdateInterval: TimeInterval = 1

    static var isSupabaseConfigured: Bool {
        supabaseURL != nil && supabaseAnonKey != nil
    }

    static var supabaseURL: URL? {
        guard let ref = projectRef, !ref.isEmpty else { return nil }
        return URL(string: "https://\(ref).supabase.co")
    }

    static var supabaseAnonKey: String? {
        guard let key = resolvedSupabaseAnonKey, !key.isEmpty else {
            return nil
        }
        return key
    }

    static var projectRef: String? {
        if let ref = resolvedProjectRef, !ref.isEmpty {
            return ref
        }

        // 兼容旧版直接注入完整 URL 的配置
        if let urlString = legacyURLString,
           let host = URL(string: urlString)?.host,
           host.hasSuffix(".supabase.co") {
            return host.replacingOccurrences(of: ".supabase.co", with: "")
        }

        return nil
    }

    static func channelTopic(roomID: String) -> String {
        "team:\(roomID)"
    }

    private static var resolvedProjectRef: String? {
        sanitizedConfigValue(for: "SUPABASE_PROJECT_REF")
    }

    private static var resolvedSupabaseAnonKey: String? {
        sanitizedConfigValue(for: "SUPABASE_ANON_KEY")
    }

    private static var legacyURLString: String? {
        sanitizedConfigValue(for: "SUPABASE_URL")
    }

    private static func sanitizedConfigValue(for key: String) -> String? {
        if let env = ProcessInfo.processInfo.environment[key], !env.isEmpty {
            return clean(env)
        }
        if let plist = Bundle.main.object(forInfoDictionaryKey: key) as? String, !plist.isEmpty {
            return clean(plist)
        }
        return nil
    }

    private static func clean(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    }
}
