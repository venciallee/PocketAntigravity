import SwiftUI
import AntigravityData
#if canImport(UIKit)
import UIKit
#endif

public typealias AntigravityShellController = AntigravityRootContainerView

/// Primary bottom navigation tabs in the Floating Liquid Glass Tab Bar.
public enum ShellTab: String, CaseIterable, Sendable, Identifiable {
    case agents
    case automations
    case settings

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .agents:      return "Agents"
        case .automations: return "Automations"
        case .settings:    return "Settings"
        }
    }

    public func localizedTitle(for language: AppLanguage) -> String {
        switch self {
        case .agents:      return language.t("Agents", "代理")
        case .automations: return language.t("Automations", "自动化")
        case .settings:    return language.t("Settings", "设置")
        }
    }

    public var symbolName: String {
        switch self {
        case .agents:      return "bubble.left"
        case .automations: return "clock.arrow.circlepath"
        case .settings:    return "slider.horizontal.3"
        }
    }

    public var fabSymbolName: String {
        switch self {
        case .agents:      return "pencil"
        case .automations: return "plus"
        case .settings:    return "qrcode.viewfinder"
        }
    }

    public init(primaryTab: PrimaryTab) {
        switch primaryTab {
        case .agents:      self = .agents
        case .automations: self = .automations
        case .settings:    self = .settings
        }
    }

    public var defaultFABAccessibilityId: String {
        switch self {
        case .agents:      return "fab-compose"
        case .automations: return "fab-add-automation"
        case .settings:    return "fab-pair-host"
        }
    }
}

/// Signature UE01 / UE06 global bottom navigation chrome:
/// Left Floating Liquid Glass 3-Tab Capsule (`Agents` | `Automations` | `Settings`)
/// + Detached Right `56×56pt` Periwinkle (`AntigravityTheme.accentPeriwinkle`) Circular FAB.
public struct AntigravityFloatingTabBar: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.appLanguage) private var lang

    public let selectedTab: ShellTab
    public let tabBarAccessibilityId: String
    public let fabAccessibilityId: String
    public var onSelectTab: (ShellTab) -> Void
    public var onTapFAB: () -> Void

    public init(
        selectedTab: ShellTab,
        tabBarAccessibilityId: String = "floating-tab-bar",
        fabAccessibilityId: String? = nil,
        onSelectTab: @escaping (ShellTab) -> Void = { _ in },
        onTapFAB: @escaping () -> Void = {}
    ) {
        self.selectedTab = selectedTab
        self.tabBarAccessibilityId = tabBarAccessibilityId
        self.fabAccessibilityId = fabAccessibilityId ?? selectedTab.defaultFABAccessibilityId
        self.onSelectTab = onSelectTab
        self.onTapFAB = onTapFAB
    }

    public var body: some View {
        let inactiveTabForeground: Color = colorScheme == .dark
            ? AntigravityTheme.inkLabel
            : AntigravityTheme.inkSecondary

        HStack(spacing: 12) {
            // Left: Floating Liquid Glass 3-Tab Capsule
            HStack(spacing: 2) {
                ForEach(ShellTab.allCases) { tab in
                    let isSelected = (tab == selectedTab)
                    Button {
                        onSelectTab(tab)
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: tab.symbolName)
                                .font(.system(size: 17, weight: .semibold))
                            Text(tab.localizedTitle(for: lang))
                                .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                                .lineLimit(1)
                        }
                        .foregroundStyle(
                            isSelected
                                ? AntigravityTheme.accentPeriwinkle
                                : inactiveTabForeground
                        )
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(
                            Group {
                                if isSelected {
                                    Capsule()
                                        .fill(AntigravityTheme.surfaceActiveTabSlot)
                                }
                            }
                        )
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("tab-item-\(tab.rawValue)")
                }
            }
            .padding(4)
            .frame(height: 60)
            .background(
                ZStack {
                    Capsule()
                        .fill(.ultraThinMaterial)
                    Capsule()
                        .fill(AntigravityTheme.surfaceGlassTab.opacity(0.90))
                }
            )
            .overlay(
                Capsule()
                    .strokeBorder(AntigravityTheme.glassHairline, lineWidth: 1)
            )
            .shadow(color: AntigravityTheme.glassShadow, radius: 18, x: 0, y: 8)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(tabBarAccessibilityId)

            // Right: Detached 56x56pt Periwinkle Circular FAB
            Button {
                onTapFAB()
            } label: {
                Image(systemName: selectedTab.fabSymbolName)
                    .font(.system(size: selectedTab == .automations ? 22 : 19, weight: .semibold))
                    .foregroundStyle(AntigravityTheme.inkOnPrimaryCTA)
                    .frame(width: 56, height: 56)
                    .background(
                        Circle()
                            .fill(AntigravityTheme.accentPeriwinkle)
                    )
                    .shadow(color: AntigravityTheme.glassShadow, radius: 14, x: 0, y: 6)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(fabAccessibilityId)
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 6)
    }
}

/// Full-bleed card row `ButtonStyle` ensuring 100% solid pixel hit-testing across
/// text, spacers, and padding on both iOS Simulator (`DeviceHub` mouse clicks) and physical touch,
/// with instant tactile press feedback and zero `PlainButtonStyle` transparent dead zones.
public struct AntigravityInteractiveRowButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                AntigravityTheme.surfaceCard
                    .overlay(AntigravityTheme.inkReading.opacity(configuration.isPressed ? 0.09 : 0.0))
            )
            .contentShape(Rectangle())
    }
}

/// Adaptive shell container (`AntigravityShellController`) routing all 20 UE v2.1 flows
/// via Sidebar-First IA or rendering deterministic isolated ESDD verification scenes (`UE01`..`UE15`).
public struct AntigravityRootContainerView: View {
    @Bindable public var store: AntigravitySessionStore
    @Binding public var activeVerifyCase: ESDDVerifySceneCase?

    @Environment(\.layoutDirection) private var layoutDirection
    @State private var selectedTab: ShellTab
    @State private var activeModalSheet: ModalSheetDestination?
    @State private var navigationPath: [ShellPushDestination] = []
    @State private var settingsScannerTriggered: Bool = false
    @State private var drawerMounted: Bool = false
    @State private var visualDrawerProgress: CGFloat = 1.0
    @State private var isDraggingDrawer: Bool = false
    @State private var shellWidth: CGFloat = 393.0
    @State private var drawerAnimationGeneration: Int = 0
    #if canImport(UIKit)
    @State private var popGestureHandler = InteractivePopGestureHandler()
    @State private var sidebarGestureHandler = SidebarDrawerGestureHandler()
    #endif

