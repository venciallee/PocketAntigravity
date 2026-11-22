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
    @State private var pendingScannedQRCode: String? = nil
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
        let isGoogleAuthExpired = store.activeHost.channel == .cloudRelay
            && (store.connectionStatusText.contains("Expired")
                || (store.connectionErrorText?.lowercased().contains("unauthorized") ?? false))

        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Settings")
                        .font(.system(size: 30, weight: .bold))
                        .tracking(-0.5)
                        .foregroundStyle(AntigravityTheme.textPrimary)
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
                                    : (isOfflinePaired
                                        ? (isGoogleAuthExpired ? AntigravityTheme.statusWaiting.opacity(0.55) : AntigravityTheme.statusError.opacity(0.50))
                                        : AntigravityTheme.cardBorder),
                                lineWidth: 1
                            )
                    )
                    .overlay(
                        VStack(spacing: 12) {
                            if store.isConnectingToBackend || store.isSwitchingHost {
                                ProgressView()
                                    .controlSize(.large)
                                    .tint(AntigravityTheme.accentPeriwinkle)
                                    .padding(.bottom, 4)

                                Text(store.isSwitchingHost ? "Switching Host..." : "Connecting to Antigravity...")
                                    .font(.system(size: 16.5, weight: .semibold))
                                    .foregroundStyle(AntigravityTheme.textPrimary)

                                Text(store.connectionStatusText)
                                    .font(.system(size: 12.5, weight: .regular))
                                    .foregroundStyle(AntigravityTheme.textSecondary)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)

                                Button {
                                    store.cancelPendingConnectionAttempt()
                                } label: {
                                    Text("Cancel")
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
                                        ? "checkmark.shield.fill"
                                        : (isOfflinePaired
                                            ? (isGoogleAuthExpired ? "person.crop.circle.badge.exclamationmark" : "wifi.slash")
                                            : "qrcode.viewfinder")
                                )
                                .font(.system(size: 48, weight: .light))
                                .foregroundStyle(
                                    isOnlineConnected
                                        ? AntigravityTheme.statusDone
                                        : (isOfflinePaired
                                            ? (isGoogleAuthExpired ? AntigravityTheme.statusWaiting : AntigravityTheme.statusError)
                                            : AntigravityTheme.accentPeriwinkle)
                                )

                                Text(
                                    isOnlineConnected
                                        ? "Connected: \(store.activeHost.hostname)"
                                        : (isNoInternet
                                            ? "No Internet Connection"
                                            : (isOfflinePaired
                                                ? (isGoogleAuthExpired ? "Google Sign-In Expired" : "Host Offline: \(store.activeHost.hostname)")
                                                : "Tap to Scan Remote Control QR"))
                                )
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(AntigravityTheme.textPrimary)
                                .multilineTextAlignment(.center)

                                let visibleSessionCount = store.summaries.filter {
                                    store.summaryMatchesHostScope($0)
                                }.count
                                Text(
                                    isOnlineConnected
                                        ? "\(store.activeHost.channel.displayName) · \(store.lastPingLatencyMs ?? store.activeHost.latencyMs)ms · \(visibleSessionCount) sessions"
                                        : (isNoInternet
                                            ? "Paused while iPhone is offline · Auto-resumes when network returns"
                                            : (isOfflinePaired
                                                ? (isGoogleAuthExpired
                                                    ? "Sign in with Google again to restore Cloud Relay sync"
                                                    : "Power-saving backoff reconnect · Tap below to retry or scan QR")
                                                : "Open Antigravity on Mac/PC → Remote Control"))
                                )
                                .font(.system(size: 13, weight: .regular))
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
                                                    Text("Sign in with Google")
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
                                        }

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

                // First-level Appearance selector (System / Dark / Light), always available even when unpaired/offline
                appearanceModeCard

                // First-level Default Permissions selector (Request Review / Default / Auto / Turbo)
                defaultPermissionsCard

                // First-level Local Notifications preferences
                notificationsCard

                // Multi-instance switcher (shown only when >1 Desktop instance is paired on the signed-in Google account)
                if store.availableRelayInstances.count > 1 {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("AVAILABLE HOSTS")
                                .font(.system(size: 11, weight: .semibold))
                                .tracking(0.7)
                                .foregroundStyle(AntigravityTheme.textMuted)
                            Spacer()
                            Button {
                                Task {
                                    await store.refreshAvailableRelayHosts(verifyEndToEnd: true)
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    if store.isRefreshingRelayHosts {
                                        ProgressView()
                                            .controlSize(.mini)
                                            .tint(AntigravityTheme.accentPeriwinkle)
                                        Text("Probing...")
                                    } else {
                                        Image(systemName: "arrow.clockwise")
                                            .font(.system(size: 10.5, weight: .semibold))
                                        Text("Refresh")
                                    }
                                }
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(AntigravityTheme.accentPeriwinkle)
                            }
                            .buttonStyle(.plain)
                            .disabled(store.isRefreshingRelayHosts)
                            .accessibilityIdentifier("btn-refresh-hosts")
                        }

                        ForEach(store.availableRelayInstances) { inst in
                            let isSelected: Bool = {
                                if case let .localHost(filterId, _) = store.selectedHostScope {
                                    return filterId == inst.uuid
                                }
                                return store.activeHost.instanceId == inst.uuid
                            }()
                            let isInstOnline = store.isDeviceNetworkReachable && inst.status.isReachable
                            let isRefreshingThisHost = store.isRefreshingHost(instanceId: inst.uuid, hostname: inst.name)
                            Button {
                                Task {
                                    let connected = await store.switchToRelayInstance(inst)
                                    if connected || (store.hasPairedBackend && store.activeHost.instanceId == inst.uuid) {
                                        onConnected?()
                                    }
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    ZStack(alignment: .topTrailing) {
                                        Image(systemName: "laptopcomputer")
                                            .font(.system(size: 16, weight: .regular))
                                            .foregroundStyle(isInstOnline ? AntigravityTheme.inkReading : AntigravityTheme.inkMuted)
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
                                            .foregroundStyle(isInstOnline ? AntigravityTheme.textPrimary : AntigravityTheme.textSecondary)
                                        let statusBadge = isInstOnline ? inst.status.badgeText : "Offline"
                                        let versionPart = inst.version.trimmingCharacters(in: .whitespacesAndNewlines)
                                        let subtitleLine = versionPart.isEmpty ? statusBadge : "\(statusBadge) · \(versionPart)"
                                        Text(subtitleLine)
                                            .font(.system(size: 11.5, weight: .regular, design: .monospaced))
                                            .foregroundStyle(isInstOnline ? AntigravityTheme.textSecondary : AntigravityTheme.statusError)
                                    }
                                    Spacer()
                                    if isRefreshingThisHost {
                                        ProgressView()
                                            .controlSize(.small)
                                            .tint(AntigravityTheme.accentPeriwinkle)
                                    } else if isSelected {
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
        .refreshable {
            if store.hasPairedBackend && !store.isVerificationMode {
                await store.refreshAvailableRelayHosts(verifyEndToEnd: true)
            }
            await store.reconnectNow(userInitiated: true)
        }
        .background(AntigravityTheme.canvasObsidian)
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
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: currentMode.sfSymbolName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AntigravityTheme.accentPeriwinkle)
                    .frame(width: 34, height: 34)
                    .background(
                        AntigravityTheme.accentPeriwinkle.opacity(0.14),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text("Appearance")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AntigravityTheme.textPrimary)
                    Text("Follow iOS or lock Dark / Light mode")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(AntigravityTheme.textSecondary)
                }

                Spacer(minLength: 8)

                Text(currentMode.displayLabel)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AntigravityTheme.accentPeriwinkle)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(AntigravityTheme.surfaceSelectionTint)
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(AntigravityTheme.accentPeriwinkle.opacity(0.28), lineWidth: 1)
                    )
            }

            HStack(spacing: 6) {
                ForEach(AppAppearanceMode.allCases) { mode in
                    let isSelected = (currentMode == mode)
                    Button {
                        store.setAppearanceMode(mode)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: mode.sfSymbolName)
                                .font(.system(size: 13.5, weight: .semibold))
                            Text(mode.displayLabel)
                                .font(.system(size: 13.5, weight: isSelected ? .semibold : .medium))
                                .lineLimit(1)
                        }
                        .foregroundStyle(
                            isSelected
                                ? AntigravityTheme.accentPeriwinkle
                                : AntigravityTheme.inkSecondary
                        )
                        .frame(maxWidth: .infinity, minHeight: AntigravityTheme.minTouchTargetPt)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(isSelected ? AntigravityTheme.surfaceSelectionTint : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(
                                    isSelected ? AntigravityTheme.accentPeriwinkle.opacity(0.55) : Color.clear,
                                    lineWidth: 1.2
                                )
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(appearanceModeAccessibilityId(for: mode))
                    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                    .accessibilityValue(isSelected ? "selected" : "unselected")
                }
            }
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(AntigravityTheme.surfaceSubtleBox)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
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
        .accessibilityIdentifier("card-appearance-mode")
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
                    Text("Permissions")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AntigravityTheme.textPrimary)
                    Text("Default policy for commands & tools")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(AntigravityTheme.textSecondary)
                }

                Spacer(minLength: 8)

                Text(selected.displayTitle)
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
                footerTextOverride: "Applies to new turns on your paired Mac/PC. Fine-grained rules are managed in Antigravity Desktop."
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
                    Text("Notifications")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AntigravityTheme.textPrimary)
                    Text("Local alerts while agents run in background")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(AntigravityTheme.textSecondary)
                }

                Spacer(minLength: 8)
            }

            VStack(spacing: 0) {
                Toggle(isOn: $store.appearancePreferences.notificationsEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Approval & Completion Alerts")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(AntigravityTheme.textPrimary)
                        Text("Notify on waiting approval, run complete, or error")
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
                        Text("Quiet on Manual Stop")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(AntigravityTheme.textPrimary)
                        Text("Skip alert when you stop a run yourself")
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
                        Text("Companion for Antigravity")
                            .font(.system(size: 12.5, weight: .regular))
                            .foregroundStyle(AntigravityTheme.textSecondary)
                    }
                }

                Rectangle()
                    .fill(AntigravityTheme.subtleDivider)
                    .frame(height: 1)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Original App Icon & Client Code © 2026 PocketAntigravity Contributors.")
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
