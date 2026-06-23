//
//  GeoStampOverlayView.swift
//  AltiPin
//

import SwiftUI

struct GeoStampOverlayView: View {
    let metadata: GeoStampMetadata

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(metadata.overlayLines.enumerated()), id: \.offset) { index, line in
                Text(line)
                    .font(.system(size: 12, weight: index == 0 ? .semibold : .regular, design: .monospaced))
                    .foregroundStyle(index == 0 ? AltitudeTheme.accent : .white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.55))
    }
}