    private enum ModalSheetDestination: String, Identifiable {
        case displayOptions
        case createProject
        case contextMenuPreview

        var id: String { rawValue }
    }

    private enum ShellPushDestination: Hashable {
        case cascadeChat
        case automationDetail(String)
        case rulesAndSkills
        case planReview
        case turnDiffReview
    }

    public init(
        store: AntigravitySessionStore,
        activeVerifyCase: Binding<ESDDVerifySceneCase?>
    ) {
        self.store = store
        self._activeVerifyCase = activeVerifyCase
        self._selectedTab = State(initialValue: ShellTab(primaryTab: store.selectedTab))
    }

    public var body: some View {
        Group {
            if let verifyCase = activeVerifyCase {
                isolatedESDDSceneView(for: verifyCase)
            } else {
                interactiveNavigationView
            }
        }
        .background(AntigravityTheme.canvasObsidian.ignoresSafeArea())
        .onChange(of: store.activeRoute) { _, newRoute in
            if newRoute == .pairingSettings {
                selectedTab = .settings
            }
            if activeVerifyCase == nil {
                syncNavigationPath(from: newRoute)
            }
        }
        .onChange(of: store.selectedTab) { _, newPrimaryTab in
            let mapped = ShellTab(primaryTab: newPrimaryTab)
            if selectedTab != mapped {
                selectedTab = mapped
            }
        }
        .onChange(of: selectedTab) { _, newTab in
            switch newTab {
            case .agents:      store.selectedTab = .agents
            case .automations: store.selectedTab = .automations
            case .settings:    store.selectedTab = .settings
            }
        }
    }

    // MARK: - Interactive Navigation Shell

    @ViewBuilder
    private var interactiveNavigationView: some View {
        if !store.isVerificationMode && !store.hasPairedBackend && !store.isLiveBackendConnected {
            AntigravityWelcomeView(
                store: store,
                onConnected: {
                    if case .cascadeChat(let cid) = store.activeRoute, !cid.isEmpty {
                        selectedTab = .agents
                    } else {
                        store.activeRoute = .tabRoot
                        selectedTab = .agents
                    }
                }
            )
        } else {
            pairedShellView
        }
    }

    private var drawerWidth: CGFloat {
        min(334.0, max(shellWidth, 320.0) * 0.83)
    }

