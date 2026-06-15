//
//  CompassTabView.swift
//  AltiPin
//

import SwiftUI

struct CompassTabView: View {
    @ObservedObject var store: OutdoorDashboardStore
    @State private var heading: Double = 0

    var body: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 16)

            Text("\(store.compassDirectionName) \(Int(heading.rounded()))°")
                .font(.system(.largeTitle, design: .monospaced))
                .fontWeight(.semibold)
                .foregroundStyle(.white)

            CompassDialView(heading: heading, directionName: store.compassDirectionName)
                .padding(.top, 8)

            Spacer(minLength: 24)
        }
        .oledTabBackground()
        .onAppear {
            heading = store.heading
        }
        .onChange(of: store.heading) { _, newValue in
            withAnimation(.interactiveSpring(response: 0.32, dampingFraction: 0.86)) {
                heading = newValue
            }
        }
    }
}

#Preview {
    CompassTabView(store: OutdoorDashboardStore.preview())
}
