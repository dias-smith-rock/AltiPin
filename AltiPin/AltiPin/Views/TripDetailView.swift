//
//  TripDetailView.swift
//  AltiPin
//

import CoreLocation
import MapKit
import SwiftData
import SwiftUI

struct TripDetailView: View {
    let trip: TripEntity

    @Environment(\.modelContext) private var modelContext
    @State private var trackPoints: [HistoryPoint] = []
    @State private var cameraPosition: MapCameraPosition = .automatic

    private var tripStore: TripRecordStore {
        TripRecordStore(modelContext: modelContext)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                statsSection

                if trackPoints.isEmpty {
                    ContentUnavailableView(
                        "No Track Data",
                        systemImage: "map",
                        description: Text("Could not load GPS track for this record.")
                    )
                    .frame(height: 280)
                } else {
                    mapSection
                }
            }
            .padding(.bottom, 24)
        }
        .navigationTitle(trip.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            trackPoints = tripStore.loadTrackPoints(for: trip)
            updateCamera()
        }
    }

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 16) {
                statItem(title: L10n.t("Distance"), value: formatDistance(trip.totalDistance))
                statItem(title: L10n.t("Ascent"), value: String(format: "%.0f m", trip.totalAscent))
                statItem(title: L10n.t("Highest"), value: String(format: "%.0f m", trip.maxElevation))
            }

            Text("\(formatDateTime(trip.startTime)) — \(formatDateTime(trip.endTime))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var mapSection: some View {
        Map(position: $cameraPosition) {
            MapPolyline(coordinates: trackPoints.map(\.coordinate))
                .stroke(AltitudeTheme.accent, lineWidth: 4)

            if let start = trackPoints.first {
                Annotation(L10n.t("Start Point"), coordinate: start.coordinate, anchor: .center) {
                    Image(systemName: "play.circle.fill")
                        .font(.title3)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, AltitudeTheme.accent)
                }
            }

            if let end = trackPoints.last {
                Annotation(L10n.t("End Point"), coordinate: end.coordinate, anchor: .center) {
                    Image(systemName: "flag.checkered.circle.fill")
                        .font(.title3)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(AltitudeTheme.accent, .white.opacity(0.9))
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic, emphasis: .muted))
        .mapControlVisibility(.hidden)
        .frame(height: 360)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 12)
    }

    private func statItem(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func formatDistance(_ meters: Double) -> String {
        if meters >= 1000 {
            return String(format: "%.1f km", meters / 1000)
        }
        return String(format: "%.0f m", meters)
    }

    private func formatDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = L10n.activeLocale
        formatter.setLocalizedDateFormatFromTemplate("MMMdHHmm")
        return formatter.string(from: date)
    }

    private func updateCamera() {
        let coordinates = trackPoints.map(\.coordinate)
        guard !coordinates.isEmpty else { return }

        if coordinates.count == 1, let only = coordinates.first {
            cameraPosition = .region(
                MKCoordinateRegion(
                    center: only,
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                )
            )
            return
        }

        var minLat = coordinates[0].latitude
        var maxLat = coordinates[0].latitude
        var minLon = coordinates[0].longitude
        var maxLon = coordinates[0].longitude

        for coordinate in coordinates {
            minLat = min(minLat, coordinate.latitude)
            maxLat = max(maxLat, coordinate.latitude)
            minLon = min(minLon, coordinate.longitude)
            maxLon = max(maxLon, coordinate.longitude)
        }

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.4, 0.005),
            longitudeDelta: max((maxLon - minLon) * 1.4, 0.005)
        )
        cameraPosition = .region(MKCoordinateRegion(center: center, span: span))
    }
}