    @ViewBuilder
    private var pairedShellView: some View {
        let clampedProgress = min(max(visualDrawerProgress, 0.0), 1.0)
        let slideOriginX: CGFloat = (layoutDirection == .rightToLeft ? drawerWidth : -drawerWidth)
        let dragOffsetX: CGFloat = slideOriginX * (1.0 - clampedProgress)

        ZStack(alignment: .leading) {
            NavigationStack(path: $navigationPath) {
                withInteractivePopGesture(
                    tabRootContentView
                        .toolbar(.hidden, for: .navigationBar)
                )
                .navigationDestination(for: ShellPushDestination.self) { destination in
                    withInteractivePopGesture(
                        pushedDestinationView(for: destination)
                            .toolbar(.hidden, for: .navigationBar)
                            .navigationBarBackButtonHidden(true)
                    )
                }
            }
            .background(AntigravityTheme.canvasObsidian.ignoresSafeArea())

            // Slide-over Left Sidebar Drawer (`UE01B`)
            if drawerMounted {
                Color.black.opacity(0.62)
                    .ignoresSafeArea()
                    .opacity(clampedProgress)
                    .contentShape(Rectangle())
                    .allowsHitTesting(clampedProgress > 0.01)
                    .onTapGesture {
                        closeSidebarDrawer()
                    }
                    .accessibilityIdentifier("sidebar-drawer-scrim")
                    .transition(.opacity)
                    .zIndex(49)

                AgentsSidebarDrawerPanelView(
                    store: store,
                    isVisible: store.isSidebarPresented || isDraggingDrawer,
                    onClose: {
                        closeSidebarDrawer()
                    },
                    onNewConversation: {
                        closeSidebarDrawer()
                        navigationPath.removeAll()
                        selectedTab = .agents
                        store.activeRoute = .tabRoot
                    },
                    onOpenAutomations: {
                        closeSidebarDrawer()
                        navigationPath.removeAll()
                        selectedTab = .automations
                        store.activeRoute = .tabRoot
                    },
                    onOpenCustomizations: {
                        closeSidebarDrawer()
                        store.activeRoute = .rulesAndSkills
                    },
                    onOpenSettings: {
                        closeSidebarDrawer()
                        navigationPath.removeAll()
                        selectedTab = .settings
                        store.activeRoute = .pairingSettings
                    },
                    onOpenDisplayOptions: {
                        activeModalSheet = .displayOptions
                    },
                    onOpenNewProject: {
                        activeModalSheet = .createProject
                    },
                    onSelectProject: { slug in
                        closeSidebarDrawer()
                        navigationPath.removeAll()
                        selectedTab = .agents
                        store.selectProject(slug)
                    },
                    onOpenProjectCustomizations: { slug in
                        closeSidebarDrawer()
                        store.selectProject(slug)
                        store.activeRoute = .rulesAndSkills
                    },
                    onOpenConversation: { convId in
                        closeSidebarDrawer()
                        selectedTab = .agents
                        openOrCreateConversation(convId, defaultProjectSlug: store.selectedProjectId)
                    }
                )
                .frame(width: drawerWidth)
                .frame(maxHeight: .infinity)
                .ignoresSafeArea(.keyboard, edges: .bottom)
                .offset(x: dragOffsetX)
                .allowsHitTesting(clampedProgress > 0.01)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("sidebar-drawer-panel")
                .transition(.offset(x: slideOriginX))
                .zIndex(50)
            }
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { newWidth in
            if newWidth > 0, abs(shellWidth - newWidth) > 0.5 {
                shellWidth = newWidth
            }
        }
        .background {
            #if canImport(UIKit)
            SidebarDrawerGestureInstaller(
                handler: sidebarGestureHandler,
                isDrawerOpen: store.isSidebarPresented,
                canOpenBySwipe: canOpenSidebarBySwipe,
                currentProgress: { drawerMounted ? visualDrawerProgress : 0.0 },
                onDragBegan: { startProgress in
                    handleSidebarDragBegan(startProgress)
                },
                onDragChanged: { progress in
                    handleSidebarDragChanged(progress)
                },
                onDragEnded: { shouldOpen in
                    handleSidebarDragEnded(shouldOpen: shouldOpen)
                }
            )
            .frame(width: 0, height: 0)
            #endif
        }
        .overlay(alignment: .top) {
            if !store.isVerificationMode,
               let notice = store.compatibilityNoticeText,
               !notice.isEmpty {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AntigravityTheme.statusWaiting)
                        .padding(.top, 1)
                    Text(notice)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(AntigravityTheme.inkReading)
                        .lineLimit(3)
                    Spacer(minLength: 4)
                    Button {
                        store.dismissCompatibilityNotice()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(AntigravityTheme.inkSecondary)
                            .frame(width: 26, height: 26)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("btn-dismiss-compat-notice")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(AntigravityTheme.surfaceCard.opacity(0.96), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(AntigravityTheme.statusWaiting.opacity(0.4), lineWidth: 1)
                )
                .shadow(color: AntigravityTheme.glassShadow, radius: 12, x: 0, y: 6)
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .accessibilityIdentifier("banner-compatibility-notice")
            }
        }
        .onAppear {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                syncNavigationPath(from: store.activeRoute)
                if store.isSidebarPresented {
                    visualDrawerProgress = 1.0
                    drawerMounted = true
                }
            }
        }
        .onChange(of: store.isSidebarPresented) { _, isPresented in
            dismissKeyboard()
            guard !isDraggingDrawer else { return }
            if isPresented {
                animateDrawerOpen(fromCurrentProgress: false)
            } else {
                animateDrawerClosed()
            }
        }
        .onChange(of: navigationPath) { _, newPath in
            syncActiveRoute(from: newPath)
        }
        .background {
            Color.clear
                .frame(width: 0, height: 0)
                .sheet(item: $store.presentedSheet) { modal in
                    switch modal {
                    case .conversationOverview:
                        ConversationOverviewSheetView(store: store)
                    case .sideQuestion:
                        SideQuestionSheetView(store: store)
                    case .swarmBoard(let stepIndex):
                        SwarmBoardSheetView(store: store, stepIndex: stepIndex)
                    case .voiceMode:
                        VoiceModeSheetView(store: store)
                    case .richArtifactViewer(let artifactPath):
                        RichArtifactViewerSheet(store: store, artifactPath: artifactPath)
                    case .customizationsSettings:
                        CustomizationsSettingsView(store: store)
                    case .automationEdit(let automationId):
                        AutomationEditSheetView(
                            store: store,
                            automationId: automationId,
                            onDismiss: { store.presentedSheet = nil }
                        )
                    case .permissionsPreset:
                        PermissionsSheetView(
                            store: store,
                            onDismiss: { store.presentedSheet = nil }
                        )
                    case .slashMenu:
                        SlashCommandMenuOverlayView(
                            store: store,
                            showHomeBackdrop: false,
                            onDismiss: { store.presentedSheet = nil }
                        )
                    case .modelAndMode, .modelConfigPicker:
                        ModelAndModeSheetView(
                            store: store,
                            isPresentedAsNativeSheet: true,
                            onDismiss: { store.presentedSheet = nil }
                        )
                    case .addContext, .fileMentionPicker:
                        AddContextSheetView(
                            store: store,
                            startExpanded: true,
                            showHomeBackdrop: false,
                            isPresentedAsNativeSheet: true,
                            onDismiss: { store.presentedSheet = nil }
                        )
                        .presentationDetents([.fraction(0.86), .large])
                        .presentationDragIndicator(.visible)
                        .presentationCornerRadius(28)
                        .presentationBackground(AntigravityTheme.surfaceSheet)
                    case .displayOptions:
                        DisplayOptionsSheetView(store: store, onDismiss: { store.presentedSheet = nil })
                    case .createProject:
                        CreateProjectSheetView(store: store, onDismiss: { store.presentedSheet = nil })
                    case .contextMenuPreview:
                        ConversationContextPreviewMenu(store: store, onDismiss: { store.presentedSheet = nil })
                    case .permissionGate(let stepIndex):
                        InteractionGateSheetController(store: store, mode: .permissionGate, stepIndex: stepIndex)
                    case .askQuestion, .newCascadeSheet:
                        StructuredQuestionCardView(store: store)
                    }
                }
        }
        .sheet(item: $activeModalSheet) { sheet in
            switch sheet {
            case .displayOptions:
                DisplayOptionsSheetView(
                    store: store,
                    onDismiss: { activeModalSheet = nil }
                )
            case .createProject:
                CreateProjectSheetView(
                    store: store,
                    onDismiss: { activeModalSheet = nil }
                )
            case .contextMenuPreview:
                ConversationContextPreviewMenu(
                    store: store,
                    onDismiss: { activeModalSheet = nil }
                )
            }
        }
    }

    private var canPopNavigation: Bool {
        !navigationPath.isEmpty
    }

    private var canOpenSidebarBySwipe: Bool {
        guard !canPopNavigation else { return false }
        guard activeModalSheet == nil, store.presentedSheet == nil else { return false }
        return true
    }

    private func dismissKeyboard() {
        #if canImport(UIKit)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
    }

    private func openSidebarDrawer() {
        dismissKeyboard()
        if !store.isSidebarPresented {
            store.isSidebarPresented = true
        }
        animateDrawerOpen(fromCurrentProgress: drawerMounted)
    }

    private func closeSidebarDrawer() {
        dismissKeyboard()
        if store.isSidebarPresented {
            store.isSidebarPresented = false
        }
        animateDrawerClosed()
    }

    private func animateDrawerOpen(fromCurrentProgress: Bool) {
        drawerAnimationGeneration &+= 1
        if !drawerMounted {
            if visualDrawerProgress < 0.999 {
                var resetTransaction = Transaction()
                resetTransaction.disablesAnimations = true
                withTransaction(resetTransaction) {
                    visualDrawerProgress = 1.0
                }
            }
            withAnimation(.spring(duration: 0.34, bounce: 0.0)) {
                drawerMounted = true
            }
        } else if fromCurrentProgress || visualDrawerProgress < 0.999 {
            withAnimation(.spring(duration: 0.30, bounce: 0.0)) {
                visualDrawerProgress = 1.0
            }
        }
    }

