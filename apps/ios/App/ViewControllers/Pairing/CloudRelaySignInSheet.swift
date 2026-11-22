import SwiftUI
import AntigravityData
#if canImport(WebKit) && canImport(UIKit)
import WebKit
import UIKit
#endif

/// Extracts or clears Google Cloud Relay session cookies (`SAPISID`, `__Secure-1PAPISID`, `__Secure-3PAPISID`, `SID`, etc.)
/// from `WKWebsiteDataStore.default()`, strictly scoped to `antigravity.google.com` per RFC 6265.
@MainActor
public enum CloudRelayCookieExtractor {
    public static func readGoogleCookieHeader(forHost targetHost: String = "antigravity.google.com") async -> String? {
        #if canImport(WebKit) && canImport(UIKit)
        let store = WKWebsiteDataStore.default().httpCookieStore
        let allCookies = await store.allCookies()
        let descriptors = allCookies.map { cookie in
            SAPISIDHashGenerator.RelayCookieDescriptor(
                name: cookie.name,
                value: cookie.value,
                domain: cookie.domain,
                path: cookie.path,
                expiresDate: cookie.expiresDate
            )
        }
        return SAPISIDHashGenerator.buildCookieHeader(
            from: descriptors,
            forHost: targetHost
        )
        #else
        return nil
        #endif
    }

    public static func clearGoogleCookies() async {
        #if canImport(WebKit) && canImport(UIKit)
        let store = WKWebsiteDataStore.default().httpCookieStore
        let allCookies = await store.allCookies()
        for cookie in allCookies {
            let domain = cookie.domain.lowercased()
            let cleanDomain = domain.trimmingCharacters(in: CharacterSet(charactersIn: "."))
            if domain.hasSuffix("google.com")
                || RemoteHostInstance.isAntigravityRelayHost(cleanDomain) {
                await store.deleteCookie(cookie)
            }
        }
        #endif
    }
}

/// Interactive Google Sign-In sheet (`WKWebView`) opening `https://antigravity.google.com/r/<id>`,
/// automatically capturing the authenticated Google cookies and frontend `X-Goog-Api-Key`
/// to establish native Connect-RPC over `devtools_jetski_boq_api_proto.ApiService`.
public struct CloudRelaySignInSheet: View {
    public let targetRelayURLString: String
    public let clearExistingSession: Bool
    public var onAuthenticated: (
        _ cookieHeader: String,
        _ finalURLString: String?,
        _ authUser: String?,
        _ relayApiKey: String?
    ) -> Void
    public var onDismiss: () -> Void

    @State private var currentURLDisplay: String = "antigravity.google.com"
    @State private var latestFullURLString: String? = nil
    @State private var isLoadingPage: Bool = true
    @State private var detectedCookiesReady: Bool = false
    @State private var detectedRelayApiKey: String? = nil

    public init(
        targetRelayURLString: String,
        clearExistingSession: Bool = false,
        onAuthenticated: @escaping (
            _ cookieHeader: String,
            _ finalURLString: String?,
            _ authUser: String?,
            _ relayApiKey: String?
        ) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.targetRelayURLString = targetRelayURLString
        self.clearExistingSession = clearExistingSession
        self.onAuthenticated = onAuthenticated
        self.onDismiss = onDismiss
    }

    private var initialURL: URL {
        let trimmed = targetRelayURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        if let parsed = RemoteHostInstance.parseRemoteControlTarget(trimmed) {
            if let orig = parsed.originalURLString,
               let origURL = URL(string: orig),
               let scheme = origURL.scheme?.lowercased(),
               (scheme == "https" || scheme == "http") {
                return origURL
            }
            if let canonicalURL = URL(string: parsed.canonicalRelayURLString) {
                return canonicalURL
            }
        }
        return URL(string: SAPISIDHashGenerator.defaultOrigin)!
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Top Chrome Bar
            HStack(spacing: 12) {
                Button {
                    onDismiss()
                } label: {
                    Text("Cancel")
                        .font(.system(size: 15.5, weight: .medium))
                        .foregroundStyle(AntigravityTheme.textSecondary)
                        .frame(minHeight: AntigravityTheme.minTouchTargetPt)
                }
                .buttonStyle(.plain)

                Spacer()

                VStack(spacing: 2) {
                    HStack(spacing: 5) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(AntigravityTheme.statusDone)
                        Text("Google Remote Control Sign-In")
                            .font(.system(size: 14.5, weight: .semibold))
                            .foregroundStyle(AntigravityTheme.inkReading)
                    }
                    Text(currentURLDisplay)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundStyle(AntigravityTheme.textSecondary)
                        .lineLimit(1)
                }

                Spacer()

                Button {
                    Task {
                        let targetHost = initialURL.host ?? "antigravity.google.com"
                        if let cookie = await CloudRelayCookieExtractor.readGoogleCookieHeader(forHost: targetHost) {
                            let parsed = latestFullURLString.flatMap {
                                RemoteHostInstance.parseRemoteControlTarget($0)
                            }
                            onAuthenticated(cookie, latestFullURLString, parsed?.authUser, detectedRelayApiKey)
                        }
                    }
                } label: {
                    Text("Connect")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(
                            detectedCookiesReady
                                ? AntigravityTheme.accentPeriwinkle
                                : AntigravityTheme.textMuted
                        )
                        .frame(minHeight: AntigravityTheme.minTouchTargetPt)
                }
                .buttonStyle(.plain)
                .disabled(!detectedCookiesReady)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(AntigravityTheme.surfaceCard)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(AntigravityTheme.subtleDivider)
                    .frame(height: 1)
            }

