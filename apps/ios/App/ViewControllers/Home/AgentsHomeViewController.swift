import SwiftUI
import AntigravityData
#if canImport(UIKit)
import UIKit
#endif

/// State `UE01_AGENTS_HOME`: Minimalist New Conversation Home (`docs/ue/ios/Main.png`).
/// - Top bar: Left sidebar trigger (`btn-sidebar`), centered Host Switcher capsule (`host-switcher-pill`),
///   right Global Search trigger (`btn-global-search`).
/// - Center: Hero greeting (`Welcome back, Alex. Where should we pick up?`).
/// - Bottom: Compact amber `Needs approval` banner (when an agent awaits approval) + docked outer
///   project/branch/runtime selector wrapping `ChatComposerView`.
public struct AgentsHomeViewController: View {
    @Bindable public var store: AntigravitySessionStore
    @Environment(\.displayScale) private var displayScale
    @Environment(\.colorScheme) private var colorScheme

    public var onSelectTab: ((ShellTab) -> Void)?
    public var onOpenSidebar: (() -> Void)?
    public var onOpenDisplayOptions: (() -> Void)?
    public var onOpenNewProject: (() -> Void)?
    public var onOpenProjectDetail: ((String) -> Void)?
    public var onOpenContextMenuPreview: (() -> Void)?
    public var onOpenConversation: ((String) -> Void)?
    public var onOpenSettings: (() -> Void)?

    public typealias HostFilterTarget = AgentsHostFilterScope

    @State private var selectedProjectSlug: String = "ledger-svc"
    @State private var selectedBranchOption: String = "Repo default"
    @State private var isCloudTargetSelected: Bool = false
    @State private var isShowingGlobalSearch: Bool = false
    @State private var isShowingGoogleSignIn: Bool = false
    @State private var standaloneSheet: StandaloneModal?

    private enum StandaloneModal: String, Identifiable {
        case displayOptions
        case newProject
        case contextMenu

        var id: String { rawValue }
    }

    public init(
        store: AntigravitySessionStore,
        onSelectTab: ((ShellTab) -> Void)? = nil,
        onOpenSidebar: (() -> Void)? = nil,
        onOpenDisplayOptions: (() -> Void)? = nil,
        onOpenNewProject: (() -> Void)? = nil,
        onOpenProjectDetail: ((String) -> Void)? = nil,
        onOpenContextMenuPreview: (() -> Void)? = nil,
        onOpenConversation: ((String) -> Void)? = nil,
        onOpenSettings: (() -> Void)? = nil
    ) {
        self.store = store
        self.onSelectTab = onSelectTab
        self.onOpenSidebar = onOpenSidebar
        self.onOpenDisplayOptions = onOpenDisplayOptions
        self.onOpenNewProject = onOpenNewProject
        self.onOpenProjectDetail = onOpenProjectDetail
        self.onOpenContextMenuPreview = onOpenContextMenuPreview
        self.onOpenConversation = onOpenConversation
        self.onOpenSettings = onOpenSettings
    }

    private var selectedHost: AgentsHostFilterScope {
        store.selectedHostScope
    }

    private var usesLiveStoreData: Bool {
        !store.isVerificationMode || store.hasPairedBackend || store.isLiveBackendConnected
    }

    private var pairedLocalHosts: [RemoteHostInstance] {
        store.pairedLocalHosts
    }

    private func selectedLocalHostResolvedName(id: String, fallback: String) -> String {
        store.resolvedHostName(forInstanceUuid: id, fallback: fallback)
    }

    private func isLocalHostOnline(_ host: RemoteHostInstance) -> Bool {
        store.isLocalHostOnline(instanceId: host.instanceId, hostname: host.hostname)
    }

    private var isSelectedHostOnline: Bool {
        switch selectedHost {
        case .antigravityCloud:
            guard store.isDeviceNetworkReachable else { return false }
            if store.activeHost.channel == .cloudRelay && !store.availableRelayInstances.isEmpty {
                return store.availableRelayInstances.contains(where: \.status.isReachable) || store.isLiveBackendConnected
            }
            return true
        case .localHost(let id, let name):
            if !store.hasPairedBackend { return true }
            return store.isLocalHostOnline(instanceId: id, hostname: name)
        case .allHosts:
            if !store.hasPairedBackend { return true }
            guard store.isDeviceNetworkReachable else { return false }
            if pairedLocalHosts.count > 1 {
                return pairedLocalHosts.contains(where: { isLocalHostOnline($0) }) || store.isLiveBackendConnected
            }
            return store.isLiveBackendConnected && store.activeHost.isOnline
        }
    }

    private var selectedHostDisplayName: String {
        switch selectedHost {
        case .antigravityCloud:
            return "Antigravity Cloud"
        case .localHost(let id, let name):
            return selectedLocalHostResolvedName(id: id, fallback: name)
        case .allHosts:
            if store.hasPairedBackend {
                return pairedLocalHosts.count > 1 ? "All Hosts" : store.activeHost.hostname
            }
            return "MacBook Pro"
        }
    }

    private var isConnectingToHost: Bool {
        !store.isVerificationMode
            && store.hasPairedBackend
            && store.isDeviceNetworkReachable
            && !store.isLiveBackendConnected
            && (store.isConnectingToBackend || store.connectionLifecyclePhase == .connecting)
    }

    private var hostSwitcherDotColor: Color {
        switch selectedHost {
        case .antigravityCloud:
            return isSelectedHostOnline ? AntigravityTheme.accentPeriwinkle : AntigravityTheme.statusError
        case .localHost, .allHosts:
            if store.hasPairedBackend {
                return isSelectedHostOnline ? AntigravityTheme.statusDone : AntigravityTheme.statusError
            }
            return AntigravityTheme.statusDone
        }
    }

