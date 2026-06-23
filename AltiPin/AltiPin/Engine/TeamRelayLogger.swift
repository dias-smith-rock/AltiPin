//
//  TeamRelayLogger.swift
//  AltiPin
//

import Foundation

enum TeamRelayLogger {
    private static let prefix = "[TeamRelay]"
    private static var throttledLogTimes: [String: Date] = [:]

    static func log(_ message: String, file: String = #fileID, line: Int = #line) {
        #if DEBUG
        print("\(prefix) \(message) (\(file):\(line))")
        #endif
    }

    static func session(_ message: String, file: String = #fileID, line: Int = #line) {
        log("[Session] \(message)", file: file, line: line)
    }

    static func presence(_ message: String, file: String = #fileID, line: Int = #line) {
        log("[Presence] \(message)", file: file, line: line)
    }

    static func location(
        _ message: String,
        throttleKey: String? = nil,
        throttleSeconds: TimeInterval = 5,
        file: String = #fileID,
        line: Int = #line
    ) {
        if let throttleKey,
           shouldThrottle(key: throttleKey, interval: throttleSeconds) {
            return
        }
        log("[Location] \(message)", file: file, line: line)
    }

    static func ui(_ message: String, file: String = #fileID, line: Int = #line) {
        log("[UI] \(message)", file: file, line: line)
    }

    static func relay(_ message: String, file: String = #fileID, line: Int = #line) {
        log("[Relay] \(message)", file: file, line: line)
    }

    static func formatCoordinate(lat: Double, lon: Double, ele: Double? = nil) -> String {
        if let ele {
            return String(format: "lat=%.5f lon=%.5f ele=%.1fm", lat, lon, ele)
        }
        return String(format: "lat=%.5f lon=%.5f", lat, lon)
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

        relay("─── Supabase 配置诊断 ───")
        relay("isSupabaseConfigured=\(configured)")
        relay("SUPABASE_PROJECT_REF(raw)=\(rawRef ?? "nil"), parsed=\(projectRef)")
        relay("SUPABASE_URL(parsed)=\(parsedURL), host=\(parsedHost)")
        relay("SUPABASE_ANON_KEY=\(keyPrefix), jwt.ref=\(jwtRef)")
        if projectRef != "nil", jwtRef != "unknown", projectRef != jwtRef {
            relay("⚠️ PROJECT_REF 与 JWT ref 不一致：ref=\(projectRef), jwt.ref=\(jwtRef)")
        }
        relay("────────────────────────")
        #endif
    }

    private static func shouldThrottle(key: String, interval: TimeInterval) -> Bool {
        let now = Date()
        if let last = throttledLogTimes[key], now.timeIntervalSince(last) < interval {
            return true
        }
        throttledLogTimes[key] = now
        return false
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