            if isLoadingPage {
                ProgressView()
                    .progressViewStyle(.linear)
                    .tint(AntigravityTheme.accentPeriwinkle)
            }

            #if canImport(WebKit) && canImport(UIKit)
            CloudRelayWebViewRepresentable(
                initialURL: initialURL,
                clearExistingSession: clearExistingSession,
                onStateChange: { hostStr, fullURLStr, loading, cookiesReady, apiKey in
                    if let hostStr {
                        currentURLDisplay = hostStr
                    }
                    if let fullURLStr {
                        latestFullURLString = fullURLStr
                    }
                    isLoadingPage = loading
                    detectedCookiesReady = cookiesReady
                    if let apiKey, !apiKey.isEmpty {
                        detectedRelayApiKey = apiKey
                    }
                },
                onAutoCapturedSession: { cookieHeader, finalURL, authUser, apiKey in
                    onAuthenticated(cookieHeader, finalURL, authUser, apiKey)
                }
            )
            #else
            VStack(spacing: 12) {
                Spacer()
                Text("WebKit Sign-In is available on iOS.")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(AntigravityTheme.textSecondary)
                Spacer()
            }
            #endif
        }
        .background(AntigravityTheme.canvasObsidian.ignoresSafeArea())
    }
}

#if canImport(WebKit) && canImport(UIKit)
private struct CloudRelayWebViewRepresentable: UIViewControllerRepresentable {
    let initialURL: URL
    let clearExistingSession: Bool
    let onStateChange: (String?, String?, Bool, Bool, String?) -> Void
    let onAutoCapturedSession: (String, String?, String?, String?) -> Void

    func makeUIViewController(context: Context) -> CloudRelayWebAuthViewController {
        let vc = CloudRelayWebAuthViewController(
            initialURL: initialURL,
            clearExistingSession: clearExistingSession
        )
        vc.onStateChange = onStateChange
        vc.onAutoCapturedSession = onAutoCapturedSession
        return vc
    }

    func updateUIViewController(_ uiViewController: CloudRelayWebAuthViewController, context: Context) {}
}

@MainActor
private final class WeakRelayScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var owner: CloudRelayWebAuthViewController?

    init(owner: CloudRelayWebAuthViewController) {
        self.owner = owner
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let rawKey = message.body as? String else { return }
        owner?.recordCapturedWebApiKey(rawKey)
    }
}

