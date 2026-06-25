//
//  HistoryToggleMapView.swift
//  AltiPin
//

import CoreLocation
import MapKit
import SwiftUI

struct HistoryToggleMapView: View {
    var recentPoints: [HistoryPoint]

    @State private var cameraPosition: MapCameraPosition = .automatic

    private var displayPoints: [HistoryPoint] {
        if !recentPoints.isEmpty {
            return Array(recentPoints.suffix(20))
        }
        #if DEBUG
        #if targetEnvironment(simulator)
        return HistoryPoint.mockPoints
        #else
        return []
        #endif
        #else
        return []
        #endif
    }

    var body: some View {
        Group {
            if displayPoints.isEmpty {
                emptyPlaceholder
            } else {
                horizontalMapView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .onAppear {
            updateCameraPosition()
        }
        .onChange(of: displayPoints) { _, _ in
            updateCameraPosition()
        }
    }

    // MARK: - Map

    private var horizontalMapView: some View {
        Map(position: $cameraPosition) {
            MapPolyline(coordinates: displayPoints.map(\.coordinate))
                .stroke(AltitudeTheme.accent, lineWidth: 4)

            if let start = displayPoints.first {
                Annotation(L10n.t("Start Point"), coordinate: start.coordinate, anchor: .center) {
                    Image(systemName: "play.circle.fill")
                        .font(.title3)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, AltitudeTheme.accent)
                        .shadow(color: .black.opacity(0.45), radius: 3, y: 1)
                }
            }

            if let end = displayPoints.last {
                Annotation("当前位置", coordinate: end.coordinate, anchor: .center) {
                    Image(systemName: "location.north.flash.fill")
                        .font(.title3)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(AltitudeTheme.accent, .white.opacity(0.9))
                        .shadow(color: .black.opacity(0.45), radius: 3, y: 1)
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic, emphasis: .muted))
        .mapControlVisibility(.hidden)
    }

    // MARK: - Empty State

    private var emptyPlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "map")
                .font(.title2)
                .foregroundStyle(.white.opacity(0.35))
            Text("No Track Data")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.45))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }

    // MARK: - Camera

    private func updateCameraPosition() {
        guard !displayPoints.isEmpty else { return }
        cameraPosition = Self.cameraPosition(for: displayPoints.map(\.coordinate))
    }

    private static func cameraPosition(for coordinates: [CLLocationCoordinate2D]) -> MapCameraPosition {
        guard !coordinates.isEmpty else { return .automatic }

        if coordinates.count == 1, let coordinate = coordinates.first {
            return .region(
                MKCoordinateRegion(
                    center: coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.004, longitudeDelta: 0.004)
                )
            )
        }

        var rect = MKMapRect.null
        for coordinate in coordinates {
            let point = MKMapPoint(coordinate)
            let pointRect = MKMapRect(x: point.x, y: point.y, width: 1, height: 1)
            rect = rect.union(pointRect)
        }

        let paddingFactor = 0.35
        let paddedRect = rect.insetBy(
            dx: -rect.size.width * paddingFactor,
            dy: -rect.size.height * paddingFactor
        )
        return .rect(paddedRect)
    }
}

// MARK: - Previews

#Preview("With Data") {
    ZStack {
        Color.black.ignoresSafeArea()
        HistoryToggleMapView(recentPoints: HistoryPoint.mockPoints)
    }
}

#Preview("Simulator Mock") {
    ZStack {
        Color.black.ignoresSafeArea()
        HistoryToggleMapView(recentPoints: [])
    }
}
