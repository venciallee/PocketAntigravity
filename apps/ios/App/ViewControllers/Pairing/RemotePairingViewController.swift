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
    public var onDismiss: (() -> Void)?

    @State private var pendingRelayURL: String = ""
    @State private var pendingScannedQRCode: String? = nil
    @State private var isShowingQRScanner: Bool = false
    @State private var isShowingGoogleSignIn: Bool = false

    public init(
        store: AntigravitySessionStore,
        externalScannerTrigger: Binding<Bool>? = nil,
        onConnected: (() -> Void)? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        self.store = store
        self.externalScannerTrigger = externalScannerTrigger
        self.onConnected = onConnected
        self.onDismiss = onDismiss
    }

    private var displayedHosts: [RelayInstanceInfo] {
        if !store.availableRelayInstances.isEmpty {
            return store.availableRelayInstances
        }
        if store.isVerificationMode {
            return [
                RelayInstanceInfo(
                    uuid: "macbook-pro-local",
                    name: "MacBook Pro",
                    version: "2.33.1",
                    supportsChunking: true,
                    status: .connected
                ),
                RelayInstanceInfo(
                    uuid: "office-imac-local",
                    name: "Office iMac",
                    version: "2.32.0",
                    supportsChunking: true,
                    status: .disconnected
                )
            ]
        }
        return []
    }

    private var lang: AppLanguage {
        store.appearancePreferences.language
    }

    public var body: some View {
        let isNoInternet = store.hasPairedBackend && !store.isDeviceNetworkReachable
        let isOnlineConnected = store.isVerificationMode
            || (store.isDeviceNetworkReachable && store.isLiveBackendConnected && store.activeHost.isOnline)
        let isOfflinePaired = !store.isVerificationMode && store.hasPairedBackend && !isOnlineConnected
        let isGoogleAuthExpired = store.activeHost.channel == .cloudRelay
            && (store.connectionStatusText.contains("Expired")
                || (store.connectionErrorText?.lowercased().contains("unauthorized") ?? false))

        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .center) {
                        Text(lang.t("Settings", "设置"))
                            .font(.system(size: 32, weight: .bold))
                            .tracking(-0.5)
                            .foregroundStyle(AntigravityTheme.textPrimary)
                        Spacer()
                        Button {
                            if let onDismiss {
                                onDismiss()
                            } else {
                                store.activeRoute = .tabRoot
                            }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 13.5, weight: .semibold))
                                .foregroundStyle(AntigravityTheme.textPrimary)
                                .frame(width: 34, height: 34)
                                .background(Circle().fill(AntigravityTheme.surfaceElevated))
                                .frame(width: AntigravityTheme.minTouchTargetPt, height: AntigravityTheme.minTouchTargetPt)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("btn-settings-close")
                    }
                    Text(lang.t(
                        "Scan Antigravity Desktop's Remote Control QR code — works over Wi-Fi & 5G",
                        "扫描 Antigravity 桌面端的远程控制二维码 — 支持 Wi-Fi 与 5G"
                    ))
                        .font(.system(size: 13.5, weight: .regular))
                        .foregroundStyle(AntigravityTheme.textSecondary)
                }

                // 1. Primary Connection Hero Card (`ios-settings.png`)
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(AntigravityTheme.surfaceCard)
                    .frame(minHeight: 176)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .strokeBorder(
                                isOnlineConnected
                                    ? AntigravityTheme.statusDone.opacity(0.45)
                                    : (isOfflinePaired
                                        ? (isGoogleAuthExpired ? AntigravityTheme.statusWaiting.opacity(0.55) : AntigravityTheme.statusError.opacity(0.50))
                                        : AntigravityTheme.cardBorder),
                                lineWidth: 1
                            )
                    )
                    .overlay(
                        VStack(spacing: 10) {
                            if store.isConnectingToBackend || store.isSwitchingHost {
                                ProgressView()
                                    .controlSize(.large)
                                    .tint(AntigravityTheme.accentPeriwinkle)
                                    .padding(.bottom, 4)

                                Text(store.isSwitchingHost
                                    ? lang.t("Switching Host...", "正在切换主机...")
                                    : lang.t("Connecting to Antigravity...", "正在连接 Antigravity..."))
                                    .font(.system(size: 16.5, weight: .semibold))
                                    .foregroundStyle(AntigravityTheme.textPrimary)

                                Text(AppLocalizationFormatter.localizeConnectionStatus(store.connectionStatusText, language: lang))
                                    .font(.system(size: 12.5, weight: .regular))
                                    .foregroundStyle(AntigravityTheme.textSecondary)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)

                                Button {
                                    store.cancelPendingConnectionAttempt()
                                } label: {
                                    Text(lang.t("Cancel", "取消"))
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(AntigravityTheme.textSecondary)
                                        .padding(.horizontal, 16)
                                        .frame(minHeight: 34)
                                        .background(Capsule().fill(AntigravityTheme.surfacePill))
                                        .overlay(Capsule().strokeBorder(AntigravityTheme.cardBorder, lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                                .padding(.top, 2)
                                .accessibilityIdentifier("btn-cancel-connecting")
                            } else {
                                Image(
                                    systemName: isOnlineConnected
                                        ? "checkmark.shield"
                                        : (isOfflinePaired
                                            ? (isGoogleAuthExpired ? "person.crop.circle.badge.exclamationmark" : "wifi.slash")
                                            : "qrcode.viewfinder")
                                )
                                .font(.system(size: 32, weight: .medium))
                                .foregroundStyle(
                                    isOnlineConnected
                                        ? AntigravityTheme.statusDone
                                        : (isOfflinePaired
                                            ? (isGoogleAuthExpired ? AntigravityTheme.statusWaiting : AntigravityTheme.statusError)
                                            : AntigravityTheme.accentPeriwinkle)
                                )

                                Text(
                                    isOnlineConnected
                                        ? lang.t("Connected: \(store.activeHost.hostname)", "已连接：\(store.activeHost.hostname)")
                                        : (isNoInternet
                                            ? lang.t("No Internet Connection", "无网络连接")
                                            : (isOfflinePaired
                                                ? (isGoogleAuthExpired
                                                    ? lang.t("Google Sign-In Expired", "Google 登录已过期")
                                                    : lang.t("Host Offline: \(store.activeHost.hostname)", "主机离线：\(store.activeHost.hostname)"))
                                                : lang.t("Tap to Scan Remote Control QR", "轻点扫描远程控制二维码")))
                                )
                                .font(.system(size: 17.5, weight: .bold))
                                .foregroundStyle(AntigravityTheme.textPrimary)
                                .multilineTextAlignment(.center)

                                let visibleSessionCount = store.isVerificationMode
                                    ? 12
                                    : store.summaries.filter { store.summaryMatchesHostScope($0) }.count
                                let channelLabel = store.activeHost.channel == .directHost
                                    ? lang.t("Direct LAN", "局域网直连")
                                    : lang.t("Cloud Relay", "云端中继")
                                let latencyMs = store.isVerificationMode ? 42 : (store.lastPingLatencyMs ?? store.activeHost.latencyMs)
                                Text(
                                    isOnlineConnected
                                        ? lang.t(
                                            "\(channelLabel) · \(latencyMs)ms · \(visibleSessionCount) sessions",
                                            "\(channelLabel) · \(latencyMs)ms · \(visibleSessionCount) 个会话"
                                        )
                                        : (isNoInternet
                                            ? lang.t(
                                                "Paused while iPhone is offline · Auto-resumes when network returns",
                                                "iPhone 离线时已暂停 · 网络恢复后自动继续"
                                            )
                                            : (isOfflinePaired
                                                ? (isGoogleAuthExpired
                                                    ? lang.t(
                                                        "Sign in with Google again to restore Cloud Relay sync",
                                                        "请重新登录 Google 以恢复云端中继同步"
                                                    )
                                                    : lang.t(
                                                        "Power-saving backoff reconnect · Tap below to retry or scan QR",
                                                        "节能退避重连中 · 点击下方重试或重新扫码"
                                                    ))
                                                : lang.t(
                                                    "Open Antigravity on Mac/PC → Remote Control",
                                                    "在 Mac/PC 上打开 Antigravity → 远程控制"
                                                )))
                                )
                                .font(.system(size: 13.5, weight: .regular))
                                .foregroundStyle(AntigravityTheme.textSecondary)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)

                                if isOfflinePaired {
                                    HStack(spacing: 10) {
                                        if isGoogleAuthExpired {
                                            Button {
                                                let targetURL = store.lastScannedRelayURL.isEmpty
                                                    ? store.activeHost.endpointURL.absoluteString
                                                    : store.lastScannedRelayURL
                                                pendingRelayURL = targetURL
                                                isShowingGoogleSignIn = true
                                            } label: {
                                                HStack(spacing: 6) {
                                                    Image(systemName: "person.crop.circle.badge.checkmark")
                                                        .font(.system(size: 12.5, weight: .semibold))
                                                    Text(lang.t("Sign in with Google", "使用 Google 登录"))
                                                        .font(.system(size: 13, weight: .semibold))
                                                }
                                                .foregroundStyle(AntigravityTheme.inkOnPrimaryCTA)
                                                .padding(.horizontal, 14)
                                                .frame(minHeight: 36)
                                                .background(Capsule().fill(AntigravityTheme.accentPeriwinkle))
                                            }
                                            .buttonStyle(.plain)
                                            .accessibilityIdentifier("btn-settings-google-reauth")
                                        } else {
                                            Button {
                                                Task {
                                                    await store.reconnectNow(userInitiated: true)
                                                }
                                            } label: {
                                                HStack(spacing: 6) {
                                                    Image(systemName: "arrow.clockwise")
                                                        .font(.system(size: 12.5, weight: .semibold))
                                                    Text(lang.t("Reconnect Now", "立即重连"))
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
                                        }

                                        Button {
                                            isShowingQRScanner = true
                                        } label: {
                                            HStack(spacing: 6) {
                                                Image(systemName: "qrcode.viewfinder")
                                                    .font(.system(size: 12.5, weight: .semibold))
                                                Text(lang.t("Scan QR", "扫描二维码"))
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
                                        HStack(spacing: 7) {
                                            Image(systemName: "qrcode.viewfinder")
                                                .font(.system(size: 13.5, weight: .semibold))
                                            Text(lang.t("Scan New QR", "扫描新二维码"))
                                                .font(.system(size: 14, weight: .semibold))
                                        }
                                        .foregroundStyle(AntigravityTheme.textPrimary)
                                        .padding(.horizontal, 18)
                                        .frame(minHeight: 38)
                                        .background(Capsule().fill(AntigravityTheme.surfaceElevated))
                                        .overlay(Capsule().strokeBorder(AntigravityTheme.cardBorder, lineWidth: 1))
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.top, 4)
                                    .accessibilityIdentifier("btn-scan-new-qr")
                                }
                            }
                        }
                        .padding(20)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .onTapGesture {
                        if !store.isConnectingToBackend && !store.isSwitchingHost && !isOnlineConnected && !isOfflinePaired {
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

                // 2. AVAILABLE HOSTS (`ios-settings.png`)
                if !displayedHosts.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(lang.t("AVAILABLE HOSTS", "可用主机"))
                                .font(.system(size: 11.5, weight: .semibold))
                                .tracking(0.8)
                                .foregroundStyle(AntigravityTheme.textMuted)
                            Spacer()
                            Button {
                                Task {
                                    await store.refreshAvailableRelayHosts(verifyEndToEnd: true)
                                }
                            } label: {
                                HStack(spacing: 5) {
                                    if store.isRefreshingRelayHosts {
                                        ProgressView()
                                            .controlSize(.mini)
                                            .tint(AntigravityTheme.accentPeriwinkle)
                                        Text(lang.t("Probing...", "探测中..."))
                                    } else {
                                        Image(systemName: "arrow.clockwise")
                                            .font(.system(size: 11.5, weight: .semibold))
                                        Text(lang.t("Refresh", "刷新"))
                                    }
                                }
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(AntigravityTheme.accentPeriwinkle)
                            }
                            .buttonStyle(.plain)
                            .disabled(store.isRefreshingRelayHosts)
                            .accessibilityIdentifier("btn-refresh-hosts")
                        }

                        ForEach(displayedHosts) { inst in
                            let isSelected: Bool = {
                                if case let .localHost(filterId, _) = store.selectedHostScope {
                                    return filterId == inst.uuid
                                }
                                return store.activeHost.instanceId == inst.uuid
                            }()
                            let isInstOnline = (store.isVerificationMode || store.isDeviceNetworkReachable) && inst.status.isReachable
                            let isRefreshingThisHost = store.isRefreshingHost(instanceId: inst.uuid, hostname: inst.name)
                            Button {
                                if store.isVerificationMode {
                                    store.selectHostScope(.localHost(id: inst.uuid, name: inst.name))
                                } else {
                                    Task {
                                        let connected = await store.switchToRelayInstance(inst)
                                        if connected || (store.hasPairedBackend && store.activeHost.instanceId == inst.uuid) {
                                            onConnected?()
                                        }
                                    }
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    ZStack(alignment: .topTrailing) {
                                        Image(systemName: inst.name.lowercased().contains("imac") ? "desktopcomputer" : "laptopcomputer")
                                            .font(.system(size: 17, weight: .regular))
                                            .foregroundStyle(isInstOnline ? AntigravityTheme.inkReading : AntigravityTheme.inkMuted)
                                            .frame(width: 26, height: 22)
                                        ZStack {
                                            Circle()
                                                .fill(AntigravityTheme.surfaceCard)
                                                .frame(width: 11, height: 11)
                                            if isInstOnline {
                                                Circle()
                                                    .fill(AntigravityTheme.statusDone)
                                                    .frame(width: 7.5, height: 7.5)
                                            } else {
                                                Circle()
                                                    .strokeBorder(AntigravityTheme.statusError, lineWidth: 1.7)
                                                    .frame(width: 7.5, height: 7.5)
                                            }
                                        }
                                        .offset(x: 3, y: -3)
                                    }
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(inst.name)
                                            .font(.system(size: 15.5, weight: .semibold))
                                            .foregroundStyle(isInstOnline ? AntigravityTheme.textPrimary : AntigravityTheme.textSecondary)
                                        let statusBadge = isInstOnline ? lang.t("Online", "在线") : lang.t("Offline", "离线")
                                        let versionPart = inst.version.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "v", with: "")
                                        let subtitleLine = versionPart.isEmpty ? statusBadge : "\(statusBadge) · \(versionPart)"
                                        Text(subtitleLine)
                                            .font(.system(size: 12.5, weight: .regular, design: .monospaced))
                                            .foregroundStyle(isInstOnline ? AntigravityTheme.textSecondary : AntigravityTheme.statusError)
                                    }
                                    Spacer()
                                    if isRefreshingThisHost {
                                        ProgressView()
                                            .controlSize(.small)
                                            .tint(AntigravityTheme.accentPeriwinkle)
                                    } else if isSelected {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 19))
                                            .foregroundStyle(AntigravityTheme.accentPeriwinkle)
                                    }
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10.5)
                                .background(AntigravityTheme.surfaceCard)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .strokeBorder(
                                            isSelected ? AntigravityTheme.accentPeriwinkle.opacity(0.65) : AntigravityTheme.cardBorder,
                                            lineWidth: 1
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("settings-host-\(inst.uuid)")
                        }
                    }
                }

                // 3. GENERAL (`Appearance` + `Theme` + `Language`, `ios-settings.png`)
                VStack(alignment: .leading, spacing: 10) {
                    Text(lang.t("GENERAL", "通用"))
                        .font(.system(size: 11.5, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(AntigravityTheme.textMuted)

                    appearanceModeCard
                    languageCard
                }

                // 4. Permissions, Notifications, Disconnect & About (`ios-settings-more.png`)
                defaultPermissionsCard
                notificationsCard

                if store.hasPairedBackend || store.isLiveBackendConnected || store.isVerificationMode {
                    Button {
                        Task {
                            await CloudRelayCookieExtractor.clearGoogleCookies()
                            await store.disconnectBackendAndClearKeychain()
                        }
                    } label: {
                        Text(lang.t("Sign Out & Disconnect Host", "退出登录并断开主机"))
                            .font(.system(size: 14.5, weight: .semibold))
                            .foregroundStyle(AntigravityTheme.statusError)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(AntigravityTheme.statusError.opacity(0.12))
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("btn-disconnect-host")
                }

                aboutAndCopyrightCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .refreshable {
            if store.hasPairedBackend && !store.isVerificationMode {
                await store.refreshAvailableRelayHosts(verifyEndToEnd: true)
            }
            await store.reconnectNow(userInitiated: true)
        }
        .background(AntigravityTheme.canvasObsidian.ignoresSafeArea())
        .task {
            if store.hasPairedBackend && !store.isVerificationMode && store.activeHost.channel == .cloudRelay {
                await store.refreshAvailableRelayHosts(verifyEndToEnd: true)
            }
        }
        .onChange(of: externalScannerTrigger?.wrappedValue ?? false) { _, triggered in
            if triggered {
                isShowingQRScanner = true
                externalScannerTrigger?.wrappedValue = false
            }
        }
        .sheet(
            isPresented: $isShowingQRScanner,
            onDismiss: {
                if let scanned = pendingScannedQRCode {
                    pendingScannedQRCode = nil
                    handleScannedQRValue(scanned)
                }
            }
        ) {
            RemoteControlQRScannerSheet(
                onScannedQR: { scannedValue in
                    pendingScannedQRCode = scannedValue
                    isShowingQRScanner = false
                },
                onDismiss: {
                    pendingScannedQRCode = nil
                    isShowingQRScanner = false
                }
            )
        }
        .sheet(isPresented: $isShowingGoogleSignIn) {
            CloudRelaySignInSheet(
                targetRelayURLString: pendingRelayURL.isEmpty ? SAPISIDHashGenerator.defaultOrigin : pendingRelayURL,
                clearExistingSession: isGoogleAuthExpired,
                onAuthenticated: { cookieHeader, finalURL, detectedAuthUser, detectedRelayApiKey in
                    isShowingGoogleSignIn = false
                    let effectiveURL = RemoteHostInstance.resolveEffectiveRelayTarget(
                        scannedInput: pendingRelayURL,
                        webViewFinalURL: finalURL
                    )
                    Task {
                        let ok = await store.connectCloudRelay(
                            relayURLString: effectiveURL,
                            sessionCookie: cookieHeader,
                            authUser: detectedAuthUser,
                            relayApiKey: detectedRelayApiKey,
                            ignoreCachedRelayApiKey: true
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

    private var appearanceModeCard: some View {
        let currentMode = store.appearancePreferences.appearanceMode
        let currentTheme = store.appearancePreferences.theme
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "circle.lefthalf.filled")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(AntigravityTheme.textPrimary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(lang.t("Appearance", "外观"))
                        .font(.system(size: 15.5, weight: .semibold))
                        .foregroundStyle(AntigravityTheme.textPrimary)
                    Text(lang.t("Follow iOS or lock Dark / Light mode", "跟随系统或锁定深色 / 浅色模式"))
                        .font(.system(size: 12.5, weight: .regular))
                        .foregroundStyle(AntigravityTheme.textSecondary)
                }

                Spacer(minLength: 8)
            }

            HStack(spacing: 10) {
                ForEach(AppAppearanceMode.allCases) { mode in
                    let isSelected = (currentMode == mode)
                    Button {
                        store.setAppearanceMode(mode)
                    } label: {
                        VStack(spacing: 8) {
                            appearancePreviewThumbnail(for: mode)
                            Text(mode.localizedTitle(for: lang))
                                .font(.system(size: 13.5, weight: isSelected ? .semibold : .medium))
                                .foregroundStyle(isSelected ? AntigravityTheme.textPrimary : AntigravityTheme.textSecondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(isSelected ? AntigravityTheme.surfaceSelectionTint : AntigravityTheme.surfaceObsidian)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(
                                    isSelected ? AntigravityTheme.accentPeriwinkle : AntigravityTheme.cardBorder,
                                    lineWidth: isSelected ? 1.5 : 1
                                )
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(appearanceModeAccessibilityId(for: mode))
                    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                    .accessibilityValue(isSelected ? "selected" : "unselected")
                }
            }

            Divider()
                .overlay(AntigravityTheme.subtleDivider)

            // Theme Swatch Row (`Obsidian`, `Nord`, `Everforest`)
            HStack(spacing: 10) {
                Text(lang.t("Theme", "主题"))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(AntigravityTheme.textPrimary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 8)
                HStack(spacing: 12) {
                    themeSwatchButton(
                        preset: .obsidian,
                        idKey: "obsidian",
                        label: AppThemePreset.obsidian.localizedTitle(for: lang),
                        darkHalf: Color(red: 0.08, green: 0.08, blue: 0.10),
                        accentHalf: Color(red: 0.55, green: 0.72, blue: 1.0),
                        isSelected: currentTheme == .obsidian
                    )
                    themeSwatchButton(
                        preset: .nord,
                        idKey: "nord",
                        label: AppThemePreset.nord.localizedTitle(for: lang),
                        darkHalf: Color(red: 0.18, green: 0.20, blue: 0.25),
                        accentHalf: Color(red: 0.53, green: 0.75, blue: 0.82),
                        isSelected: currentTheme == .nord
                    )
                    themeSwatchButton(
                        preset: .everforestDark,
                        idKey: "everforest",
                        label: AppThemePreset.everforestDark.localizedTitle(for: lang),
                        darkHalf: Color(red: 0.18, green: 0.21, blue: 0.23),
                        accentHalf: Color(red: 0.65, green: 0.75, blue: 0.50),
                        isSelected: currentTheme == .everforestDark || currentTheme == .everforestLight
                    )
                }
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
        .accessibilityIdentifier("card-appearance-mode")
    }

    @ViewBuilder
    private func appearancePreviewThumbnail(for mode: AppAppearanceMode) -> some View {
        switch mode {
        case .system:
            HStack(spacing: 0) {
                Color(red: 0.94, green: 0.95, blue: 0.96)
                Color(red: 0.06, green: 0.06, blue: 0.08)
            }
            .frame(width: 48, height: 28)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(AntigravityTheme.cardBorder, lineWidth: 1))
        case .dark:
            ZStack(alignment: .bottomLeading) {
                Color(red: 0.08, green: 0.08, blue: 0.10)
                Capsule()
                    .fill(AntigravityTheme.accentPeriwinkle)
                    .frame(width: 22, height: 4)
                    .padding(6)
            }
            .frame(width: 48, height: 28)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(AntigravityTheme.cardBorder, lineWidth: 1))
        case .light:
            ZStack(alignment: .bottomLeading) {
                Color.white
                Capsule()
                    .fill(Color(red: 0.23, green: 0.45, blue: 0.92))
                    .frame(width: 22, height: 4)
                    .padding(6)
            }
            .frame(width: 48, height: 28)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(AntigravityTheme.cardBorder, lineWidth: 1))
        }
    }

    private func themeSwatchButton(
        preset: AppThemePreset,
        idKey: String,
        label: String,
        darkHalf: Color,
        accentHalf: Color,
        isSelected: Bool
    ) -> some View {
        Button {
            store.appearancePreferences.theme = preset
            store.saveAppearancePreferences()
        } label: {
            VStack(spacing: 5) {
                ZStack {
                    Circle()
                        .fill(darkHalf)
                    GeometryReader { geo in
                        Path { path in
                            path.move(to: CGPoint(x: geo.size.width, y: 0))
                            path.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height))
                            path.addLine(to: CGPoint(x: 0, y: geo.size.height))
                            path.closeSubpath()
                        }
                        .fill(accentHalf)
                    }
                    .clipShape(Circle())
                }
                .frame(width: 28, height: 28)
                .padding(3)
                .overlay(
                    Circle()
                        .strokeBorder(
                            isSelected ? AntigravityTheme.accentPeriwinkle : Color.clear,
                            lineWidth: 2
                        )
                )

                Text(label)
                    .font(.system(size: 11.5, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? AntigravityTheme.textPrimary : AntigravityTheme.textSecondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("theme-preset-\(idKey)")
    }

    private var languageCard: some View {
        let currentLang = store.appearancePreferences.language
        return HStack(spacing: 10) {
            Image(systemName: "globe")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(AntigravityTheme.textPrimary)
                .frame(width: 24)

            Text(lang.t("Language", "语言"))
                .font(.system(size: 15.5, weight: .semibold))
                .foregroundStyle(AntigravityTheme.textPrimary)

            Spacer(minLength: 8)

            HStack(spacing: 2) {
                ForEach(AppLanguage.allCases) { option in
                    let isSelected = (currentLang == option)
                    Button {
                        store.setAppLanguage(option)
                    } label: {
                        Text(option.displayLabel)
                            .font(.system(size: 13.5, weight: isSelected ? .semibold : .medium))
                            .foregroundStyle(isSelected ? AntigravityTheme.textPrimary : AntigravityTheme.textSecondary)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 34)
                            .background(
                                Group {
                                    if isSelected {
                                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                                            .fill(AntigravityTheme.surfaceActiveTabSlot)
                                    }
                                }
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("btn-lang-\(option.rawValue)")
                }
            }
            .padding(3)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AntigravityTheme.surfaceSubtleBox)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(AntigravityTheme.cardBorder, lineWidth: 1)
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AntigravityTheme.surfaceCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(AntigravityTheme.cardBorder, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("card-settings-language")
    }

    private func appearanceModeAccessibilityId(for mode: AppAppearanceMode) -> String {
        switch mode {
        case .system: return "appearance-mode-system"
        case .dark:   return "appearance-mode-dark"
        case .light:  return "appearance-mode-light"
        }
    }

    private var defaultPermissionsCard: some View {
        let selected = store.localPermissionPreset
        let badgeAccent: Color = (selected == .turbo) ? AntigravityTheme.statusWaiting : AntigravityTheme.accentPeriwinkle
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AntigravityTheme.accentPeriwinkle)
                    .frame(width: 34, height: 34)
                    .background(
                        AntigravityTheme.accentPeriwinkle.opacity(0.14),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(lang.t("Permissions", "权限"))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AntigravityTheme.textPrimary)
                    Text(lang.t("Default policy for commands & tools", "命令与工具的默认审批策略"))
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(AntigravityTheme.textSecondary)
                }

                Spacer(minLength: 8)

                Text(selected.localizedTitle(for: lang))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(badgeAccent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(selected == .turbo ? AntigravityTheme.surfaceAmberTint : AntigravityTheme.surfaceSelectionTint)
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(badgeAccent.opacity(0.28), lineWidth: 1)
                    )
            }

            PermissionsPresetListCard(
                store: store,
                isRemoteOverride: false,
                accessibilityIdPrefix: "settings-permission",
                footerTextOverride: lang.t(
                    "Applies to new turns on your paired Mac/PC. Fine-grained rules are managed in Antigravity Desktop.",
                    "适用于已配对 Mac/PC 上的新轮次。更细粒度的规则请在 Antigravity 桌面端中管理。"
                )
            )
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
        .accessibilityIdentifier("card-default-permissions")
    }

    private var notificationsCard: some View {
        let alertsEnabled = store.appearancePreferences.notificationsEnabled
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: alertsEnabled ? "bell.badge.fill" : "bell.slash.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(alertsEnabled ? AntigravityTheme.accentPeriwinkle : AntigravityTheme.inkMuted)
                    .frame(width: 34, height: 34)
                    .background(
                        (alertsEnabled ? AntigravityTheme.accentPeriwinkle : AntigravityTheme.inkMuted).opacity(0.14),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(lang.t("Notifications", "通知"))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AntigravityTheme.textPrimary)
                    Text(lang.t("Local alerts while agents run in background", "代理在后台运行时的本地提醒"))
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(AntigravityTheme.textSecondary)
                }

                Spacer(minLength: 8)
            }

            VStack(spacing: 0) {
                Toggle(isOn: $store.appearancePreferences.notificationsEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(lang.t("Approval & Completion Alerts", "审批与完成提醒"))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(AntigravityTheme.textPrimary)
                        Text(lang.t("Notify on waiting approval, run complete, or error", "在等待审批、运行完成或发生错误时提醒"))
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(AntigravityTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .tint(AntigravityTheme.accentPeriwinkle)
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .accessibilityIdentifier("toggle-notifications-enabled")
                .onChange(of: store.appearancePreferences.notificationsEnabled) { _, _ in
                    store.saveAppearancePreferences()
                    NotificationCoordinator.shared.requestAuthorizationIfNeeded(preferences: store.appearancePreferences)
                }

                Divider()
                    .overlay(AntigravityTheme.subtleDivider)
                    .padding(.leading, 12)

                Toggle(isOn: $store.appearancePreferences.suppressManualStopNotification) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(lang.t("Quiet on Manual Stop", "手动停止时静默"))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(AntigravityTheme.textPrimary)
                        Text(lang.t("Skip alert when you stop a run yourself", "当你主动停止运行时跳过通知"))
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(AntigravityTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .tint(AntigravityTheme.accentPeriwinkle)
                .disabled(!alertsEnabled)
                .opacity(alertsEnabled ? 1.0 : 0.45)
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .accessibilityIdentifier("toggle-notifications-suppress-manual-stop")
                .onChange(of: store.appearancePreferences.suppressManualStopNotification) { _, _ in
                    store.saveAppearancePreferences()
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AntigravityTheme.surfaceSubtleBox)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(AntigravityTheme.glassHairline, lineWidth: 1)
            )
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
        .accessibilityIdentifier("card-notifications-preferences")
    }

    private var appVersionLabel: String {
        let info = Bundle.main.infoDictionary
        let version = (info?["CFBundleShortVersionString"] as? String) ?? "2.0.0"
        let build = (info?["CFBundleVersion"] as? String) ?? "1"
        return "v\(version) (\(build))"
    }

    private var aboutAndCopyrightCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(lang.t("ABOUT & COPYRIGHT · 版权与商标声明", "关于与版权 · 版权与商标声明"))
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
                                .strokeBorder(AntigravityTheme.cardBorder, lineWidth: 1)
                        )

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text("AG Pocket")
                                .font(.system(size: 15.5, weight: .semibold))
                                .foregroundStyle(AntigravityTheme.textPrimary)
                            Text(appVersionLabel)
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundStyle(AntigravityTheme.accentPeriwinkle)
                        }
                        Text(lang.t("Companion for Antigravity", "Antigravity 移动伴侣"))
                            .font(.system(size: 12.5, weight: .regular))
                            .foregroundStyle(AntigravityTheme.textSecondary)
                    }
                }

                Rectangle()
                    .fill(AntigravityTheme.subtleDivider)
                    .frame(height: 1)

                VStack(alignment: .leading, spacing: 6) {
                    Text(lang.t(
                        "Original App Icon & Client Code © 2026 PocketAntigravity Contributors.",
                        "原创应用图标与客户端代码 © 2026 PocketAntigravity Contributors。"
                    ))
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(AntigravityTheme.textPrimary)

                    Text("AG Pocket is an independent, unofficial third-party companion client and is not affiliated with, endorsed by, or sponsored by Google LLC. \"Google\" and \"Antigravity\" are trademarks of Google LLC, referenced solely to describe compatibility with user-hosted Antigravity Desktop and Cloud instances.")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(AntigravityTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("原创 7 段轨道应用图标与客户端代码版权归 © 2026 PocketAntigravity Contributors 所有（不含任何第三方官方品牌图形资产）。“Google” 与 “Antigravity” 为 Google LLC 的商标，仅用于说明伴侣客户端兼容性，与 Google LLC 无隶属或官方背书关系。")
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

        let alreadyExpired = store.connectionStatusText.contains("Expired")
            || (store.connectionErrorText?.lowercased().contains("unauthorized") ?? false)
        if alreadyExpired {
            isShowingGoogleSignIn = true
            return
        }

        // 1. Reuse existing saved Keychain Google session cookie if already signed in and not expired
        if let cached = await store.loadSavedSessionCookie(), !cached.cookie.isEmpty {
            let ok = await store.connectCloudRelay(
                relayURLString: effectiveURL,
                sessionCookie: cached.cookie,
                authUser: cached.authUser
            )
            if ok {
                onConnected?()
                return
            }
            // If cached Google session expired (401/403), automatically present Google Sign-In
            if store.connectionStatusText.contains("Expired")
                || (store.connectionErrorText?.lowercased().contains("unauthorized") ?? false) {
                isShowingGoogleSignIn = true
            }
            return
        }

        // 2. First-time pairing -> automatically present Google Sign-In sheet (`WKWebView`)
        isShowingGoogleSignIn = true
    }
}
