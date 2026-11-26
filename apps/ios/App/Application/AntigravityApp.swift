import SwiftUI
import AntigravityData
#if canImport(UIKit)
import UIKit
#endif

@main
public struct AntigravityApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var store: AntigravitySessionStore
    @State private var activeVerifyCase: ESDDVerifySceneCase?
    @State private var launchAppearanceOverride: AppAppearanceMode?

    public init() {
        let launchCase = DebugSceneFactory.launchVerifyCase()
        let isSettingsVerify = DebugSceneFactory.isVerifySettingsLaunch()
        let appearanceOverride = DebugSceneFactory.launchAppearanceOverride()
        let initialStore: AntigravitySessionStore
        if let launchCase {
            initialStore = AntigravitySessionStore.makeESDDVerificationStore()
            initialStore.configureForVerifyScene(launchCase)
        } else if isSettingsVerify {
            initialStore = AntigravitySessionStore.makeESDDVerificationStore()
            initialStore.selectedTab = .settings
            initialStore.activeRoute = .pairingSettings
            initialStore.isInitialSessionCheckComplete = true
        } else {
            initialStore = AntigravitySessionStore.makeLiveStore()
            initialStore.prepareFastLaunchSessionState()
        }
        if let appearanceOverride {
            initialStore.appearancePreferences.appearanceMode = appearanceOverride
        }
        self._store = State(initialValue: initialStore)
        self._activeVerifyCase = State(initialValue: launchCase)
        self._launchAppearanceOverride = State(initialValue: appearanceOverride)
    }

    public var body: some Scene {
        WindowGroup {
            AntigravityRootContainerView(store: store, activeVerifyCase: $activeVerifyCase)
                .environment(\.appLanguage, store.appearancePreferences.language)
                .environment(\.locale, Locale(identifier: store.appearancePreferences.language.localeIdentifier))
                .preferredColorScheme(resolvedColorScheme)
                .onAppear {
                    applyUIKitWindowInterfaceStyle(resolvedColorScheme)
                }
                .onChange(of: resolvedColorScheme) { _, newScheme in
                    applyUIKitWindowInterfaceStyle(newScheme)
                }
                .task {
                    await performInitialLaunchTask()
                }
                .modifier(WatchCompanionSyncModifier(store: store, isVerifyMode: activeVerifyCase != nil))
                .onChange(of: scenePhase) { _, newPhase in
                    handleScenePhaseChange(newPhase)
                }
                #if canImport(UIKit)
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataWillBecomeUnavailableNotification)) { _ in
                    guard activeVerifyCase == nil else { return }
                    store.suspendNetworkingForBackground()
                }
                #endif
                .onOpenURL { url in
                    handleOpenURL(url)
                }
        }
    }

    @MainActor
    private func performInitialLaunchTask() async {
        guard activeVerifyCase == nil && !store.isVerificationMode else {
            store.isInitialSessionCheckComplete = true
            return
        }
        defer {
            store.isInitialSessionCheckComplete = true
        }
        // Initialize Kotlin/Native KMP coordinator off the main thread in parallel with
        // instant disk hydration so UILaunchScreen & Frame 0 enter Conversations immediately.
        let kmpInitTask: Task<(any AntigravityKmpEnginePort)?, Never>? = (store.kmpEngine == nil)
            ? Task.detached(priority: .userInitiated) {
                KmpCoreEngineAdapter.makeDefault()
            }
            : nil

        // Load non-critical preferences & pending Live Activity actions concurrently so they
        // never delay entering Conversations or restoring cached sessions.
        let activeStore = store
        let appearanceOverride = launchAppearanceOverride
        Task {
            await activeStore.loadPersistedV233Preferences()
            if let appearanceOverride {
                activeStore.appearancePreferences.appearanceMode = appearanceOverride
            }
            await activeStore.consumePendingLiveActivityActions()
        }
        let env = ProcessInfo.processInfo.environment
        if let relayURL = env["ANTIGRAVITY_RELAY_URL"], !relayURL.isEmpty {
            let cookie = env["ANTIGRAVITY_RELAY_COOKIE"] ?? ""
            let authUser = env["ANTIGRAVITY_AUTHUSER"]
            let relayApiKey = env[SAPISIDHashGenerator.relayApiKeyEnvVarName]
            if store.kmpEngine == nil, let kmpInitTask {
                store.kmpEngine = await kmpInitTask.value
            }
            _ = await store.connectCloudRelay(
                relayURLString: relayURL,
                sessionCookie: cookie,
                authUser: authUser,
                relayApiKey: relayApiKey,
                hostName: env["ANTIGRAVITY_HOST_NAME"] ?? "Antigravity Desktop"
            )
        } else if let backendURL = env["ANTIGRAVITY_BACKEND_URL"], !backendURL.isEmpty {
            let csrf = env["ANTIGRAVITY_CSRF_TOKEN"] ?? ""
            let sha256 = env["ANTIGRAVITY_CERT_SHA256"]
            if store.kmpEngine == nil, let kmpInitTask {
                store.kmpEngine = await kmpInitTask.value
            }
            _ = await store.connectDirectLAN(
                endpointURLString: backendURL,
                csrfToken: csrf,
                certSHA256: sha256,
                hostName: env["ANTIGRAVITY_HOST_NAME"] ?? "MacBook Pro"
            )
        } else if let saved = await store.hydrateSavedSessionFromDisk() {
            if store.kmpEngine == nil, let kmpInitTask {
                store.kmpEngine = await kmpInitTask.value
            }
            _ = await store.connectSavedCredentials(saved)
        } else if store.kmpEngine == nil, let kmpInitTask {
            Task {
                if activeStore.kmpEngine == nil {
                    activeStore.kmpEngine = await kmpInitTask.value
                }
            }
        }
        LiveActivityCoordinator.shared.sync(with: store)
        NotificationCoordinator.shared.attach(store: store)
        WatchConnectivityBridge.shared.attach(store: store)
    }

    @MainActor
    private func handleScenePhaseChange(_ newPhase: ScenePhase) {
        guard activeVerifyCase == nil else { return }
        switch newPhase {
        case .background:
            LiveActivityCoordinator.shared.sync(with: store)
            WatchConnectivityBridge.shared.sync(with: store, immediate: true)
            store.suspendNetworkingForBackground()
        case .active:
            applyUIKitWindowInterfaceStyle(resolvedColorScheme)
            guard store.isNetworkingSuspended
                    || (store.isInitialSessionCheckComplete && !store.isConnectingToBackend && store.hasPairedBackend && !store.isLiveBackendConnected) else {
                return
            }
            let activeStore = store
            Task {
                await activeStore.consumePendingLiveActivityActions()
                await activeStore.resumeNetworkingFromForeground()
                LiveActivityCoordinator.shared.sync(with: activeStore)
                WatchConnectivityBridge.shared.sync(with: activeStore, immediate: true)
            }
        case .inactive:
            break
        @unknown default:
            break
        }
    }

    @MainActor
    private func handleOpenURL(_ url: URL) {
        if let sceneCase = DebugSceneFactory.resolveDeepLink(url) {
            let deepLinkAppearance = DebugSceneFactory.resolveDeepLinkAppearance(url)
            if !store.isVerificationMode {
                let verifyStore = AntigravitySessionStore.makeESDDVerificationStore()
                verifyStore.configureForVerifyScene(sceneCase)
                if let deepLinkAppearance {
                    verifyStore.appearancePreferences.appearanceMode = deepLinkAppearance
                }
                store = verifyStore
            } else {
                store.configureForVerifyScene(sceneCase)
                if let deepLinkAppearance {
                    store.appearancePreferences.appearanceMode = deepLinkAppearance
                }
            }
            launchAppearanceOverride = deepLinkAppearance
            activeVerifyCase = sceneCase
            return
        }
        if let scheme = url.scheme?.lowercased(),
           (scheme == "agpocket" || scheme == "antigravity"),
           let host = url.host?.lowercased() {
            let pathId = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            switch host {
            case "share":
                let activeStore = store
                Task {
                    _ = await activeStore.consumePendingSharePayload(id: pathId.isEmpty ? nil : pathId)
                }
                return
            case "cascade", "c":
                if !pathId.isEmpty {
                    store.selectCascade(pathId)
                }
                return
            case "changes", "diff":
                if !pathId.isEmpty {
                    store.selectCascade(pathId)
                }
                store.activeRoute = .turnDiffReview
                return
            case "artifact", "plan":
                if !pathId.isEmpty {
                    store.selectCascade(pathId)
                }
                store.activeRoute = .planReview
                return
            default:
                break
            }
        }
        let rawURL = url.absoluteString
        if RemoteHostInstance.isDirectLANPairingURI(rawURL)
            || RemoteHostInstance.parseRemoteControlTarget(rawURL) != nil {
            activeVerifyCase = nil
            launchAppearanceOverride = nil
            if store.isVerificationMode {
                let liveStore = AntigravitySessionStore.makeLiveStore()
                liveStore.isInitialSessionCheckComplete = true
                store = liveStore
            }
            let activeStore = store
            if RemoteHostInstance.isDirectLANPairingURI(rawURL),
               let comps = URLComponents(string: rawURL),
               let targetURL = comps.queryItems?.first(where: { $0.name == "url" })?.value {
                let name = comps.queryItems?.first(where: { $0.name == "name" })?.value ?? "MacBook Pro"
                activeStore.beginOptimisticConnectingSession(
                    hostName: name,
                    channel: .directHost,
                    endpointURLString: targetURL
                )
            } else if let target = RemoteHostInstance.parseRemoteControlTarget(rawURL) {
                let displayHost = target.instanceId.isEmpty ? "Antigravity Desktop" : target.instanceId
                activeStore.beginOptimisticConnectingSession(
                    hostName: displayHost,
                    channel: .cloudRelay,
                    endpointURLString: target.canonicalRelayURLString,
                    instanceId: target.instanceId,
                    deepLinkedConversationId: target.conversationId
                )
            }
            Task {
                if activeStore.kmpEngine == nil {
                    activeStore.kmpEngine = await Task.detached(priority: .userInitiated) {
                        KmpCoreEngineAdapter.makeDefault()
                    }.value
                }
                let webCookie = await CloudRelayCookieExtractor.readGoogleCookieHeader() ?? ""
                let ok = await activeStore.connectWithPairingURI(rawURL, fallbackCookie: webCookie)
                if ok {
                    if case .cascadeChat = activeStore.activeRoute {
                        // Keep deep-linked conversation open (`?p=c%2F<cascadeId>`)
                    } else {
                        activeStore.activeRoute = .tabRoot
                    }
                } else if activeStore.hasPairedBackend {
                    activeStore.activeRoute = .pairingSettings
                }
            }
        }
    }

    private var resolvedColorScheme: ColorScheme? {
        if let activeVerifyCase {
            if let overrideMode = launchAppearanceOverride {
                return colorScheme(for: overrideMode)
            }
            return activeVerifyCase == .liveActivitySpec ? .light : .dark
        }
        return colorScheme(for: store.appearancePreferences.appearanceMode)
    }

    private func colorScheme(for mode: AppAppearanceMode) -> ColorScheme? {
        switch mode {
        case .system:
            return nil
        case .dark:
            return .dark
        case .light:
            return .light
        }
    }

    private func applyUIKitWindowInterfaceStyle(_ scheme: ColorScheme?) {
        #if canImport(UIKit)
        let style: UIUserInterfaceStyle
        switch scheme {
        case .dark:
            style = .dark
        case .light:
            style = .light
        case nil:
            style = .unspecified
        @unknown default:
            style = .unspecified
        }
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows where window.overrideUserInterfaceStyle != style {
                window.overrideUserInterfaceStyle = style
            }
        }
        #endif
    }
}

