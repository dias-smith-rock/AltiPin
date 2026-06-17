//
//  TeamRelayConfiguration.swift
//  AltiPin
//

import Foundation

enum TeamRelayConfiguration {
    static let broadcastEvent = "broadcast_update"
    static let locationUpdateInterval: TimeInterval = 4

    static var useMockRelay: Bool {
        if ProcessInfo.processInfo.environment["USE_MOCK_TEAM_RELAY"] == "1" {
            return true
        }

        #if DEBUG
        if !isSupabaseConfigured {
            return true
        }
        #else
        if !isSupabaseConfigured {
            return false
        }
        #endif

        return false
    }

    static var isSupabaseConfigured: Bool {
        guard let urlString = supabaseURLString,
              let key = supabaseAnonKey,
              !urlString.isEmpty,
              !key.isEmpty,
              URL(string: urlString) != nil else {
            return false
        }
        return true
    }

    static var supabaseURL: URL? {
        guard let urlString = supabaseURLString,
              let url = URL(string: urlString),
              !urlString.isEmpty else {
            return nil
        }
        return url
    }

    static var supabaseAnonKey: String? {
        guard let key = resolvedSupabaseAnonKey, !key.isEmpty else {
            return nil
        }
        return key
    }

    static func channelTopic(roomID: String) -> String {
        "team:\(roomID)"
    }

    private static var supabaseURLString: String? {
        if let env = ProcessInfo.processInfo.environment["SUPABASE_URL"], !env.isEmpty {
            return env
        }
        return Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String
    }

    private static var resolvedSupabaseAnonKey: String? {
        if let env = ProcessInfo.processInfo.environment["SUPABASE_ANON_KEY"], !env.isEmpty {
            return env
        }
        return Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String
    }
}