    private func animateDrawerClosed() {
        drawerAnimationGeneration &+= 1
        let gen = drawerAnimationGeneration
        guard drawerMounted else { return }
        if visualDrawerProgress >= 0.999 {
            withAnimation(.spring(duration: 0.28, bounce: 0.0)) {
                drawerMounted = false
            }
            return
        }
        if visualDrawerProgress <= 0.001 {
            var unmountTransaction = Transaction()
            unmountTransaction.disablesAnimations = true
            withTransaction(unmountTransaction) {
                drawerMounted = false
                visualDrawerProgress = 1.0
            }
            return
        }
        withAnimation(.spring(duration: 0.24, bounce: 0.0)) {
            visualDrawerProgress = 0.0
        } completion: {
            if drawerAnimationGeneration == gen && !store.isSidebarPresented && !isDraggingDrawer && visualDrawerProgress <= 0.001 {
                var unmountTransaction = Transaction()
                unmountTransaction.disablesAnimations = true
                withTransaction(unmountTransaction) {
                    drawerMounted = false
                    visualDrawerProgress = 1.0
                }
            }
        }
        // Guaranteed fallback unmount if simultaneous NavigationStack / store mutations
        // interrupt the SwiftUI animation completion callback on iOS 18+.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            guard drawerAnimationGeneration == gen, !store.isSidebarPresented, !isDraggingDrawer, drawerMounted else { return }
            var unmountTransaction = Transaction()
            unmountTransaction.disablesAnimations = true
            withTransaction(unmountTransaction) {
                drawerMounted = false
                visualDrawerProgress = 1.0
            }
        }
    }

    private func handleSidebarDragBegan(_ startProgress: CGFloat) {
        dismissKeyboard()
        drawerAnimationGeneration &+= 1
        isDraggingDrawer = true
        if !drawerMounted {
            var mountTransaction = Transaction()
            mountTransaction.disablesAnimations = true
            withTransaction(mountTransaction) {
                visualDrawerProgress = startProgress
                drawerMounted = true
            }
        }
    }

    private func handleSidebarDragChanged(_ progress: CGFloat) {
        guard isDraggingDrawer else { return }
        visualDrawerProgress = progress
    }

    private func handleSidebarDragEnded(shouldOpen: Bool) {
        isDraggingDrawer = false
        if shouldOpen {
            if !store.isSidebarPresented {
                store.isSidebarPresented = true
            } else {
                animateDrawerOpen(fromCurrentProgress: true)
            }
        } else {
            if store.isSidebarPresented {
                store.isSidebarPresented = false
            } else {
                animateDrawerClosed()
            }
        }
    }

    @ViewBuilder
    private var tabRootContentView: some View {
        switch selectedTab {
        case .agents:
            AgentsHomeViewController(
                store: store,
                onSelectTab: { tab in selectedTab = tab },
                onOpenSidebar: {
                    openSidebarDrawer()
                },
                onOpenDisplayOptions: { activeModalSheet = .displayOptions },
                onOpenNewProject: { activeModalSheet = .createProject },
                onOpenContextMenuPreview: { activeModalSheet = .contextMenuPreview },
                onOpenConversation: { convId in
                    openOrCreateConversation(convId, defaultProjectSlug: store.selectedProjectId)
                },
                onOpenSettings: {
                    selectedTab = .settings
                    store.activeRoute = .pairingSettings
                }
            )
        case .automations:
            AutomationsViewController(
                store: store,
                onSelectTab: { tab in selectedTab = tab },
                onOpenDisplayOptions: { activeModalSheet = .displayOptions },
                onOpenSidebar: {
                    openSidebarDrawer()
                },
                onOpenAutomationDetail: { autoId in
                    store.openAutomationDetail(autoId)
                }
            )
        case .settings:
            settingsTabContainerView
        }
    }

    @ViewBuilder
    private func pushedDestinationView(for destination: ShellPushDestination) -> some View {
        switch destination {
        case .cascadeChat:
            CascadeChatViewController(
                store: store,
                onBack: {
                    popTopDestination()
                }
            )
        case .automationDetail(let automationId):
            AutomationDetailView(
                store: store,
                automationId: automationId,
                onBack: {
                    popTopDestination()
                }
            )
        case .rulesAndSkills:
            CustomizationsSettingsView(
                store: store,
                projectName: store.selectedProject?.name ?? "ledger-svc",
                onBack: {
                    popTopDestination()
                }
            )
        case .planReview:
            ImplementationPlanReviewViewController(store: store)
        case .turnDiffReview:
            TurnDiffReviewViewController(store: store)
        }
    }

    @ViewBuilder
    private func withInteractivePopGesture<Content: View>(_ content: Content) -> some View {
        #if canImport(UIKit)
        content.background {
            InteractivePopGestureEnabler(
                handler: popGestureHandler,
                stackDepth: navigationPath.count,
                allowsInteractivePop: canPopNavigation,
                onPopFallback: {
                    withAnimation(.easeInOut(duration: 0.24)) {
                        popTopDestination()
                    }
                }
            )
            .frame(width: 0, height: 0)
        }
        #else
        content
        #endif
    }

    private func popTopDestination() {
        if !navigationPath.isEmpty {
            navigationPath.removeLast()
        } else {
            store.activeRoute = .tabRoot
        }
    }

    private func syncNavigationPath(from newRoute: AntigravityNavigationRoute) {
        switch newRoute {
        case .tabRoot:
            if !navigationPath.isEmpty {
                navigationPath.removeAll()
            }
        case .pairingSettings:
            selectedTab = .settings
            if !navigationPath.isEmpty {
                navigationPath.removeAll()
            }
        case .cascadeChat:
            if navigationPath.last == .cascadeChat {
                return
            }
            if let existingIndex = navigationPath.lastIndex(of: .cascadeChat) {
                navigationPath.removeSubrange((existingIndex + 1)...)
            } else if case .automationDetail = navigationPath.last {
                navigationPath.append(.cascadeChat)
            } else {
                navigationPath = [.cascadeChat]
            }
        case .automationDetail(let aid):
            let target = ShellPushDestination.automationDetail(aid)
            if navigationPath.last == target {
                return
            }
            navigationPath = [target]
        case .rulesAndSkills:
            if navigationPath.last == .rulesAndSkills {
                return
            }
            navigationPath = [.rulesAndSkills]
        case .planReview:
            if navigationPath.last == .planReview {
                return
            }
            if let chatIdx = navigationPath.lastIndex(of: .cascadeChat) {
                var updated = Array(navigationPath.prefix(through: chatIdx))
                updated.append(.planReview)
                navigationPath = updated
            } else {
                navigationPath = [.cascadeChat, .planReview]
            }
        case .turnDiffReview:
            if navigationPath.last == .turnDiffReview {
                return
            }
            if let chatIdx = navigationPath.lastIndex(of: .cascadeChat) {
                var updated = Array(navigationPath.prefix(through: chatIdx))
                updated.append(.turnDiffReview)
                navigationPath = updated
            } else {
                navigationPath = [.cascadeChat, .turnDiffReview]
            }
        }
    }

    private func syncActiveRoute(from path: [ShellPushDestination]) {
        if !path.contains(.cascadeChat), store.activeCascadeId.isEmpty {
            store.discardPendingDraftConversation()
        }
        switch path.last {
        case .none:
            if store.activeRoute != .tabRoot && store.activeRoute != .pairingSettings {
                store.activeRoute = .tabRoot
            }
        case .cascadeChat:
            if case .cascadeChat = store.activeRoute {
                // Keep exact activeCascadeId while already on the conversation route.
            } else {
                store.activeRoute = .cascadeChat(store.activeCascadeId)
            }
        case .automationDetail(let aid):
            if store.activeRoute != .automationDetail(aid) {
                store.activeRoute = .automationDetail(aid)
            }
        case .rulesAndSkills:
            if store.activeRoute != .rulesAndSkills {
                store.activeRoute = .rulesAndSkills
            }
        case .planReview:
            if store.activeRoute != .planReview {
                store.activeRoute = .planReview
            }
        case .turnDiffReview:
            if store.activeRoute != .turnDiffReview {
                store.activeRoute = .turnDiffReview
            }
        }
    }

    private var settingsTabContainerView: some View {
        RemotePairingViewController(
            store: store,
            externalScannerTrigger: $settingsScannerTriggered,
            onConnected: {
                if case .cascadeChat(let cid) = store.activeRoute, !cid.isEmpty {
                    selectedTab = .agents
                } else {
                    store.activeRoute = .tabRoot
                    selectedTab = .agents
                }
            },
            onDismiss: {
                selectedTab = .agents
                store.activeRoute = .tabRoot
            }
        )
        .background(AntigravityTheme.canvasObsidian.ignoresSafeArea())
    }

    private func openOrCreateConversation(_ rawId: String, defaultProjectSlug: String) {
        if rawId == "new-conversation" || rawId.hasPrefix("new-") {
            let slug: String = {
                if rawId.hasPrefix("new-") && rawId != "new-conversation" {
                    return String(rawId.dropFirst(4))
                }
                if !defaultProjectSlug.isEmpty {
                    return defaultProjectSlug
                }
                return (store.hasPairedBackend || store.isLiveBackendConnected)
                    ? AntigravityCloudDetector.noProjectDisplayName
                    : "ledger-svc"
            }()
            _ = store.createConversationInProject(slug)
            return
        }
        let mappedId: String = {
            switch rawId {
            case "conv-rate-limiter", "proj-conv-rate-limiter": return "cas-rate-limiter"
            case "conv-flaky-settlement", "proj-conv-flaky-batch": return "cas-flaky-settlement"
            case "conv-upgrade-go", "proj-conv-upgrade-go": return "cas-upgrade-go"
            case "conv-release-checklist": return "cas-release-checklist"
            default: return rawId
            }
        }()
        store.selectCascade(mappedId)
    }

    // MARK: - Isolated Deterministic ESDD Scenes (All 19 UE v2.1 Boards)

    @ViewBuilder
    private func isolatedESDDSceneView(for verifyCase: ESDDVerifySceneCase) -> some View {
        switch verifyCase {
        case .agentsHome:
            AgentsHomeViewController(store: store)
        case .sidebarDrawer:
            AgentsSidebarDrawerView(store: store, showWelcomeBackdrop: true)
        case .displayOptions:
            DisplayOptionsSheetView(store: store)
        case .contextMenuPin:
            ConversationContextPreviewMenu(store: store)
        case .createProject:
            CreateProjectSheetView(store: store)
        case .automations:
            AutomationsViewController(store: store)
        case .automationDetail:
            AutomationDetailView(store: store)
        case .automationEdit:
            AutomationEditSheetView(store: store)
        case .chatAndComposer:
            CascadeChatViewController(store: store)
        case .permissionsPreset:
            PermissionsPresetPopoverView(store: store, showHomeBackdrop: true)
        case .addContext:
            AddContextSheetView(store: store, startExpanded: false, showHomeBackdrop: true)
        case .slashMenu:
            SlashCommandMenuOverlayView(store: store, showHomeBackdrop: true)
        case .modelAndMode:
            ModelAndModeSheetView(store: store)
        case .structuredQuestion:
            StructuredQuestionCardView(store: store)
        case .planReview:
            ImplementationPlanReviewViewController(store: store)
        case .turnDiffReview:
            TurnDiffReviewViewController(store: store)
        case .liveActivitySpec:
            AntigravityLiveActivitySpecShowcaseView(store: store)
        case .rulesAndSkills:
            CustomizationsSettingsView(store: store, projectName: "ledger-svc")
        case .settings:
            RemotePairingViewController(store: store)
        }
    }
}

