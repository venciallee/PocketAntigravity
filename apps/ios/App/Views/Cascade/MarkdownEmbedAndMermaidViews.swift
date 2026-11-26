import SwiftUI
import AntigravityData
#if canImport(UIKit)
import UIKit
#endif
#if canImport(WebKit)
import WebKit
#endif

// MARK: - Antigravity `<agent-embed>` Interactive Widget Card & Sandboxed WKWebView

internal struct MarkdownAgentEmbedCardView: View {
    let src: String
    let explicitTitle: String?
    let kind: MarkdownEmbedKind
    let isStreamingIncomplete: Bool
    let store: AntigravitySessionStore?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.appLanguage) private var lang
    @State private var resolved: ResolvedEmbedResource? = nil
    @State private var isLoading: Bool = false
    @State private var webViewHeight: CGFloat = 260
    @State private var showFullScreenSheet: Bool = false
    @State private var showSourceCode: Bool = false
    @State private var didCopyPath: Bool = false

    private var displayTitle: String {
        AntigravityMarkdownParser.humanReadableEmbedTitle(src: src, explicitTitle: explicitTitle)
    }

    private var shortFilename: String {
        MarkdownLinkFormatting.shortFileBadge(src)
    }

    private var isDarkMode: Bool {
        colorScheme == .dark
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Card Header
            HStack(spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(AntigravityTheme.accentPeriwinkle.opacity(0.14))
                        .frame(width: 30, height: 30)
                    Image(systemName: kind.semanticIcon.sfSymbolName)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(AntigravityTheme.accentPeriwinkle)
                }

                VStack(alignment: .leading, spacing: 1.5) {
                    Text(displayTitle)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(AntigravityTheme.inkReading)
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        Text(kind.displayBadge)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(AntigravityTheme.accentPeriwinkle)
                        if !shortFilename.isEmpty {
                            Text("· \(shortFilename)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(AntigravityTheme.inkSecondary)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer(minLength: 4)

                if resolved?.textContent != nil && (resolved?.isHTML == true || resolved?.isSVG == true) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.16)) {
                            showSourceCode.toggle()
                        }
                    } label: {
                        Image(systemName: showSourceCode ? "eye" : "chevron.left.forwardslash.chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AntigravityTheme.inkLabel)
                            .frame(width: 30, height: 30)
                            .background(AntigravityTheme.surfaceElevated)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }

                if canPresentInteractivePreview {
                    Button {
                        showFullScreenSheet = true
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AntigravityTheme.accentPeriwinkle)
                            .frame(width: 30, height: 30)
                            .background(AntigravityTheme.accentPeriwinkle.opacity(0.14))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(AntigravityTheme.surfaceSubtleBox)

            Rectangle()
                .fill(AntigravityTheme.subtleDivider)
                .frame(height: 1)

            // Body Content
            if isStreamingIncomplete {
                HStack(spacing: 10) {
                    AntigravityFourDotLoadingView(isAnimated: true, dotSize: 4.0, spacing: 3.0, tint: AntigravityTheme.accentPeriwinkle)
                    Text(lang.t("Streaming interactive embed…", "正在流式接收交互式组件…"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AntigravityTheme.inkSecondary)
                    Spacer()
                }
                .padding(14)
            } else if isLoading {
                HStack(spacing: 10) {
                    ProgressView()
                        .tint(AntigravityTheme.accentPeriwinkle)
                        .scaleEffect(0.85)
                    Text(lang.t("Loading \(shortFilename.isEmpty ? "artifact" : shortFilename)…", "正在加载 \(shortFilename.isEmpty ? "产物" : shortFilename)…"))
                        .font(.system(size: 13))
                        .foregroundStyle(AntigravityTheme.inkSecondary)
                    Spacer()
                }
                .padding(14)
            } else if showSourceCode, let rawText = resolved?.textContent {
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(String(rawText.prefix(6000)))
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(AntigravityTheme.inkLabel)
                        .padding(12)
                }
                .frame(maxHeight: 280)
                .background(AntigravityTheme.surfaceCodeBlock)
            } else if let res = resolved, res.isHTML || res.isSVG, let htmlText = res.textContent {
                #if canImport(WebKit) && canImport(UIKit)
                let documentHTML = res.isSVG
                    ? AntigravityEmbedHTMLWrapper.wrapSVG(htmlText, isDarkMode: isDarkMode)
                    : AntigravityEmbedHTMLWrapper.wrapHTML(htmlText, isDarkMode: isDarkMode)
                SandboxedHTMLWidgetWebView(
                    htmlContent: documentHTML,
                    remoteURL: nil,
                    allowInternalScroll: false,
                    isDarkMode: isDarkMode,
                    measuredHeight: $webViewHeight
                )
                .frame(height: min(500, max(160, webViewHeight)))
                .background(AntigravityTheme.canvasObsidian)
                #else
                unavailableEmbedFooter(reason: lang.t("Interactive HTML preview is available on iOS.", "交互式 HTML 预览仅在 iOS 上可用。"))
                #endif
            } else if let res = resolved, res.source == .directNetwork, let url = URL(string: res.uri) {
                #if canImport(WebKit) && canImport(UIKit)
                SandboxedHTMLWidgetWebView(
                    htmlContent: nil,
                    remoteURL: url,
                    allowInternalScroll: false,
                    isDarkMode: isDarkMode,
                    measuredHeight: $webViewHeight
                )
                .frame(height: min(460, max(200, webViewHeight)))
                .background(AntigravityTheme.canvasObsidian)
                #else
                unavailableEmbedFooter(reason: res.uri)
                #endif
            } else if let res = resolved, res.isImage, let data = res.binaryData {
                #if canImport(UIKit)
                if let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 360)
                        .background(AntigravityTheme.surfaceCodeBlock)
                        .onTapGesture { showFullScreenSheet = true }
                } else {
                    unavailableEmbedFooter(reason: lang.t("Could not decode image data.", "无法解码图片数据。"))
                }
                #else
                unavailableEmbedFooter(reason: lang.t("Image preview is available on iOS.", "图片预览仅在 iOS 上可用。"))
                #endif
            } else if let res = resolved, let mdText = res.textContent, kind == .markdown {
                AntigravityMarkdownView(markdown: mdText, variant: .blockquote, store: store)
                    .padding(12)
            } else {
                unavailableEmbedFooter(reason: nil)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AntigravityTheme.surfaceCard)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AntigravityTheme.accentPeriwinkle.opacity(0.22), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .task(id: src) {
            guard !isStreamingIncomplete, !src.isEmpty else { return }
            await loadEmbedResource()
        }
        .sheet(isPresented: $showFullScreenSheet) {
            EmbedFullScreenModalView(
                title: displayTitle,
                src: src,
                resolved: resolved
            )
        }
    }

    private var canPresentInteractivePreview: Bool {
        guard let res = resolved else { return false }
        return (res.textContent != nil && (res.isHTML || res.isSVG))
            || res.source == .directNetwork
            || (res.isImage && res.binaryData != nil)
    }

    private func loadEmbedResource() async {
        if let cached = store?.cachedEmbedResource(for: src) {
            resolved = cached
            return
        }
        isLoading = true
        defer {
            isLoading = false
        }
        if let store {
            resolved = await store.resolveEmbedResource(uri: src)
        } else if src.lowercased().hasPrefix("data:") {
            resolved = ResolvedEmbedResource.decodeDataURI(src)
        } else if src.lowercased().hasPrefix("https://") || src.lowercased().hasPrefix("http://") {
            resolved = ResolvedEmbedResource(
                uri: src,
                mimeType: ResolvedEmbedResource.inferredMimeType(for: src),
                source: .directNetwork
            )
        }
    }

    @ViewBuilder
    private func unavailableEmbedFooter(reason: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(
                reason ?? (
                    src.lowercased().hasPrefix("file://")
                        ? lang.t(
                            "Host-local interactive artifact on your paired Mac. Tap Retry when Desktop or Companion Bridge is online, or copy the file path.",
                            "此交互产物位于已配对的 Mac 本地。请在桌面端或桥接服务在线时点击重试，或复制文件路径。"
                        )
                        : lang.t("Interactive embed preview unavailable.", "暂无法预览交互式嵌入内容。")
                )
            )
            .font(.system(size: 12.5))
            .foregroundStyle(AntigravityTheme.inkSecondary)
            .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                if store != nil {
                    Button {
                        Task { await loadEmbedResource() }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11, weight: .semibold))
                            Text(lang.t("Retry", "重试"))
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(AntigravityTheme.accentPeriwinkle)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background(AntigravityTheme.accentPeriwinkle.opacity(0.14))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    MarkdownClipboardHelper.copyText(MarkdownLinkFormatting.cleanDisplayPath(src))
                    withAnimation(.easeInOut(duration: 0.15)) {
                        didCopyPath = true
                    }
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(1.5))
                        withAnimation(.easeInOut(duration: 0.15)) {
                            didCopyPath = false
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: didCopyPath ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11, weight: .semibold))
                        Text(didCopyPath ? lang.t("Path Copied", "已复制路径") : lang.t("Copy Path", "复制路径"))
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(didCopyPath ? AntigravityTheme.statusDone : AntigravityTheme.inkLabel)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(AntigravityTheme.surfaceElevated)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Spacer()
            }
        }
        .padding(12)
    }
}

