import SwiftUI
import AntigravityData
#if canImport(UIKit)
import UIKit
#endif

/// Minimalist Settings & Remote Control pairing screen (`RemotePairingViewController`).
/// Pairs directly by scanning Antigravity Desktop's official Remote Control QR code (`https://antigravity.google.com/r/<id>`)
/// over Google Cloud Relay across Wi-Fi & 5G.
public struct RemotePairingViewController: View {
    @Bindable public var store: AntigravitySessionStore
    public var externalScannerTrigger: Binding<Bool>?
    public var onConnected: (() -> Void)?

    @State private var pendingRelayURL: String = ""
    @State private var isShowingQRScanner: Bool = false
    @State private var isShowingGoogleSignIn: Bool = false

    public init(
        store: AntigravitySessionStore,
        externalScannerTrigger: Binding<Bool>? = nil,
        onConnected: (() -> Void)? = nil
    ) {
        self.store = store
        self.externalScannerTrigger = externalScannerTrigger
        self.onConnected = onConnected
    }

    public var body: some View {
        let isNoInternet = store.hasPairedBackend && !store.isDeviceNetworkReachable
        let isOnlineConnected = store.isDeviceNetworkReachable && store.isLiveBackendConnected && store.activeHost.isOnline
        let isOfflinePaired = store.hasPairedBackend && !isOnlineConnected

        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Settings")
                        .font(.system(size: 30, weight: .bold))
                        .tracking(-0.5)
                        .foregroundStyle(Color.white)
                    Text("Scan Antigravity Desktop's Remote Control QR code — works over Wi-Fi & 5G")
                        .font(.system(size: 13.5, weight: .regular))
                        .foregroundStyle(AntigravityTheme.textSecondary)
                }

