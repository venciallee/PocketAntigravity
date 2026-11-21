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

    public init() {
        let launchCase = DebugSceneFactory.launchVerifyCase()
        let initialStore: AntigravitySessionStore
        if let launchCase {
            initialStore = AntigravitySessionStore.makeESDDVerificationStore()
            initialStore.configureForVerifyScene(launchCase)
        } else {
            initialStore = AntigravitySessionStore.makeLiveStore()
            initialStore.prepareFastLaunchSessionState()
        }
        self._store = State(initialValue: initialStore)
        self._activeVerifyCase = State(initialValue: launchCase)
    }

    public var body: some Scene {
        WindowGroup {
            AntigravityRootContainerView(store: store, activeVerifyCase: $activeVerifyCase)
                .preferredColorScheme(resolvedColorScheme)
                .task {
                    guard activeVerifyCase == nil else {
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
                    Task {
                        await activeStore.loadPersistedV233Preferences()
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
                }
                .onChange(of: store.summaries) { _, _ in
                    guard activeVerifyCase == nil else { return }
                    LiveActivityCoordinator.shared.sync(with: store)
                }
                .onChange(of: store.lastNotificationEvent?.id) { _, _ in
                    guard activeVerifyCase == nil else { return }
                    NotificationCoordinator.shared.deliverIfNeeded(event: store.lastNotificationEvent)
                }
                .onChange(of: scenePhase) { _, newPhase in
                    guard activeVerifyCase == nil else { return }
                    switch newPhase {
                    case .background:
                        LiveActivityCoordinator.shared.sync(with: store)
                        store.suspendNetworkingForBackground()
                    case .active:
                        guard store.isNetworkingSuspended
                                || (store.isInitialSessionCheckComplete && !store.isConnectingToBackend && store.hasPairedBackend && !store.isLiveBackendConnected) else {
                            return
                        }
                        Task {
                            await store.consumePendingLiveActivityActions()
                            await store.resumeNetworkingFromForeground()
                            LiveActivityCoordinator.shared.sync(with: store)
                        }
                    case .inactive:
                        break
                    @unknown default:
                        break
                    }
                }
                #if canImport(UIKit)
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataWillBecomeUnavailableNotification)) { _ in
                    guard activeVerifyCase == nil else { return }
                    store.suspendNetworkingForBackground()
                }
                #endif
                .onOpenURL { url in
                    if let sceneCase = DebugSceneFactory.resolveDeepLink(url) {
                        if !store.isVerificationMode {
                            let verifyStore = AntigravitySessionStore.makeESDDVerificationStore()
                            verifyStore.configureForVerifyScene(sceneCase)
                            store = verifyStore
                        } else {
                            store.configureForVerifyScene(sceneCase)
                        }
                        activeVerifyCase = sceneCase
                        return
                    }
                    if url.scheme?.lowercased() == "antigravity",
                       url.host?.lowercased() == "share" {
                        let shareId = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                        Task {
                            _ = await store.consumePendingSharePayload(id: shareId.isEmpty ? nil : shareId)
                        }
                        return
                    }
                    let rawURL = url.absoluteString
                    if RemoteHostInstance.isDirectLANPairingURI(rawURL)
                        || RemoteHostInstance.parseRemoteControlTarget(rawURL) != nil {
                        activeVerifyCase = nil
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
        }
    }

    private var resolvedColorScheme: ColorScheme? {
        if let activeVerifyCase {
            return activeVerifyCase == .liveActivitySpec ? .light : .dark
        }
        switch store.appearancePreferences.theme {
        case .everforestLight:
            return .light
        case .obsidian, .nord, .everforestDark:
            return .dark
        }
    }
}