internal struct EmbedFullScreenModalView: View {
    let title: String
    let src: String
    let resolved: ResolvedEmbedResource?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.appLanguage) private var lang
    @State private var dummyHeight: CGFloat = 600

    private var isDarkMode: Bool {
        colorScheme == .dark
    }

    var body: some View {
        NavigationStack {
            Group {
                if let res = resolved, (res.isHTML || res.isSVG), let htmlText = res.textContent {
                    #if canImport(WebKit) && canImport(UIKit)
                    let doc = res.isSVG
                        ? AntigravityEmbedHTMLWrapper.wrapSVG(htmlText, isDarkMode: isDarkMode)
                        : AntigravityEmbedHTMLWrapper.wrapHTML(htmlText, isDarkMode: isDarkMode)
                    SandboxedHTMLWidgetWebView(
                        htmlContent: doc,
                        remoteURL: nil,
                        allowInternalScroll: true,
                        isDarkMode: isDarkMode,
                        measuredHeight: $dummyHeight
                    )
                    #else
                    Text(htmlText)
                    #endif
                } else if let res = resolved, res.source == .directNetwork, let url = URL(string: res.uri) {
                    #if canImport(WebKit) && canImport(UIKit)
                    SandboxedHTMLWidgetWebView(
                        htmlContent: nil,
                        remoteURL: url,
                        allowInternalScroll: true,
                        isDarkMode: isDarkMode,
                        measuredHeight: $dummyHeight
                    )
                    #else
                    Text(res.uri)
                    #endif
                } else if let res = resolved, res.isImage, let data = res.binaryData {
                    #if canImport(UIKit)
                    if let img = UIImage(data: data) {
                        ScrollView([.horizontal, .vertical]) {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFit()
                                .padding(12)
                        }
                    }
                    #endif
                } else {
                    Text(src)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(AntigravityTheme.inkSecondary)
                        .padding(16)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AntigravityTheme.canvasObsidian.ignoresSafeArea())
            .navigationTitle(title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(lang.t("Done", "完成")) { dismiss() }
                        .foregroundStyle(AntigravityTheme.accentPeriwinkle)
                }
            }
        }
    }
}