#if canImport(UIKit)
/// Dedicated `UIGestureRecognizerDelegate` that preserves native iOS left-edge interactive
/// swipe-back (`interactivePopGestureRecognizer`) when SwiftUI hides the system navigation bar
/// in favor of custom UE v2.0 top headers, while safely disabling edge-swipe at stack root.
@MainActor
private final class InteractivePopGestureHandler: NSObject, UIGestureRecognizerDelegate {
    private weak var navigationController: UINavigationController?
    private var gestureStartStackCount: Int = 0
    private var nativeInteractivePopObservedInCurrentGesture: Bool = false
    private lazy var edgeSwipeFallbackRecognizer: UIPanGestureRecognizer = {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handleEdgeSwipeFallback(_:)))
        pan.maximumNumberOfTouches = 1
        pan.cancelsTouchesInView = false
        pan.delegate = self
        return pan
    }()
    var allowsInteractivePop: Bool = false
    var onPopFallback: (@MainActor () -> Void)?

    override init() {
        super.init()
    }

    func attach(to navController: UINavigationController) {
        if self.navigationController !== navController {
            if let previousView = edgeSwipeFallbackRecognizer.view {
                previousView.removeGestureRecognizer(edgeSwipeFallbackRecognizer)
            }
            self.navigationController = navController
            navController.view.backgroundColor = AntigravityTheme.canvasObsidianUIColor
        }
        if edgeSwipeFallbackRecognizer.view !== navController.view {
            navController.view.addGestureRecognizer(edgeSwipeFallbackRecognizer)
        }
        if let popGesture = navController.interactivePopGestureRecognizer {
            if popGesture.delegate !== self {
                popGesture.delegate = self
            }
            if !popGesture.isEnabled {
                popGesture.isEnabled = true
            }
            if popGesture.requiresExclusiveTouchType {
                popGesture.requiresExclusiveTouchType = false
            }
        }
    }

    @objc
    private func handleEdgeSwipeFallback(_ pan: UIPanGestureRecognizer) {
        guard allowsInteractivePop, let nav = navigationController else { return }

        switch pan.state {
        case .began:
            gestureStartStackCount = nav.viewControllers.count
            nativeInteractivePopObservedInCurrentGesture = (nav.transitionCoordinator != nil)
            if !nativeInteractivePopObservedInCurrentGesture && nav.viewControllers.count > 1 {
                _ = nav.view.endEditing(true)
            }
            return

        case .changed:
            if nav.transitionCoordinator != nil || nav.viewControllers.count != gestureStartStackCount {
                nativeInteractivePopObservedInCurrentGesture = true
            }
            return

        case .ended:
            defer {
                gestureStartStackCount = 0
                nativeInteractivePopObservedInCurrentGesture = false
            }
            guard !nativeInteractivePopObservedInCurrentGesture,
                  nav.transitionCoordinator == nil,
                  nav.presentedViewController == nil,
                  nav.viewControllers.count > 1,
                  nav.viewControllers.count == gestureStartStackCount else {
                return
            }

            let translation = pan.translation(in: nav.view)
            let velocity = pan.velocity(in: nav.view)
            let isRTL = nav.view.effectiveUserInterfaceLayoutDirection == .rightToLeft
            let dx = isRTL ? -translation.x : translation.x
            let vx = isRTL ? -velocity.x : velocity.x
            let dy = abs(translation.y)

            let passedThreshold = (dx >= 60.0) || (dx >= 28.0 && vx >= 280.0)
            guard passedThreshold && dx > dy * 1.15 else { return }

            _ = nav.view.endEditing(true)
            if let onPopFallback {
                onPopFallback()
            } else {
                _ = nav.popViewController(animated: true)
            }

        default:
            gestureStartStackCount = 0
            nativeInteractivePopObservedInCurrentGesture = false
        }
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard allowsInteractivePop else { return false }
        guard let nav = navigationController else { return false }
        guard nav.viewControllers.count > 1 else { return false }
        guard nav.presentedViewController == nil else { return false }
        guard nav.transitionCoordinator == nil else { return false }

        if gestureRecognizer === edgeSwipeFallbackRecognizer,
           let pan = gestureRecognizer as? UIPanGestureRecognizer {
            let viewBounds = nav.view.bounds
            let location = pan.location(in: nav.view)
            let translation = pan.translation(in: nav.view)
            let velocity = pan.velocity(in: nav.view)
            let isRTL = nav.view.effectiveUserInterfaceLayoutDirection == .rightToLeft
            let startX = location.x - translation.x
            let edgeBand: CGFloat = 36.0
            let startedInEdge = isRTL
                ? (startX >= viewBounds.width - edgeBand)
                : (startX <= edgeBand)
            guard startedInEdge else { return false }

            let horizontalTranslation = isRTL ? -translation.x : translation.x
            let horizontalVelocity = isRTL ? -velocity.x : velocity.x
            if horizontalTranslation < -4.0 || horizontalVelocity < -20.0 {
                return false
            }
            if abs(velocity.y) > max(abs(velocity.x) * 1.25, 45.0) {
                return false
            }
            return true
        }

        if let pan = gestureRecognizer as? UIPanGestureRecognizer {
            let velocity = pan.velocity(in: nav.view)
            let isRTL = nav.view.effectiveUserInterfaceLayoutDirection == .rightToLeft
            let horizontalVelocity = isRTL ? -velocity.x : velocity.x
            if horizontalVelocity < -10.0 {
                return false
            }
            if abs(velocity.y) > abs(velocity.x) * 1.5 && abs(velocity.y) > 40 {
                return false
            }
        }

        Task { @MainActor [weak nav, weak gestureRecognizer] in
            guard let gestureRecognizer,
                  gestureRecognizer.state == .began || gestureRecognizer.state == .changed else {
                return
            }
            _ = nav?.view.endEditing(true)
        }

        return true
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        guard allowsInteractivePop else { return false }
        if gestureRecognizer === edgeSwipeFallbackRecognizer || otherGestureRecognizer === edgeSwipeFallbackRecognizer {
            return true
        }
        return false
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        guard allowsInteractivePop else { return false }
        guard let nav = navigationController else { return false }
        guard nav.viewControllers.count > 1 else { return false }
        guard nav.presentedViewController == nil else { return false }
        if gestureRecognizer === edgeSwipeFallbackRecognizer {
            return false
        }
        if otherGestureRecognizer === edgeSwipeFallbackRecognizer {
            return false
        }
        return otherGestureRecognizer is UIPanGestureRecognizer
    }
}

