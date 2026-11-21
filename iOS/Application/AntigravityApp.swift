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
                    await store.loadPersistedV233Preferences()
                    await store.consumePendingLiveActivityActions()
                    let env = ProcessInfo.processInfo.environment
                    if let relayURL = env["ANTIGRAVITY_RELAY_URL"], !relayURL.isEmpty {
                        let cookie = env["ANTIGRAVITY_RELAY_COOKIE"] ?? ""
                        let authUser = env["ANTIGRAVITY_AUTHUSER"]
                        _ = await store.connectCloudRelay(
                            relayURLString: relayURL,
                            sessionCookie: cookie,
                            authUser: authUser,
                            hostName: env["ANTIGRAVITY_HOST_NAME"] ?? "Antigravity Desktop"
                        )
                    } else if let backendURL = env["ANTIGRAVITY_BACKEND_URL"], !backendURL.isEmpty {
                        let csrf = env["ANTIGRAVITY_CSRF_TOKEN"] ?? ""
                        let sha256 = env["ANTIGRAVITY_CERT_SHA256"]
                        _ = await store.connectDirectLAN(
                            endpointURLString: backendURL,
                            csrfToken: csrf,
                            certSHA256: sha256,
                            hostName: env["ANTIGRAVITY_HOST_NAME"] ?? "MacBook Pro"
                        )
                    } else {
                        _ = await store.restoreSavedBackendSession()
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
                        guard store.isInitialSessionCheckComplete || store.isNetworkingSuspended else { return }
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
                        Task {
                            let webCookie = await CloudRelayCookieExtractor.readGoogleCookieHeader() ?? ""
                            let ok = await store.connectWithPairingURI(rawURL, fallbackCookie: webCookie)
                            if ok {
                                if case .cascadeChat = store.activeRoute {
                                    // Keep deep-linked conversation open (`?p=c%2F<cascadeId>`)
                                } else {
                                    store.activeRoute = .tabRoot
                                }
                            } else {
                                store.activeRoute = .pairingSettings
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
