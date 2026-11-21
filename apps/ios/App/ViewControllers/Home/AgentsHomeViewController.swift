import SwiftUI
import AntigravityData
#if canImport(UIKit)
import UIKit
#endif

/// State `UE01_AGENTS_HOME`: Primary Agents Hub (Conversation & Project Hub).
/// Matches `/home/antigravity/iOS_·_Agents_首页.png` 1:1.
public struct AgentsHomeViewController: View {
    @Bindable public var store: AntigravitySessionStore
    @Environment(\.displayScale) private var displayScale
    @Environment(\.colorScheme) private var colorScheme

    public var onSelectTab: ((ShellTab) -> Void)?
    public var onOpenDisplayOptions: (() -> Void)?
    public var onOpenNewProject: (() -> Void)?
    public var onOpenProjectDetail: ((String) -> Void)?
    public var onOpenContextMenuPreview: (() -> Void)?
    public var onOpenConversation: ((String) -> Void)?

    public typealias HostFilterTarget = AgentsHostFilterScope

    public enum QuickStatusFilter: String, CaseIterable, Identifiable {
        case all
        case running
        case needsYou
        case unread

        public var id: String { rawValue }
    }

    public enum IndicatorStyle: Equatable {
        case runningArc
        case needsReviewHalo
        case unreadDot
        case none
    }

    public struct AgentConversationItem: Identifiable, Equatable {
        public let id: String
        public var title: String
        public var statusLine: String
        public var statusHighlight: StatusTone
        public var projectSlug: String
        public var timestampLabel: String
        public var additions: Int?
        public var deletions: Int?
        public var indicator: IndicatorStyle
        public var isPinned: Bool
        public var isUnread: Bool
        public var isArchived: Bool

        public enum StatusTone: Equatable {
            case running
            case waiting
            case neutral
        }
    }

    public struct AgentProjectSection: Identifiable, Equatable {
        public let id: String
        public var slug: String
        public var subtitle: String
        public var isCloud: Bool
        public var conversations: [AgentConversationItem]
    }

    private var selectedHost: AgentsHostFilterScope {
        store.selectedHostScope
    }
    @State private var searchText: String = ""
    @State private var selectedFilter: QuickStatusFilter = .all
    @State private var collapsedProjects: Set<String> = []
    @State private var standaloneSheet: StandaloneModal?

    @State private var pinnedItems: [AgentConversationItem] = [
        AgentConversationItem(
            id: "conv-rate-limiter",
            title: "Add rate limiter to /transfers",
            statusLine: "Running · Step 4 of 7 · go test ./internal/...",
            statusHighlight: .running,
            projectSlug: "ledger-svc",
            timestampLabel: "now",
            additions: nil,
            deletions: nil,
            indicator: .runningArc,
            isPinned: true,
            isUnread: false,
            isArchived: false
        ),
        AgentConversationItem(
            id: "conv-release-checklist",
            title: "Release checklist v2.3",
            statusLine: "Done · Walkthrough ready",
            statusHighlight: .neutral,
            projectSlug: "web-console",
            timestampLabel: "1h",
            additions: nil,
            deletions: nil,
            indicator: .none,
            isPinned: true,
            isUnread: false,
            isArchived: false
        )
    ]

    @State private var projectSections: [AgentProjectSection] = [
        AgentProjectSection(
            id: "ledger-svc",
            slug: "ledger-svc",
            subtitle: "Local · MacBook Pro · main",
            isCloud: false,
            conversations: [
                AgentConversationItem(
                    id: "conv-flaky-settlement",
                    title: "Fix flaky TestSettlementBatch",
                    statusLine: "Needs review · Implementation plan ready",
                    statusHighlight: .waiting,
                    projectSlug: "ledger-svc",
                    timestampLabel: "8m",
                    additions: nil,
                    deletions: nil,
                    indicator: .needsReviewHalo,
                    isPinned: false,
                    isUnread: true,
                    isArchived: false
                ),
                AgentConversationItem(
                    id: "conv-upgrade-go",
                    title: "Upgrade to Go 1.25",
                    statusLine: "Done · 6 files changed",
                    statusHighlight: .neutral,
                    projectSlug: "ledger-svc",
                    timestampLabel: "1h",
                    additions: 42,
                    deletions: 31,
                    indicator: .unreadDot,
                    isPinned: false,
                    isUnread: true,
                    isArchived: false
                ),
                AgentConversationItem(
                    id: "conv-idempotency-keys",
                    title: "Idempotency keys for payouts",
                    statusLine: "Done · Merged into main",
                    statusHighlight: .neutral,
                    projectSlug: "ledger-svc",
                    timestampLabel: "Yesterday",
                    additions: nil,
                    deletions: nil,
                    indicator: .none,
                    isPinned: false,
                    isUnread: false,
                    isArchived: false
                )
            ]
        ),
        AgentProjectSection(
            id: "web-console",
            slug: "web-console",
            subtitle: "Cloud · acme/web-console · main",
            isCloud: true,
            conversations: [
                AgentConversationItem(
                    id: "conv-web-console-csp",
                    title: "Audit CSP headers for checkout",
                    statusLine: "Running in cloud · Step 2 of 5",
                    statusHighlight: .running,
                    projectSlug: "web-console",
                    timestampLabel: "now",
                    additions: nil,
                    deletions: nil,
                    indicator: .runningArc,
                    isPinned: false,
                    isUnread: true,
                    isArchived: false
                )
            ]
        )
    ]