internal struct RemoteArtifactPreviewSheet: View {
    let uri: String
    let store: AntigravitySessionStore?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var lang

    var body: some View {
        NavigationStack {
            ScrollView {
                MarkdownAgentEmbedCardView(
                    src: uri,
                    explicitTitle: nil,
                    kind: MarkdownEmbedKind.detect(from: uri),
                    isStreamingIncomplete: false,
                    store: store
                )
                .padding(14)
            }
            .background(AntigravityTheme.canvasObsidian.ignoresSafeArea())
            .navigationTitle(AntigravityMarkdownParser.humanReadableEmbedTitle(src: uri))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(lang.t("Done", "完成")) { dismiss() }
                        .foregroundStyle(AntigravityTheme.accentPeriwinkle)
                }
            }
        }
    }
}

/// Injects adaptive Light/Dark Antigravity theme CSS variables, responsive mobile viewport meta,
/// and `ResizeObserver` height bridge into agent-generated HTML/SVG widgets.
internal enum AntigravityEmbedHTMLWrapper {
    private static let bridgeMarker = "data-agy-theme-bridge"

    private static func themeBridgeInjection(isDarkMode: Bool) -> String {
        let background = isDarkMode ? "#090A0D" : "#F4F5F8"
        let card = isDarkMode ? "#141519" : "#FFFFFF"
        let popover = isDarkMode ? "#1D1F26" : "#FFFFFF"
        let foreground = isDarkMode ? "#F5F6F8" : "#111318"
        let primary = isDarkMode ? "#8EB4FF" : "#2F66E8"
        let primaryForeground = isDarkMode ? "#0A0E17" : "#FFFFFF"
        let secondary = isDarkMode ? "#1D1F26" : "#E6E9F2"
        let secondaryForeground = isDarkMode ? "#DCE6FF" : "#1E46A8"
        let muted = isDarkMode ? "#1D1F26" : "#EEF0F6"
        let mutedForeground = isDarkMode ? "#8A909E" : "#5B6170"
        let destructive = isDarkMode ? "#F07167" : "#CF372E"
        let border = isDarkMode ? "rgba(255,255,255,0.10)" : "rgba(0,0,0,0.10)"
        let input = isDarkMode ? "rgba(255,255,255,0.12)" : "rgba(0,0,0,0.12)"
        let colorSchemeCSS = isDarkMode ? "dark" : "light"
        let mermaidTheme = isDarkMode ? "dark" : "default"

        return """
        <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=3.0">
        <style \(bridgeMarker)="\(colorSchemeCSS)">
          :root {
            --background: \(background);
            --card: \(card);
            --card-foreground: \(foreground);
            --popover: \(popover);
            --popover-foreground: \(foreground);
            --foreground: \(foreground);
            --primary: \(primary);
            --primary-foreground: \(primaryForeground);
            --secondary: \(secondary);
            --secondary-foreground: \(secondaryForeground);
            --muted: \(muted);
            --muted-foreground: \(mutedForeground);
            --accent: \(secondary);
            --accent-foreground: \(foreground);
            --destructive: \(destructive);
            --border: \(border);
            --input: \(input);
            --ring: \(primary);
            color-scheme: \(colorSchemeCSS);
          }
          html, body {
            margin: 0;
            padding: 0;
            background: var(--background);
            color: var(--foreground);
            font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
            max-width: 100%;
            overflow-x: auto;
            -webkit-text-size-adjust: 100%;
          }
          svg, img, canvas { max-width: 100%; height: auto; }
        </style>
        <script>
          window.__antigravityColorScheme = '\(colorSchemeCSS)';
          window.__antigravityMermaidTheme = '\(mermaidTheme)';
          (function() {
            function postHeight() {
              try {
                var h = Math.max(
                  document.documentElement ? document.documentElement.scrollHeight : 0,
                  document.body ? document.body.scrollHeight : 0
                );
                if (h > 0 && window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.embedHeight) {
                  window.webkit.messageHandlers.embedHeight.postMessage(h);
                }
              } catch (e) {}
            }
            window.addEventListener('load', postHeight);
            window.addEventListener('resize', postHeight);
            if (typeof ResizeObserver !== 'undefined') {
              var ro = new ResizeObserver(postHeight);
              document.addEventListener('DOMContentLoaded', function() {
                if (document.body) ro.observe(document.body);
                postHeight();
              });
            }
            setTimeout(postHeight, 120);
            setTimeout(postHeight, 450);
          })();
        </script>
        """
    }

