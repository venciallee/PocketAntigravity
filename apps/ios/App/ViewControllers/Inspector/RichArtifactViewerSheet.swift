import SwiftUI
import AntigravityData
#if canImport(PDFKit)
import PDFKit
#endif
#if canImport(WebKit)
import WebKit
#endif
#if canImport(UIKit)
import UIKit
#endif

/// Rich native viewer for PDF documents (`PDFKit`), Jupyter Notebooks (`.ipynb` Preview/Raw + Cell Comment),
/// Fullscreen Images (drag-to-select region comments), Video assets, and Generative UI / URL HTML artifacts (`WKWebView`).
public struct RichArtifactViewerSheet: View {
    @Bindable private var store: AntigravitySessionStore
    private let artifactPath: String
    @State private var showRawNotebook: Bool = false
    @State private var commentDraft: String = ""
    @State private var selectedRegion: CGRect? = nil
    @State private var dragStart: CGPoint? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    public init(store: AntigravitySessionStore, artifactPath: String) {
        self.store = store
        self.artifactPath = artifactPath
    }

    private var artifact: ArtifactSnapshot? {
        store.activeArtifacts.first(where: { $0.artifactPath == artifactPath })
            ?? store.activeArtifacts.first
    }

    public var body: some View {
        NavigationStack {
            Group {
                if let art = artifact {
                    switch art.kind {
                    case .pdfDocument:
                        pdfArtifactView(art)
                    case .jupyterNotebook:
                        jupyterArtifactView(art)
                    case .imageAsset:
                        imageAnnotationArtifactView(art)
                    case .generativeUIHTML, .urlBookmark:
                        webArtifactView(art)
                    case .unsupportedAsset:
                        unsupportedArtifactView(art)
                    default:
                        markdownFallbackView(art)
                    }
                } else {
                    Text("Artifact not found: \(artifactPath)")
                        .font(.system(size: 14))
                        .foregroundStyle(AntigravityTheme.inkSecondary)
                }
            }
            .background(AntigravityTheme.canvasObsidian.ignoresSafeArea())
            .navigationTitle(artifact?.title ?? "Artifact Viewer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        store.presentedSheet = nil
                        dismiss()
                    }
                    .foregroundStyle(AntigravityTheme.accentPeriwinkle)
                }
            }
        }
        .accessibilityIdentifier("sheet_rich_artifact_viewer")
    }

    // MARK: - PDF Viewer (`PDFKit`)

    private func pdfArtifactView(_ art: ArtifactSnapshot) -> some View {
        VStack(spacing: 12) {
            #if canImport(PDFKit) && canImport(UIKit)
            PDFKitDocumentContainer(base64OrPath: art.content, fallbackTitle: art.title)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            #else
            Text("PDF preview: \(art.title)")
                .foregroundStyle(AntigravityTheme.inkReading)
            #endif

            HStack(spacing: 10) {
                TextField("Comment or quote PDF passage...", text: $commentDraft)
                    .font(.system(size: 14))
                    .foregroundStyle(AntigravityTheme.inkReading)
                    .padding(10)
                    .background(AntigravityTheme.surfaceCard, in: RoundedRectangle(cornerRadius: 12))
                Button("Quote") {
                    let quote = commentDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                    store.quoteDiffLinesToComposer(
                        filePath: art.artifactPath,
                        startLine: 1,
                        endLine: 1,
                        snippet: quote.isEmpty ? art.title : quote
                    )
                    commentDraft = ""
                    store.presentedSheet = nil
                    dismiss()
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AntigravityTheme.inkOnPrimaryCTA)
                .padding(.horizontal, 14)
                .frame(minHeight: 40)
                .background(AntigravityTheme.accentPeriwinkle, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(16)
    }

    // MARK: - Jupyter Notebook (`.ipynb`) Viewer

    private func jupyterArtifactView(_ art: ArtifactSnapshot) -> some View {
        VStack(spacing: 12) {
            Picker("Mode", selection: $showRawNotebook) {
                Text("Preview").tag(false)
                Text("Raw JSON").tag(true)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.top, 8)

            if showRawNotebook {
                ScrollView {
                    Text(art.content)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(AntigravityTheme.inkLabel)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                }
            } else if let doc = JupyterNotebookDocument.parse(jsonString: art.content) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("Kernel: \(doc.kernelName)", systemImage: "cpu")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundStyle(AntigravityTheme.accentPeriwinkle)
                            Spacer()
                            Text("\(doc.cells.count) cells")
                                .font(.system(size: 12))
                                .foregroundStyle(AntigravityTheme.inkSecondary)
                        }
                        ForEach(Array(doc.cells.enumerated()), id: \.element.id) { idx, cell in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(cell.cellType == .code ? "In [\(cell.executionCount.map(String.init) ?? " ")]:" : "Markdown #\(idx + 1)")
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                        .foregroundStyle(AntigravityTheme.inkSecondary)
                                    Spacer()
                                    Button("Comment") {
                                        store.quoteDiffLinesToComposer(
                                            filePath: art.artifactPath,
                                            startLine: idx + 1,
                                            endLine: idx + 1,
                                            snippet: String(cell.source.prefix(240))
                                        )
                                        store.presentedSheet = nil
                                        dismiss()
                                    }
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(AntigravityTheme.accentPeriwinkle)
                                }
                                Text(cell.source)
                                    .font(cell.cellType == .code ? .system(size: 12, design: .monospaced) : .system(size: 14))
                                    .foregroundStyle(AntigravityTheme.inkReading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(10)
                                    .background(AntigravityTheme.surfaceObsidian, in: RoundedRectangle(cornerRadius: 10))
                                ForEach(cell.outputs) { out in
                                    if let errVal = out.errorValue {
                                        Text("\(out.errorName ?? "Error"): \(errVal)")
                                            .font(.system(size: 12, design: .monospaced))
                                            .foregroundStyle(AntigravityTheme.statusError)
                                    } else if let txt = out.text, !txt.isEmpty {
                                        Text(txt)
                                            .font(.system(size: 12, design: .monospaced))
                                            .foregroundStyle(AntigravityTheme.statusDone)
                                    }
                                }
                            }
                            .padding(12)
                            .background(AntigravityTheme.surfaceCard, in: RoundedRectangle(cornerRadius: 14))
                        }
                    }
                    .padding(16)
                }
            } else {
                Text("Unable to parse Jupyter Notebook JSON.")
                    .font(.system(size: 14))
                    .foregroundStyle(AntigravityTheme.statusError)
                    .padding()
            }
        }
    }

    // MARK: - Fullscreen Image + Drag-to-Select Region Commenting

    private func imageAnnotationArtifactView(_ art: ArtifactSnapshot) -> some View {
        let existingComments = store.imageRegionComments.filter { $0.artifactPath == art.artifactPath }
        return VStack(spacing: 12) {
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(AntigravityTheme.surfaceCard)
                        .overlay(
                            VStack(spacing: 8) {
                                Image(systemName: "photo.artframe")
                                    .font(.system(size: 40))
                                    .foregroundStyle(AntigravityTheme.accentPeriwinkle)
                                Text(art.title)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(AntigravityTheme.inkReading)
                                Text("Drag across image to annotate a specific region")
                                    .font(.system(size: 12))
                                    .foregroundStyle(AntigravityTheme.inkSecondary)
                            }
                        )

                    ForEach(existingComments) { item in
                        Rectangle()
                            .stroke(AntigravityTheme.statusWaiting, lineWidth: 2)
                            .background(AntigravityTheme.statusWaiting.opacity(0.16))
                            .frame(
                                width: item.normalizedWidth * geo.size.width,
                                height: item.normalizedHeight * geo.size.height
                            )
                            .offset(
                                x: item.normalizedX * geo.size.width,
                                y: item.normalizedY * geo.size.height
                            )
                    }

                    if let rect = selectedRegion {
                        Rectangle()
                            .stroke(AntigravityTheme.accentPeriwinkle, lineWidth: 2)
                            .background(AntigravityTheme.accentPeriwinkle.opacity(0.18))
                            .frame(width: rect.width, height: rect.height)
                            .offset(x: rect.minX, y: rect.minY)
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 8)
                        .onChanged { value in
                            if dragStart == nil { dragStart = value.startLocation }
                            let start = dragStart ?? value.startLocation
                            let x = min(start.x, value.location.x)
                            let y = min(start.y, value.location.y)
                            let w = abs(value.location.x - start.x)
                            let h = abs(value.location.y - start.y)
                            selectedRegion = CGRect(x: x, y: y, width: max(12, w), height: max(12, h))
                        }
                        .onEnded { _ in
                            dragStart = nil
                        }
                )
            }
            .frame(height: 300)

            HStack(spacing: 10) {
                TextField("Comment on selected region...", text: $commentDraft)
                    .font(.system(size: 14))
                    .foregroundStyle(AntigravityTheme.inkReading)
                    .padding(10)
                    .background(AntigravityTheme.surfaceCard, in: RoundedRectangle(cornerRadius: 12))
                Button("Add") {
                    let body = commentDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !body.isEmpty else { return }
                    let rect = selectedRegion ?? CGRect(x: 40, y: 40, width: 120, height: 80)
                    store.addImageRegionComment(
                        ImageRegionComment(
                            artifactPath: art.artifactPath,
                            normalizedX: Double(rect.minX / 360.0),
                            normalizedY: Double(rect.minY / 300.0),
                            normalizedWidth: Double(rect.width / 360.0),
                            normalizedHeight: Double(rect.height / 300.0),
                            body: body
                        )
                    )
                    commentDraft = ""
                    selectedRegion = nil
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AntigravityTheme.inkOnPrimaryCTA)
                .padding(.horizontal, 14)
                .frame(minHeight: 40)
                .background(AntigravityTheme.accentPeriwinkle, in: RoundedRectangle(cornerRadius: 12))
            }

            if !existingComments.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(existingComments) { item in
                            Text("Region (\(Int(item.normalizedX * 100))%, \(Int(item.normalizedY * 100))%): \(item.body)")
                                .font(.system(size: 13))
                                .foregroundStyle(AntigravityTheme.inkReading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                                .background(AntigravityTheme.surfaceCard, in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
            }
        }
        .padding(16)
    }

    // MARK: - Generative UI / URL Artifact Sandboxed WebView

    private func webArtifactView(_ art: ArtifactSnapshot) -> some View {
        #if canImport(WebKit) && canImport(UIKit)
        SandboxedArtifactWebView(htmlOrUrl: art.content, isDarkMode: colorScheme == .dark)
            .ignoresSafeArea(edges: .bottom)
        #else
        ScrollView {
            Text(art.content)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(AntigravityTheme.inkReading)
                .padding(16)
        }
        #endif
    }

    private func unsupportedArtifactView(_ art: ArtifactSnapshot) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: "doc.questionmark")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(AntigravityTheme.accentPeriwinkle)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(art.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(AntigravityTheme.inkReading)
                        if let rawKind = art.rawKindName, !rawKind.isEmpty {
                            Text("Format: \(rawKind)")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(AntigravityTheme.inkSecondary)
                        }
                    }
                    Spacer()
                }
                if !art.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(art.summary)
                        .font(.system(size: 13.5))
                        .foregroundStyle(AntigravityTheme.inkReading)
                }
                Text(art.artifactPath)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(AntigravityTheme.inkSecondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AntigravityTheme.surfaceCard, in: RoundedRectangle(cornerRadius: 10))
                Text("This artifact format isn't natively previewable in this iOS build yet. Open it in Antigravity Desktop or update the iOS app.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(AntigravityTheme.inkMuted)
                #if canImport(UIKit)
                Button {
                    UIPasteboard.general.string = art.artifactPath
                } label: {
                    Label("Copy Artifact Path", systemImage: "doc.on.doc")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(AntigravityTheme.inkOnPrimaryCTA)
                        .frame(maxWidth: .infinity, minHeight: 42)
                        .background(AntigravityTheme.accentPeriwinkle, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                #endif
            }
            .padding(16)
        }
    }

    private func markdownFallbackView(_ art: ArtifactSnapshot) -> some View {
        ScrollView {
            Text(art.content)
                .font(.system(size: 14))
                .foregroundStyle(AntigravityTheme.inkReading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
        }
    }
}

