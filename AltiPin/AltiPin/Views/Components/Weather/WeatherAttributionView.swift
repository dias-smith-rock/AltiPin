//
//  WeatherAttributionView.swift
//  TopoLog
//

import SwiftUI
import WeatherKit

struct WeatherAttributionView: View {
    let attribution: WeatherAttribution
    var dataSource: WeatherDataSource = .weatherKit
    var markHeight: CGFloat = 18
    var alignment: HorizontalAlignment = .leading

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if dataSource == .weatherKit {
            VStack(alignment: alignment, spacing: 4) {
                AsyncImage(url: markURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(height: markHeight)
                    case .failure:
                        Text(attribution.serviceName)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.white.opacity(0.7))
                    default:
                        ProgressView()
                            .controlSize(.mini)
                            .tint(.white.opacity(0.5))
                    }
                }
                .accessibilityLabel(attribution.serviceName)

                Link(destination: attribution.legalPageURL) {
                    Text(L10n.t("Weather Data Sources"))
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.55))
                        .underline()
                }
            }
            .frame(maxWidth: .infinity, alignment: frameAlignment)
        }
    }

    private var markURL: URL {
        colorScheme == .dark
            ? attribution.combinedMarkDarkURL
            : attribution.combinedMarkLightURL
    }

    private var frameAlignment: Alignment {
        switch alignment {
        case .center: .center
        case .trailing: .trailing
        default: .leading
        }
    }
}

struct WeatherAttributionServiceView: View {
    @ObservedObject var weatherService: CompassWeatherService
    var markHeight: CGFloat = 18
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        if weatherService.usesAppleWeatherData,
           let attribution = weatherService.attribution {
            WeatherAttributionView(
                attribution: attribution,
                dataSource: weatherService.dataSource,
                markHeight: markHeight,
                alignment: alignment
            )
        }
    }
}