    static func wrapHTML(_ rawHTML: String, isDarkMode: Bool = true) -> String {
        if rawHTML.contains(bridgeMarker) {
            return rawHTML
        }
        let injection = themeBridgeInjection(isDarkMode: isDarkMode)
        if let headRange = rawHTML.range(of: "<head>", options: .caseInsensitive) {
            var out = rawHTML
            out.insert(contentsOf: "\n" + injection + "\n", at: headRange.upperBound)
            return out
        }
        if rawHTML.lowercased().contains("<html") {
            return injection + "\n" + rawHTML
        }
        return """
        <!doctype html>
        <html>
        <head><meta charset="utf-8">\(injection)</head>
        <body>\(rawHTML)</body>
        </html>
        """
    }

    static func wrapSVG(_ rawSVG: String, isDarkMode: Bool = true) -> String {
        let injection = themeBridgeInjection(isDarkMode: isDarkMode)
        return """
        <!doctype html>
        <html>
        <head><meta charset="utf-8">\(injection)</head>
        <body style="display:flex;justify-content:center;align-items:center;padding:12px;box-sizing:border-box;">
          \(rawSVG)
        </body>
        </html>
        """
    }
}

#if canImport(WebKit) && canImport(UIKit)
internal struct SandboxedHTMLWidgetWebView: UIViewRepresentable {
    let htmlContent: String?
    let remoteURL: URL?
    let allowInternalScroll: Bool
    let isDarkMode: Bool
    @Binding var measuredHeight: CGFloat
    @Environment(\.openURL) private var openURL

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onHeightChange: { newHeight in
                if abs(measuredHeight - newHeight) > 2.0 {
                    measuredHeight = newHeight
                }
            },
            onExternalLink: { url in
                openURL(url)
            }
        )
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.allowsInlineMediaPlayback = true
        config.userContentController.add(context.coordinator, name: "embedHeight")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = AntigravityTheme.canvasObsidianUIColor
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = allowInternalScroll
        webView.scrollView.bounces = allowInternalScroll
        loadContent(into: webView, coordinator: context.coordinator)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        context.coordinator.onHeightChange = { newHeight in
            if abs(measuredHeight - newHeight) > 2.0 {
                measuredHeight = newHeight
            }
        }
        context.coordinator.onExternalLink = { url in
            openURL(url)
        }
        uiView.backgroundColor = AntigravityTheme.canvasObsidianUIColor
        uiView.scrollView.isScrollEnabled = allowInternalScroll
        loadContent(into: uiView, coordinator: context.coordinator)
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.navigationDelegate = nil
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "embedHeight")
    }

    private func loadContent(into webView: WKWebView, coordinator: Coordinator) {
        let signature = "\(isDarkMode)|\(htmlContent ?? "")|\(remoteURL?.absoluteString ?? "")"
        guard coordinator.lastLoadedSignature != signature else { return }
        coordinator.lastLoadedSignature = signature
        if let htmlContent {
            webView.loadHTMLString(htmlContent, baseURL: URL(string: "https://antigravity.local/"))
        } else if let remoteURL {
            webView.load(URLRequest(url: remoteURL))
        }
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var onHeightChange: @MainActor (CGFloat) -> Void
        var onExternalLink: @MainActor (URL) -> Void
        var lastLoadedSignature: String = ""

        init(
            onHeightChange: @escaping @MainActor (CGFloat) -> Void,
            onExternalLink: @escaping @MainActor (URL) -> Void
        ) {
            self.onHeightChange = onHeightChange
            self.onExternalLink = onExternalLink
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "embedHeight" else { return }
            if let num = message.body as? NSNumber {
                let h = CGFloat(num.doubleValue)
                if h.isFinite && h >= 40 && h <= 2400 {
                    let targetHeight = ceil(h) + 4
                    Task { @MainActor [weak self] in
                        self?.onHeightChange(targetHeight)
                    }
                }
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction
        ) async -> WKNavigationActionPolicy {
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url,
               let scheme = url.scheme?.lowercased(),
               (scheme == "https" || scheme == "http" || scheme == "mailto") {
                onExternalLink(url)
                return .cancel
            }
            return .allow
        }
    }
}
#endif

