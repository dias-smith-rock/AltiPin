//
//  MailComposeView.swift
//  AltiPin
//

import MessageUI
import SwiftUI

struct MailComposeView: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss

    let recipients: [String]
    let subject: String
    let body: String

    static var canSendMail: Bool {
        MFMailComposeViewController.canSendMail()
    }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setToRecipients(recipients)
        controller.setSubject(subject)
        controller.setMessageBody(body, isHTML: false)
        return controller
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(dismiss: dismiss)
    }

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        private let dismiss: DismissAction

        init(dismiss: DismissAction) {
            self.dismiss = dismiss
        }

        func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult,
            error: Error?
        ) {
            dismiss()
        }
    }
}

enum FeedbackMailPresenter {
    @MainActor
    static func open(from openURL: OpenURLAction) -> Bool {
        if MailComposeView.canSendMail {
            return false
        }
        guard let url = AppLinks.mailtoFallbackURL else { return false }
        openURL(url)
        return true
    }
}
