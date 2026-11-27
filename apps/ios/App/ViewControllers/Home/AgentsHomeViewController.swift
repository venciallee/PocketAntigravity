import SwiftUI
import AntigravityData
#if canImport(UIKit)
import UIKit
#endif

/// State `UE01_AGENTS_HOME`: Minimalist New Conversation Home (`docs/ue/ios/Main.png`).
/// - Top bar: Left sidebar trigger (`btn-sidebar`), centered Host Switcher capsule (`host-switcher-pill`),
///   right Global Search trigger (`btn-global-search`).
/// - Center: Dynamic hero greeting (`Welcome back, <name>. Where should we pick up?`, or nameless fallback).
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
    public var onOpenContextMenuPreview: (() -> Void)?
    public var onOpenConversation: ((String) -> Void)?
    public var onOpenSettings: (() -> Void)?

    public typealias HostFilterTarget = AgentsHostFilterScope

    @State private var selectedProjectSlug: String = "ledger-svc"
    @State private var selectedBranchOption: String = "Repo default"
    @State private var isCloudTargetSelected: Bool = false
    @State private var activeHomeSheet: HomeModalSheet?

    private enum HomeModalSheet: String, Identifiable {
        case globalSearch
        case displayOptions
        case newProject
        case contextMenu
        case googleSignIn

        var id: String { rawValue }
    }

    public init(
        store: AntigravitySessionStore,
        onSelectTab: ((ShellTab) -> Void)? = nil,
        onOpenSidebar: (() -> Void)? = nil,
        onOpenDisplayOptions: (() -> Void)? = nil,
        onOpenNewProject: (() -> Void)? = nil,
        onOpenContextMenuPreview: (() -> Void)? = nil,
        onOpenConversation: ((String) -> Void)? = nil,
        onOpenSettings: (() -> Void)? = nil
    ) {
        self.store = store
        self.onSelectTab = onSelectTab
        self.onOpenSidebar = onOpenSidebar
        self.onOpenDisplayOptions = onOpenDisplayOptions
        self.onOpenNewProject = onOpenNewProject
        self.onOpenContextMenuPreview = onOpenContextMenuPreview
        self.onOpenConversation = onOpenConversation
        self.onOpenSettings = onOpenSettings
    }

    private var lang: AppLanguage {
        store.appearancePreferences.language
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
                return pairedLocalHosts.count > 1 ? lang.t("All Hosts", "全部主机") : store.activeHost.hostname
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
            return lang.t("No Network", "无网络")
        }
        switch selectedHost {
        case .antigravityCloud:
            return "Antigravity"
        case .localHost(let id, let fallbackName):
            let resolved = selectedLocalHostResolvedName(id: id, fallback: fallbackName)
            if store.hasPairedBackend && !isConnectingToHost {
                return isSelectedHostOnline ? resolved : lang.t("\(resolved) · Offline", "\(resolved) · 离线")
            }
            return resolved
        case .allHosts:
            if store.hasPairedBackend {
                if pairedLocalHosts.count > 1 {
                    if isConnectingToHost { return lang.t("All Hosts", "全部主机") }
                    return isSelectedHostOnline ? lang.t("All Hosts", "全部主机") : lang.t("All Hosts · Offline", "全部主机 · 离线")
                }
                if isConnectingToHost { return store.activeHost.hostname }
                return isSelectedHostOnline
                    ? store.activeHost.hostname
                    : lang.t("\(store.activeHost.hostname) · Offline", "\(store.activeHost.hostname) · 离线")
            }
            return "MacBook Pro"
        }
    }

    private func localizedBranchOptionLabel(_ raw: String) -> String {
        switch raw {
        case "Repo default": return lang.t("Repo default", "仓库默认")
        case "New worktree": return lang.t("New worktree", "新建 Worktree")
        default: return raw
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
        return store.summaries.first(where: {
            $0.status == .waiting && !$0.isArchived && store.summaryMatchesHostScope($0)
        })
    }

    private var selectableProjects: [ProjectWorkspace] {
        let scoped = store.projects.filter { proj in
            !proj.isNoProject && store.projectMatchesHostScope(proj)
        }
        if usesLiveStoreData {
            return scoped
        }
        if !scoped.isEmpty { return scoped }
        let fallbackFixtures = [
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
        let scopedFallback = fallbackFixtures.filter { store.projectMatchesHostScope($0) }
        return scopedFallback.isEmpty ? fallbackFixtures : scopedFallback
    }

    private var resolvedSelectedProject: ProjectWorkspace? {
        if let match = selectableProjects.first(where: { $0.id == selectedProjectSlug }) {
            return match
        }
        if let match = selectableProjects.first(where: { $0.name == selectedProjectSlug }) {
            return match
        }
        if selectedHost == .antigravityCloud {
            return selectableProjects.first(where: { $0.runtime == .cloud }) ?? selectableProjects.first
        }
        return selectableProjects.first(where: { $0.runtime != .cloud }) ?? selectableProjects.first
    }

    private var resolvedSelectedProjectTitle: String {
        if let project = resolvedSelectedProject {
            return project.name
        }
        if usesLiveStoreData {
            if store.isSwitchingHost || store.isRefreshingSelectedHost {
                return lang.t("Loading...", "加载中...")
            }
            return lang.t(AntigravityCloudDetector.noProjectDisplayName, "无项目")
        }
        return "ledger-svc"
    }

    private func syncSelectedProjectWithLiveStore() {
        let scoped = selectableProjects
        guard !scoped.isEmpty else {
            selectedProjectSlug = ""
            isCloudTargetSelected = (selectedHost == .antigravityCloud)
            store.selectedWorkspaceUri = ""
            return
        }
        if let current = scoped.first(where: { $0.id == selectedProjectSlug })
            ?? scoped.first(where: { $0.name == selectedProjectSlug }) {
            selectedProjectSlug = current.id
            isCloudTargetSelected = (current.runtime == .cloud)
            if store.selectedProjectId != current.id {
                store.selectedProjectId = current.id
            }
            if store.selectedWorkspaceUri != current.workspaceUri {
                store.selectedWorkspaceUri = current.workspaceUri
            }
            return
        }
        let preferred: ProjectWorkspace? = {
            if let storeMatch = scoped.first(where: { $0.id == store.selectedProjectId }) {
                return storeMatch
            }
            if selectedHost == .antigravityCloud {
                return scoped.first(where: { $0.runtime == .cloud }) ?? scoped.first
            }
            return scoped.first(where: { $0.runtime != .cloud }) ?? scoped.first
        }()
        if let preferred {
            selectedProjectSlug = preferred.id
            isCloudTargetSelected = (preferred.runtime == .cloud)
            if store.selectedProjectId != preferred.id {
                store.selectedProjectId = preferred.id
            }
            if store.selectedWorkspaceUri != preferred.workspaceUri {
                store.selectedWorkspaceUri = preferred.workspaceUri
            }
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
                    Text(lang.t("Connecting to \(selectedHostDisplayName)...", "正在连接 \(selectedHostDisplayName)..."))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AntigravityTheme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(AntigravityTheme.surfaceCard))
                .overlay(
                    Capsule()
                        .strokeBorder(AntigravityTheme.cardBorder, lineWidth: 1)
                )
                .padding(.horizontal, 16)
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
            Text(store.homeHeroGreetingText)
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
        .onChange(of: store.selectedHostScope) { _, _ in
            syncSelectedProjectWithLiveStore()
        }
        .onChange(of: store.activeHost.instanceId) { _, _ in
            syncSelectedProjectWithLiveStore()
        }
        .onChange(of: store.projects.map { "\($0.id):\($0.runtime.rawValue):\($0.originInstanceUuid ?? ""):\($0.hostName)" }) { _, _ in
            syncSelectedProjectWithLiveStore()
        }
        .onChange(of: store.selectedProjectId) { _, newProjectId in
            if let matched = selectableProjects.first(where: { $0.id == newProjectId }) {
                selectedProjectSlug = matched.id
                isCloudTargetSelected = (matched.runtime == .cloud)
            } else {
                syncSelectedProjectWithLiveStore()
            }
        }
        .sheet(item: $activeHomeSheet) { modal in
            switch modal {
            case .globalSearch:
                GlobalConversationSearchSheet(
                    store: store,
                    onSelectConversation: { cid in
                        activeHomeSheet = nil
                        triggerOpenConversation(cid)
                    },
                    onSelectProject: { slug in
                        activeHomeSheet = nil
                        store.selectProject(slug)
                    },
                    onDismiss: {
                        activeHomeSheet = nil
                    }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)

            case .displayOptions:
                DisplayOptionsSheetView(store: store, onDismiss: { activeHomeSheet = nil })

            case .newProject:
                CreateProjectSheetView(store: store, onDismiss: { activeHomeSheet = nil })

            case .contextMenu:
                ConversationContextPreviewMenu(store: store, onDismiss: { activeHomeSheet = nil })

            case .googleSignIn:
                let targetURL = store.lastScannedRelayURL.isEmpty
                    ? store.activeHost.endpointURL.absoluteString
                    : store.lastScannedRelayURL
                CloudRelaySignInSheet(
                    targetRelayURLString: targetURL.isEmpty ? SAPISIDHashGenerator.defaultOrigin : targetURL,
                    clearExistingSession: true,
                    onAuthenticated: { cookieHeader, finalURL, detectedAuthUser, detectedRelayApiKey in
                        activeHomeSheet = nil
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
                        activeHomeSheet = nil
                    }
                )
            }
        }
    }

    // MARK: - Top Bar (Sidebar Trigger + Centered Host Pill + Search Trigger)

    private var topNavigationBar: some View {
        HStack(spacing: 8) {
            Button {
                if let onOpenSidebar {
                    onOpenSidebar()
                } else {
                    withAnimation(.spring(duration: 0.34, bounce: 0.0)) {
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
            .fixedSize()
            .layoutPriority(1)
            .accessibilityLabel(lang.t("Open sidebar", "打开侧边栏"))
            .accessibilityIdentifier("btn-sidebar")

            // Centered Host Switcher Capsule (strictly bounded between sidebar & search buttons)
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
                                    ? (selectedHost == .allHosts
                                        ? lang.t("Sync Desktop & Cloud Now", "立即同步桌面端与云端")
                                        : lang.t("Sync \(selectedHostDisplayName) Now", "立即同步 \(selectedHostDisplayName)"))
                                    : lang.t("Reconnect \(selectedHostDisplayName)", "重新连接 \(selectedHostDisplayName)"),
                                systemImage: isSelectedHostOnline ? "arrow.clockwise" : "bolt.horizontal.circle"
                            )
                        }
                    } else {
                        Button {
                            if let onOpenSettings {
                                onOpenSettings()
                            } else {
                                store.activeRoute = .pairingSettings
                            }
                        } label: {
                            Label(lang.t("Pair Mac / Cloud Host...", "配对 Mac / 云端主机..."), systemImage: "qrcode.viewfinder")
                        }
                    }
                }

                Section {
                    Toggle(isOn: hostSelectionBinding(for: .allHosts)) {
                        Label(lang.t("All Hosts (Cloud & Local)", "全部主机（云端与本地）"), systemImage: "square.stack.3d.up")
                    }

                    Toggle(isOn: hostSelectionBinding(for: .antigravityCloud)) {
                        Label(lang.t("Antigravity (Cloud)", "Antigravity（云端）"), systemImage: "cloud")
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
                            .accessibilityLabel("\(host.hostname), \(online ? lang.t("Online", "在线") : lang.t("Offline", "离线"))")
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
                        .accessibilityLabel(lang.t("MacBook Pro, Online", "MacBook Pro，在线"))
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    if isConnectingToHost || store.isRefreshingSelectedHost || store.isSwitchingHost {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(AntigravityTheme.accentPeriwinkle)
                            .fixedSize()
                    } else {
                        Circle()
                            .fill(hostSwitcherDotColor)
                            .frame(width: 8, height: 8)
                            .fixedSize()
                    }
                    Text(hostSwitcherLabelText)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(AntigravityTheme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .layoutPriority(-1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AntigravityTheme.textSecondary)
                        .fixedSize()
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
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .center)

            Button {
                activeHomeSheet = .globalSearch
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(AntigravityTheme.textPrimary)
                    .frame(width: AntigravityTheme.minTouchTargetPt, height: AntigravityTheme.minTouchTargetPt, alignment: .trailing)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .fixedSize()
            .layoutPriority(1)
            .accessibilityLabel(lang.t("Search conversations", "搜索对话"))
            .accessibilityIdentifier("btn-global-search")
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
                    Text(lang.t("Needs approval", "需要审批"))
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(AntigravityTheme.statusWaiting)
                    Text(" · \(store.displayTitle(for: summary))")
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
            HStack(spacing: 12) {
                Menu {
                    if selectableProjects.isEmpty && usesLiveStoreData {
                        Button {} label: {
                            Text(
                                (store.isSwitchingHost || store.isRefreshingSelectedHost)
                                    ? lang.t("Syncing repositories...", "正在同步仓库...")
                                    : lang.t("No repositories on \(selectedHostDisplayName)", "\(selectedHostDisplayName) 上暂无仓库")
                            )
                        }
                        .disabled(true)

                        Button {
                            Task {
                                _ = await store.refreshConversationsForHostScope(selectedHost, forceFullSync: true)
                            }
                        } label: {
                            Label(lang.t("Sync Repositories", "同步仓库"), systemImage: "arrow.clockwise")
                        }
                    } else {
                        ForEach(selectableProjects) { proj in
                            Button {
                                selectedProjectSlug = proj.id
                                isCloudTargetSelected = (proj.runtime == .cloud)
                                store.selectedProjectId = proj.id
                                store.selectedWorkspaceUri = proj.workspaceUri
                            } label: {
                                if proj.id == resolvedSelectedProject?.id {
                                    Label(proj.name, systemImage: "checkmark")
                                } else {
                                    Text(proj.name)
                                }
                            }
                        }
                    }
                    Divider()
                    Button {
                        if let onOpenNewProject {
                            onOpenNewProject()
                        } else {
                            activeHomeSheet = .newProject
                        }
                    } label: {
                        Label(lang.t("New Project...", "新建项目..."), systemImage: "folder.badge.plus")
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isCloudTargetSelected ? "cloud" : "folder")
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(AntigravityTheme.textSecondary)
                            .fixedSize()
                        Text(resolvedSelectedProjectTitle)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(AntigravityTheme.textBody)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .layoutPriority(-1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(AntigravityTheme.textSecondary)
                            .fixedSize()
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
                                Label(localizedBranchOptionLabel(opt), systemImage: "checkmark")
                            } else {
                                Text(localizedBranchOptionLabel(opt))
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(AntigravityTheme.textSecondary)
                        Text(localizedBranchOptionLabel(selectedBranchOption))
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
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)
                .accessibilityIdentifier("home-branch-selector")

                Spacer(minLength: 4)

                Button {
                    isCloudTargetSelected.toggle()
                } label: {
                    Image(systemName: isCloudTargetSelected ? "cloud.fill" : "laptopcomputer")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(isCloudTargetSelected ? AntigravityTheme.accentPeriwinkle : AntigravityTheme.textSecondary)
                        .frame(width: 34, height: 34)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .fixedSize()
                .layoutPriority(1)
                .accessibilityLabel(isCloudTargetSelected ? lang.t("Cloud runtime selected", "已选择云端运行环境") : lang.t("Local runtime selected", "已选择本地运行环境"))
                .accessibilityValue(isCloudTargetSelected ? "cloud" : "computer")
                .accessibilityIdentifier("home-runtime-toggle")
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)

            ChatComposerView(
                store: store,
                placeholderOverride: lang.t("Ask anything, @ to mention, / for actions", "输入任何内容，@ 引用上下文，/ 快捷操作"),
                isHomeComposer: true,
                isRemoteSessionOverride: isCloudTargetSelected,
                onSubmitDraft: { promptText in
                    let slug = resolvedSelectedProject?.id
                        ?? (usesLiveStoreData ? AntigravityCloudDetector.noProjectDisplayName : "ledger-svc")
                    let attachments = store.composerAttachments
                    let cleanTitle = String(promptText.trimmingCharacters(in: .whitespacesAndNewlines).prefix(48))
                    let fallbackTitle = attachments.first?.label ?? lang.t("New Conversation", "新建对话")
                    _ = store.createConversationInProject(
                        slug,
                        title: cleanTitle.isEmpty ? fallbackTitle : cleanTitle,
                        initialPrompt: promptText,
                        initialAttachments: attachments,
                        isCloudOverride: isCloudTargetSelected
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
                Text(lang.t("Google sign-in session expired. Tap below to sign in again.", "Google 登录会话已过期，请点击下方重新登录。"))
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(AntigravityTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                activeHomeSheet = .googleSignIn
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                        .font(.system(size: 13.5, weight: .semibold))
                    Text(lang.t("Sign in with Google Again", "重新登录 Google"))
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
    public var onSelectProject: ((String) -> Void)?
    public var onOpenProjectCustomizations: ((String) -> Void)?
    public var onOpenConversation: ((String) -> Void)?
    public var onOpenContextMenuPreview: ((String) -> Void)?

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
        onSelectProject: ((String) -> Void)? = nil,
        onOpenProjectCustomizations: ((String) -> Void)? = nil,
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
        self.onSelectProject = onSelectProject
        self.onOpenProjectCustomizations = onOpenProjectCustomizations
        self.onOpenConversation = onOpenConversation
        self.onOpenContextMenuPreview = onOpenContextMenuPreview
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
                AgentsSidebarDrawerPanelView(
                    store: store,
                    isVisible: clampedProgress > 0.05,
                    onClose: onClose,
                    onNewConversation: onNewConversation,
                    onOpenAutomations: onOpenAutomations,
                    onOpenCustomizations: onOpenCustomizations,
                    onOpenSettings: onOpenSettings,
                    onOpenDisplayOptions: onOpenDisplayOptions,
                    onOpenNewProject: onOpenNewProject,
                    onSelectProject: onSelectProject,
                    onOpenProjectCustomizations: onOpenProjectCustomizations,
                    onOpenConversation: onOpenConversation,
                    onOpenContextMenuPreview: onOpenContextMenuPreview
                )
                .frame(width: drawerWidth)
                .frame(maxHeight: .infinity)
                .offset(x: hiddenOffsetX)
                .allowsHitTesting(clampedProgress > 0.01)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("sidebar-drawer-panel")
            }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    private func dismissDrawer() {
        if let onClose {
            onClose()
        } else {
            withAnimation(.spring(duration: 0.28, bounce: 0.0)) {
                store.isSidebarPresented = false
            }
        }
    }
}

/// Isolated left sidebar panel content without `presentationProgress` dependencies so GPU slide-in,
/// slide-out, and 1:1 interactive swipe transforms never trigger list body re-evaluations.
public struct AgentsSidebarDrawerPanelView: View {
    @Bindable public var store: AntigravitySessionStore
    public var isVisible: Bool
    public var onClose: (() -> Void)?
    public var onNewConversation: (() -> Void)?
    public var onOpenAutomations: (() -> Void)?
    public var onOpenCustomizations: (() -> Void)?
    public var onOpenSettings: (() -> Void)?
    public var onOpenDisplayOptions: (() -> Void)?
    public var onOpenNewProject: (() -> Void)?
    public var onSelectProject: ((String) -> Void)?
    public var onOpenProjectCustomizations: ((String) -> Void)?
    public var onOpenConversation: ((String) -> Void)?
    public var onOpenContextMenuPreview: ((String) -> Void)?

    @State private var isSearchExpanded: Bool = false
    @State private var searchQuery: String = ""

    public init(
        store: AntigravitySessionStore,
        isVisible: Bool = true,
        onClose: (() -> Void)? = nil,
        onNewConversation: (() -> Void)? = nil,
        onOpenAutomations: (() -> Void)? = nil,
        onOpenCustomizations: (() -> Void)? = nil,
        onOpenSettings: (() -> Void)? = nil,
        onOpenDisplayOptions: (() -> Void)? = nil,
        onOpenNewProject: (() -> Void)? = nil,
        onSelectProject: ((String) -> Void)? = nil,
        onOpenProjectCustomizations: ((String) -> Void)? = nil,
        onOpenConversation: ((String) -> Void)? = nil,
        onOpenContextMenuPreview: ((String) -> Void)? = nil
    ) {
        self.store = store
        self.isVisible = isVisible
        self.onClose = onClose
        self.onNewConversation = onNewConversation
        self.onOpenAutomations = onOpenAutomations
        self.onOpenCustomizations = onOpenCustomizations
        self.onOpenSettings = onOpenSettings
        self.onOpenDisplayOptions = onOpenDisplayOptions
        self.onOpenNewProject = onOpenNewProject
        self.onSelectProject = onSelectProject
        self.onOpenProjectCustomizations = onOpenProjectCustomizations
        self.onOpenConversation = onOpenConversation
        self.onOpenContextMenuPreview = onOpenContextMenuPreview
    }

    private var lang: AppLanguage {
        store.appearancePreferences.language
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
        var isTitleLoading: Bool = false
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
                    timestampLabel: AppLocalizationFormatter.localizeRelativeTime("1h", language: lang),
                    isSelected: false
                )
            ].filter(matchesSearch)
        }
        return store.summaries
            .filter { $0.isPinned && !$0.isArchived && store.summaryMatchesHostScope($0) }
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
                    timestampLabel: AppLocalizationFormatter.localizeRelativeTime("4h", language: lang),
                    isSelected: false
                ),
                DrawerConversationRow(
                    id: "cas-idempotency-keys",
                    title: "Idempotency keys for payouts",
                    projectSlug: "ledger-svc",
                    status: .done,
                    isUnread: false,
                    isPinned: false,
                    timestampLabel: AppLocalizationFormatter.localizeRelativeTime("1d", language: lang),
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
                    timestampLabel: AppLocalizationFormatter.localizeRelativeTime("2d", language: lang),
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
            guard store.summaryMatchesHostScope(summary) else { return false }
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
        for proj in store.projects where store.projectMatchesHostScope(proj) {
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
                        displayName: proj.isNoProject ? lang.t(proj.name, "无项目") : proj.name,
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
                    displayName: lang.t(AntigravityCloudDetector.noProjectDisplayName, "无项目"),
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
            title: store.displayTitle(for: summary),
            projectSlug: summary.projectSlug,
            status: summary.status,
            isUnread: summary.isUnread,
            isPinned: summary.isPinned,
            timestampLabel: AppLocalizationFormatter.localizeRelativeTime(summary.relativeTimeLabel, language: lang),
            isSelected: summary.cascadeId == store.activeCascadeId && {
                if case .cascadeChat = store.activeRoute { return true }
                return false
            }(),
            isTitleLoading: store.isSummaryTitleLoading(summary)
        )
    }

    private func matchesSearch(_ row: DrawerConversationRow) -> Bool {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return true }
        return row.title.lowercased().contains(q) || row.projectSlug.lowercased().contains(q)
    }

    public var body: some View {
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
                .accessibilityLabel(lang.t("Close sidebar", "关闭侧边栏"))
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
                .accessibilityLabel(lang.t("Search sidebar", "搜索侧边栏"))
                .accessibilityIdentifier("btn-drawer-search")
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            if isSearchExpanded {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14))
                        .foregroundStyle(AntigravityTheme.textMuted)
                    TextField(lang.t("Search conversations", "搜索对话"), text: $searchQuery)
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
                LazyVStack(alignment: .leading, spacing: 6) {
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
                            Text(lang.t("New Conversation", "新建对话"))
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
                        title: lang.t("Automations", "自动化"),
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
                        title: lang.t("Customizations", "自定义"),
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
                        Text(lang.t("Pinned", "已置顶"))
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(AntigravityTheme.textSecondary)
                            .padding(.horizontal, 18)
                            .padding(.top, 16)
                            .padding(.bottom, 4)

                        ForEach(pinnedConversations) { row in
                            drawerConversationItem(row, indented: false)
                                .onAppear {
                                    store.requestPreloadForVisibleConversation(row.id)
                                }
                        }
                    }

                    // Projects Section Header + Filter / New Project Actions
                    HStack(spacing: 8) {
                        Text(lang.t("Projects", "项目"))
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
                        .accessibilityLabel(lang.t("Display options", "显示选项"))
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
                        .accessibilityLabel(lang.t("New project", "新建项目"))
                        .accessibilityIdentifier("btn-new-project")
                    }
                    .padding(.leading, 18)
                    .padding(.trailing, 10)
                    .padding(.top, 14)

                    // Project Groups & Conversations (with direct tap collapse/expand & long-press project actions)
                    ForEach(projectGroups) { group in
                        let isCollapsed = searchQuery.isEmpty && store.isProjectCollapsed(group.id)
                        let isNoProjectGroup = AntigravityCloudDetector.isNoProjectSlug(group.id)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 2) {
                                Button {
                                    if !group.conversations.isEmpty {
                                        withAnimation(.snappy(duration: 0.2)) {
                                            store.toggleProjectCollapsedPersisted(group.id)
                                        }
                                    } else if let onSelectProject {
                                        onSelectProject(group.id)
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
                                            .truncationMode(.tail)
                                        if isCollapsed && !group.conversations.isEmpty {
                                            Text("\(group.conversations.count)")
                                                .font(.system(size: 12, weight: .medium))
                                                .foregroundStyle(AntigravityTheme.textMuted)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(
                                                    Capsule()
                                                        .fill(AntigravityTheme.surfaceElevated)
                                                )
                                                .accessibilityIdentifier("project-collapsed-count-\(group.id)")
                                        }
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("project-header-\(group.id)")
                                .contextMenu {
                                    Button {
                                        if let onOpenConversation {
                                            onOpenConversation("new-\(group.id)")
                                        } else {
                                            store.isSidebarPresented = false
                                            _ = store.createConversationInProject(group.id)
                                        }
                                    } label: {
                                        Label(lang.t("New Conversation in Project", "在项目中新建会话"), systemImage: "plus.bubble")
                                    }

                                    if !isNoProjectGroup {
                                        Button {
                                            if let onOpenProjectCustomizations {
                                                onOpenProjectCustomizations(group.id)
                                            } else {
                                                store.isSidebarPresented = false
                                                store.selectProject(group.id)
                                                store.activeRoute = .rulesAndSkills
                                            }
                                        } label: {
                                            Label(lang.t("Project Rules & Skills", "项目规则与技能"), systemImage: "doc.text")
                                        }

                                        if !group.isCloud {
                                            Button {
                                                store.revealProjectInFinder(group.id)
                                            } label: {
                                                Label(lang.t("Reveal in Finder on Mac", "在 Mac 访达中显示"), systemImage: "laptopcomputer")
                                            }
                                        }
                                    }
                                }

                                if !group.conversations.isEmpty {
                                    Button {
                                        withAnimation(.snappy(duration: 0.2)) {
                                            store.toggleProjectCollapsedPersisted(group.id)
                                        }
                                    } label: {
                                        Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                                            .font(.system(size: 11.5, weight: .semibold))
                                            .foregroundStyle(AntigravityTheme.textMuted)
                                            .frame(width: 32, height: 36)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(isCollapsed ? lang.t("Expand \(group.displayName)", "展开 \(group.displayName)") : lang.t("Collapse \(group.displayName)", "收起 \(group.displayName)"))
                                    .accessibilityIdentifier("btn-toggle-project-\(group.id)")
                                }

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

                            if !isCollapsed {
                                LazyVStack(alignment: .leading, spacing: 2) {
                                    ForEach(group.conversations) { row in
                                        drawerConversationItem(row, indented: true)
                                            .onAppear {
                                                store.requestPreloadForVisibleConversation(row.id)
                                            }
                                    }
                                }
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
                    Text(lang.t("Settings", "设置"))
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
        .background(AntigravityTheme.surfaceSheet.ignoresSafeArea())
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(AntigravityTheme.cardBorder)
                .frame(width: 1)
                .ignoresSafeArea()
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .onAppear {
            store.scheduleConversationPreload()
        }
        .onChange(of: store.isSidebarPresented) { _, presented in
            if presented {
                store.scheduleConversationPreload()
            }
        }
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
                if row.isTitleLoading {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(AntigravityTheme.textMuted)
                        Text(lang.t("Loading...", "加载中..."))
                            .font(.system(size: 14.5, weight: .regular))
                            .foregroundStyle(AntigravityTheme.textMuted)
                            .lineLimit(1)
                    }
                    .accessibilityIdentifier("drawer-conv-loading-\(row.id)")
                } else {
                    Text(row.title)
                        .font(.system(size: 15.5, weight: .regular))
                        .foregroundStyle(AntigravityTheme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

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
                Label(row.isPinned ? lang.t("Unpin", "取消置顶") : lang.t("Pin", "置顶"), systemImage: row.isPinned ? "pin.slash" : "pin")
            }
            Button {
                store.toggleUnreadCascade(row.id)
            } label: {
                Label(row.isUnread ? lang.t("Mark as read", "标为已读") : lang.t("Mark as unread", "标为未读"), systemImage: "envelope.badge")
            }
            Button {
                store.archiveCascade(row.id)
            } label: {
                Label(lang.t("Archive", "归档"), systemImage: "archivebox")
            }
            Divider()
            Button(role: .destructive) {
                store.deleteCascade(row.id)
            } label: {
                Label(lang.t("Delete", "删除"), systemImage: "trash")
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
            AntigravityRunningArcIndicatorView(
                isAnimated: isVisible && (!store.isVerificationMode || store.isLiveBackendConnected)
            )
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
            withAnimation(.spring(duration: 0.28, bounce: 0.0)) {
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

    private var lang: AppLanguage {
        store.appearancePreferences.language
    }

    private var matchingConversations: [CascadeSummary] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let isLive = !store.isVerificationMode || store.hasPairedBackend || store.isLiveBackendConnected
        let base = store.summaries.filter { !$0.isArchived && (!isLive || store.summaryMatchesHostScope($0)) }
        guard !q.isEmpty else { return Array(base.prefix(8)) }
        return base.filter {
            store.displayTitle(for: $0).lowercased().contains(q)
                || $0.projectSlug.lowercased().contains(q)
                || $0.statusSubtitle.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(AntigravityTheme.textSecondary)
                TextField(lang.t("Search conversations & projects", "搜索对话与项目"), text: $query)
                    .font(.system(size: 16))
                    .foregroundStyle(AntigravityTheme.textPrimary)
                    .onChange(of: query) { _, newValue in
                        if !store.isVerificationMode {
                            Task { await store.runFullTextConversationSearch(newValue) }
                        }
                    }
                    .accessibilityIdentifier("global-search-input")

                Button(lang.t("Cancel", "取消")) {
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
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(matchingConversations) { summary in
                        let isTitleLoading = store.isSummaryTitleLoading(summary)
                        Button {
                            onSelectConversation(summary.cascadeId)
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    if isTitleLoading {
                                        HStack(spacing: 8) {
                                            ProgressView()
                                                .controlSize(.mini)
                                                .tint(AntigravityTheme.textMuted)
                                            Text(lang.t("Loading...", "加载中..."))
                                                .font(.system(size: 14.5, weight: .medium))
                                                .foregroundStyle(AntigravityTheme.textMuted)
                                                .lineLimit(1)
                                        }
                                    } else {
                                        Text(store.displayTitle(for: summary))
                                            .font(.system(size: 15.5, weight: .medium))
                                            .foregroundStyle(AntigravityTheme.textPrimary)
                                            .lineLimit(1)
                                    }
                                    Text("\(summary.projectSlug) · \(summary.statusSubtitle)")
                                        .font(.system(size: 13))
                                        .foregroundStyle(AntigravityTheme.textSecondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Text(AppLocalizationFormatter.localizeRelativeTime(summary.relativeTimeLabel, language: lang))
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
                        .onAppear {
                            store.requestPreloadForVisibleConversation(summary.cascadeId)
                        }
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
