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

    public var defaultFABAccessibilityId: String {
        switch self {
        case .agents:      return "fab-compose"
        case .automations: return "fab-add-automation"
        case .settings:    return "fab-pair-host"
        }
    }
}

/// Shared UE v2.0 surface, border, and ink tokens complementing `AntigravityTheme`.
enum UEChromePalette {
    static let surfacePopover = Color(red: 0x25 / 255.0, green: 0x27 / 255.0, blue: 0x2F / 255.0)
    static let surfaceSheet = Color(red: 0x17 / 255.0, green: 0x18 / 255.0, blue: 0x1D / 255.0)
    static let surfaceSheetGroup = Color(red: 0x20 / 255.0, green: 0x22 / 255.0, blue: 0x29 / 255.0)
    static let surfacePill = Color(red: 0x17 / 255.0, green: 0x19 / 255.0, blue: 0x1F / 255.0)
    static let surfaceSubtleBox = Color(red: 0x1B / 255.0, green: 0x1D / 255.0, blue: 0x23 / 255.0)
    static let surfaceGlassTab = Color(red: 0x1B / 255.0, green: 0x1D / 255.0, blue: 0x23 / 255.0)
    static let surfaceActiveTabSlot = Color(red: 0x31 / 255.0, green: 0x34 / 255.0, blue: 0x3E / 255.0)
    static let inkOnPrimaryCTA = Color(red: 0x0A / 255.0, green: 0x0E / 255.0, blue: 0x17 / 255.0)
    static let textPrimary = Color(red: 0xF5 / 255.0, green: 0xF7 / 255.0, blue: 0xFA / 255.0)
    static let textBody = Color(red: 0xD5 / 255.0, green: 0xD8 / 255.0, blue: 0xE2 / 255.0)
    static let textSecondary = Color(red: 0x8E / 255.0, green: 0x93 / 255.0, blue: 0xA2 / 255.0)
    static let textMuted = Color(red: 0x7C / 255.0, green: 0x81 / 255.0, blue: 0x90 / 255.0)
    static let cardBorder = Color.white.opacity(0.08)
    static let subtleDivider = Color.white.opacity(0.07)
}

/// Signature UE01 / UE06 global bottom navigation chrome:
/// Left Floating Liquid Glass 3-Tab Capsule (`Agents` | `Automations` | `Settings`)
/// + Detached Right `56×56pt` Periwinkle (`AntigravityTheme.accentPeriwinkle`) Circular FAB.
public struct AntigravityFloatingTabBar: View {
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
                            Text(tab.title)
                                .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                                .lineLimit(1)
                        }
                        .foregroundStyle(
                            isSelected
                                ? AntigravityTheme.accentPeriwinkle
                                : Color(red: 0xC2 / 255.0, green: 0xC6 / 255.0, blue: 0xD2 / 255.0)
                        )
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(
                            Group {
                                if isSelected {
                                    Capsule()
                                        .fill(UEChromePalette.surfaceActiveTabSlot)
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
                        .fill(UEChromePalette.surfaceGlassTab.opacity(0.90))
                }
            )
            .overlay(
                Capsule()
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.45), radius: 18, x: 0, y: 8)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(tabBarAccessibilityId)

            // Right: Detached 56x56pt Periwinkle Circular FAB
            Button {
                onTapFAB()
            } label: {
                Image(systemName: selectedTab.fabSymbolName)
                    .font(.system(size: selectedTab == .automations ? 22 : 19, weight: .semibold))
                    .foregroundStyle(UEChromePalette.inkOnPrimaryCTA)
                    .frame(width: 56, height: 56)
                    .background(
                        Circle()
                            .fill(AntigravityTheme.accentPeriwinkle)
                    )
                    .shadow(color: Color.black.opacity(0.40), radius: 14, x: 0, y: 6)
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
                    .overlay(Color.white.opacity(configuration.isPressed ? 0.09 : 0.0))
            )
            .contentShape(Rectangle())
    }
}

/// Adaptive shell container (`AntigravityShellController`) routing all 13 UE v2.0 flows
/// interactively or rendering deterministic isolated ESDD verification scenes (`UE01`..`UE13`).
public struct AntigravityRootContainerView: View {
    @Bindable public var store: AntigravitySessionStore
    @Binding public var activeVerifyCase: ESDDVerifySceneCase?

    @State private var selectedTab: ShellTab = .agents
    @State private var activeModalSheet: ModalSheetDestination?
    @State private var navigationPath: [ShellPushDestination] = []
    @State private var settingsScannerTriggered: Bool = false
    #if canImport(UIKit)
    @State private var popGestureHandler = InteractivePopGestureHandler()
    #endif

    private enum ModalSheetDestination: String, Identifiable {
        case displayOptions
        case createProject
        case contextMenuPreview

        var id: String { rawValue }
    }

    private enum ShellPushDestination: Hashable {
        case projectDetail(String)
        case cascadeChat
        case planReview
        case turnDiffReview
    }