// MARK: - Offline Interactive Mermaid Diagram Card (` ```mermaid `)

internal struct MarkdownMermaidCardView: View {
    let source: String
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.appLanguage) private var lang
    @State private var showCode: Bool = false
    @State private var didCopy: Bool = false
    @State private var diagramHeight: CGFloat = 240
    @State private var showFullScreen: Bool = false

    private var isDarkMode: Bool {
        colorScheme == .dark
    }

    private var offlineDiagramHTML: String? {
        OfflineMermaidSVGRenderer.renderHTML(from: source, isDarkMode: isDarkMode)
    }

    var body: some View {
        let renderedHTML = offlineDiagramHTML
        let displayingCode = showCode || renderedHTML == nil

        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(AntigravityTheme.accentPeriwinkle)
                    Text("mermaid")
                        .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(AntigravityTheme.inkSecondary)
                }

                Spacer()

                if renderedHTML != nil {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            showCode.toggle()
                        }
                    } label: {
                        Text(showCode ? lang.t("Diagram", "图表") : lang.t("Code", "源码"))
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(AntigravityTheme.inkLabel)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(AntigravityTheme.surfaceElevated)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    Button {
                        showFullScreen = true
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(AntigravityTheme.accentPeriwinkle)
                            .padding(6)
                            .background(AntigravityTheme.accentPeriwinkle.opacity(0.12))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    MarkdownClipboardHelper.copyText(source)
                    withAnimation(.easeInOut(duration: 0.15)) { didCopy = true }
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(1.6))
                        withAnimation(.easeInOut(duration: 0.15)) { didCopy = false }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 10.5, weight: .semibold))
                        Text(didCopy ? lang.t("Copied", "已复制") : lang.t("Copy", "复制"))
                            .font(.system(size: 11.5, weight: .semibold))
                    }
                    .foregroundStyle(didCopy ? AntigravityTheme.statusDone : AntigravityTheme.accentPeriwinkle)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AntigravityTheme.surfaceElevated)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(AntigravityTheme.surfaceSubtleBox)

            Rectangle()
                .fill(AntigravityTheme.subtleDivider)
                .frame(height: 1)

            if displayingCode {
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(source.isEmpty ? " " : source)
                        .font(.system(size: 12.5, design: .monospaced))
                        .foregroundStyle(AntigravityTheme.inkReading)
                        .lineSpacing(2.5)
                        .textSelection(.enabled)
                        .padding(12)
                }
            } else if let html = renderedHTML {
                #if canImport(WebKit) && canImport(UIKit)
                SandboxedHTMLWidgetWebView(
                    htmlContent: html,
                    remoteURL: nil,
                    allowInternalScroll: false,
                    isDarkMode: isDarkMode,
                    measuredHeight: $diagramHeight
                )
                .frame(height: min(460, max(160, diagramHeight)))
                #else
                Text(source)
                    .font(.system(size: 12.5, design: .monospaced))
                    .padding(12)
                #endif
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AntigravityTheme.surfaceCodeBlock)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AntigravityTheme.glassHairline, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .sheet(isPresented: $showFullScreen) {
            if let html = renderedHTML {
                EmbedFullScreenModalView(
                    title: lang.t("Mermaid Diagram", "Mermaid 图表"),
                    src: "mermaid://diagram",
                    resolved: ResolvedEmbedResource(
                        uri: "mermaid://diagram",
                        mimeType: "text/html",
                        textContent: html,
                        source: .inlineDataURI
                    )
                )
            }
        }
    }
}

/// Zero-CDN offline SVG diagram generator for Mermaid `flowchart` / `graph` / `stateDiagram` / `sequenceDiagram`.
internal enum OfflineMermaidSVGRenderer {
    static func renderHTML(from rawSource: String, isDarkMode: Bool = true) -> String? {
        let lines = rawSource
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("%%") }

