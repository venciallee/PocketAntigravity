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
        let normalizedTargetHost: String = {
            let clean = targetHost.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if clean == "antigravity.google" || clean.hasSuffix(".antigravity.google") {
                return "antigravity.google.com"
            }
            return clean.isEmpty ? "antigravity.google.com" : clean
        }()
        return SAPISIDHashGenerator.buildCookieHeader(
            from: descriptors,
            forHost: normalizedTargetHost
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
                        let liveHost = latestFullURLString.flatMap { URL(string: $0)?.host }
                        let targetHost = liveHost ?? initialURL.host ?? "antigravity.google.com"
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
        if let dict = message.body as? [String: Any] {
            let kind = (dict["kind"] as? String) ?? "fallbackKey"
            let apiKey = dict["apiKey"] as? String
            let authUser = dict["authUser"] as? String
            owner?.recordInterceptedRelaySignal(kind: kind, apiKey: apiKey, authUser: authUser)
        } else if let rawKey = message.body as? String {
            owner?.recordInterceptedRelaySignal(kind: "fallbackKey", apiKey: rawKey, authUser: nil)
        }
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
      function isApiServiceUrl(rawUrl) {
        if (!rawUrl || typeof rawUrl !== 'string') { return false; }
        var lower = rawUrl.toLowerCase();
        return lower.indexOf('/$rpc/') !== -1
          || lower.indexOf('/%24rpc/') !== -1
          || lower.indexOf('devtools_jetski_boq_api_proto') !== -1
          || lower.indexOf('apiservice/listinstances') !== -1
          || lower.indexOf('apiservice/proxycommand') !== -1;
      }
      function extractQueryKey(rawUrl) {
        if (!rawUrl || typeof rawUrl !== 'string') { return ''; }
        var m = rawUrl.match(/[?&]key=([A-Za-z0-9_.-]{16,128})/i);
        return m && m[1] ? m[1] : '';
      }
      function isUnrelatedTelemetryUrl(rawUrl) {
        if (!rawUrl || typeof rawUrl !== 'string') { return false; }
        var lower = rawUrl.toLowerCase();
        return lower.indexOf('play.google.com') !== -1
          || lower.indexOf('ogs.google.com') !== -1
          || lower.indexOf('ogads-pa') !== -1
          || lower.indexOf('waa-pa') !== -1
          || lower.indexOf('people-pa') !== -1
          || lower.indexOf('accounts.google.com') !== -1;
      }
      function postSignal(kind, apiKey, authUser) {
        if (!isRelayHost()) { return; }
        var cleanKey = (typeof apiKey === 'string') ? apiKey.trim() : '';
        var cleanUser = (typeof authUser === 'string') ? authUser.trim() : '';
        if (kind === 'apiServiceKey' || kind === 'apiServiceVerified') {
          if (cleanKey.length >= 8 && cleanKey.length <= 128) {
            window.__agApiServiceKey = cleanKey;
            window.__agCapturedRelayApiKey = cleanKey;
          }
          if (cleanUser.length > 0) {
            window.__agApiServiceAuthUser = cleanUser;
          }
        } else if (cleanKey.length >= 8 && cleanKey.length <= 128 && !window.__agApiServiceKey) {
          window.__agCapturedRelayApiKey = cleanKey;
        }
        try {
          if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.\(apiKeyMessageHandlerName)) {
            window.webkit.messageHandlers.\(apiKeyMessageHandlerName).postMessage({
              kind: kind,
              apiKey: cleanKey,
              authUser: cleanUser
            });
          }
        } catch (_) {}
      }
      function extractHeader(headers, targetLower) {
        if (!headers) { return ''; }
        try {
          if (typeof headers.get === 'function') {
            var direct = headers.get(targetLower);
            if (direct) { return String(direct); }
          }
          if (Array.isArray(headers)) {
            for (var i = 0; i < headers.length; i++) {
              var pair = headers[i];
              if (Array.isArray(pair) && pair.length >= 2 && String(pair[0]).toLowerCase() === targetLower) {
                return String(pair[1]);
              }
            }
          } else if (typeof headers === 'object') {
            var keys = Object.keys(headers);
            for (var j = 0; j < keys.length; j++) {
              if (keys[j].toLowerCase() === targetLower) {
                return String(headers[keys[j]]);
              }
            }
          }
        } catch (_) {}
        return '';
      }
      var origOpen = XMLHttpRequest.prototype.open;
      if (typeof origOpen === 'function') {
        XMLHttpRequest.prototype.open = function(method, url) {
          try {
            this.__agReqUrl = (typeof url === 'string') ? url : String(url || '');
            this.__agReqHeaders = {};
          } catch (_) {}
          return origOpen.apply(this, arguments);
        };
      }
      var origSetHeader = XMLHttpRequest.prototype.setRequestHeader;
      if (typeof origSetHeader === 'function') {
        XMLHttpRequest.prototype.setRequestHeader = function(name, value) {
          try {
            if (typeof name === 'string') {
              var lowerName = name.toLowerCase();
              if (!this.__agReqHeaders) { this.__agReqHeaders = {}; }
              this.__agReqHeaders[lowerName] = String(value);
              if (lowerName === 'x-goog-api-key') {
                var reqUrl = this.__agReqUrl || '';
                if (isApiServiceUrl(reqUrl)) {
                  postSignal('apiServiceKey', String(value), this.__agReqHeaders['x-goog-authuser'] || '');
                } else if (!isUnrelatedTelemetryUrl(reqUrl)) {
                  postSignal('fallbackKey', String(value), this.__agReqHeaders['x-goog-authuser'] || '');
                }
              }
            }
          } catch (_) {}
          return origSetHeader.apply(this, arguments);
        };
      }
      var origSend = XMLHttpRequest.prototype.send;
      if (typeof origSend === 'function') {
        XMLHttpRequest.prototype.send = function() {
          try {
            var reqUrl = this.__agReqUrl || '';
            if (isApiServiceUrl(reqUrl)) {
              var hdrs = this.__agReqHeaders || {};
              var xhrKey = hdrs['x-goog-api-key'] || extractQueryKey(reqUrl);
              if (xhrKey) {
                postSignal('apiServiceKey', xhrKey, hdrs['x-goog-authuser'] || '');
              }
              this.addEventListener('load', function() {
                if (this.status >= 200 && this.status < 300) {
                  var h = this.__agReqHeaders || {};
                  var verifiedKey = h['x-goog-api-key'] || extractQueryKey(this.__agReqUrl || '') || window.__agApiServiceKey || '';
                  postSignal('apiServiceVerified', verifiedKey, h['x-goog-authuser'] || window.__agApiServiceAuthUser || '');
                }
              });
            }
          } catch (_) {}
          return origSend.apply(this, arguments);
        };
      }
      if (typeof window.fetch === 'function') {
        var origFetch = window.fetch;
        window.fetch = function(input, init) {
          var reqUrl = '';
          var apiKey = '';
          var authUser = '';
          try {
            reqUrl = (typeof input === 'string') ? input : ((input && input.url) ? String(input.url) : '');
            if (init && init.headers) {
              apiKey = extractHeader(init.headers, 'x-goog-api-key');
              authUser = extractHeader(init.headers, 'x-goog-authuser');
            }
            if (!apiKey && input && typeof input === 'object' && input.headers) {
              apiKey = extractHeader(input.headers, 'x-goog-api-key');
              if (!authUser) { authUser = extractHeader(input.headers, 'x-goog-authuser'); }
            }
            if (!apiKey && isApiServiceUrl(reqUrl)) {
              apiKey = extractQueryKey(reqUrl);
            }
            if (apiKey) {
              if (isApiServiceUrl(reqUrl)) {
                postSignal('apiServiceKey', apiKey, authUser);
              } else if (!isUnrelatedTelemetryUrl(reqUrl)) {
                postSignal('fallbackKey', apiKey, authUser);
              }
            }
          } catch (_) {}
          var promise = origFetch.apply(this, arguments);
          if (isApiServiceUrl(reqUrl) && promise && typeof promise.then === 'function') {
            promise.then(function(resp) {
              if (resp && resp.status >= 200 && resp.status < 300) {
                postSignal('apiServiceVerified', apiKey || window.__agApiServiceKey || '', authUser || window.__agApiServiceAuthUser || '');
              }
            }, function() {});
          }
          return promise;
        };
      }
    })();
    """

    private static let apiKeyInspectScriptSource = #"""
    (function() {
      try {
        if (typeof window.__agApiServiceKey === 'string' && window.__agApiServiceKey.length >= 8) {
          return window.__agApiServiceKey;
        }
        var meta = document.querySelector('meta[name="antigravity-relay-api-key"]');
        if (meta && meta.getAttribute('content')) {
          return meta.getAttribute('content');
        }
        var keyPattern = new RegExp("^AI" + "za[0-9A-Za-z_-]{35}$");
        var wiz = window.WIZ_global_data;
        if (wiz && typeof wiz === 'object') {
          var priorityKeys = ['WIu0Nc', 'QrtxK', 'P10xbc', 'apiKey', 'api_key', 'webApiKey'];
          for (var i = 0; i < priorityKeys.length; i++) {
            var val = wiz[priorityKeys[i]];
            if (typeof val === 'string' && keyPattern.test(val.trim())) {
              return val.trim();
            }
          }
          var allKeys = Object.keys(wiz);
          for (var j = 0; j < allKeys.length; j++) {
            var candidate = wiz[allKeys[j]];
            if (typeof candidate === 'string' && keyPattern.test(candidate.trim())) {
              return candidate.trim();
            }
          }
        }
        if (typeof window.__agCapturedRelayApiKey === 'string' && window.__agCapturedRelayApiKey.length >= 8) {
          return window.__agCapturedRelayApiKey;
        }
        var inlinePattern = new RegExp("(?:x-goog-api-key|WIu0Nc|QrtxK|P10xbc|apiKey)[\"']?\\s*[:=]\\s*[\"'](AI" + "za[0-9A-Za-z_-]{35})[\"']", "i");
        var scripts = document.scripts || [];
        for (var s = 0; s < scripts.length && s < 24; s++) {
          var text = scripts[s] && scripts[s].textContent ? scripts[s].textContent : '';
          if (text.length > 0 && text.length < 250000) {
            var m = text.match(inlinePattern);
            if (m && m[1]) {
              return m[1];
            }
          }
        }
      } catch (_) {}
      return '';
    })();
    """#

    private let initialURL: URL
    private let clearExistingSession: Bool
    var onStateChange: ((String?, String?, Bool, Bool, String?) -> Void)?
    var onAutoCapturedSession: ((String, String?, String?, String?) -> Void)?

    private var webView: WKWebView!
    private var didCompleteCapture = false
    private var isObservingCookieStore = false
    private var isReadyForAutoCapture = false
    private var verifiedApiServiceKey: String?
    private var fallbackRelayApiKey: String?
    private var capturedApiServiceAuthUser: String?
    private var didObserveApiServiceSuccess = false
    private var pendingCompletionFallbackTask: Task<Void, Never>?

    private var bestCapturedRelayApiKey: String? {
        verifiedApiServiceKey ?? fallbackRelayApiKey
    }

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
            bestCapturedRelayApiKey
        )
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor [weak self] in
            await self?.evaluateSessionReadiness(autoFinishIfOnRelayHost: true)
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor [weak self] in
            await self?.evaluateSessionReadiness(autoFinishIfOnRelayHost: true)
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor [weak self] in
            await self?.evaluateSessionReadiness(autoFinishIfOnRelayHost: true)
        }
    }

    func recordInterceptedRelaySignal(kind: String, apiKey: String?, authUser: String?) {
        if let authUser {
            let cleanUser = authUser.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleanUser.isEmpty {
                capturedApiServiceAuthUser = cleanUser
            }
        }
        if let apiKey {
            let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.count >= 8, trimmed.count <= 128 {
                let normalized = SAPISIDHashGenerator.extractWebApiKey(from: trimmed) ?? trimmed
                if kind == "apiServiceKey" || kind == "apiServiceVerified" {
                    verifiedApiServiceKey = normalized
                } else if fallbackRelayApiKey == nil {
                    fallbackRelayApiKey = normalized
                }
            }
        }
        if kind == "apiServiceVerified" {
            didObserveApiServiceSuccess = true
        }
        if kind == "apiServiceVerified" || kind == "apiServiceKey" {
            pendingCompletionFallbackTask?.cancel()
            pendingCompletionFallbackTask = nil
            Task { @MainActor [weak self] in
                // Allow WKHTTPCookieStore a brief tick to flush Set-Cookie from the verified response
                try? await Task.sleep(nanoseconds: 150_000_000)
                await self?.evaluateSessionReadiness(autoFinishIfOnRelayHost: true)
            }
        }
    }

    private func extractWebApiKeyFromWebView() async -> String? {
        if let existing = verifiedApiServiceKey, !existing.isEmpty {
            return existing
        }
        guard let raw = (try? await webView.evaluateJavaScript(Self.apiKeyInspectScriptSource)) as? String else {
            return fallbackRelayApiKey
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fallbackRelayApiKey }
        let extracted = SAPISIDHashGenerator.extractWebApiKey(from: trimmed) ?? trimmed
        if fallbackRelayApiKey == nil {
            fallbackRelayApiKey = extracted
        }
        return verifiedApiServiceKey ?? extracted
    }

    private func completeCapture(cookieHeader: String, currentURL: URL?) {
        guard !didCompleteCapture else { return }
        didCompleteCapture = true
        pendingCompletionFallbackTask?.cancel()
        pendingCompletionFallbackTask = nil
        let finalURLStr = currentURL?.absoluteString
        let parsed = finalURLStr.flatMap { RemoteHostInstance.parseRemoteControlTarget($0) }
        let resolvedAuthUser = capturedApiServiceAuthUser ?? parsed?.authUser
        onAutoCapturedSession?(cookieHeader, finalURLStr, resolvedAuthUser, bestCapturedRelayApiKey)
    }

    private func evaluateSessionReadiness(autoFinishIfOnRelayHost: Bool) async {
        guard !didCompleteCapture, isReadyForAutoCapture else { return }
        let currentURL = webView.url
        let host = currentURL?.host?.lowercased() ?? ""
        let isOnAntigravityRelay = RemoteHostInstance.isAntigravityRelayHost(host)

        let targetHost = host.isEmpty ? (initialURL.host ?? "antigravity.google.com") : host
        let cookieHeader = await CloudRelayCookieExtractor.readGoogleCookieHeader(forHost: targetHost)
        let hasCookies = (cookieHeader != nil)
        onStateChange?(
            currentURL?.host ?? initialURL.host,
            currentURL?.absoluteString,
            webView.isLoading,
            hasCookies,
            bestCapturedRelayApiKey
        )

        guard autoFinishIfOnRelayHost && isOnAntigravityRelay, let cookieHeader else {
            return
        }

        // Fast verified path: antigravity.google.com itself issued an ApiService RPC carrying X-Goog-Api-Key
        // (and completed Google's OSID redirect bounce).
        if didObserveApiServiceSuccess || verifiedApiServiceKey != nil {
            completeCapture(cookieHeader: cookieHeader, currentURL: currentURL)
            return
        }

        if pendingCompletionFallbackTask == nil {
            // Wait up to 3.5s on the relay host so Google's passive `osid=1` redirect or SPA ApiService/ListInstances
            // XHR can fire, without hanging indefinitely if a third-party analytics/font subresource keeps isLoading=true.
            pendingCompletionFallbackTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 3_500_000_000)
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
#endif