    public init(
        store: AntigravitySessionStore,
        activeVerifyCase: Binding<ESDDVerifySceneCase?>
    ) {
        self.store = store
        self._activeVerifyCase = activeVerifyCase
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

    @ViewBuilder
    private var pairedShellView: some View {
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
        .onAppear {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                syncNavigationPath(from: store.activeRoute)
            }
        }
        .onChange(of: navigationPath) { _, newPath in
            syncActiveRoute(from: newPath)
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
            case .modelAndMode, .modelConfigPicker:
                ModelAndModeSheetView(store: store)
            case .addContext, .fileMentionPicker:
                AddContextSheetView(store: store)
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

    @ViewBuilder
    private var tabRootContentView: some View {
        switch selectedTab {
        case .agents:
            AgentsHomeViewController(
                store: store,
                onSelectTab: { tab in selectedTab = tab },
                onOpenDisplayOptions: { activeModalSheet = .displayOptions },
                onOpenNewProject: { activeModalSheet = .createProject },
                onOpenProjectDetail: { slug in
                    store.selectProject(slug)
                },
                onOpenContextMenuPreview: { activeModalSheet = .contextMenuPreview },
                onOpenConversation: { convId in
                    openOrCreateConversation(convId, defaultProjectSlug: store.selectedProjectId)
                }
            )
        case .automations:
            AutomationsViewController(
                store: store,
                onSelectTab: { tab in selectedTab = tab },
                onOpenDisplayOptions: { activeModalSheet = .displayOptions }
            )
        case .settings:
            settingsTabContainerView
        }
    }

    @ViewBuilder
    private func pushedDestinationView(for destination: ShellPushDestination) -> some View {
        switch destination {
        case .projectDetail(let projectSlug):
            ProjectDetailViewController(
                store: store,
                projectSlug: projectSlug,
                onBack: {
                    popTopDestination()
                },
                onOpenConversation: { convId in
                    openOrCreateConversation(convId, defaultProjectSlug: projectSlug)
                }
            )
        case .cascadeChat:
            CascadeChatViewController(
                store: store,
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
                stackDepth: navigationPath.count
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
        case .projectDetail(let slug):
            let target = ShellPushDestination.projectDetail(slug)
            if navigationPath.last == target {
                return
            }
            if let existingIndex = navigationPath.lastIndex(of: target) {
                navigationPath.removeSubrange((existingIndex + 1)...)
            } else {
                navigationPath = [target]
            }
        case .cascadeChat:
            if navigationPath.last == .cascadeChat {
                return
            }
            if let existingIndex = navigationPath.lastIndex(of: .cascadeChat) {
                navigationPath.removeSubrange((existingIndex + 1)...)
            } else if case .projectDetail = navigationPath.last {
                navigationPath.append(.cascadeChat)
            } else {
                navigationPath = [.cascadeChat]
            }
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
        switch path.last {
        case .none:
            if store.activeRoute != .tabRoot && store.activeRoute != .pairingSettings {
                store.activeRoute = .tabRoot
            }
        case .projectDetail(let slug):
            if store.activeRoute != .projectDetail(slug) {
                store.activeRoute = .projectDetail(slug)
            }
        case .cascadeChat:
            if case .cascadeChat = store.activeRoute {
                // Keep exact activeCascadeId while already on the conversation route.
            } else {
                store.activeRoute = .cascadeChat(store.activeCascadeId)
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
        VStack(spacing: 0) {
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
                }
            )
            Spacer(minLength: 0)
            AntigravityFloatingTabBar(
                selectedTab: .settings,
                onSelectTab: { tab in
                    store.activeRoute = .tabRoot
                    selectedTab = tab
                },
                onTapFAB: {
                    settingsScannerTriggered = true
                }
            )
        }
        .background(AntigravityTheme.canvasObsidian)
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

    // MARK: - Isolated Deterministic ESDD Scenes (UE01 .. UE13)

    @ViewBuilder
    private func isolatedESDDSceneView(for verifyCase: ESDDVerifySceneCase) -> some View {
        switch verifyCase {
        case .agentsHome:
            AgentsHomeViewController(store: store)
        case .displayOptions:
            DisplayOptionsSheetView(store: store)
        case .contextMenuPin:
            ConversationContextPreviewMenu(store: store)
        case .projectDetail:
            ProjectDetailViewController(store: store)
        case .createProject:
            CreateProjectSheetView(store: store)
        case .automations:
            AutomationsViewController(store: store)
        case .chatAndComposer:
            CascadeChatViewController(store: store)
        case .addContext:
            AddContextSheetView(store: store)
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

    override init() {
        super.init()
    }

    func attach(to navController: UINavigationController) {
        if self.navigationController !== navController {
            self.navigationController = navController
            navController.view.backgroundColor = UIColor(
                red: 0x09 / 255.0,
                green: 0x0A / 255.0,
                blue: 0x0D / 255.0,
                alpha: 1.0
            )
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

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let nav = navigationController else { return false }
        guard nav.viewControllers.count > 1 else { return false }
        guard nav.presentedViewController == nil else { return false }
        guard nav.transitionCoordinator == nil else { return false }

        if let pan = gestureRecognizer as? UIPanGestureRecognizer {
            let velocity = pan.velocity(in: nav.view)
            let isRTL = nav.view.effectiveUserInterfaceLayoutDirection == .rightToLeft
            let horizontalVelocity = isRTL ? -velocity.x : velocity.x
            if horizontalVelocity < 0 {
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
        shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        guard let nav = navigationController else { return false }
        guard nav.viewControllers.count > 1 else { return false }
        guard nav.presentedViewController == nil else { return false }
        return otherGestureRecognizer is UIPanGestureRecognizer
    }
}

private struct InteractivePopGestureEnabler: UIViewControllerRepresentable {
    let handler: InteractivePopGestureHandler
    let stackDepth: Int

    func makeUIViewController(context: Context) -> InteractivePopGestureAnchorViewController {
        InteractivePopGestureAnchorViewController(handler: handler)
    }

    func updateUIViewController(_ uiViewController: InteractivePopGestureAnchorViewController, context: Context) {
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

    func configureNavigationController() {
        guard let navController = resolveNavigationController() else { return }
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
#endif

