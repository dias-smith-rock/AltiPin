//
//  SupabaseClientProvider.swift
//  AltiPin
//

import Foundation
import Supabase

enum SupabaseClientProvider {
    static let shared: SupabaseClient? = makeClient()

    private static func makeClient() -> SupabaseClient? {
        TeamRelayLogger.logConfigDiagnostics()

        guard let url = TeamRelayConfiguration.supabaseURL,
              let key = TeamRelayConfiguration.supabaseAnonKey else {
            TeamRelayLogger.log("SupabaseClient 创建失败：project ref 或 anon key 缺失")
            return nil
        }

        let client = SupabaseClient(supabaseURL: url, supabaseKey: key)
        TeamRelayLogger.log("SupabaseClient 创建成功 url=\(url.host ?? "?")")
        return client
    }
}
