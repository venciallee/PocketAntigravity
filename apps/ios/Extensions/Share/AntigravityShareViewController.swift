import Foundation
import SwiftUI
import AntigravityData
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif
#if canImport(UIKit)
import UIKit
#endif

/// Credential-free Share Extension (`AntigravityShare`) that writes shared URLs, screenshots,
/// or stack traces into `SharedAppGroupBridge` and wakes the main app via `antigravity://share/<id>`.
public struct AntigravityShareSheetView: View {
    public var sharedText: String
    public var sharedURLString: String?
    public var sharedFileName: String?
    public var targetHostName: String
    public var targetWorkspaceName: String
    public var onSend: () -> Void
    public var onCancel: () -> Void

    public init(
        sharedText: String,
        sharedURLString: String? = nil,
        sharedFileName: String? = nil,
        targetHostName: String = "MacBook Pro",
        targetWorkspaceName: String = "ledger-svc",
        onSend: @escaping () -> Void = {},
        onCancel: @escaping () -> Void = {}
    ) {
        self.sharedText = sharedText
        self.sharedURLString = sharedURLString
        self.sharedFileName = sharedFileName
        self.targetHostName = targetHostName
        self.targetWorkspaceName = targetWorkspaceName
        self.onSend = onSend
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Send to AG Pocket")
                    .font(AntigravityTheme.TypographyTier.evidence.font)
                    .foregroundStyle(AntigravityTheme.inkReading)
                Spacer()
                Text("\(targetWorkspaceName) · \(targetHostName)")
                    .font(AntigravityTheme.TypographyTier.metadata.font)
                    .foregroundStyle(AntigravityTheme.inkSecondary)
            }

            if let urlStr = sharedURLString, !urlStr.isEmpty {
                Label(urlStr, systemImage: "link")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(AntigravityTheme.accentPeriwinkle)
                    .lineLimit(2)
            }

            if let fname = sharedFileName, !fname.isEmpty {
                Label(fname, systemImage: "doc.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AntigravityTheme.inkLabel)
            }

            Text(sharedText.isEmpty ? "Shared attachment ready for Antigravity composer." : sharedText)
                .font(AntigravityTheme.TypographyTier.reading.font)
                .foregroundStyle(AntigravityTheme.inkLabel)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AntigravityTheme.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            HStack(spacing: 12) {
                Button("Cancel", action: onCancel)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AntigravityTheme.inkSecondary)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(AntigravityTheme.surfaceCard, in: RoundedRectangle(cornerRadius: 14))

                Button("Open in AG Pocket", action: onSend)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AntigravityTheme.inkOnPrimaryCTA)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(AntigravityTheme.accentPeriwinkle, in: RoundedRectangle(cornerRadius: 14))
            }
        }
        .padding(20)
        .background(AntigravityTheme.canvasObsidian)
    }
}

#if canImport(UIKit)
public final class AntigravityShareExtensionViewController: UIViewController {
    private var extractedText: String = ""
    private var extractedURL: String? = nil
    private var extractedFileName: String? = nil
    private var hostingController: UIHostingController<AntigravityShareSheetView>?

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AntigravityTheme.canvasObsidianUIColor
        mountSheetView()
        extractSharedItemsFromContext()
    }

    private func mountSheetView() {
        let root = AntigravityShareSheetView(
            sharedText: extractedText,
            sharedURLString: extractedURL,
            sharedFileName: extractedFileName,
            onSend: { [weak self] in
                self?.persistAndWakeMainApp()
            },
            onCancel: { [weak self] in
                self?.extensionContext?.completeRequest(returningItems: nil)
            }
        )
        if let hostingController {
            hostingController.rootView = root
        } else {
            let host = UIHostingController(rootView: root)
            host.view.backgroundColor = .clear
            addChild(host)
            host.view.frame = view.bounds
            host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(host.view)
            host.didMove(toParent: self)
            self.hostingController = host
        }
    }

    private func extractSharedItemsFromContext() {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else { return }
        for item in items {
            if let attr = item.attributedContentText?.string, !attr.isEmpty, extractedText.isEmpty {
                extractedText = attr
            }
            for provider in item.attachments ?? [] {
                #if canImport(UniformTypeIdentifiers)
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { [weak self] data, _ in
                        let urlStr = (data as? URL)?.absoluteString ?? (data as? String)
                        Task { @MainActor [weak self] in
                            guard let self, let urlStr else { return }
                            self.extractedURL = urlStr
                            self.mountSheetView()
                        }
                    }
                } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { [weak self] data, _ in
                        let text = data as? String
                        Task { @MainActor [weak self] in
                            guard let self, let text else { return }
                            self.extractedText = text
                            self.mountSheetView()
                        }
                    }
                } else if provider.hasItemConformingToTypeIdentifier(UTType.item.identifier) {
                    provider.loadItem(forTypeIdentifier: UTType.item.identifier, options: nil) { [weak self] data, _ in
                        let fname = (data as? URL)?.lastPathComponent
                        Task { @MainActor [weak self] in
                            guard let self, let fname else { return }
                            self.extractedFileName = fname
                            self.mountSheetView()
                        }
                    }
                }
                #endif
            }
        }
        mountSheetView()
    }

    private func persistAndWakeMainApp() {
        let payload = PendingSharePayload(
            text: extractedText,
            urlString: extractedURL,
            fileName: extractedFileName
        )
        Task { @MainActor [weak self] in
            await SharedAppGroupBridge.shared.saveSharePayload(payload)
            if let url = URL(string: "antigravity://share/\(payload.id)") {
                self?.extensionContext?.open(url) { _ in
                    Task { @MainActor [weak self] in
                        self?.extensionContext?.completeRequest(returningItems: nil)
                    }
                }
            } else {
                self?.extensionContext?.completeRequest(returningItems: nil)
            }
        }
    }
}
#endif