private struct InteractivePopGestureEnabler: UIViewControllerRepresentable {
    let handler: InteractivePopGestureHandler
    let stackDepth: Int
    let allowsInteractivePop: Bool
    let onPopFallback: @MainActor () -> Void

    func makeUIViewController(context: Context) -> InteractivePopGestureAnchorViewController {
        handler.allowsInteractivePop = allowsInteractivePop
        handler.onPopFallback = onPopFallback
        return InteractivePopGestureAnchorViewController(handler: handler)
    }

    func updateUIViewController(_ uiViewController: InteractivePopGestureAnchorViewController, context: Context) {
        handler.allowsInteractivePop = allowsInteractivePop
        handler.onPopFallback = onPopFallback
        uiViewController.handler = handler
        uiViewController.configureNavigationController()
    }
}

@MainActor
private final class InteractivePopGestureAnchorViewController: UIViewController {
    var handler: InteractivePopGestureHandler

    init(handler: InteractivePopGestureHandler) {
        self.handler = handler
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let anchorView = UIView(frame: .zero)
        anchorView.backgroundColor = .clear
        anchorView.isUserInteractionEnabled = false
        anchorView.isAccessibilityElement = false
        anchorView.accessibilityElementsHidden = true
        self.view = anchorView
    }

    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        configureNavigationController()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        configureNavigationController()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        configureNavigationController()
        Task { @MainActor [weak self] in
            self?.configureNavigationController()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        configureNavigationController()
    }

    private weak var lastAttachedNavController: UINavigationController?

    func configureNavigationController() {
        guard let navController = resolveNavigationController() else { return }
        if lastAttachedNavController === navController && navController.interactivePopGestureRecognizer?.delegate === handler {
            return
        }
        lastAttachedNavController = navController
        handler.attach(to: navController)
    }

    private func resolveNavigationController() -> UINavigationController? {
        if let nav = self.navigationController {
            return nav
        }
        var currentParent = self.parent
        while let parentVC = currentParent {
            if let nav = parentVC as? UINavigationController {
                return nav
            }
            if let nav = parentVC.navigationController {
                return nav
            }
            currentParent = parentVC.parent
        }
        var responder: UIResponder? = self.view
        while let current = responder {
            if let nav = current as? UINavigationController {
                return nav
            }
            responder = current.next
        }
        return nil
    }
}