    private enum StandaloneModal: String, Identifiable {
        case displayOptions
        case newProject
        case contextMenu

        var id: String { rawValue }
    }

    public init(
        store: AntigravitySessionStore,
        onSelectTab: ((ShellTab) -> Void)? = nil,
        onOpenDisplayOptions: (() -> Void)? = nil,
        onOpenNewProject: (() -> Void)? = nil,
        onOpenProjectDetail: ((String) -> Void)? = nil,
        onOpenContextMenuPreview: (() -> Void)? = nil,
        onOpenConversation: ((String) -> Void)? = nil
    ) {
        self.store = store
        self.onSelectTab = onSelectTab
        self.onOpenDisplayOptions = onOpenDisplayOptions
        self.onOpenNewProject = onOpenNewProject
        self.onOpenProjectDetail = onOpenProjectDetail
        self.onOpenContextMenuPreview = onOpenContextMenuPreview
        self.onOpenConversation = onOpenConversation
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    topHeaderToolbar
                    heroTitleAndSearchSection
                    filterPillStrip
                    if !filteredPinnedItems.isEmpty {
                        pinnedSectionView
                    }
                    ForEach(filteredProjectSections) { project in
                        projectSectionView(project)
                    }
                    if usesLiveStoreData && filteredPinnedItems.isEmpty && filteredProjectSections.isEmpty {
                        liveEmptyConversationsCard
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 96)
            }
            .refreshable {
                if store.hasPairedBackend && store.isDeviceNetworkReachable && isSelectedHostOnline {
                    _ = await store.refreshConversationsForHostScope(store.selectedHostScope, forceFullSync: true)
                } else {
                    await store.reconnectNow(userInitiated: true)
                }
            }