private struct WatchCompanionSyncModifier: ViewModifier {
    let store: AntigravitySessionStore
    let isVerifyMode: Bool

    func body(content: Content) -> some View {
        content
            .onChange(of: store.summaries) { _, _ in
                guard !isVerifyMode else { return }
                LiveActivityCoordinator.shared.sync(with: store)
                WatchConnectivityBridge.shared.sync(with: store)
            }
            .onChange(of: store.activeHost) { _, _ in
                guard !isVerifyMode else { return }
                WatchConnectivityBridge.shared.sync(with: store)
            }
            .onChange(of: store.selectedHostScope) { _, _ in
                guard !isVerifyMode else { return }
                WatchConnectivityBridge.shared.sync(with: store)
            }
            .onChange(of: store.activeTurnDiffs.count) { _, _ in
                guard !isVerifyMode else { return }
                WatchConnectivityBridge.shared.sync(with: store)
            }
            .onChange(of: store.lastNotificationEvent?.id) { _, _ in
                guard !isVerifyMode else { return }
                NotificationCoordinator.shared.deliverIfNeeded(event: store.lastNotificationEvent, store: store)
                WatchConnectivityBridge.shared.sync(with: store, immediate: true)
            }
            .onContinueUserActivity(WatchConnectivityCodec.handoffActivityType) { activity in
                guard !isVerifyMode else { return }
                if let userInfo = activity.userInfo {
                    WatchConnectivityBridge.shared.handleHandoffUserInfo(userInfo, in: store)
                }
            }
    }
}