/// Native UIKit `UIPanGestureRecognizer` coordinator enabling 1:1 interactive left-to-right
/// swipe-to-open and right-to-left swipe-to-close for the Left Sidebar Drawer (`UE01B`) across
/// all top-level sidebar screens without interfering with vertical scrolling, horizontal code
/// blocks, modal sheets, or pushed `<` back-navigation edge-swipe pops.
@MainActor
private final class SidebarDrawerGestureHandler: NSObject, UIGestureRecognizerDelegate {
    private static let leadingEdgeBandPt: CGFloat = 56.0

    private struct WeakPanRecognizer {
        weak var recognizer: UIPanGestureRecognizer?
    }

    private(set) weak var attachedView: UIView?
    private var dragStartProgress: CGFloat = 0.0
    private var trackedScrollPans: [WeakPanRecognizer] = []

    private lazy var panRecognizer: UIPanGestureRecognizer = {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.maximumNumberOfTouches = 1
        pan.cancelsTouchesInView = true
        pan.delegate = self
        return pan
    }()

    var isDrawerOpen: Bool = false
    var canOpenBySwipe: Bool = true
    var currentProgress: (@MainActor () -> CGFloat)?
    var onDragBegan: (@MainActor (CGFloat) -> Void)?
    var onDragChanged: (@MainActor (CGFloat) -> Void)?
    var onDragEnded: (@MainActor (Bool) -> Void)?

    override init() {
        super.init()
    }

    func attach(to containerView: UIView) {
        if attachedView !== containerView {
            if let previousView = panRecognizer.view {
                previousView.removeGestureRecognizer(panRecognizer)
            }
            attachedView = containerView
        }
        if panRecognizer.view !== containerView {
            containerView.addGestureRecognizer(panRecognizer)
        }
    }

    func detach(from containerView: UIView?) {
        guard let containerView, attachedView === containerView else { return }
        if panRecognizer.view === containerView {
            containerView.removeGestureRecognizer(panRecognizer)
        }
        attachedView = nil
        trackedScrollPans.removeAll()
    }

    @objc
    private func handlePan(_ pan: UIPanGestureRecognizer) {
        guard let containerView = attachedView else { return }
        let bounds = containerView.bounds
        guard bounds.width > 0 else { return }

        let drawerWidth = min(334.0, bounds.width * 0.83)
        let isRTL = containerView.effectiveUserInterfaceLayoutDirection == .rightToLeft
        let translation = pan.translation(in: containerView)
        let velocity = pan.velocity(in: containerView)
        let dx = isRTL ? -translation.x : translation.x
        let vx = isRTL ? -velocity.x : velocity.x

        switch pan.state {
        case .began:
            cancelTrackedScrollPans()
            _ = containerView.endEditing(true)
            let baseline = currentProgress?() ?? (isDrawerOpen ? 1.0 : 0.0)
            dragStartProgress = min(max(baseline, 0.0), 1.0)
            onDragBegan?(dragStartProgress)
            let initialProgress = min(max(dragStartProgress + (dx / max(drawerWidth, 1.0)), 0.0), 1.0)
            onDragChanged?(initialProgress)

        case .changed:
            let progress = min(max(dragStartProgress + (dx / max(drawerWidth, 1.0)), 0.0), 1.0)
            onDragChanged?(progress)

        case .ended:
            let progress = min(max(dragStartProgress + (dx / max(drawerWidth, 1.0)), 0.0), 1.0)
            let shouldOpen: Bool
            if dragStartProgress < 0.5 {
                shouldOpen = (progress >= 0.28) || (vx >= 320.0 && dx >= 18.0)
            } else {
                let shouldClose = (progress <= 0.72) || (vx <= -320.0 && dx <= -18.0)
                shouldOpen = !shouldClose
            }
            trackedScrollPans.removeAll()
            onDragEnded?(shouldOpen)

        case .cancelled, .failed:
            trackedScrollPans.removeAll()
            onDragEnded?(dragStartProgress >= 0.5)

        default:
            break
        }
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === panRecognizer,
              let containerView = attachedView else { return false }
        guard !hasActiveModalPresentation(in: containerView) else { return false }

        let bounds = containerView.bounds
        guard bounds.width > 0 else { return false }

        let location = panRecognizer.location(in: containerView)
        let translation = panRecognizer.translation(in: containerView)
        let velocity = panRecognizer.velocity(in: containerView)
        let isRTL = containerView.effectiveUserInterfaceLayoutDirection == .rightToLeft

        let dx = isRTL ? -translation.x : translation.x
        let vx = isRTL ? -velocity.x : velocity.x
        let dy = abs(translation.y)
        let vy = abs(velocity.y)

        // Require predominantly horizontal motion so vertical scrolling never triggers the drawer.
        if vy > max(abs(vx) * 0.85, 35.0) { return false }
        if dy > max(abs(dx) * 0.85, 12.0) { return false }

        let startPoint = CGPoint(x: location.x - translation.x, y: location.y - translation.y)
        let leadingStartX = isRTL ? (bounds.width - startPoint.x) : startPoint.x

        if isDrawerOpen {
            // Drawer is open: allow dragging toward the leading edge to close.
            guard dx < -2.0 || vx < -25.0 else { return false }
            if isEditingTextInput(in: containerView, at: startPoint) {
                return false
            }
            return true
        } else {
            // Drawer is closed: allow dragging from leading toward trailing edge to open.
            guard canOpenBySwipe else { return false }
            guard dx > 2.0 || vx > 25.0 else { return false }

            if leadingStartX <= Self.leadingEdgeBandPt {
                return true
            }

            if touchesInteractiveHorizontalControlOrText(in: containerView, at: startPoint) {
                return false
            }
            if touchesScrollableHorizontalScrollView(in: containerView, at: startPoint, isRTL: isRTL) {
                return false
            }
            return true
        }
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        guard gestureRecognizer === panRecognizer,
              let containerView = attachedView,
              let otherPan = otherGestureRecognizer as? UIPanGestureRecognizer,
              let scrollView = otherPan.view as? UIScrollView else {
            return false
        }

        let bounds = containerView.bounds
        let isRTL = containerView.effectiveUserInterfaceLayoutDirection == .rightToLeft
        if !isDrawerOpen && canOpenBySwipe && panRecognizer.numberOfTouches > 0 && bounds.width > 0 {
            let loc = panRecognizer.location(in: containerView)
            let leadingX = isRTL ? (bounds.width - loc.x) : loc.x
            if leadingX <= Self.leadingEdgeBandPt {
                return false
            }
        }

        let canScrollHorizontally = scrollView.contentSize.width > scrollView.bounds.width + 1.0
        if canScrollHorizontally {
            let atLeadingEdge = isRTL
                ? (scrollView.contentOffset.x >= (scrollView.contentSize.width - scrollView.bounds.width + scrollView.adjustedContentInset.right - 1.0))
                : (scrollView.contentOffset.x <= (-scrollView.adjustedContentInset.left + 1.0))
            if !atLeadingEdge {
                return false
            }
        }

        trackedScrollPans.removeAll { $0.recognizer == nil || $0.recognizer === otherPan }
        trackedScrollPans.append(WeakPanRecognizer(recognizer: otherPan))
        return true
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        guard gestureRecognizer === panRecognizer,
              let containerView = attachedView,
              !hasActiveModalPresentation(in: containerView),
              otherGestureRecognizer is UIPanGestureRecognizer else {
            return false
        }
        guard !isDrawerOpen && canOpenBySwipe && panRecognizer.numberOfTouches > 0 else { return false }

        let bounds = containerView.bounds
        guard bounds.width > 0 else { return false }
        let isRTL = containerView.effectiveUserInterfaceLayoutDirection == .rightToLeft
        let loc = panRecognizer.location(in: containerView)
        let leadingX = isRTL ? (bounds.width - loc.x) : loc.x
        return leadingX <= Self.leadingEdgeBandPt
    }