            // Subtle bottom obsidian gradient behind floating liquid glass chrome
            LinearGradient(
                colors: [
                    AntigravityTheme.canvasObsidian.opacity(0.0),
                    AntigravityTheme.canvasObsidian.opacity(0.82),
                    AntigravityTheme.canvasObsidian
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 84)
            .allowsHitTesting(false)

            AntigravityFloatingTabBar(
                selectedTab: .agents,
                tabBarAccessibilityId: "floating-tab-bar",
                fabAccessibilityId: "fab-compose",
                onSelectTab: { tab in
                    onSelectTab?(tab)
                },
                onTapFAB: {
                    triggerOpenConversation("new-conversation")
                }
            )
        }
        .background(AntigravityTheme.canvasObsidian.ignoresSafeArea())
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
    }

    // MARK: - 1. Top Bar (Host Switcher + Display Options + New Project)

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

    private func isProjectHostOnline(_ proj: ProjectWorkspace) -> Bool {
        guard store.hasPairedBackend else { return true }
        if proj.runtime == .cloud {
            return store.isDeviceNetworkReachable
        }
        return store.isLocalHostOnline(instanceId: proj.originInstanceUuid, hostname: proj.hostName)
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
            if store.hasPairedBackend {
                if isConnectingToHost {
                    return resolved
                }
                return isSelectedHostOnline ? resolved : "\(resolved) · Offline"
            }
            return resolved
        case .allHosts:
            if store.hasPairedBackend {
                if pairedLocalHosts.count > 1 {
                    if isConnectingToHost {
                        return "All Hosts"
                    }
                    return isSelectedHostOnline ? "All Hosts" : "All Hosts · Offline"
                }
                if isConnectingToHost {
                    return store.activeHost.hostname
                }
                return isSelectedHostOnline
                    ? store.activeHost.hostname
                    : "\(store.activeHost.hostname) · Offline"
            }
            return "MacBook Pro"
        }
    }

    private var topHeaderToolbar: some View {
        HStack(spacing: 8) {
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
                            onSelectTab?(.settings)
                        } label: {
                            Label("Host & Pairing Settings", systemImage: "qrcode.viewfinder")
                        }
                    } else {
                        Button {
                            onSelectTab?(.settings)
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
                        .font(.system(size: 14.5, weight: .medium))
                        .foregroundStyle(AntigravityTheme.textPrimary)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AntigravityTheme.textSecondary)
                }
                .padding(.horizontal, 14)
                .frame(minHeight: AntigravityTheme.minTouchTargetPt)
                .background(
                    Capsule()
                        .fill(AntigravityTheme.surfacePill)
                )
                .overlay(
                    Capsule()
                        .strokeBorder(AntigravityTheme.cardBorder, lineWidth: 1)
                )
            }
            .accessibilityIdentifier("host-switcher-pill")

            Spacer()

            Button {
                if let onOpenDisplayOptions {
                    onOpenDisplayOptions()
                } else {
                    standaloneSheet = .displayOptions
                }
            } label: {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AntigravityTheme.textPrimary)
                    .frame(width: AntigravityTheme.minTouchTargetPt, height: AntigravityTheme.minTouchTargetPt)
                    .background(
                        Circle()
                            .fill(AntigravityTheme.surfacePill)
                    )
                    .overlay(
                        Circle()
                            .strokeBorder(AntigravityTheme.cardBorder, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("btn-display-options")

            Button {
                if let onOpenNewProject {
                    onOpenNewProject()
                } else {
                    standaloneSheet = .newProject
                }
            } label: {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AntigravityTheme.textPrimary)
                    .frame(width: AntigravityTheme.minTouchTargetPt, height: AntigravityTheme.minTouchTargetPt)
                    .background(
                        Circle()
                            .fill(AntigravityTheme.surfacePill)
                    )
                    .overlay(
                        Circle()
                            .strokeBorder(AntigravityTheme.cardBorder, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("btn-new-project")
        }
    }

    // MARK: - 2. Large Title & Search Conversations Input

    private var heroTitleAndSearchSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Agents")
                .font(.system(size: 32, weight: .bold))
                .tracking(-0.5)
                .foregroundStyle(AntigravityTheme.textPrimary)

            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(AntigravityTheme.textMuted)

                TextField("Search conversations", text: $searchText)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(AntigravityTheme.textPrimary)
                    .tint(AntigravityTheme.accentPeriwinkle)
                    .onChange(of: searchText) { _, newValue in
                        if usesLiveStoreData {
                            Task {
                                await store.runFullTextConversationSearch(newValue)
                            }
                        }
                    }

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                        if usesLiveStoreData {
                            store.remoteSearchResults = []
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(AntigravityTheme.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 13)
            .frame(minHeight: AntigravityTheme.minTouchTargetPt)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AntigravityTheme.surfacePill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(AntigravityTheme.glassHairline, lineWidth: 1)
            )
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("agents-search-input")
        }
    }

    // MARK: - 3. Filter Pills Strip

    private var filterPillStrip: some View {
        let usesPairedCounts = usesLiveStoreData
        let runningBadge = usesPairedCounts ? store.runningCount(for: selectedHost) : 2
        let needsYouBadge = usesPairedCounts ? store.needsYouCount(for: selectedHost) : 1
        let unreadBadge = usesPairedCounts ? store.unreadCount(for: selectedHost) : 3

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                filterPillButton(
                    filter: .all,
                    label: "All",
                    dotColor: nil,
                    accessibilityId: "filter-pill-all"
                )
                filterPillButton(
                    filter: .running,
                    label: "Running \(runningBadge)",
                    dotColor: AntigravityTheme.statusRunning,
                    accessibilityId: "filter-pill-running"
                )
                filterPillButton(
                    filter: .needsYou,
                    label: "Needs you \(needsYouBadge)",
                    dotColor: AntigravityTheme.statusWaiting,
                    accessibilityId: "filter-pill-needs-you"
                )
                filterPillButton(
                    filter: .unread,
                    label: "Unread \(unreadBadge)",
                    dotColor: nil,
                    accessibilityId: "filter-pill-unread"
                )
            }
        }
    }

    private func filterPillButton(
        filter: QuickStatusFilter,
        label: String,
        dotColor: Color?,
        accessibilityId: String
    ) -> some View {
        let isActive = (selectedFilter == filter)
        return Button {
            selectedFilter = filter
        } label: {
            HStack(spacing: 5) {
                if let dotColor {
                    Circle()
                        .fill(isActive ? AntigravityTheme.pillActiveForeground : dotColor)
                        .frame(width: 7, height: 7)
                }
                Text(label)
                    .font(.system(size: 13.5, weight: isActive ? .semibold : .medium))
                    .foregroundStyle(isActive ? AntigravityTheme.pillActiveForeground : AntigravityTheme.textBody)
                    .lineLimit(1)
            }
            .padding(.horizontal, 11.5)
            .frame(minWidth: 44, minHeight: AntigravityTheme.minTouchTargetPt)
            .background(
                Capsule()
                    .fill(isActive ? AntigravityTheme.pillActiveBackground : AntigravityTheme.surfacePill)
            )
            .overlay(
                Capsule()
                    .strokeBorder(isActive ? Color.clear : AntigravityTheme.cardBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityId)
    }

    // MARK: - 4. Pinned Conversations Card

    private var pinnedSectionView: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 5) {
                Image(systemName: "pin")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AntigravityTheme.textMuted)
                Text("PINNED")
                    .font(.system(size: 11.5, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(AntigravityTheme.textMuted)
            }
            .padding(.leading, 4)
            .padding(.top, 2)

            VStack(spacing: 0) {
                ForEach(Array(filteredPinnedItems.enumerated()), id: \.element.id) { index, item in
                    conversationRow(item: item, showProjectSlug: true)
                    if index < filteredPinnedItems.count - 1 {
                        Divider()
                            .overlay(AntigravityTheme.subtleDivider)
                            .padding(.leading, 44)
                    }
                }
            }
            .background(AntigravityTheme.surfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(AntigravityTheme.cardBorder, lineWidth: 1)
            )
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("pinned-section-card")
        }
    }

    // MARK: - 5. Collapsible Project Group Sections

    private func projectSectionView(_ project: AgentProjectSection) -> some View {
        let isCollapsed = store.isVerificationMode
            ? collapsedProjects.contains(project.id)
            : store.isProjectCollapsed(project.id)
        let isNoProj = AntigravityCloudDetector.isNoProjectSlug(project.slug)
        let headerIcon = project.isCloud ? "cloud" : (isNoProj ? "bubble.left.and.bubble.right" : "folder")
        let a11ySuffix = (project.id != project.slug) ? project.id : project.slug
        let displayedSubtitle: String = {
            if !store.isVerificationMode && store.appearancePreferences.interfaceLayout == .knowledgeWork {
                return project.isCloud ? "Antigravity Cloud" : "Workspace"
            }
            return project.subtitle
        }()

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    triggerOpenProjectDetail(project.id)
                } label: {
                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(AntigravityTheme.surfacePill)
                            .frame(width: 34, height: 34)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(AntigravityTheme.cardBorder, lineWidth: 1)
                            )
                            .overlay(
                                Image(systemName: headerIcon)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(AntigravityTheme.textBody)
                            )

                        VStack(alignment: .leading, spacing: 1) {
                            Text(project.slug)
                                .font(.system(size: 16.5, weight: .semibold))
                                .foregroundStyle(AntigravityTheme.textPrimary)
                            Text(displayedSubtitle)
                                .font(.system(size: 12.5, weight: .regular))
                                .foregroundStyle(AntigravityTheme.textMuted)
                        }
                    }
                    .frame(minHeight: AntigravityTheme.minTouchTargetPt)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("project-header-\(a11ySuffix)")

                Spacer(minLength: 4)

                Button {
                    triggerOpenConversation("new-\(project.id)")
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(AntigravityTheme.textBody)
                        .frame(width: AntigravityTheme.minTouchTargetPt, height: AntigravityTheme.minTouchTargetPt)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("btn-add-conv-\(a11ySuffix)")

                Button {
                    if store.isVerificationMode {
                        if isCollapsed {
                            collapsedProjects.remove(project.id)
                        } else {
                            collapsedProjects.insert(project.id)
                        }
                    } else {
                        store.toggleProjectCollapsedPersisted(project.id)
                    }
                } label: {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AntigravityTheme.textSecondary)
                        .frame(width: AntigravityTheme.minTouchTargetPt, height: AntigravityTheme.minTouchTargetPt)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("btn-collapse-\(a11ySuffix)")
            }

            if !isCollapsed {
                VStack(spacing: 0) {
                    if project.conversations.isEmpty && usesLiveStoreData {
                        Button {
                            triggerOpenConversation("new-\(project.id)")
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "plus.bubble")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(AntigravityTheme.accentPeriwinkle)
                                Text(isNoProj ? "No unassigned conversations yet · Start one" : "No conversations yet · Start one in \(project.slug)")
                                    .font(.system(size: 14, weight: .regular))
                                    .foregroundStyle(AntigravityTheme.textSecondary)
                                Spacer()
                            }
                            .padding(.horizontal, 14)
                            .frame(minHeight: 52)
                        }
                        .buttonStyle(AntigravityInteractiveRowButtonStyle())
                        .accessibilityIdentifier("empty-project-conv-\(a11ySuffix)")
                    } else {
                        ForEach(Array(project.conversations.enumerated()), id: \.element.id) { index, item in
                            conversationRow(item: item, showProjectSlug: false)
                            if index < project.conversations.count - 1 {
                                Divider()
                                    .overlay(AntigravityTheme.subtleDivider)
                                    .padding(.leading, 44)
                            }
                        }
                    }
                }
                .background(AntigravityTheme.surfaceCard)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(AntigravityTheme.cardBorder, lineWidth: 1)
                )
            }
        }
        .padding(.top, 2)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(
            project.slug == "ledger-svc" ? "project-group-ledger-svc" : "project-group-\(a11ySuffix)"
        )
    }

    // MARK: - 6. Conversation Row with Full-Width Hit-Testing & Context Menu

    private func triggerOpenConversation(_ id: String) {
        if id == "new-conversation" {
            if selectedHost == .antigravityCloud {
                if usesLiveStoreData {
                    let cloudTarget = "new-cloud:\(AntigravityCloudDetector.noProjectDisplayName)"
                    if let onOpenConversation {
                        onOpenConversation(cloudTarget)
                    } else {
                        _ = store.createConversationInProject("cloud:\(AntigravityCloudDetector.noProjectDisplayName)")
                    }
                } else if let cloudProj = store.projects.first(where: { $0.runtime == .cloud }) {
                    if let onOpenConversation {
                        onOpenConversation("new-\(cloudProj.id)")
                    } else {
                        _ = store.createConversationInProject(cloudProj.id)
                    }
                } else {
                    store.newProjectDraft.runsOn = .cloud
                    if let onOpenNewProject {
                        onOpenNewProject()
                    } else {
                        standaloneSheet = .newProject
                    }
                }
                return
            }

            if usesLiveStoreData {
                let noProjTarget = "new-\(AntigravityCloudDetector.noProjectDisplayName)"
                if let onOpenConversation {
                    onOpenConversation(noProjTarget)
                } else {
                    _ = store.createConversationInProject(AntigravityCloudDetector.noProjectDisplayName)
                }
                return
            }
        }

        if let onOpenConversation {
            onOpenConversation(id)
            return
        }
        if id == "new-conversation" || id.hasPrefix("new-") {
            let slug: String = {
                if id.hasPrefix("new-") && id != "new-conversation" {
                    return String(id.dropFirst(4))
                }
                if !store.selectedProjectId.isEmpty {
                    return store.selectedProjectId
                }
                return "ledger-svc"
            }()
            _ = store.createConversationInProject(slug)
            return
        }
        store.selectCascade(id)
    }

    private func triggerOpenProjectDetail(_ slug: String) {
        if let onOpenProjectDetail {
            onOpenProjectDetail(slug)
        } else {
            store.selectProject(slug)
        }
    }

    private var shouldAnimateLive: Bool {
        !store.isVerificationMode || store.isLiveBackendConnected
    }

    private func conversationRow(item: AgentConversationItem, showProjectSlug: Bool) -> some View {
        Button {
            triggerOpenConversation(item.id)
        } label: {
            HStack(alignment: .center, spacing: 11) {
                HStack(alignment: .top, spacing: 11) {
                    leadingStatusIndicator(item.indicator)
                        .frame(width: 18, height: 20)
                        .padding(.top, 1)

                    VStack(alignment: .leading, spacing: 2.5) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(item.title)
                                .font(.system(size: 15.5, weight: .semibold))
                                .foregroundStyle(AntigravityTheme.textPrimary)
                                .lineLimit(1)
                            Spacer(minLength: 6)
                            if item.indicator == .runningArc {
                                AntigravityFourDotLoadingView(isAnimated: shouldAnimateLive)
                                    .accessibilityElement(children: .ignore)
                                    .accessibilityLabel("Running")
                                    .accessibilityIdentifier("loading-four-dots-\(item.id)")
                            } else {
                                Text(item.timestampLabel)
                                    .font(.system(size: 12.5, weight: .regular))
                                    .foregroundStyle(AntigravityTheme.textMuted)
                            }
                        }

                        HStack(spacing: 5) {
                            Text(item.statusLine)
                                .font(.system(size: 13.5, weight: .regular))
                                .foregroundStyle(statusTextColor(for: item.statusHighlight))
                                .lineLimit(1)

                            if let add = item.additions, let del = item.deletions {
                                Text("+\(add)")
                                    .font(.system(size: 13.5, weight: .medium))
                                    .foregroundStyle(AntigravityTheme.statusDone)
                                Text("−\(del)")
                                    .font(.system(size: 13.5, weight: .medium))
                                    .foregroundStyle(AntigravityTheme.statusError)
                            }
                        }

                        if showProjectSlug {
                            let cleanSlug = AntigravityCloudDetector.stripProjectScopePrefix(item.projectSlug)
                            let displaySlug = AntigravityCloudDetector.isNoProjectSlug(cleanSlug)
                                ? AntigravityCloudDetector.noProjectDisplayName
                                : cleanSlug
                            Text(displaySlug)
                                .font(.system(size: 12.5, weight: .regular))
                                .foregroundStyle(AntigravityTheme.textMuted)
                        }
                    }
                }

                if store.isLiveBackendConnected && item.indicator != .runningArc {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(AntigravityTheme.textMuted.opacity(0.65))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(minHeight: 58)
        }
        .buttonStyle(AntigravityInteractiveRowButtonStyle())
        .contextMenu {
            Button {
                togglePinConversation(id: item.id)
            } label: {
                Label(item.isPinned ? "Unpin" : "Pin", systemImage: "pin")
            }
            Button {
                toggleUnreadConversation(id: item.id)
            } label: {
                Label("Mark as Unread", systemImage: "circle.inset.filled")
            }
            Button {
                if let onOpenContextMenuPreview {
                    onOpenContextMenuPreview()
                } else {
                    standaloneSheet = .contextMenu
                }
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            Button {
                triggerOpenProjectDetail(item.projectSlug)
            } label: {
                Label("Move to Project", systemImage: "folder")
            }
            Divider()
            Button {
                archiveConversation(id: item.id)
            } label: {
                Label("Archive", systemImage: "archivebox")
            }
            Button(role: .destructive) {
                deleteConversation(id: item.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .accessibilityIdentifier("conv-row-\(item.id)")
    }

    @ViewBuilder
    private func leadingStatusIndicator(_ style: IndicatorStyle) -> some View {
        switch style {
        case .runningArc:
            AntigravityRunningArcIndicatorView(isAnimated: shouldAnimateLive)
        case .needsReviewHalo:
            ZStack {
                Circle()
                    .fill(AntigravityTheme.statusWaiting.opacity(0.22))
                    .frame(width: 18, height: 18)
                Circle()
                    .fill(AntigravityTheme.statusWaiting)
                    .frame(width: 8.5, height: 8.5)
            }
        case .unreadDot:
            ZStack {
                Circle()
                    .fill(AntigravityTheme.statusRunning.opacity(0.20))
                    .frame(width: 17, height: 17)
                Circle()
                    .fill(AntigravityTheme.statusRunning)
                    .frame(width: 8, height: 8)
            }
        case .none:
            Color.clear
                .frame(width: 15, height: 15)
        }
    }

    private func statusTextColor(for tone: AgentConversationItem.StatusTone) -> Color {
        switch tone {
        case .running: return AntigravityTheme.statusRunning
        case .waiting: return AntigravityTheme.statusWaiting
        case .neutral: return AntigravityTheme.textSecondary
        }
    }

    // MARK: - Filtering & Live Store Binding

    private var syncingStatusMessage: String {
        if isConnectingToHost {
            let trimmedStatus = store.connectionStatusText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedStatus.isEmpty && trimmedStatus != "Not Connected" {
                return trimmedStatus
            }
            return "Connecting to \(selectedHostDisplayName)..."
        }
        switch selectedHost {
        case .antigravityCloud:
            return "Syncing Antigravity Cloud sessions..."
        case .allHosts where pairedLocalHosts.count > 1:
            return "Syncing conversations across all hosts..."
        default:
            return "Syncing conversations from \(selectedHostDisplayName)..."
        }
    }

    private var isShowingLoadingEmptyState: Bool {
        isConnectingToHost || store.isRefreshingSummaries || store.isRefreshingSelectedHost || store.isSwitchingHost
    }

    private var liveEmptyConversationsCard: some View {
        VStack(spacing: 10) {
            if isShowingLoadingEmptyState {
                VStack(spacing: 10) {
                    AntigravityFourDotLoadingView(
                        isAnimated: shouldAnimateLive,
                        dotSize: 5.5,
                        spacing: 4.5,
                        tint: AntigravityTheme.accentPeriwinkle
                    )
                    Text(isConnectingToHost ? "Loading conversations..." : "Syncing conversations...")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AntigravityTheme.textPrimary)
                        .accessibilityIdentifier("agents-loading-conversations")
                    Text(syncingStatusMessage)
                        .font(.system(size: 13.5, weight: .regular))
                        .foregroundStyle(AntigravityTheme.textSecondary)
                        .multilineTextAlignment(.center)
                }
            } else if selectedHost == .antigravityCloud && searchText.isEmpty && selectedFilter == .all {
                Image(systemName: "cloud")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(AntigravityTheme.accentPeriwinkle)
                Text(store.cloudAgentWarmingUp ? "Antigravity Cloud is warming up..." : "No Antigravity Cloud conversations yet")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AntigravityTheme.textPrimary)
                Text(
                    store.cloudAgentWarmingUp
                        ? "Remote Agents are initializing on your desktop daemon. Pull down to refresh in a few seconds."
                        : "Create a Cloud project connected to GitHub or start a Cloud Agent session from Antigravity."
                )
                .font(.system(size: 13.5, weight: .regular))
                .foregroundStyle(AntigravityTheme.textSecondary)
                .multilineTextAlignment(.center)

                Button {
                    store.newProjectDraft.runsOn = .cloud
                    if let onOpenNewProject {
                        onOpenNewProject()
                    } else {
                        standaloneSheet = .newProject
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 12.5, weight: .bold))
                        Text("New Cloud Project")
                            .font(.system(size: 13.5, weight: .semibold))
                    }
                    .foregroundStyle(AntigravityTheme.inkOnPrimaryCTA)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 38)
                    .background(AntigravityTheme.accentPeriwinkle)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            } else if store.hasPairedBackend && !isSelectedHostOnline && searchText.isEmpty && selectedFilter == .all {
                Image(systemName: "wifi.slash")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(AntigravityTheme.statusError)
                Text("\(selectedHostDisplayName) is offline")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AntigravityTheme.textPrimary)
                Text("Ensure Antigravity Desktop with Remote Control is running on \(selectedHostDisplayName), or choose another host above.")
                    .font(.system(size: 13.5, weight: .regular))
                    .foregroundStyle(AntigravityTheme.textSecondary)
                    .multilineTextAlignment(.center)

                HStack(spacing: 10) {
                    Button {
                        Task {
                            await store.reconnectNow(userInitiated: true)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 12.5, weight: .bold))
                            Text("Retry Connection")
                                .font(.system(size: 13.5, weight: .semibold))
                        }
                        .foregroundStyle(AntigravityTheme.inkOnPrimaryCTA)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 38)
                        .background(AntigravityTheme.accentPeriwinkle)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    if let onSelectTab {
                        Button {
                            onSelectTab(.settings)
                        } label: {
                            Text("Settings")
                                .font(.system(size: 13.5, weight: .semibold))
                                .foregroundStyle(AntigravityTheme.textPrimary)
                                .padding(.horizontal, 14)
                                .frame(minHeight: 38)
                                .background(AntigravityTheme.surfacePill)
                                .overlay(
                                    Capsule()
                                        .strokeBorder(AntigravityTheme.cardBorder, lineWidth: 1)
                                )
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 4)
            } else {
                Image(systemName: searchText.isEmpty && selectedFilter == .all ? "bubble.left.and.bubble.right" : "magnifyingglass")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(AntigravityTheme.textMuted)
                Text(
                    searchText.isEmpty && selectedFilter == .all
                        ? "No conversations yet"
                        : "No matching conversations"
                )
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AntigravityTheme.textPrimary)
                Text(
                    searchText.isEmpty && selectedFilter == .all
                        ? "Tap the compose button below to start a new session on \(selectedHostDisplayName)."
                        : "Try clearing your search or switching filters."
                )
                .font(.system(size: 13.5, weight: .regular))
                .foregroundStyle(AntigravityTheme.textSecondary)
                .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AntigravityTheme.surfaceCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(AntigravityTheme.cardBorder, lineWidth: 1)
        )
        .padding(.top, 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(isShowingLoadingEmptyState ? "agents-loading-conversations" : "agents-empty-state")
    }

    private var usesLiveStoreData: Bool {
        !store.isVerificationMode || store.hasPairedBackend || store.isLiveBackendConnected || store.summaries.contains(where: { summary in
            ![
                "cas-rate-limiter",
                "cas-release-checklist",
                "cas-flaky-settlement",
                "cas-upgrade-go",
                "cas-idempotency-payouts",
                "cas-pgx-v5-migration",
                "cas-audit-csp-headers",
                "cas-audit-log-admin"
            ].contains(summary.cascadeId)
        })
    }

    private func summaryMatchesHostFilter(_ s: CascadeSummary) -> Bool {
        store.summaryMatchesHostScope(s, scope: selectedHost)
    }

    private func projectMatchesHostFilter(_ proj: ProjectWorkspace) -> Bool {
        store.projectMatchesHostScope(proj, scope: selectedHost)
    }

    private func mapStoreSummary(_ s: CascadeSummary) -> AgentConversationItem {
        let tone: AgentConversationItem.StatusTone
        let indicator: IndicatorStyle
        switch s.status {
        case .inProgress, .pending:
            tone = .running
            indicator = .runningArc
        case .waiting, .blocked:
            tone = .waiting
            indicator = .needsReviewHalo
        default:
            tone = .neutral
            indicator = s.isUnread ? .unreadDot : .none
        }
        return AgentConversationItem(
            id: s.cascadeId,
            title: s.title,
            statusLine: s.statusSubtitle.isEmpty ? (s.lastMessagePreview ?? s.status.displayBadgeText) : s.statusSubtitle,
            statusHighlight: tone,
            projectSlug: s.projectSlug,
            timestampLabel: s.relativeTimeLabel,
            additions: s.totalAdditions > 0 ? s.totalAdditions : nil,
            deletions: s.totalDeletions > 0 ? s.totalDeletions : nil,
            indicator: indicator,
            isPinned: s.isPinned,
            isUnread: s.isUnread,
            isArchived: s.isArchived
        )
    }

    private var filteredPinnedItems: [AgentConversationItem] {
        let source: [AgentConversationItem]
        if usesLiveStoreData {
            source = store.summaries
                .filter { $0.isPinned && summaryMatchesHostFilter($0) }
                .map(mapStoreSummary)
        } else {
            source = pinnedItems.filter { item in
                switch selectedHost {
                case .allHosts: return true
                case .antigravityCloud: return item.projectSlug == "web-console"
                case .localHost: return item.projectSlug != "web-console"
                }
            }
        }
        return source.filter { matchesFilters($0) }
    }

    private var filteredProjectSections: [AgentProjectSection] {
        let sourceSections: [AgentProjectSection]
        if usesLiveStoreData {
            var builtSections: [AgentProjectSection] = store.projects
                .filter { projectMatchesHostFilter($0) }
                .map { proj in
                    let convs = store.summaries
                        .filter { !$0.isPinned && $0.projectSlug == proj.id && summaryMatchesHostFilter($0) }
                        .map(mapStoreSummary)
                    var displayProj = proj
                    if displayProj.runtime != .cloud {
                        displayProj.hostName = store.resolvedHostName(
                            forInstanceUuid: proj.originInstanceUuid,
                            fallback: proj.hostName
                        )
                    }
                    return AgentProjectSection(
                        id: proj.id,
                        slug: proj.name,
                        subtitle: displayProj.homeSubtitle(isHostOnline: isProjectHostOnline(displayProj)),
                        isCloud: proj.runtime == .cloud,
                        conversations: convs
                    )
                }

            let coveredSummaryIds = Set(builtSections.flatMap { $0.conversations.map(\.id) })
            let orphaned = store.summaries.filter {
                !$0.isPinned
                    && !$0.isArchived
                    && summaryMatchesHostFilter($0)
                    && !coveredSummaryIds.contains($0.cascadeId)
            }
            let orphanedLocalSummaries = orphaned.filter { !$0.isCloud }
            if !orphanedLocalSummaries.isEmpty {
                let firstOrphan = orphanedLocalSummaries[0]
                let orphanHostName = store.resolvedHostName(
                    forInstanceUuid: firstOrphan.originInstanceUuid,
                    fallback: firstOrphan.originHostName ?? selectedHostDisplayName
                )
                let orphanOnline = !store.hasPairedBackend
                    || store.isLocalHostOnline(instanceId: firstOrphan.originInstanceUuid, hostname: orphanHostName)
                builtSections.append(
                    AgentProjectSection(
                        id: AntigravityCloudDetector.noProjectDisplayName,
                        slug: AntigravityCloudDetector.noProjectDisplayName,
                        subtitle: "\(orphanOnline ? "Local" : "Offline") · \(orphanHostName)",
                        isCloud: false,
                        conversations: orphanedLocalSummaries.map(mapStoreSummary)
                    )
                )
            }
            let orphanedCloud = orphaned.filter(\.isCloud).map(mapStoreSummary)
            if !orphanedCloud.isEmpty {
                builtSections.append(
                    AgentProjectSection(
                        id: "cloud:\(AntigravityCloudDetector.noProjectDisplayName)",
                        slug: AntigravityCloudDetector.noProjectDisplayName,
                        subtitle: "Antigravity Cloud",
                        isCloud: true,
                        conversations: orphanedCloud
                    )
                )
            }
            sourceSections = builtSections
        } else {
            sourceSections = projectSections.filter { sec in
                switch selectedHost {
                case .allHosts: return true
                case .antigravityCloud: return sec.isCloud
                case .localHost: return !sec.isCloud
                }
            }
        }

        return sourceSections.compactMap { section in
            let filteredConvs = section.conversations.filter { matchesFilters($0) }
            if filteredConvs.isEmpty && (!searchText.isEmpty || (usesLiveStoreData && selectedFilter != .all)) {
                return nil
            }
            var copy = section
            copy.conversations = filteredConvs
            return copy
        }
    }

    private func matchesFilters(_ item: AgentConversationItem) -> Bool {
        guard !item.isArchived else { return false }

        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let query = searchText.lowercased()
            let matchesTitle = item.title.lowercased().contains(query)
            let matchesProject = AntigravityCloudDetector.stripProjectScopePrefix(item.projectSlug)
                .lowercased()
                .contains(query)
            let matchesStatus = item.statusLine.lowercased().contains(query)
            if !matchesTitle && !matchesProject && !matchesStatus {
                return false
            }
        }

        switch selectedFilter {
        case .all:
            return true
        case .running:
            return item.statusHighlight == .running
        case .needsYou:
            return item.statusHighlight == .waiting
        case .unread:
            return item.isUnread
        }
    }

    private func togglePinConversation(id: String) {
        store.togglePinCascade(id)
        if let idx = pinnedItems.firstIndex(where: { $0.id == id }) {
            var removed = pinnedItems.remove(at: idx)
            removed.isPinned = false
            if let pIdx = projectSections.firstIndex(where: { $0.slug == removed.projectSlug }) {
                projectSections[pIdx].conversations.insert(removed, at: 0)
            }
            return
        }
        for pIdx in projectSections.indices {
            if let cIdx = projectSections[pIdx].conversations.firstIndex(where: { $0.id == id }) {
                var moved = projectSections[pIdx].conversations.remove(at: cIdx)
                moved.isPinned = true
                pinnedItems.insert(moved, at: 0)
                return
            }
        }
    }

    private func toggleUnreadConversation(id: String) {
        store.toggleUnreadCascade(id)
        for pIdx in projectSections.indices {
            if let cIdx = projectSections[pIdx].conversations.firstIndex(where: { $0.id == id }) {
                projectSections[pIdx].conversations[cIdx].isUnread.toggle()
                if projectSections[pIdx].conversations[cIdx].indicator == .none {
                    projectSections[pIdx].conversations[cIdx].indicator = .unreadDot
                }
                return
            }
        }
    }

    private func archiveConversation(id: String) {
        store.archiveCascade(id)
        if let idx = pinnedItems.firstIndex(where: { $0.id == id }) {
            pinnedItems[idx].isArchived = true
            return
        }
        for pIdx in projectSections.indices {
            if let cIdx = projectSections[pIdx].conversations.firstIndex(where: { $0.id == id }) {
                projectSections[pIdx].conversations[cIdx].isArchived = true
                return
            }
        }
    }

    private func deleteConversation(id: String) {
        store.deleteCascade(id)
        pinnedItems.removeAll { $0.id == id }
        for pIdx in projectSections.indices {
            projectSections[pIdx].conversations.removeAll { $0.id == id }
        }
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

            // Cut out a transparent halo so the status indicator separates crisply from the laptop bezel
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