@MainActor
private final class CloudRelayWebAuthViewController: UIViewController, WKNavigationDelegate, WKHTTPCookieStoreObserver {
    private static let apiKeyMessageHandlerName = "antigravityRelayApiKey"
    private static let apiKeyCaptureUserScriptSource = """
    (function() {
      if (window.__agRelayApiKeyHookInstalled) { return; }
      window.__agRelayApiKeyHookInstalled = true;
      function isRelayHost() {
        var host = (window.location && window.location.hostname ? window.location.hostname : '').toLowerCase();
        return host === 'antigravity.google.com'
          || host === 'antigravity.google'
          || host.endsWith('.antigravity.google.com')
          || host.endsWith('.antigravity.google')
          || host === '127.0.0.1'
          || host === 'localhost';
      }
      function record(val) {
        if (!isRelayHost()) { return; }
        if (typeof val !== 'string') { return; }
        var trimmed = val.trim();
        if (trimmed.length < 8 || trimmed.length > 128) { return; }
        window.__agCapturedRelayApiKey = trimmed;
        try {
          if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.\(apiKeyMessageHandlerName)) {
            window.webkit.messageHandlers.\(apiKeyMessageHandlerName).postMessage(trimmed);
          }
        } catch (_) {}
      }
      function inspectHeaders(headers) {
        if (!headers) { return; }
        try {
          if (typeof headers.get === 'function') {
            var direct = headers.get('x-goog-api-key') || headers.get('X-Goog-Api-Key');
            if (direct) { record(direct); return; }
          }
          if (Array.isArray(headers)) {
            for (var i = 0; i < headers.length; i++) {
              var pair = headers[i];
              if (Array.isArray(pair) && pair.length >= 2 && String(pair[0]).toLowerCase() === 'x-goog-api-key') {
                record(String(pair[1]));
                return;
              }
            }
          } else if (typeof headers === 'object') {
            var keys = Object.keys(headers);
            for (var j = 0; j < keys.length; j++) {
              if (keys[j].toLowerCase() === 'x-goog-api-key') {
                record(String(headers[keys[j]]));
                return;
              }
            }
          }
        } catch (_) {}
      }
      var origSetHeader = XMLHttpRequest.prototype.setRequestHeader;
      if (typeof origSetHeader === 'function') {
        XMLHttpRequest.prototype.setRequestHeader = function(name, value) {
          if (typeof name === 'string' && name.toLowerCase() === 'x-goog-api-key') {
            record(String(value));
          }
          return origSetHeader.apply(this, arguments);
        };
      }
      if (typeof window.fetch === 'function') {
        var origFetch = window.fetch;
        window.fetch = function(input, init) {
          if (init && init.headers) { inspectHeaders(init.headers); }
          if (input && typeof input === 'object' && input.headers) { inspectHeaders(input.headers); }
          return origFetch.apply(this, arguments);
        };
      }
    })();
    """

    private static let apiKeyInspectScriptSource = """
    (function() {
      try {
        if (typeof window.__agCapturedRelayApiKey === 'string' && window.__agCapturedRelayApiKey.length >= 8) {
          return window.__agCapturedRelayApiKey;
        }
        var meta = document.querySelector('meta[name="antigravity-relay-api-key"]');
        if (meta && meta.getAttribute('content')) {
          return meta.getAttribute('content');
        }
        var re = new RegExp('(?:^|[^0-9A-Za-z_-])(AI' + 'za[0-9A-Za-z_-]{35})(?![0-9A-Za-z_-])');
        if (window.WIZ_global_data) {
          var wizStr = JSON.stringify(window.WIZ_global_data);
          var wizMatch = wizStr.match(re);
          if (wizMatch && wizMatch[1]) { return wizMatch[1]; }
        }
        var html = document.documentElement ? document.documentElement.innerHTML : '';
        var htmlMatch = html.match(re);
        if (htmlMatch && htmlMatch[1]) { return htmlMatch[1]; }
      } catch (_) {}
      return '';
    })();
    """

    private let initialURL: URL
    private let clearExistingSession: Bool
    var onStateChange: ((String?, String?, Bool, Bool, String?) -> Void)?
    var onAutoCapturedSession: ((String, String?, String?, String?) -> Void)?

    private var webView: WKWebView!
    private var didCompleteCapture = false
    private var isObservingCookieStore = false
    private var isReadyForAutoCapture = false
    private var capturedRelayApiKey: String?
    private var pendingCompletionFallbackTask: Task<Void, Never>?