    private func cancelTrackedScrollPans() {
        for entry in trackedScrollPans {
            guard let scrollPan = entry.recognizer else { continue }
            if scrollPan.state == .began || scrollPan.state == .changed || scrollPan.state == .possible {
                scrollPan.isEnabled = false
                scrollPan.isEnabled = true
            }
        }
        trackedScrollPans.removeAll()
    }

    private func hasActiveModalPresentation(in view: UIView) -> Bool {
        guard let rootVC = view.window?.rootViewController else { return false }
        return hasPresentedViewController(in: rootVC)
    }

    private func hasPresentedViewController(in vc: UIViewController) -> Bool {
        if vc.presentedViewController != nil {
            return true
        }
        for child in vc.children {
            if hasPresentedViewController(in: child) {
                return true
            }
        }
        return false
    }

    private func isEditingTextInput(in containerView: UIView, at point: CGPoint) -> Bool {
        var current = containerView.hitTest(point, with: nil)
        while let view = current, view !== containerView {
            if (view is UITextField || view is UITextView) && view.isFirstResponder {
                return true
            }
            current = view.superview
        }
        return false
    }

    private func touchesInteractiveHorizontalControlOrText(in containerView: UIView, at point: CGPoint) -> Bool {
        var current = containerView.hitTest(point, with: nil)
        while let view = current, view !== containerView {
            if view is UISlider || view is UISwitch || view is UITextField || view is UITextView {
                return true
            }
            current = view.superview
        }
        return false
    }

    private func touchesScrollableHorizontalScrollView(
        in containerView: UIView,
        at point: CGPoint,
        isRTL: Bool
    ) -> Bool {
        var current = containerView.hitTest(point, with: nil)
        while let view = current, view !== containerView {
            if let scrollView = view as? UIScrollView,
               scrollView.isScrollEnabled,
               scrollView.contentSize.width > scrollView.bounds.width + 1.0 {
                let atLeadingEdge = isRTL
                    ? (scrollView.contentOffset.x >= (scrollView.contentSize.width - scrollView.bounds.width + scrollView.adjustedContentInset.right - 1.0))
                    : (scrollView.contentOffset.x <= (-scrollView.adjustedContentInset.left + 1.0))
                if !atLeadingEdge {
                    return true
                }
            }
            current = view.superview
        }
        return false
    }
}

private struct SidebarDrawerGestureInstaller: UIViewControllerRepresentable {
    let handler: SidebarDrawerGestureHandler
    let isDrawerOpen: Bool
    let canOpenBySwipe: Bool
    let currentProgress: @MainActor () -> CGFloat
    let onDragBegan: @MainActor (CGFloat) -> Void
    let onDragChanged: @MainActor (CGFloat) -> Void
    let onDragEnded: @MainActor (Bool) -> Void

    func makeUIViewController(context: Context) -> SidebarDrawerGestureAnchorViewController {
        syncHandler()
        return SidebarDrawerGestureAnchorViewController(handler: handler)
    }

    func updateUIViewController(_ uiViewController: SidebarDrawerGestureAnchorViewController, context: Context) {
        syncHandler()
        uiViewController.handler = handler
        uiViewController.configureContainerView()
    }

    static func dismantleUIViewController(_ uiViewController: SidebarDrawerGestureAnchorViewController, coordinator: ()) {
        uiViewController.detachHandler()
    }

    private func syncHandler() {
        handler.isDrawerOpen = isDrawerOpen
        handler.canOpenBySwipe = canOpenBySwipe
        handler.currentProgress = currentProgress
        handler.onDragBegan = onDragBegan
        handler.onDragChanged = onDragChanged
        handler.onDragEnded = onDragEnded
    }
}

@MainActor
private final class SidebarDrawerGestureAnchorViewController: UIViewController {
    var handler: SidebarDrawerGestureHandler
    private weak var lastAttachedView: UIView?

    init(handler: SidebarDrawerGestureHandler) {
        self.handler = handler
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let anchorView = UIView(frame: .zero)
        anchorView.backgroundColor = .clear
        anchorView.isUserInteractionEnabled = false
        anchorView.isAccessibilityElement = false
        anchorView.accessibilityElementsHidden = true
        self.view = anchorView
    }

    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        configureContainerView()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        configureContainerView()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        configureContainerView()
        Task { @MainActor [weak self] in
            self?.configureContainerView()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        configureContainerView()
    }

    func configureContainerView() {
        guard let containerView = resolveContainerView() else { return }
        if lastAttachedView === containerView && handler.attachedView === containerView {
            return
        }
        lastAttachedView = containerView
        handler.attach(to: containerView)
    }

    func detachHandler() {
        handler.detach(from: lastAttachedView)
        lastAttachedView = nil
    }

    private func resolveContainerView() -> UIView? {
        if let parentView = self.parent?.view {
            return parentView
        }
        if let rootView = self.view.window?.rootViewController?.view {
            return rootView
        }
        var current = self.view.superview
        var topMost: UIView?
        while let view = current {
            if view is UIWindow { break }
            topMost = view
            current = view.superview
        }
        return topMost
    }
}
#endif