                // Single Primary Card: Tap to Scan Remote Control QR (or Live Connection Status)
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(AntigravityTheme.surfaceCard)
                    .frame(minHeight: 236)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .strokeBorder(
                                isOnlineConnected
                                    ? AntigravityTheme.statusDone.opacity(0.45)
                                    : (isOfflinePaired ? AntigravityTheme.statusError.opacity(0.50) : AntigravityTheme.cardBorder),
                                lineWidth: 1
                            )
                    )
                    .overlay(
                        VStack(spacing: 12) {
                            if store.isConnectingToBackend {
                                ProgressView()
                                    .controlSize(.large)
                                    .tint(AntigravityTheme.accentPeriwinkle)
                                    .padding(.bottom, 4)

                                Text("Connecting to Antigravity...")
                                    .font(.system(size: 16.5, weight: .semibold))
                                    .foregroundStyle(Color.white)

                                Text(store.connectionStatusText)
                                    .font(.system(size: 12.5, weight: .regular))
                                    .foregroundStyle(AntigravityTheme.textSecondary)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                            } else {
                                Image(
                                    systemName: isOnlineConnected
                                        ? "checkmark.shield.fill"
                                        : (isOfflinePaired ? "wifi.slash" : "qrcode.viewfinder")
                                )
                                .font(.system(size: 48, weight: .light))
                                .foregroundStyle(
                                    isOnlineConnected
                                        ? AntigravityTheme.statusDone
                                        : (isOfflinePaired ? AntigravityTheme.statusError : AntigravityTheme.accentPeriwinkle)
                                )

                                Text(
                                    isOnlineConnected
                                        ? "Connected: \(store.activeHost.hostname)"
                                        : (isNoInternet
                                            ? "No Internet Connection"
                                            : (isOfflinePaired ? "Host Offline: \(store.activeHost.hostname)" : "Tap to Scan Remote Control QR"))
                                )
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(Color.white)
                                .multilineTextAlignment(.center)

                                Text(
                                    isOnlineConnected
                                        ? "\(store.activeHost.channel.displayName) · \(store.lastPingLatencyMs ?? store.activeHost.latencyMs)ms · \(store.summaries.count) sessions"
                                        : (isNoInternet
                                            ? "Paused while iPhone is offline · Auto-resumes when network returns"
                                            : (isOfflinePaired
                                                ? "Power-saving backoff reconnect · Tap below to retry or scan QR"
                                                : "Open Antigravity on Mac/PC → Remote Control"))
                                )
                                .font(.system(size: 13, weight: .regular))
                                .foregroundStyle(AntigravityTheme.textSecondary)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)

                                if isOfflinePaired {
                                    HStack(spacing: 10) {
                                        Button {
                                            Task {
                                                await store.reconnectNow(userInitiated: true)
                                            }
                                        } label: {
                                            HStack(spacing: 6) {
                                                Image(systemName: "arrow.clockwise")
                                                    .font(.system(size: 12.5, weight: .semibold))
                                                Text("Reconnect Now")
                                                    .font(.system(size: 13, weight: .semibold))
                                            }
                                            .foregroundStyle(AntigravityTheme.accentPeriwinkle)
                                            .padding(.horizontal, 14)
                                            .frame(minHeight: 36)
                                            .background(Capsule().fill(AntigravityTheme.surfacePill))
                                            .overlay(Capsule().strokeBorder(AntigravityTheme.cardBorder, lineWidth: 1))
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityIdentifier("btn-retry-connection")

                                        Button {
                                            isShowingQRScanner = true
                                        } label: {
                                            HStack(spacing: 6) {
                                                Image(systemName: "qrcode.viewfinder")
                                                    .font(.system(size: 12.5, weight: .semibold))
                                                Text("Scan QR")
                                                    .font(.system(size: 13, weight: .semibold))
                                            }
                                            .foregroundStyle(AntigravityTheme.textPrimary)
                                            .padding(.horizontal, 14)
                                            .frame(minHeight: 36)
                                            .background(Capsule().fill(AntigravityTheme.surfacePill))
                                            .overlay(Capsule().strokeBorder(AntigravityTheme.cardBorder, lineWidth: 1))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.top, 2)
                                } else if isOnlineConnected {
                                    Button {
                                        isShowingQRScanner = true
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: "qrcode.viewfinder")
                                                .font(.system(size: 12.5, weight: .semibold))
                                            Text("Scan New QR")
                                                .font(.system(size: 13, weight: .semibold))
                                        }
                                        .foregroundStyle(AntigravityTheme.accentPeriwinkle)
                                        .padding(.horizontal, 14)
                                        .frame(minHeight: 36)
                                        .background(Capsule().fill(AntigravityTheme.surfacePill))
                                        .overlay(Capsule().strokeBorder(AntigravityTheme.cardBorder, lineWidth: 1))
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.top, 2)
                                }
                            }
                        }
                        .padding(24)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .onTapGesture {
                        if !store.isConnectingToBackend && !isOnlineConnected && !isOfflinePaired {
                            isShowingQRScanner = true
                        }
                    }
                    .accessibilityIdentifier("qr-viewfinder")

                if let errorText = store.connectionErrorText, !errorText.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(AntigravityTheme.statusError)
                        Text(errorText)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(AntigravityTheme.statusError)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AntigravityTheme.statusError.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                // Antigravity 2.0 (v2.33) Permissions, Customizations Hub & Appearance Card
                Button {
                    store.presentedSheet = .customizationsSettings
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(AntigravityTheme.accentPeriwinkle)
                            .frame(width: 38, height: 38)
                            .background(AntigravityTheme.accentPeriwinkle.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Permissions, Customizations & Layout")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Color.white)
                            Text("\(store.appearancePreferences.globalPermissionPreset.rawValue) · \(store.customizations.plugins.filter(\.isInstalled).count) plugins · \(store.appearancePreferences.interfaceLayout.rawValue)")
                                .font(.system(size: 12.5))
                                .foregroundStyle(AntigravityTheme.textSecondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AntigravityTheme.textMuted)
                    }
                    .padding(14)
                    .background(AntigravityTheme.surfaceCard, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(AntigravityTheme.cardBorder, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("btn-open-customizations-settings")

                // Multi-instance switcher (shown only when >1 Desktop instance is online on the signed-in Google account)
                if store.availableRelayInstances.count > 1 {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("AVAILABLE HOSTS")
                            .font(.system(size: 11, weight: .semibold))
                            .tracking(0.7)
                            .foregroundStyle(AntigravityTheme.textMuted)

                        ForEach(store.availableRelayInstances) { inst in
                            let isSelected = (store.activeHost.instanceId == inst.uuid)
                            let isInstOnline = store.isDeviceNetworkReachable && inst.status.isReachable
                            Button {
                                Task {
                                    if let cached = await store.loadSavedSessionCookie() {
                                        let ok = await store.connectCloudRelay(
                                            relayURLString: "https://antigravity.google.com/r/\(inst.uuid)",
                                            sessionCookie: cached.cookie,
                                            authUser: store.activeAuthUser,
                                            resolvedInstanceUuid: inst.uuid,
                                            hostName: inst.name
                                        )
                                        if ok {
                                            onConnected?()
                                        }
                                    }
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    ZStack(alignment: .topTrailing) {
                                        Image(systemName: "laptopcomputer")
                                            .font(.system(size: 16, weight: .regular))
                                            .foregroundStyle(isInstOnline ? Color.white.opacity(0.94) : Color.white.opacity(0.45))
                                            .frame(width: 24, height: 20)
                                        ZStack {
                                            Circle()
                                                .fill(AntigravityTheme.surfaceCard)
                                                .frame(width: 10, height: 10)
                                            if isInstOnline {
                                                Circle()
                                                    .fill(AntigravityTheme.statusDone)
                                                    .frame(width: 6.5, height: 6.5)
                                            } else {
                                                Circle()
                                                    .strokeBorder(AntigravityTheme.statusError, lineWidth: 1.5)
                                                    .frame(width: 6.5, height: 6.5)
                                            }
                                        }
                                        .offset(x: 2, y: -2)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(inst.name)
                                            .font(.system(size: 14.5, weight: .semibold))
                                            .foregroundStyle(isInstOnline ? Color.white : AntigravityTheme.textSecondary)
                                        Text("\(isInstOnline ? inst.status.badgeText : "Offline") · \(inst.version)")
                                            .font(.system(size: 11.5, weight: .regular, design: .monospaced))
                                            .foregroundStyle(AntigravityTheme.textSecondary)
                                    }
                                    Spacer()
                                    if isSelected {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(AntigravityTheme.accentPeriwinkle)
                                    }
                                }
                                .padding(12)
                                .background(AntigravityTheme.surfaceCard)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .strokeBorder(
                                            isSelected ? AntigravityTheme.accentPeriwinkle.opacity(0.5) : AntigravityTheme.cardBorder,
                                            lineWidth: 1
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if store.hasPairedBackend || store.isLiveBackendConnected {
                    Button {
                        Task {
                            await CloudRelayCookieExtractor.clearGoogleCookies()
                            await store.disconnectBackendAndClearKeychain()
                        }
                    } label: {
                        Text("Sign Out & Disconnect Host")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AntigravityTheme.statusError)
                            .frame(maxWidth: .infinity, minHeight: AntigravityTheme.minTouchTargetPt)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(AntigravityTheme.statusError.opacity(0.10))
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("btn-disconnect-host")
                }

                aboutAndCopyrightCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .background(AntigravityTheme.canvasObsidian)
        .onChange(of: externalScannerTrigger?.wrappedValue ?? false) { _, triggered in
            if triggered {
                isShowingQRScanner = true
                externalScannerTrigger?.wrappedValue = false
            }
        }
        .sheet(isPresented: $isShowingQRScanner) {
            RemoteControlQRScannerSheet(
                onScannedQR: { scannedValue in
                    isShowingQRScanner = false
                    handleScannedQRValue(scannedValue)
                },
                onDismiss: {
                    isShowingQRScanner = false
                }
            )
        }
        .sheet(isPresented: $isShowingGoogleSignIn) {
            CloudRelaySignInSheet(
                targetRelayURLString: pendingRelayURL.isEmpty ? SAPISIDHashGenerator.defaultOrigin : pendingRelayURL,
                onAuthenticated: { cookieHeader, finalURL, detectedAuthUser in
                    isShowingGoogleSignIn = false
                    let effectiveURL = RemoteHostInstance.resolveEffectiveRelayTarget(
                        scannedInput: pendingRelayURL,
                        webViewFinalURL: finalURL
                    )
                    Task {
                        let ok = await store.connectCloudRelay(
                            relayURLString: effectiveURL,
                            sessionCookie: cookieHeader,
                            authUser: detectedAuthUser
                        )
                        if ok {
                            onConnected?()
                        }
                    }
                },
                onDismiss: {
                    isShowingGoogleSignIn = false
                }
            )
        }
    }

    private var appVersionLabel: String {
        let info = Bundle.main.infoDictionary
        let version = (info?["CFBundleShortVersionString"] as? String) ?? "2.0.0"
        let build = (info?["CFBundleVersion"] as? String) ?? "1"
        return "v\(version) (\(build))"
    }

    private var aboutAndCopyrightCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ABOUT & COPYRIGHT · 版权与商标声明")
                .font(.system(size: 11.5, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(AntigravityTheme.textMuted)

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    appIconBadgeView
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                        )

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text("AG Orbit")
                                .font(.system(size: 15.5, weight: .semibold))
                                .foregroundStyle(Color.white)
                            Text(appVersionLabel)
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundStyle(AntigravityTheme.accentPeriwinkle)
                        }
                        Text("Companion for Antigravity")
                            .font(.system(size: 12.5, weight: .regular))
                            .foregroundStyle(AntigravityTheme.textSecondary)
                    }
                }

                Rectangle()
                    .fill(AntigravityTheme.subtleDivider)
                    .frame(height: 1)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Original App Icon & Client Code © 2026 iOSAntigravity Contributors.")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(AntigravityTheme.textPrimary)

                    Text("AG Orbit is an independent, unofficial third-party companion client and is not affiliated with, endorsed by, or sponsored by Google LLC. \"Google\" and \"Antigravity\" are trademarks of Google LLC, referenced solely to describe compatibility with user-hosted Antigravity Desktop and Cloud instances.")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(AntigravityTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("原创 7 段轨道应用图标与客户端代码版权归 © 2026 iOSAntigravity Contributors 所有（不含任何第三方官方品牌图形资产）。“Google” 与 “Antigravity” 为 Google LLC 的商标，仅用于说明伴侣客户端兼容性，与 Google LLC 无隶属或官方背书关系。")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(AntigravityTheme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(AntigravityTheme.surfaceCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(AntigravityTheme.cardBorder, lineWidth: 1)
            )
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("card-about-copyright")
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private var appIconBadgeView: some View {
        #if canImport(UIKit)
        if let uiImage = UIImage(named: "AntigravityAppIconPreview") {
            Image(uiImage: uiImage)
                .resizable()
                .interpolation(.high)
                .scaledToFill()
        } else {
            fallbackBrandGlyphBadge
        }
        #else
        fallbackBrandGlyphBadge
        #endif
    }

    private var fallbackBrandGlyphBadge: some View {
        ZStack {
            AntigravityTheme.surfaceElevated
            Image(systemName: "terminal")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(AntigravityTheme.accentPeriwinkle)
        }
    }

    private func handleScannedQRValue(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if RemoteHostInstance.isDirectLANPairingURI(trimmed) {
            Task {
                let ok = await store.connectWithPairingURI(trimmed, fallbackCookie: "")
                if ok {
                    onConnected?()
                }
            }
            return
        }
        pendingRelayURL = trimmed
        Task {
            await initiateCloudRelayConnection(targetInput: trimmed)
        }
    }

    private func initiateCloudRelayConnection(targetInput: String) async {
        let target = targetInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveURL = target.isEmpty ? SAPISIDHashGenerator.defaultOrigin : target

        // 1. Reuse existing Keychain or WKWebsiteDataStore Google session cookie if already signed in
        var existingCookie: String? = nil
        var savedAuthUser: String? = nil
        if let cached = await store.loadSavedSessionCookie() {
            existingCookie = cached.cookie
            savedAuthUser = cached.authUser
        } else if let webKitCookie = await CloudRelayCookieExtractor.readGoogleCookieHeader() {
            existingCookie = webKitCookie
        }

        if let existingCookie, !existingCookie.isEmpty {
            let ok = await store.connectCloudRelay(
                relayURLString: effectiveURL,
                sessionCookie: existingCookie,
                authUser: savedAuthUser
            )
            if ok {
                onConnected?()
                return
            }
            // If cached Google session expired (401/403), automatically present Google Sign-In
            if store.connectionStatusText.contains("Expired") {
                isShowingGoogleSignIn = true
            }
            return
        }

        // 2. First-time pairing -> automatically present Google Sign-In sheet (`WKWebView`)
        isShowingGoogleSignIn = true
    }
}
