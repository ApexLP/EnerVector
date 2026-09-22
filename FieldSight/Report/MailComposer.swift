import MessageUI
import PDFKit
import SwiftUI

struct MailAttachment {
    var data: Data
    var mimeType: String
    var fileName: String
}

/// Wraps MFMailComposeViewController. Check `MailComposeView.canSend` first — fall back to the share sheet otherwise.
struct MailComposeView: UIViewControllerRepresentable {
    static var canSend: Bool { MFMailComposeViewController.canSendMail() }

    var subject: String
    var recipients: [String]
    var body: String
    var attachments: [MailAttachment]
    var onFinish: (MFMailComposeResult) -> Void

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.mailComposeDelegate = context.coordinator
        vc.setSubject(subject)
        vc.setToRecipients(recipients.filter { !$0.isEmpty })
        vc.setMessageBody(body, isHTML: false)
        for a in attachments { vc.addAttachmentData(a.data, mimeType: a.mimeType, fileName: a.fileName) }
        return vc
    }

    func updateUIViewController(_ vc: MFMailComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let onFinish: (MFMailComposeResult) -> Void
        init(onFinish: @escaping (MFMailComposeResult) -> Void) { self.onFinish = onFinish }

        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            onFinish(result)
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    var items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

struct PDFKitView: UIViewRepresentable {
    let data: Data

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.backgroundColor = .secondarySystemBackground
        view.document = PDFDocument(data: data)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        guard context.coordinator.data != data else { return }
        context.coordinator.data = data
        view.document = PDFDocument(data: data)
    }

    func makeCoordinator() -> Coordinator { Coordinator(data: data) }

    final class Coordinator {
        var data: Data
        init(data: Data) { self.data = data }
    }
}