    private var hostSwitcherLabelText: String {
        if store.hasPairedBackend && !store.isDeviceNetworkReachable {
            return "No Network"
        }
        switch selectedHost {
        case .antigravityCloud:
            return "Antigravity"
        case .localHost(let id, let fallbackName):
            let resolved = selectedLocalHostResolvedName(id: id, fallback: fallbackName)
            if store.hasPairedBackend && !isConnectingToHost {
                return isSelectedHostOnline ? resolved : "\(resolved) · Offline"
            }
            return resolved
        case .allHosts:
            if store.hasPairedBackend {
                if pairedLocalHosts.count > 1 {
                    if isConnectingToHost { return "All Hosts" }
                    return isSelectedHostOnline ? "All Hosts" : "All Hosts · Offline"
                }
                if isConnectingToHost { return store.activeHost.hostname }
                return isSelectedHostOnline
                    ? store.activeHost.hostname
                    : "\(store.activeHost.hostname) · Offline"
            }
            return "MacBook Pro"
        }
    }

    private func hostSelectionBinding(for target: HostFilterTarget) -> Binding<Bool> {
        Binding(
            get: {
                switch (selectedHost, target) {
                case (.allHosts, .allHosts), (.antigravityCloud, .antigravityCloud):
                    return true
                case (.localHost(let lhsId, let lhsName), .localHost(let rhsId, let rhsName)):
                    return lhsId == rhsId || lhsName == rhsName
                default:
                    return false
                }
            },
            set: { _ in
                store.selectHostScope(target)
            }
        )
    }

    @ViewBuilder
    private func deviceStatusMenuIcon(isOnline: Bool) -> some View {
        #if canImport(UIKit)
        Image(uiImage: DeviceStatusMenuIconRenderer.image(isOnline: isOnline, isDark: colorScheme == .dark, scale: displayScale))
            .renderingMode(.original)
        #else
        Image(systemName: isOnline ? "laptopcomputer" : "laptopcomputer.slash")
        #endif
    }

    private var waitingApprovalConversation: CascadeSummary? {
        if !usesLiveStoreData {
            return store.summaries.first(where: { $0.cascadeId == "cas-rate-limiter" })
                ?? store.summaries.first(where: { $0.status == .waiting })
        }
        return store.summaries.first(where: { $0.status == .waiting && !$0.isArchived })
    }

    private var selectableProjects: [ProjectWorkspace] {
        let nonEmpty = store.projects.filter { !$0.isNoProject }
        if !nonEmpty.isEmpty { return nonEmpty }
        return [
            ProjectWorkspace(
                id: "ledger-svc",
                name: "ledger-svc",
                pathDisplay: "~/code/ledger-svc",
                workspaceUri: "file:///Users/alex/code/ledger-svc",
                runtime: .macBookPro,
                hostName: "MacBook Pro",
                activeBranch: "main"
            ),
            ProjectWorkspace(
                id: "web-console",
                name: "acme/web-console",
                pathDisplay: "Cloud · acme/web-console",
                workspaceUri: "cloud://acme/web-console",
                runtime: .cloud,
                hostName: "Antigravity Cloud",
                activeBranch: "main"
            )
        ]
    }

    private var resolvedSelectedProject: ProjectWorkspace? {
        if let match = selectableProjects.first(where: { $0.id == selectedProjectSlug || $0.name == selectedProjectSlug }) {
            return match
        }
        return selectableProjects.first(where: { $0.runtime != .cloud }) ?? selectableProjects.first
    }

    private var resolvedSelectedProjectTitle: String {
        resolvedSelectedProject?.name ?? "ledger-svc"
    }

