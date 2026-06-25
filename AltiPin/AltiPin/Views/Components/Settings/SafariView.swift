//
//  SafariView.swift
//  AltiPin
//

import SafariServices
import SwiftUI

struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.preferredControlTintColor = UIColor(AltitudeTheme.accent)
        return controller
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

struct SafariLinkSheet: Identifiable {
    let id = UUID()
    let url: URL
    let title: String
}