        guard let header = lines.first?.lowercased() else { return nil }
        if header.hasPrefix("flowchart") || header.hasPrefix("graph") {
            let isHorizontal = header.contains("lr") || header.contains("rl")
            return renderFlowchartSVG(lines: Array(lines.dropFirst()), isHorizontal: isHorizontal, isDarkMode: isDarkMode)
        }
        if header.hasPrefix("statediagram") {
            return renderFlowchartSVG(lines: Array(lines.dropFirst()), isHorizontal: false, isDarkMode: isDarkMode)
        }
        if header.hasPrefix("sequencediagram") {
            return renderSequenceSVG(lines: Array(lines.dropFirst()), isDarkMode: isDarkMode)
        }
        return nil
    }

    private static func escapeXML(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func parseNodeToken(_ raw: String) -> (id: String, label: String, shape: String) {
        let t = raw.trimmingCharacters(in: .whitespaces)
        let delimiters: [(open: String, close: String, shape: String)] = [
            ("([", "])", "pill"),
            ("((", "))", "circle"),
            ("[", "]", "rect"),
            ("(", ")", "round"),
            ("{", "}", "diamond"),
        ]
        for delim in delimiters {
            if let openRange = t.range(of: delim.open),
               t.hasSuffix(delim.close),
               openRange.lowerBound > t.startIndex {
                let id = String(t[..<openRange.lowerBound]).trimmingCharacters(in: .whitespaces)
                let labelRaw = String(t[openRange.upperBound..<t.index(t.endIndex, offsetBy: -delim.close.count)])
                let cleanLabel = labelRaw.trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
                return (id, cleanLabel.isEmpty ? id : cleanLabel, delim.shape)
            }
        }
        if t == "[*]" {
            return ("__start__", "●", "circle")
        }
        return (t, t, "rect")
    }

    private static func renderFlowchartSVG(lines: [String], isHorizontal: Bool, isDarkMode: Bool) -> String? {
        var nodeOrder: [String] = []
        var nodeLabels: [String: String] = [:]
        var nodeShapes: [String: String] = [:]
        var edges: [(from: String, to: String, label: String)] = []

        func registerNode(_ raw: String) -> String {
            let parsed = parseNodeToken(raw)
            if nodeLabels[parsed.id] == nil {
                nodeOrder.append(parsed.id)
                nodeLabels[parsed.id] = parsed.label
                nodeShapes[parsed.id] = parsed.shape
            } else if parsed.label != parsed.id {
                nodeLabels[parsed.id] = parsed.label
                nodeShapes[parsed.id] = parsed.shape
            }
            return parsed.id
        }

        let arrowTokens = ["-->", "-.->", "==>", "---", "->"]
        for line in lines {
            let lower = line.lowercased()
            if lower.hasPrefix("subgraph") || lower == "end" || lower.hasPrefix("classdef") || lower.hasPrefix("style ") || lower.hasPrefix("direction ") {
                continue
            }
            var matchedArrow: String? = nil
            for tok in arrowTokens where line.contains(tok) {
                matchedArrow = tok
                break
            }
            if let arrow = matchedArrow, let range = line.range(of: arrow) {
                let lhs = String(line[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                var rhs = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                var edgeLabel = ""
                if rhs.hasPrefix("|"), let secondPipe = rhs.dropFirst().firstIndex(of: "|") {
                    edgeLabel = String(rhs[rhs.index(after: rhs.startIndex)..<secondPipe]).trimmingCharacters(in: .whitespaces)
                    rhs = String(rhs[rhs.index(after: secondPipe)...]).trimmingCharacters(in: .whitespaces)
                } else if let colonRange = rhs.range(of: ":") {
                    let potentialTarget = String(rhs[..<colonRange.lowerBound]).trimmingCharacters(in: .whitespaces)
                    if !potentialTarget.contains("[") && !potentialTarget.contains("(") {
                        edgeLabel = String(rhs[colonRange.upperBound...]).trimmingCharacters(in: .whitespaces)
                        rhs = potentialTarget
                    }
                }
                if !lhs.isEmpty && !rhs.isEmpty {
                    let fromId = registerNode(lhs)
                    let toId = registerNode(rhs)
                    edges.append((fromId, toId, edgeLabel))
                }
            }
        }

        guard !nodeOrder.isEmpty else { return nil }

        // Assign topological layers via BFS relaxation
        var depthByNode: [String: Int] = [:]
        for id in nodeOrder { depthByNode[id] = 0 }
        for _ in 0..<min(16, nodeOrder.count) {
            for e in edges {
                let nextD = (depthByNode[e.from] ?? 0) + 1
                if nextD > (depthByNode[e.to] ?? 0) && nextD < nodeOrder.count {
                    depthByNode[e.to] = nextD
                }
            }
        }

        var layers: [Int: [String]] = [:]
        for id in nodeOrder {
            let d = depthByNode[id] ?? 0
            layers[d, default: []].append(id)
        }
        let maxLayer = layers.keys.max() ?? 0
        let nodeW: CGFloat = 152
        let nodeH: CGFloat = 44
        let gapX: CGFloat = isHorizontal ? 54 : 24
        let gapY: CGFloat = isHorizontal ? 24 : 48
        let pad: CGFloat = 18

        var positions: [String: CGRect] = [:]
        var maxX: CGFloat = 0
        var maxY: CGFloat = 0

        for layerIdx in 0...maxLayer {
            let nodes = layers[layerIdx] ?? []
            for (slotIdx, id) in nodes.enumerated() {
                let x = isHorizontal
                    ? pad + CGFloat(layerIdx) * (nodeW + gapX)
                    : pad + CGFloat(slotIdx) * (nodeW + gapX)
                let y = isHorizontal
                    ? pad + CGFloat(slotIdx) * (nodeH + gapY)
                    : pad + CGFloat(layerIdx) * (nodeH + gapY)
                let rect = CGRect(x: x, y: y, width: nodeW, height: nodeH)
                positions[id] = rect
                maxX = max(maxX, rect.maxX + pad)
                maxY = max(maxY, rect.maxY + pad)
            }
        }

        let mermaidTheme = isDarkMode ? "dark" : "default"
        let accentHex = isDarkMode ? "#8EB4FF" : "#2F66E8"
        let edgeStroke = isDarkMode ? "rgba(142,180,255,0.65)" : "rgba(47,102,232,0.70)"
        let amberHex = isDarkMode ? "#EBB365" : "#B86E00"
        let nodeFillHex = isDarkMode ? "#141519" : "#FFFFFF"
        let nodeStrokeDefault = isDarkMode ? "rgba(142,180,255,0.45)" : "rgba(47,102,232,0.45)"
        let textHex = isDarkMode ? "#F5F6F8" : "#111318"

        var svg = """
        <svg xmlns="http://www.w3.org/2000/svg" data-mermaid-theme="\(mermaidTheme)" viewBox="0 0 \(Int(maxX)) \(Int(maxY))" width="\(Int(maxX))" height="\(Int(maxY))">
        <defs>
          <marker id="agy-arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse">
            <path d="M 0 1 L 10 5 L 0 9 z" fill="\(accentHex)" />
          </marker>
        </defs>
        """

        for e in edges {
            guard let r1 = positions[e.from], let r2 = positions[e.to] else { continue }
            let x1 = isHorizontal ? r1.maxX : r1.midX
            let y1 = isHorizontal ? r1.midY : r1.maxY
            let x2 = isHorizontal ? r2.minX : r2.midX
            let y2 = isHorizontal ? r2.midY : r2.minY
            let cx1 = isHorizontal ? (x1 + x2) / 2 : x1
            let cy1 = isHorizontal ? y1 : (y1 + y2) / 2
            let cx2 = isHorizontal ? (x1 + x2) / 2 : x2
            let cy2 = isHorizontal ? y2 : (y1 + y2) / 2
            svg += "<path d=\"M \(Int(x1)) \(Int(y1)) C \(Int(cx1)) \(Int(cy1)), \(Int(cx2)) \(Int(cy2)), \(Int(x2)) \(Int(y2))\" fill=\"none\" stroke=\"\(edgeStroke)\" stroke-width=\"1.6\" marker-end=\"url(#agy-arrow)\" />"
            if !e.label.isEmpty {
                let lx = Int((x1 + x2) / 2)
                let ly = Int((y1 + y2) / 2) - 4
                svg += "<text x=\"\(lx)\" y=\"\(ly)\" text-anchor=\"middle\" fill=\"\(amberHex)\" font-size=\"10.5\" font-family=\"-apple-system,sans-serif\">\(escapeXML(String(e.label.prefix(24))))</text>"
            }
        }

        for id in nodeOrder {
            guard let r = positions[id] else { continue }
            let label = String((nodeLabels[id] ?? id).prefix(22))
            let shape = nodeShapes[id] ?? "rect"
            let rx = (shape == "pill" || shape == "circle") ? 22 : (shape == "diamond" ? 6 : 10)
            let stroke = shape == "diamond" ? amberHex : nodeStrokeDefault
            svg += "<rect x=\"\(Int(r.minX))\" y=\"\(Int(r.minY))\" width=\"\(Int(r.width))\" height=\"\(Int(r.height))\" rx=\"\(rx)\" fill=\"\(nodeFillHex)\" stroke=\"\(stroke)\" stroke-width=\"1.25\" />"
            svg += "<text x=\"\(Int(r.midX))\" y=\"\(Int(r.midY + 4))\" text-anchor=\"middle\" fill=\"\(textHex)\" font-size=\"12\" font-weight=\"600\" font-family=\"-apple-system,sans-serif\">\(escapeXML(label))</text>"
        }

        svg += "</svg>"
        return AntigravityEmbedHTMLWrapper.wrapSVG(svg, isDarkMode: isDarkMode)
    }

    private static func renderSequenceSVG(lines: [String], isDarkMode: Bool) -> String? {
        var participants: [String] = []
        var messages: [(from: String, to: String, text: String, dashed: Bool)] = []

        func addParticipant(_ name: String) {
            let clean = name.trimmingCharacters(in: .whitespaces)
            if !clean.isEmpty && !participants.contains(clean) {
                participants.append(clean)
            }
        }

        for line in lines {
            if line.lowercased().hasPrefix("participant ") || line.lowercased().hasPrefix("actor ") {
                let rest = line.split(separator: " ", maxSplits: 1).dropFirst().first.map(String.init) ?? ""
                let name = rest.components(separatedBy: " as ").first ?? rest
                addParticipant(name)
                continue
            }
            for arrow in ["-->>", "->>", "-->", "->"] {
                if let range = line.range(of: arrow) {
                    let from = String(line[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                    let rhs = String(line[range.upperBound...])
                    let parts = rhs.split(separator: ":", maxSplits: 1)
                    let to = String(parts[0]).trimmingCharacters(in: .whitespaces)
                    let msg = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespaces) : ""
                    if !from.isEmpty && !to.isEmpty {
                        addParticipant(from)
                        addParticipant(to)
                        messages.append((from, to, msg, arrow.hasPrefix("--")))
                    }
                    break
                }
            }
        }

        guard participants.count >= 2, !messages.isEmpty else { return nil }
        let colW: CGFloat = 118
        let pad: CGFloat = 18
        let topBoxH: CGFloat = 32
        let rowH: CGFloat = 38
        let totalW = pad * 2 + CGFloat(participants.count) * colW
        let totalH = pad * 2 + topBoxH + CGFloat(messages.count + 1) * rowH

        var colCenterX: [String: CGFloat] = [:]
        for (idx, p) in participants.enumerated() {
            colCenterX[p] = pad + CGFloat(idx) * colW + colW / 2
        }

        let mermaidTheme = isDarkMode ? "dark" : "default"
        let accentHex = isDarkMode ? "#8EB4FF" : "#2F66E8"
        let lifelineStroke = isDarkMode ? "rgba(255,255,255,0.14)" : "rgba(0,0,0,0.18)"
        let boxFillHex = isDarkMode ? "#141519" : "#FFFFFF"
        let boxStroke = isDarkMode ? "rgba(142,180,255,0.45)" : "rgba(47,102,232,0.45)"
        let participantTextHex = isDarkMode ? "#F5F6F8" : "#111318"
        let messageTextHex = isDarkMode ? "#DCE6FF" : "#1E46A8"

        var svg = """
        <svg xmlns="http://www.w3.org/2000/svg" data-mermaid-theme="\(mermaidTheme)" viewBox="0 0 \(Int(totalW)) \(Int(totalH))" width="\(Int(totalW))" height="\(Int(totalH))">
        <defs>
          <marker id="seq-arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse">
            <path d="M 0 1 L 10 5 L 0 9 z" fill="\(accentHex)" />
          </marker>
        </defs>
        """

        for p in participants {
            let cx = colCenterX[p] ?? 0
            svg += "<line x1=\"\(Int(cx))\" y1=\"\(Int(pad + topBoxH))\" x2=\"\(Int(cx))\" y2=\"\(Int(totalH - pad))\" stroke=\"\(lifelineStroke)\" stroke-dasharray=\"4 4\" />"
            svg += "<rect x=\"\(Int(cx - 48))\" y=\"\(Int(pad))\" width=\"96\" height=\"\(Int(topBoxH))\" rx=\"8\" fill=\"\(boxFillHex)\" stroke=\"\(boxStroke)\" stroke-width=\"1.2\" />"
            svg += "<text x=\"\(Int(cx))\" y=\"\(Int(pad + 20))\" text-anchor=\"middle\" fill=\"\(participantTextHex)\" font-size=\"11.5\" font-weight=\"600\" font-family=\"-apple-system,sans-serif\">\(escapeXML(String(p.prefix(14))))</text>"
        }

        for (idx, m) in messages.enumerated() {
            guard let x1 = colCenterX[m.from], let x2 = colCenterX[m.to] else { continue }
            let y = pad + topBoxH + CGFloat(idx + 1) * rowH
            let dashAttr = m.dashed ? " stroke-dasharray=\"5 3\"" : ""
            svg += "<line x1=\"\(Int(x1))\" y1=\"\(Int(y))\" x2=\"\(Int(x2))\" y2=\"\(Int(y))\" stroke=\"\(accentHex)\" stroke-width=\"1.5\"\(dashAttr) marker-end=\"url(#seq-arrow)\" />"
            if !m.text.isEmpty {
                let lx = Int((x1 + x2) / 2)
                svg += "<text x=\"\(lx)\" y=\"\(Int(y - 6))\" text-anchor=\"middle\" fill=\"\(messageTextHex)\" font-size=\"10.5\" font-family=\"-apple-system,sans-serif\">\(escapeXML(String(m.text.prefix(26))))</text>"
            }
        }

        svg += "</svg>"
        return AntigravityEmbedHTMLWrapper.wrapSVG(svg, isDarkMode: isDarkMode)
    }
}
