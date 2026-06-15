//
//  OLEDTabBackground.swift
//  AltiPin
//

import SwiftUI

struct OLEDTabBackground: ViewModifier {
    func body(content: Content) -> some View {
        ZStack {
            Color.black.ignoresSafeArea()
            content
        }
        .preferredColorScheme(.dark)
    }
}

extension View {
    func oledTabBackground() -> some View {
        modifier(OLEDTabBackground())
    }
}