    private func syncSelectedProjectWithLiveStore() {
        let nonEmpty = store.projects.filter { !$0.isNoProject }
        guard !nonEmpty.isEmpty else { return }
        if let current = nonEmpty.first(where: { $0.id == selectedProjectSlug || $0.name == selectedProjectSlug }) {
            selectedProjectSlug = current.id
            isCloudTargetSelected = (current.runtime == .cloud)
            return
        }
        let preferred = nonEmpty.first(where: { $0.id == store.selectedProjectId })
            ?? nonEmpty.first(where: { $0.runtime != .cloud })
            ?? nonEmpty.first
        if let preferred {
            selectedProjectSlug = preferred.id
            isCloudTargetSelected = (preferred.runtime == .cloud)
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            topNavigationBar
                .padding(.horizontal, 14)
                .padding(.top, 8)

            if usesLiveStoreData && isConnectingToHost {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(AntigravityTheme.accentPeriwinkle)
                    Text("Connecting to \(selectedHostDisplayName)...")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AntigravityTheme.textSecondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(AntigravityTheme.surfaceCard))
                .overlay(
                    Capsule()
                        .strokeBorder(AntigravityTheme.cardBorder, lineWidth: 1)
                )
                .padding(.top, 10)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("agents-loading-conversations")
            }

            if usesLiveStoreData
                && store.activeHost.channel == .cloudRelay
                && (store.connectionStatusText.contains("Expired")
                    || (store.connectionErrorText?.lowercased().contains("unauthorized") ?? false)) {
                googleSessionExpiredBanner
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
            }

            Spacer(minLength: 24)

            // Centered Hero Greeting (`Main.png`)
            Text("Welcome back,\nAlex. Where\nshould we pick up?")
                .font(.system(size: 30, weight: .bold))
                .tracking(-0.5)
                .lineSpacing(3)
                .multilineTextAlignment(.center)
                .foregroundStyle(AntigravityTheme.textPrimary)
                .padding(.horizontal, 28)
                .accessibilityIdentifier("home-hero-greeting")

            Spacer(minLength: 24)

            // Bottom Docked Banner + Project-Aware Composer
            VStack(spacing: 12) {
                if let waiting = waitingApprovalConversation {
                    needsApprovalBanner(waiting)
                }

                homeComposerContainer
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AntigravityTheme.canvasObsidian.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("agents-home-screen")
        .onAppear {
            syncSelectedProjectWithLiveStore()
        }
        .onChange(of: store.projects.map(\.id)) { _, _ in
            syncSelectedProjectWithLiveStore()
        }
        .sheet(isPresented: $isShowingGlobalSearch) {
            GlobalConversationSearchSheet(
                store: store,
                onSelectConversation: { cid in
                    isShowingGlobalSearch = false
                    triggerOpenConversation(cid)
                },
                onSelectProject: { slug in
                    isShowingGlobalSearch = false
                    triggerOpenProjectDetail(slug)
                },
                onDismiss: {
                    isShowingGlobalSearch = false
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $standaloneSheet) { modal in
            switch modal {
            case .displayOptions:
                DisplayOptionsSheetView(store: store, onDismiss: { standaloneSheet = nil })
            case .newProject:
                CreateProjectSheetView(store: store, onDismiss: { standaloneSheet = nil })
            case .contextMenu:
                ConversationContextPreviewMenu(store: store, onDismiss: { standaloneSheet = nil })
            }
        }
        .sheet(isPresented: $isShowingGoogleSignIn) {
            let targetURL = store.lastScannedRelayURL.isEmpty
                ? store.activeHost.endpointURL.absoluteString
                : store.lastScannedRelayURL
            CloudRelaySignInSheet(
                targetRelayURLString: targetURL.isEmpty ? SAPISIDHashGenerator.defaultOrigin : targetURL,
                clearExistingSession: true,
                onAuthenticated: { cookieHeader, finalURL, detectedAuthUser, detectedRelayApiKey in
                    isShowingGoogleSignIn = false
                    let effectiveURL = RemoteHostInstance.resolveEffectiveRelayTarget(
                        scannedInput: targetURL,
                        webViewFinalURL: finalURL
                    )
                    Task {
                        _ = await store.connectCloudRelay(
                            relayURLString: effectiveURL,
                            sessionCookie: cookieHeader,
                            authUser: detectedAuthUser,
                            relayApiKey: detectedRelayApiKey,
                            ignoreCachedRelayApiKey: true
                        )
                    }
                },
                onDismiss: {
                    isShowingGoogleSignIn = false
                }
            )
        }
    }

    // MARK: - Top Bar (Sidebar Trigger + Centered Host Pill + Search Trigger)

    private var topNavigationBar: some View {
        ZStack {
            HStack {
                Button {
                    if let onOpenSidebar {
                        onOpenSidebar()
                    } else {
                        withAnimation(.snappy(duration: 0.24)) {
                            store.isSidebarPresented = true
                        }
                    }
                } label: {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 19, weight: .regular))
                        .foregroundStyle(AntigravityTheme.textPrimary)
                        .frame(width: AntigravityTheme.minTouchTargetPt, height: AntigravityTheme.minTouchTargetPt, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open sidebar")
                .accessibilityIdentifier("btn-sidebar")

                Spacer()

                Button {
                    isShowingGlobalSearch = true
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(AntigravityTheme.textPrimary)
                        .frame(width: AntigravityTheme.minTouchTargetPt, height: AntigravityTheme.minTouchTargetPt, alignment: .trailing)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Search conversations")
                .accessibilityIdentifier("btn-global-search")
            }

            // Centered Host Switcher Capsule
            Menu {
                Section {
                    if store.hasPairedBackend {
                        Button {
                            Task {
                                if isSelectedHostOnline {
                                    _ = await store.refreshConversationsForHostScope(selectedHost, forceFullSync: true)
                                } else {
                                    await store.reconnectNow(userInitiated: true)
                                }
                            }
                        } label: {
                            Label(
                                isSelectedHostOnline
                                    ? (selectedHost == .allHosts ? "Sync Desktop & Cloud Now" : "Sync \(selectedHostDisplayName) Now")
                                    : "Reconnect \(selectedHostDisplayName)",
                                systemImage: isSelectedHostOnline ? "arrow.clockwise" : "bolt.horizontal.circle"
                            )
                        }
                        Button {
                            if let onOpenSettings {
                                onOpenSettings()
                            } else {
                                store.activeRoute = .pairingSettings
                            }
                        } label: {
                            Label("Host & Pairing Settings", systemImage: "qrcode.viewfinder")
                        }
                    } else {
                        Button {
                            if let onOpenSettings {
                                onOpenSettings()
                            } else {
                                store.activeRoute = .pairingSettings
                            }
                        } label: {
                            Label("Pair Mac / Cloud Host...", systemImage: "qrcode.viewfinder")
                        }
                    }
                }

                Section {
                    Toggle(isOn: hostSelectionBinding(for: .allHosts)) {
                        Label("All Hosts (Antigravity & Local)", systemImage: "square.stack.3d.up")
                    }

                    Toggle(isOn: hostSelectionBinding(for: .antigravityCloud)) {
                        Label("Antigravity (Cloud)", systemImage: "cloud")
                    }

                    if store.hasPairedBackend {
                        ForEach(pairedLocalHosts, id: \.instanceId) { host in
                            let target = HostFilterTarget.localHost(id: host.instanceId, name: host.hostname)
                            let online = isLocalHostOnline(host)
                            Toggle(isOn: hostSelectionBinding(for: target)) {
                                Label {
                                    Text(host.hostname)
                                } icon: {
                                    deviceStatusMenuIcon(isOnline: online)
                                }
                            }
                            .accessibilityLabel("\(host.hostname), \(online ? "Online" : "Offline")")
                        }
                    } else {
                        let mbpTarget = HostFilterTarget.localHost(id: "host-mbp-m4", name: "MacBook Pro")
                        Toggle(isOn: hostSelectionBinding(for: mbpTarget)) {
                            Label {
                                Text("MacBook Pro")
                            } icon: {
                                deviceStatusMenuIcon(isOnline: true)
                            }
                        }
                        .accessibilityLabel("MacBook Pro, Online")
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    if isConnectingToHost || store.isRefreshingSelectedHost || store.isSwitchingHost {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(AntigravityTheme.accentPeriwinkle)
                    } else {
                        Circle()
                            .fill(hostSwitcherDotColor)
                            .frame(width: 8, height: 8)
                    }
                    Text(hostSwitcherLabelText)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(AntigravityTheme.textPrimary)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AntigravityTheme.textSecondary)
                }
                .padding(.horizontal, 14)
                .frame(height: 38)
                .background(Capsule().fill(AntigravityTheme.surfaceCard))
                .overlay(
                    Capsule()
                        .strokeBorder(AntigravityTheme.cardBorder, lineWidth: 1)
                )
                .frame(minHeight: AntigravityTheme.minTouchTargetPt)
            }
            .accessibilityIdentifier("host-switcher-pill")
        }
    }

    // MARK: - Waiting Approval Banner (`Main.png`)

    private func needsApprovalBanner(_ summary: CascadeSummary) -> some View {
        Button {
            triggerOpenConversation(summary.cascadeId)
        } label: {
            HStack(spacing: 9) {
                Circle()
                    .fill(AntigravityTheme.statusWaiting)
                    .frame(width: 8, height: 8)

                HStack(spacing: 0) {
                    Text("Needs approval")
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(AntigravityTheme.statusWaiting)
                    Text(" · \(summary.title)")
                        .font(.system(size: 14.5, weight: .regular))
                        .foregroundStyle(AntigravityTheme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer(minLength: 4)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(AntigravityTheme.textSecondary)
            }
            .padding(.horizontal, 15)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(AntigravityTheme.surfaceAmberTint)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .strokeBorder(AntigravityTheme.statusWaiting.opacity(0.28), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("banner-needs-approval")
    }

    // MARK: - Docked Project/Branch Selector + Composer (`Main.png`)

    private var homeComposerContainer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 14) {
                Menu {
                    ForEach(selectableProjects) { proj in
                        Button {
                            selectedProjectSlug = proj.id
                            isCloudTargetSelected = (proj.runtime == .cloud)
                            store.selectedProjectId = proj.id
                        } label: {
                            if proj.id == selectedProjectSlug || proj.name == resolvedSelectedProjectTitle {
                                Label(proj.name, systemImage: "checkmark")
                            } else {
                                Text(proj.name)
                            }
                        }
                    }
                    Divider()
                    Button {
                        if let onOpenNewProject {
                            onOpenNewProject()
                        } else {
                            standaloneSheet = .newProject
                        }
                    } label: {
                        Label("New Project...", systemImage: "folder.badge.plus")
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isCloudTargetSelected ? "cloud" : "folder")
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(AntigravityTheme.textSecondary)
                        Text(resolvedSelectedProjectTitle)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(AntigravityTheme.textBody)
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(AntigravityTheme.textSecondary)
                    }
                    .frame(minHeight: 34)
                    .contentShape(Rectangle())
                }
                .accessibilityIdentifier("home-project-selector")

                Menu {
                    ForEach(["Repo default", "main", "New worktree"], id: \.self) { opt in
                        Button {
                            selectedBranchOption = opt
                        } label: {
                            if opt == selectedBranchOption {
                                Label(opt, systemImage: "checkmark")
                            } else {
                                Text(opt)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(AntigravityTheme.textSecondary)
                        Text(selectedBranchOption)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(AntigravityTheme.textBody)
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(AntigravityTheme.textSecondary)
                    }
                    .frame(minHeight: 34)
                    .contentShape(Rectangle())
                }
                .accessibilityIdentifier("home-branch-selector")

                Spacer(minLength: 4)

                Button {
                    isCloudTargetSelected.toggle()
                } label: {
                    Image(systemName: isCloudTargetSelected ? "cloud.fill" : "cloud")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(isCloudTargetSelected ? AntigravityTheme.accentPeriwinkle : AntigravityTheme.textSecondary)
                        .frame(width: 34, height: 34)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isCloudTargetSelected ? "Cloud runtime selected" : "Local runtime selected")
                .accessibilityIdentifier("home-runtime-toggle")
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)

            ChatComposerView(
                store: store,
                placeholderOverride: "Ask anything, @ to mention, / for actions",
                isHomeComposer: true,
                onSubmitDraft: { promptText in
                    let slug = resolvedSelectedProject?.id ?? "ledger-svc"
                    let cleanTitle = String(promptText.trimmingCharacters(in: .whitespacesAndNewlines).prefix(48))
                    _ = store.createConversationInProject(
                        slug,
                        title: cleanTitle.isEmpty ? "New Conversation" : cleanTitle,
                        initialPrompt: promptText
                    )
                }
            )
            .padding(.horizontal, 6)
            .padding(.bottom, 6)
        }
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(AntigravityTheme.surfaceCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(AntigravityTheme.cardBorder, lineWidth: 1)
        )
    }

    private var googleSessionExpiredBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AntigravityTheme.statusWaiting)
                Text("Google 登录会话已过期，请点击下方重新登录。")
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(AntigravityTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                isShowingGoogleSignIn = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                        .font(.system(size: 13.5, weight: .semibold))
                    Text("重新登录 Google")
                        .font(.system(size: 13.5, weight: .semibold))
                }
                .foregroundStyle(AntigravityTheme.inkOnPrimaryCTA)
                .padding(.horizontal, 14)
                .frame(minHeight: 36)
                .background(Capsule().fill(AntigravityTheme.accentPeriwinkle))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("btn-home-google-reauth")
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AntigravityTheme.statusWaiting.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(AntigravityTheme.statusWaiting.opacity(0.32), lineWidth: 1)
        )
        .accessibilityIdentifier("home-google-auth-expired-banner")
    }

    private func triggerOpenConversation(_ id: String) {
        if let onOpenConversation {
            onOpenConversation(id)
        } else {
            store.selectCascade(id)
        }
    }

    private func triggerOpenProjectDetail(_ slug: String) {
        if let onOpenProjectDetail {
            onOpenProjectDetail(slug)
        } else {
            store.selectProject(slug)
        }
    }
}

// MARK: - State `UE01B_SIDEBAR_DRAWER`: Left Slide-Over Sidebar Drawer (`docs/ue/ios/ios-drawer.png`)

public struct AgentsSidebarDrawerView: View {
    @Bindable public var store: AntigravitySessionStore
    @Environment(\.layoutDirection) private var layoutDirection
    public var showWelcomeBackdrop: Bool
    public var presentationProgress: CGFloat
    public var onClose: (() -> Void)?
    public var onNewConversation: (() -> Void)?
    public var onOpenAutomations: (() -> Void)?
    public var onOpenCustomizations: (() -> Void)?
    public var onOpenSettings: (() -> Void)?
    public var onOpenDisplayOptions: (() -> Void)?
    public var onOpenNewProject: (() -> Void)?
    public var onOpenProjectDetail: ((String) -> Void)?
    public var onOpenConversation: ((String) -> Void)?
    public var onOpenContextMenuPreview: ((String) -> Void)?

    @State private var isSearchExpanded: Bool = false
    @State private var searchQuery: String = ""

    public init(
        store: AntigravitySessionStore,
        showWelcomeBackdrop: Bool = false,
        presentationProgress: CGFloat = 1.0,
        onClose: (() -> Void)? = nil,
        onNewConversation: (() -> Void)? = nil,
        onOpenAutomations: (() -> Void)? = nil,
        onOpenCustomizations: (() -> Void)? = nil,
        onOpenSettings: (() -> Void)? = nil,
        onOpenDisplayOptions: (() -> Void)? = nil,
        onOpenNewProject: (() -> Void)? = nil,
        onOpenProjectDetail: ((String) -> Void)? = nil,
        onOpenConversation: ((String) -> Void)? = nil,
        onOpenContextMenuPreview: ((String) -> Void)? = nil
    ) {
        self.store = store
        self.showWelcomeBackdrop = showWelcomeBackdrop
        self.presentationProgress = presentationProgress
        self.onClose = onClose
        self.onNewConversation = onNewConversation
        self.onOpenAutomations = onOpenAutomations
        self.onOpenCustomizations = onOpenCustomizations
        self.onOpenSettings = onOpenSettings
        self.onOpenDisplayOptions = onOpenDisplayOptions
        self.onOpenNewProject = onOpenNewProject
        self.onOpenProjectDetail = onOpenProjectDetail
        self.onOpenConversation = onOpenConversation
        self.onOpenContextMenuPreview = onOpenContextMenuPreview
    }

    private var usesLiveData: Bool {
        !store.isVerificationMode || store.hasPairedBackend || store.isLiveBackendConnected
    }

    private struct DrawerConversationRow: Identifiable {
        let id: String
        let title: String
        let projectSlug: String
        let status: CortexStepStatus
        let isUnread: Bool
        let isPinned: Bool
        let timestampLabel: String
        let isSelected: Bool
    }

    private struct DrawerProjectGroup: Identifiable {
        let id: String
        let displayName: String
        let isCloud: Bool
        let conversations: [DrawerConversationRow]
    }

    private var pinnedConversations: [DrawerConversationRow] {
        if !usesLiveData {
            return [
                DrawerConversationRow(
                    id: "cas-release-checklist",
                    title: "Release checklist v2.3",
                    projectSlug: "web-console",
                    status: .done,
                    isUnread: false,
                    isPinned: true,
                    timestampLabel: "1h",
                    isSelected: false
                )
            ].filter(matchesSearch)
        }
        return store.summaries
            .filter { $0.isPinned && !$0.isArchived }
            .map(rowModel(from:))
            .filter(matchesSearch)
    }

    private var projectGroups: [DrawerProjectGroup] {
        if !usesLiveData {
            let ledgerRows: [DrawerConversationRow] = [
                DrawerConversationRow(
                    id: "cas-rate-limiter",
                    title: "Add rate limiter to /transfers",
                    projectSlug: "ledger-svc",
                    status: .waiting,
                    isUnread: false,
                    isPinned: false,
                    timestampLabel: "",
                    isSelected: true
                ),
                DrawerConversationRow(
                    id: "cas-flaky-settlement",
                    title: "Fix flaky TestSettlementBatch",
                    projectSlug: "ledger-svc",
                    status: .done,
                    isUnread: true,
                    isPinned: false,
                    timestampLabel: "",
                    isSelected: false
                ),
                DrawerConversationRow(
                    id: "cas-upgrade-go",
                    title: "Upgrade to Go 1.25",
                    projectSlug: "ledger-svc",
                    status: .done,
                    isUnread: false,
                    isPinned: false,
                    timestampLabel: "4h",
                    isSelected: false
                ),
                DrawerConversationRow(
                    id: "cas-idempotency-keys",
                    title: "Idempotency keys for payouts",
                    projectSlug: "ledger-svc",
                    status: .done,
                    isUnread: false,
                    isPinned: false,
                    timestampLabel: "1d",
                    isSelected: false
                )
            ].filter(matchesSearch)

            let webRows: [DrawerConversationRow] = [
                DrawerConversationRow(
                    id: "cas-dark-mode-settings",
                    title: "Dark mode for settings page",
                    projectSlug: "web-console",
                    status: .inProgress,
                    isUnread: false,
                    isPinned: false,
                    timestampLabel: "",
                    isSelected: false
                ),
                DrawerConversationRow(
                    id: "cas-audit-bundle-size",
                    title: "Audit bundle size",
                    projectSlug: "web-console",
                    status: .done,
                    isUnread: false,
                    isPinned: false,
                    timestampLabel: "2d",
                    isSelected: false
                )
            ].filter(matchesSearch)

            return [
                DrawerProjectGroup(id: "ledger-svc", displayName: "ledger-svc", isCloud: false, conversations: ledgerRows),
                DrawerProjectGroup(id: "web-console", displayName: "acme/web-console", isCloud: true, conversations: webRows)
            ].filter { !$0.conversations.isEmpty || searchQuery.isEmpty }
        }

        // Live mode: group real summaries by project honoring host scope and displayOptions
        let visibleSummaries = store.summaries.filter { summary in
            if store.displayOptions.archivedOnly {
                guard summary.isArchived else { return false }
            } else {
                guard !summary.isArchived && !summary.isPinned else { return false }
            }
            if store.displayOptions.filterScopeLabel == "Active only" {
                guard summary.status == .inProgress || summary.status == .waiting else { return false }
            }
            return true
        }

        var groups: [DrawerProjectGroup] = []
        var consumedIds: Set<String> = []
        for proj in store.projects {
            let projIsCloud = (proj.runtime == .cloud)
            let matching = visibleSummaries.filter { summary in
                guard !consumedIds.contains(summary.cascadeId) else { return false }
                if summary.projectSlug == proj.id {
                    return true
                }
                return summary.projectSlug == proj.name && summary.isCloud == projIsCloud
            }
            for item in matching { consumedIds.insert(item.cascadeId) }
            let rows = matching.map(rowModel(from:)).filter(matchesSearch)
            if !rows.isEmpty || (searchQuery.isEmpty && !proj.isNoProject) {
                groups.append(
                    DrawerProjectGroup(
                        id: proj.id,
                        displayName: proj.name,
                        isCloud: projIsCloud,
                        conversations: rows
                    )
                )
            }
        }
        // Suppress empty duplicate project rows when another runtime group with the same display name already has active sessions
        let populatedNames = Set(groups.filter { !$0.conversations.isEmpty }.map(\.displayName))
        groups.removeAll { $0.conversations.isEmpty && populatedNames.contains($0.displayName) }
        let ungrouped = visibleSummaries
            .filter { !consumedIds.contains($0.cascadeId) }
            .map(rowModel(from:))
            .filter(matchesSearch)
        if !ungrouped.isEmpty {
            groups.append(
                DrawerProjectGroup(
                    id: AntigravityCloudDetector.noProjectDisplayName,
                    displayName: AntigravityCloudDetector.noProjectDisplayName,
                    isCloud: false,
                    conversations: ungrouped
                )
            )
        }
        return groups
    }

    private func rowModel(from summary: CascadeSummary) -> DrawerConversationRow {
        DrawerConversationRow(
            id: summary.cascadeId,
            title: summary.title,
            projectSlug: summary.projectSlug,
            status: summary.status,
            isUnread: summary.isUnread,
            isPinned: summary.isPinned,
            timestampLabel: summary.relativeTimeLabel,
            isSelected: summary.cascadeId == store.activeCascadeId && {
                if case .cascadeChat = store.activeRoute { return true }
                return false
            }()
        )
    }

    private func matchesSearch(_ row: DrawerConversationRow) -> Bool {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return true }
        return row.title.lowercased().contains(q) || row.projectSlug.lowercased().contains(q)
    }

    public var body: some View {
        let clampedProgress = min(max(presentationProgress, 0.0), 1.0)

        GeometryReader { geo in
            let drawerWidth = min(334, geo.size.width * 0.83)
            let hiddenOffsetX: CGFloat = (layoutDirection == .rightToLeft ? drawerWidth : -drawerWidth) * (1.0 - clampedProgress)

            ZStack(alignment: .leading) {
                // Dimmed scrim & subtle right-edge peek of Home (`ios-drawer.png`)
                ZStack(alignment: .trailing) {
                    Color.black.opacity(showWelcomeBackdrop ? 0.94 : 0.62)
                        .ignoresSafeArea()
                    if showWelcomeBackdrop {
                        Text("Wel")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(AntigravityTheme.textPrimary.opacity(0.42))
                            .padding(.trailing, 4)
                            .offset(y: -48)
                    }
                }
                .opacity(clampedProgress)
                .contentShape(Rectangle())
                .allowsHitTesting(clampedProgress > 0.01)
                .onTapGesture {
                    dismissDrawer()
                }
                .accessibilityIdentifier("sidebar-drawer-scrim")

                // Left Sidebar Drawer Panel (`#101012`)
                VStack(alignment: .leading, spacing: 0) {
                    // Drawer Top Bar
                    HStack {
                        Button {
                            dismissDrawer()
                        } label: {
                            Image(systemName: "sidebar.left")
                                .font(.system(size: 19, weight: .regular))
                                .foregroundStyle(AntigravityTheme.textPrimary)
                                .frame(width: AntigravityTheme.minTouchTargetPt, height: AntigravityTheme.minTouchTargetPt, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Close sidebar")
                        .accessibilityIdentifier("btn-close-sidebar")

                        Spacer()

                        Button {
                            withAnimation(.snappy(duration: 0.2)) {
                                isSearchExpanded.toggle()
                                if !isSearchExpanded { searchQuery = "" }
                            }
                        } label: {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 18, weight: .regular))
                                .foregroundStyle(AntigravityTheme.textPrimary)
                                .frame(width: AntigravityTheme.minTouchTargetPt, height: AntigravityTheme.minTouchTargetPt, alignment: .trailing)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Search sidebar")
                        .accessibilityIdentifier("btn-drawer-search")
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                    if isSearchExpanded {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 14))
                                .foregroundStyle(AntigravityTheme.textMuted)
                            TextField("Search conversations", text: $searchQuery)
                                .font(.system(size: 15))
                                .foregroundStyle(AntigravityTheme.textPrimary)
                                .accessibilityIdentifier("drawer-search-input")
                            if !searchQuery.isEmpty {
                                Button {
                                    searchQuery = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(AntigravityTheme.textSecondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 38)
                        .background(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(AntigravityTheme.surfaceElevated)
                        )
                        .padding(.horizontal, 14)
                        .padding(.bottom, 10)
                    }

                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 6) {
                            // `+ New Conversation` Button
                            Button {
                                if let onNewConversation {
                                    onNewConversation()
                                } else {
                                    store.isSidebarPresented = false
                                    store.selectedTab = .agents
                                    store.activeRoute = .tabRoot
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "plus")
                                        .font(.system(size: 16, weight: .medium))
                                    Text("New Conversation")
                                        .font(.system(size: 16, weight: .medium))
                                    Spacer()
                                }
                                .foregroundStyle(AntigravityTheme.textPrimary)
                                .padding(.horizontal, 14)
                                .frame(maxWidth: .infinity, minHeight: 46)
                                .background(
                                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                                        .fill(AntigravityTheme.surfaceElevated)
                                )
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 12)
                            .padding(.top, 6)
                            .padding(.bottom, 6)
                            .accessibilityIdentifier("btn-new-conversation")

                            // Primary Navigation Rows (`Automations`, `Customizations`)
                            drawerPrimaryNavRow(
                                icon: "clock",
                                title: "Automations",
                                testId: "drawer-nav-automations"
                            ) {
                                if let onOpenAutomations {
                                    onOpenAutomations()
                                } else {
                                    store.isSidebarPresented = false
                                    store.selectedTab = .automations
                                    store.activeRoute = .tabRoot
                                }
                            }

                            drawerPrimaryNavRow(
                                icon: "briefcase",
                                title: "Customizations",
                                testId: "drawer-nav-customizations"
                            ) {
                                if let onOpenCustomizations {
                                    onOpenCustomizations()
                                } else {
                                    store.isSidebarPresented = false
                                    store.activeRoute = .rulesAndSkills
                                }
                            }

                            // Pinned Section
                            if !pinnedConversations.isEmpty {
                                Text("Pinned")
                                    .font(.system(size: 13, weight: .regular))
                                    .foregroundStyle(AntigravityTheme.textSecondary)
                                    .padding(.horizontal, 18)
                                    .padding(.top, 16)
                                    .padding(.bottom, 4)

                                ForEach(pinnedConversations) { row in
                                    drawerConversationItem(row, indented: false)
                                }
                            }

                            // Projects Section Header + Filter / New Project Actions
                            HStack(spacing: 8) {
                                Text("Projects")
                                    .font(.system(size: 13, weight: .regular))
                                    .foregroundStyle(AntigravityTheme.textSecondary)

                                Spacer()

                                Button {
                                    if let onOpenDisplayOptions {
                                        onOpenDisplayOptions()
                                    } else {
                                        store.presentedSheet = .displayOptions
                                    }
                                } label: {
                                    Image(systemName: "line.3.horizontal.decrease")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(AntigravityTheme.textSecondary)
                                        .frame(width: 34, height: 34)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Display options")
                                .accessibilityIdentifier("btn-display-options")

                                Button {
                                    if let onOpenNewProject {
                                        onOpenNewProject()
                                    } else {
                                        store.presentedSheet = .createProject
                                    }
                                } label: {
                                    Image(systemName: "folder.badge.plus")
                                        .font(.system(size: 14.5, weight: .medium))
                                        .foregroundStyle(AntigravityTheme.textSecondary)
                                        .frame(width: 34, height: 34)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("New project")
                                .accessibilityIdentifier("btn-new-project")
                            }
                            .padding(.leading, 18)
                            .padding(.trailing, 10)
                            .padding(.top, 14)

                            // Project Groups & Conversations
                            ForEach(projectGroups) { group in
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 8) {
                                        Button {
                                            if let onOpenProjectDetail {
                                                onOpenProjectDetail(group.id)
                                            } else {
                                                store.isSidebarPresented = false
                                                store.selectProject(group.id)
                                            }
                                        } label: {
                                            HStack(spacing: 9) {
                                                Image(systemName: group.isCloud ? "cloud" : "folder")
                                                    .font(.system(size: 14, weight: .regular))
                                                    .foregroundStyle(AntigravityTheme.textSecondary)
                                                    .frame(width: 20)
                                                Text(group.displayName)
                                                    .font(.system(size: 15.5, weight: .regular))
                                                    .foregroundStyle(AntigravityTheme.textSecondary)
                                                    .lineLimit(1)
                                            }
                                            .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
                                            .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityIdentifier("project-header-\(group.id)")

                                        Button {
                                            if let onOpenConversation {
                                                onOpenConversation("new-\(group.id)")
                                            } else {
                                                store.isSidebarPresented = false
                                                _ = store.createConversationInProject(group.id)
                                            }
                                        } label: {
                                            Image(systemName: "plus")
                                                .font(.system(size: 15, weight: .regular))
                                                .foregroundStyle(AntigravityTheme.textSecondary)
                                                .frame(width: 36, height: 36)
                                                .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityIdentifier("btn-add-conv-\(group.id)")
                                    }
                                    .padding(.leading, 18)
                                    .padding(.trailing, 10)
                                    .padding(.top, 4)

                                    ForEach(group.conversations) { row in
                                        drawerConversationItem(row, indented: true)
                                    }
                                }
                            }
                        }
                        .padding(.bottom, 16)
                    }

                    // Bottom Pinned Settings Footer (`ios-drawer.png`)
                    Divider()
                        .overlay(AntigravityTheme.subtleDivider)

                    Button {
                        if let onOpenSettings {
                            onOpenSettings()
                        } else {
                            store.isSidebarPresented = false
                            store.activeRoute = .pairingSettings
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "sun.max")
                                .font(.system(size: 17, weight: .regular))
                                .foregroundStyle(AntigravityTheme.textSecondary)
                            Text("Settings")
                                .font(.system(size: 16, weight: .regular))
                                .foregroundStyle(AntigravityTheme.textPrimary)
                            Spacer()
                        }
                        .padding(.horizontal, 18)
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("drawer-nav-settings")
                }
                .frame(width: drawerWidth)
                .frame(maxHeight: .infinity)
                .background(AntigravityTheme.surfaceSheet.ignoresSafeArea())
                .overlay(alignment: .trailing) {
                    Rectangle()
                        .fill(AntigravityTheme.cardBorder)
                        .frame(width: 1)
                        .ignoresSafeArea()
                }
                .offset(x: hiddenOffsetX)
                .allowsHitTesting(clampedProgress > 0.01)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("sidebar-drawer-panel")
            }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    private func drawerPrimaryNavRow(
        icon: String,
        title: String,
        testId: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(AntigravityTheme.textSecondary)
                    .frame(width: 22)
                Text(title)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(AntigravityTheme.textPrimary)
                Spacer()
            }
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(testId)
    }

    private func drawerConversationItem(_ row: DrawerConversationRow, indented: Bool) -> some View {
        Button {
            if let onOpenConversation {
                onOpenConversation(row.id)
            } else {
                store.isSidebarPresented = false
                store.selectCascade(row.id)
            }
        } label: {
            HStack(spacing: 10) {
                Text(row.title)
                    .font(.system(size: 15.5, weight: .regular))
                    .foregroundStyle(AntigravityTheme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 6)

                trailingIndicator(for: row)
            }
            .padding(.leading, indented ? 28 : 14)
            .padding(.trailing, 14)
            .frame(maxWidth: .infinity, minHeight: 42)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(row.isSelected ? AntigravityTheme.surfaceElevated : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
        .contextMenu {
            Button {
                store.togglePinCascade(row.id)
            } label: {
                Label(row.isPinned ? "Unpin" : "Pin", systemImage: row.isPinned ? "pin.slash" : "pin")
            }
            Button {
                store.toggleUnreadCascade(row.id)
            } label: {
                Label(row.isUnread ? "Mark as read" : "Mark as unread", systemImage: "envelope.badge")
            }
            Button {
                store.archiveCascade(row.id)
            } label: {
                Label("Archive", systemImage: "archivebox")
            }
            Divider()
            Button(role: .destructive) {
                store.deleteCascade(row.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .accessibilityIdentifier("drawer-conv-\(row.id)")
    }

    @ViewBuilder
    private func trailingIndicator(for row: DrawerConversationRow) -> some View {
        if row.status == .waiting {
            Circle()
                .fill(AntigravityTheme.statusWaiting)
                .frame(width: 8, height: 8)
        } else if row.status == .inProgress || row.status == .pending {
            AntigravityRunningArcIndicatorView(isAnimated: !store.isVerificationMode || store.isLiveBackendConnected)
                .accessibilityIdentifier("loading-four-dots-\(row.id)")
        } else if row.isUnread {
            Circle()
                .fill(AntigravityTheme.accentPeriwinkle)
                .frame(width: 8, height: 8)
        } else if !row.timestampLabel.isEmpty {
            Text(row.timestampLabel)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(AntigravityTheme.textMuted)
        }
    }

    private func dismissDrawer() {
        if let onClose {
            onClose()
        } else {
            withAnimation(.snappy(duration: 0.22)) {
                store.isSidebarPresented = false
            }
        }
    }
}

// MARK: - Global Conversation Search Sheet

private struct GlobalConversationSearchSheet: View {
    @Bindable var store: AntigravitySessionStore
    var onSelectConversation: (String) -> Void
    var onSelectProject: (String) -> Void
    var onDismiss: () -> Void

    @State private var query: String = ""

    private var matchingConversations: [CascadeSummary] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let base = store.summaries.filter { !$0.isArchived }
        guard !q.isEmpty else { return Array(base.prefix(8)) }
        return base.filter {
            $0.title.lowercased().contains(q)
                || $0.projectSlug.lowercased().contains(q)
                || $0.statusSubtitle.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(AntigravityTheme.textSecondary)
                TextField("Search conversations & projects", text: $query)
                    .font(.system(size: 16))
                    .foregroundStyle(AntigravityTheme.textPrimary)
                    .onChange(of: query) { _, newValue in
                        if !store.isVerificationMode {
                            Task { await store.runFullTextConversationSearch(newValue) }
                        }
                    }
                    .accessibilityIdentifier("global-search-input")

                Button("Cancel") {
                    onDismiss()
                }
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(AntigravityTheme.accentPeriwinkle)
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .frame(height: 46)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AntigravityTheme.surfaceElevated)
            )
            .padding(.horizontal, 16)
            .padding(.top, 16)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(matchingConversations) { summary in
                        Button {
                            onSelectConversation(summary.cascadeId)
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(summary.title)
                                        .font(.system(size: 15.5, weight: .medium))
                                        .foregroundStyle(AntigravityTheme.textPrimary)
                                        .lineLimit(1)
                                    Text("\(summary.projectSlug) · \(summary.statusSubtitle)")
                                        .font(.system(size: 13))
                                        .foregroundStyle(AntigravityTheme.textSecondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Text(summary.relativeTimeLabel)
                                    .font(.system(size: 12.5))
                                    .foregroundStyle(AntigravityTheme.textMuted)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(AntigravityTheme.surfaceCard)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
        .background(AntigravityTheme.canvasObsidian.ignoresSafeArea())
    }
}

#if canImport(UIKit)
@MainActor
private enum DeviceStatusMenuIconRenderer {
    private static var cache: [String: UIImage] = [:]

    /// Renders a `24×20pt` always-original `UIImage` combining `laptopcomputer` with a top-right
    /// online (solid emerald dot) or offline (hollow coral ring) status indicator
    /// so iOS `UIMenu` preserves status color instead of flattening SF Symbols to template monochrome.
    static func image(isOnline: Bool, isDark: Bool = true, scale: CGFloat) -> UIImage {
        let clampedScale = max(scale, 2.0)
        let cacheKey = "\(isOnline ? "online" : "offline")-\(isDark ? "dark" : "light")-\(Int((clampedScale * 10).rounded()))"
        if let cached = cache[cacheKey] {
            return cached
        }

        let traits = UITraitCollection(userInterfaceStyle: isDark ? .dark : .light)
        let canvasSize = CGSize(width: 24, height: 20)
        let format = UIGraphicsImageRendererFormat()
        format.scale = clampedScale
        format.opaque = false

        let renderer = UIGraphicsImageRenderer(size: canvasSize, format: format)
        let rendered = renderer.image { ctx in
            let cg = ctx.cgContext
            let glyphColor = AntigravityTheme.inkReadingUIColor
                .resolvedColor(with: traits)
                .withAlphaComponent(isOnline ? 0.94 : 0.48)
            let symbolConfig = UIImage.SymbolConfiguration(pointSize: 15, weight: .regular)
            if let baseSymbol = UIImage(systemName: "laptopcomputer", withConfiguration: symbolConfig)?
                .withTintColor(glyphColor, renderingMode: .alwaysOriginal) {
                let symbolSize = baseSymbol.size
                let drawRect = CGRect(
                    x: max(0, (21.5 - symbolSize.width) * 0.5),
                    y: max(0, (canvasSize.height - symbolSize.height) * 0.5 + 1.0),
                    width: symbolSize.width,
                    height: symbolSize.height
                )
                baseSymbol.draw(in: drawRect)
            }

            let dotCenter = CGPoint(x: 19.5, y: 4.8)
            let cutoutRadius: CGFloat = 4.3
            let cutoutRect = CGRect(
                x: dotCenter.x - cutoutRadius,
                y: dotCenter.y - cutoutRadius,
                width: cutoutRadius * 2,
                height: cutoutRadius * 2
            )
            cg.saveGState()
            cg.setBlendMode(.clear)
            cg.fillEllipse(in: cutoutRect)
            cg.restoreGState()

            if isOnline {
                let dotRadius: CGFloat = 3.0
                let dotRect = CGRect(
                    x: dotCenter.x - dotRadius,
                    y: dotCenter.y - dotRadius,
                    width: dotRadius * 2,
                    height: dotRadius * 2
                )
                UIColor(AntigravityTheme.statusDone).resolvedColor(with: traits).setFill()
                cg.fillEllipse(in: dotRect)
            } else {
                let lineWidth: CGFloat = 1.5
                let ringRadius: CGFloat = 3.0 - lineWidth * 0.5
                let ringRect = CGRect(
                    x: dotCenter.x - ringRadius,
                    y: dotCenter.y - ringRadius,
                    width: ringRadius * 2,
                    height: ringRadius * 2
                )
                UIColor(AntigravityTheme.statusError).resolvedColor(with: traits).setStroke()
                cg.setLineWidth(lineWidth)
                cg.strokeEllipse(in: ringRect)
            }
        }.withRenderingMode(.alwaysOriginal)

        cache[cacheKey] = rendered
        return rendered
    }
}
#endif
