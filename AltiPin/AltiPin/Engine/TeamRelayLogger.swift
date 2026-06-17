//
//  TeamRelayLogger.swift
//  AltiPin
//

import Foundation

enum TeamRelayLogger {
    private static let prefix = "[TeamRelay]"

    static func log(_ message: String, file: String = #fileID, line: Int = #line) {
        #if DEBUG
        print("\(prefix) \(message) (\(file):\(line))")
        #endif
    }

    static func logConfigDiagnostics() {
        #if DEBUG
        let rawRef = configSourceValue(for: "SUPABASE_PROJECT_REF")
        let rawKey = configSourceValue(for: "SUPABASE_ANON_KEY")
        let parsedURL = TeamRelayConfiguration.supabaseURL?.absoluteString ?? "nil"
        let parsedHost = TeamRelayConfiguration.supabaseURL?.host ?? "nil"
        let projectRef = TeamRelayConfiguration.projectRef ?? "nil"
        let keyPrefix = rawKey.map { redactKey($0) } ?? "nil"
        let jwtRef = rawKey.flatMap { jwtProjectRef($0) } ?? "unknown"
        let configured = TeamRelayConfiguration.isSupabaseConfigured

        log("─── Supabase 配置诊断 ───")
        log("isSupabaseConfigured=\(configured)")
        log("SUPABASE_PROJECT_REF(raw)=\(rawRef ?? "nil"), parsed=\(projectRef)")
        log("SUPABASE_URL(parsed)=\(parsedURL), host=\(parsedHost)")
        log("SUPABASE_ANON_KEY=\(keyPrefix), jwt.ref=\(jwtRef)")
        if projectRef != "nil", jwtRef != "unknown", projectRef != jwtRef {
            log("⚠️ PROJECT_REF 与 JWT ref 不一致：ref=\(projectRef), jwt.ref=\(jwtRef)")
        }
        log("────────────────────────")
        #endif
    }

    private static func configSourceValue(for key: String) -> String? {
        if let env = ProcessInfo.processInfo.environment[key], !env.isEmpty {
            return env
        }
        return Bundle.main.object(forInfoDictionaryKey: key) as? String
    }

    private static func redactKey(_ key: String) -> String {
        let trimmed = key.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        guard trimmed.count > 12 else { return "***" }
        let start = trimmed.prefix(8)
        let end = trimmed.suffix(4)
        return "\(start)...\(end) (len=\(trimmed.count))"
    }

    private static func jwtProjectRef(_ key: String) -> String? {
        let trimmed = key.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        let parts = trimmed.split(separator: ".")
        guard parts.count >= 2 else { return nil }

        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = (4 - payload.count % 4) % 4
        payload += String(repeating: "=", count: padding)

        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ref = json["ref"] as? String else {
            return nil
        }
        return ref
    }
}
