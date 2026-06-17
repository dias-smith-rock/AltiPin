//
//  SupabaseClientProvider.swift
//  AltiPin
//

import Foundation
import Supabase

enum SupabaseClientProvider {
    static let shared: SupabaseClient? = makeClient()

    private static func makeClient() -> SupabaseClient? {
        guard let url = TeamRelayConfiguration.supabaseURL,
              let key = TeamRelayConfiguration.supabaseAnonKey else {
            return nil
        }

        return SupabaseClient(supabaseURL: url, supabaseKey: key)
    }
}