#if canImport(PDFKit) && canImport(UIKit)
private struct PDFKitDocumentContainer: UIViewRepresentable {
    let base64OrPath: String
    let fallbackTitle: String

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.backgroundColor = AntigravityTheme.dynamicUIColor(
            dark: AntigravityTheme.RGB(0x0F1014),
            light: AntigravityTheme.RGB(0xECEEF4)
        )
        if let data = Data(base64Encoded: base64OrPath), let doc = PDFDocument(data: data) {
            view.document = doc
        } else if let url = URL(string: base64OrPath), url.isFileURL, let doc = PDFDocument(url: url) {
            view.document = doc
        }
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {}
}
#endif

#if canImport(WebKit) && canImport(UIKit)
private struct SandboxedArtifactWebView: UIViewRepresentable {
    let htmlOrUrl: String
    let isDarkMode: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = AntigravityTheme.canvasObsidianUIColor
        webView.scrollView.backgroundColor = .clear
        loadContent(into: webView, coordinator: context.coordinator)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        loadContent(into: uiView, coordinator: context.coordinator)
    }

    private func loadContent(into webView: WKWebView, coordinator: Coordinator) {
        let signature = "\(isDarkMode)|\(htmlOrUrl)"
        guard coordinator.lastLoadedSignature != signature else { return }
        coordinator.lastLoadedSignature = signature
        let trimmed = htmlOrUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("http"), let url = URL(string: trimmed) {
            webView.load(URLRequest(url: url))
        } else {
            let wrapped = AntigravityEmbedHTMLWrapper.wrapHTML(htmlOrUrl, isDarkMode: isDarkMode)
            webView.loadHTMLString(wrapped, baseURL: nil)
        }
    }

    @MainActor
    final class Coordinator {
        var lastLoadedSignature: String = ""
    }
}
#endif