    init(initialURL: URL, clearExistingSession: Bool = false) {
        self.initialURL = initialURL
        self.clearExistingSession = clearExistingSession
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AntigravityTheme.canvasObsidianUIColor
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let userContentController = WKUserContentController()
        userContentController.addUserScript(
            WKUserScript(
                source: Self.apiKeyCaptureUserScriptSource,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
        )
        userContentController.add(
            WeakRelayScriptMessageHandler(owner: self),
            name: Self.apiKeyMessageHandlerName
        )
        config.userContentController = userContentController

        let wv = WKWebView(frame: view.bounds, configuration: config)
        wv.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        wv.navigationDelegate = self
        wv.customUserAgent =
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
        view.addSubview(wv)
        self.webView = wv

        if clearExistingSession {
            isReadyForAutoCapture = false
            Task { @MainActor [weak self] in
                await CloudRelayCookieExtractor.clearGoogleCookies()
                guard let self else { return }
                self.isReadyForAutoCapture = true
                self.webView.load(URLRequest(url: self.initialURL))
            }
        } else {
            isReadyForAutoCapture = true
            wv.load(URLRequest(url: initialURL))
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if !isObservingCookieStore {
            webView.configuration.websiteDataStore.httpCookieStore.add(self)
            isObservingCookieStore = true
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        pendingCompletionFallbackTask?.cancel()
        pendingCompletionFallbackTask = nil
        if isObservingCookieStore {
            webView.configuration.websiteDataStore.httpCookieStore.remove(self)
            isObservingCookieStore = false
        }
    }

    nonisolated func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        Task { @MainActor [weak self] in
            await self?.evaluateSessionReadiness(autoFinishIfOnRelayHost: true)
        }
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        pendingCompletionFallbackTask?.cancel()
        pendingCompletionFallbackTask = nil
        onStateChange?(
            webView.url?.host ?? initialURL.host,
            webView.url?.absoluteString,
            true,
            false,
            capturedRelayApiKey
        )
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor [weak self] in
            await self?.evaluateSessionReadiness(autoFinishIfOnRelayHost: true)
        }
    }

    func recordCapturedWebApiKey(_ rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 8, trimmed.count <= 128 else { return }
        let normalized = SAPISIDHashGenerator.extractWebApiKey(from: trimmed) ?? trimmed
        capturedRelayApiKey = normalized
        if pendingCompletionFallbackTask != nil {
            pendingCompletionFallbackTask?.cancel()
            pendingCompletionFallbackTask = nil
            Task { @MainActor [weak self] in
                await self?.evaluateSessionReadiness(autoFinishIfOnRelayHost: true)
            }
        }
    }

    private func extractWebApiKeyFromWebView() async -> String? {
        if let existing = capturedRelayApiKey, !existing.isEmpty {
            return existing
        }
        guard let raw = (try? await webView.evaluateJavaScript(Self.apiKeyInspectScriptSource)) as? String else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let extracted = SAPISIDHashGenerator.extractWebApiKey(from: trimmed) ?? trimmed
        capturedRelayApiKey = extracted
        return extracted
    }

    private func completeCapture(cookieHeader: String, currentURL: URL?) {
        guard !didCompleteCapture else { return }
        didCompleteCapture = true
        pendingCompletionFallbackTask?.cancel()
        pendingCompletionFallbackTask = nil
        let finalURLStr = currentURL?.absoluteString
        let parsed = finalURLStr.flatMap { RemoteHostInstance.parseRemoteControlTarget($0) }
        onAutoCapturedSession?(cookieHeader, finalURLStr, parsed?.authUser, capturedRelayApiKey)
    }

    private func evaluateSessionReadiness(autoFinishIfOnRelayHost: Bool) async {
        guard !didCompleteCapture, isReadyForAutoCapture else { return }
        let currentURL = webView.url
        let host = currentURL?.host?.lowercased() ?? ""
        let isOnAntigravityRelay = RemoteHostInstance.isAntigravityRelayHost(host)

        if isOnAntigravityRelay && capturedRelayApiKey == nil {
            _ = await extractWebApiKeyFromWebView()
        }

        let targetHost = host.isEmpty ? (initialURL.host ?? "antigravity.google.com") : host
        let cookieHeader = await CloudRelayCookieExtractor.readGoogleCookieHeader(forHost: targetHost)
        let hasCookies = (cookieHeader != nil)
        onStateChange?(
            currentURL?.host ?? initialURL.host,
            currentURL?.absoluteString,
            webView.isLoading,
            hasCookies,
            capturedRelayApiKey
        )

        if autoFinishIfOnRelayHost && isOnAntigravityRelay, let cookieHeader {
            if capturedRelayApiKey != nil {
                completeCapture(cookieHeader: cookieHeader, currentURL: currentURL)
            } else if pendingCompletionFallbackTask == nil {
                // Allow the antigravity.google.com SPA up to 2.5s to boot and issue its first
                // XHR/fetch carrying `X-Goog-Api-Key` (or redirect to accounts.google.com if stale).
                pendingCompletionFallbackTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 2_500_000_000)
                    guard let self, !Task.isCancelled, !self.didCompleteCapture else { return }
                    let liveHost = self.webView.url?.host?.lowercased() ?? ""
                    guard RemoteHostInstance.isAntigravityRelayHost(liveHost) else {
                        self.pendingCompletionFallbackTask = nil
                        return
                    }
                    _ = await self.extractWebApiKeyFromWebView()
                    let latestCookie = await CloudRelayCookieExtractor.readGoogleCookieHeader(forHost: liveHost) ?? cookieHeader
                    self.completeCapture(cookieHeader: latestCookie, currentURL: self.webView.url ?? currentURL)
                }
            }
        }
    }
}
#endif
