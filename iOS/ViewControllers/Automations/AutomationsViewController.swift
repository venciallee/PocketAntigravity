import SwiftUI
import AntigravityData

/// State `UE06_AUTOMATIONS`: Automations Hub (`SCHEDULED · 2`, `ALWAYS ON · 1`, `PAUSED · 1`).
/// Matches `/home/antigravity/iOS_·_Automations.png` 1:1.
public struct AutomationsViewController: View {
    @Bindable public var store: AntigravitySessionStore
    public var onSelectTab: ((ShellTab) -> Void)?
    public var onOpenDisplayOptions: (() -> Void)?

    public struct ScheduledAutomationCardModel: Identifiable {
        public let id: String
        public var title: String
        public var subtitle: String
        public var nextRunText: String
        public var lastRunText: String
        public var needsReview: Bool
        public let cardAccessibilityId: String
        public let playAccessibilityId: String
    }

    private enum AutomationSectionFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case scheduled = "Scheduled"
        case alwaysOn = "Always On"
        case paused = "Paused"

        var id: String { rawValue }
    }

    @State private var quickPromptText: String = ""
    @State private var isPausedResumed: Bool = false
    @State private var isShowingEditorSheet: Bool = false
    @State private var isShowingGoogleSignIn: Bool = false
    @State private var editingAutomation: AutomationItem? = nil
    @State private var sectionFilter: AutomationSectionFilter = .all
    @State private var deletingAutomation: AutomationItem? = nil

    @State private var scheduledAutomations: [ScheduledAutomationCardModel] = [
        ScheduledAutomationCardModel(
            id: "auto-nightly-audit",
            title: "Nightly dependency audit",
            subtitle: "ledger-svc · Daily at 02:00 · Flash",
            nextRunText: "Tonight, 02:00",
            lastRunText: "Succeeded · 22h ago",
            needsReview: false,
            cardAccessibilityId: "automation-card-nightly",
            playAccessibilityId: "btn-run-nightly"
        ),
        ScheduledAutomationCardModel(
            id: "auto-weekly-flaky",
            title: "Weekly flaky-test report",
            subtitle: "ledger-svc · Mondays at 09:00 · Pro",
            nextRunText: "Mon, 09:00",
            lastRunText: "Needs review · 2d",
            needsReview: true,
            cardAccessibilityId: "automation-card-flaky",
            playAccessibilityId: "btn-run-flaky"
        )
    ]

    public init(
        store: AntigravitySessionStore,
        onSelectTab: ((ShellTab) -> Void)? = nil,
        onOpenDisplayOptions: (() -> Void)? = nil
    ) {
        self.store = store
        self.onSelectTab = onSelectTab
        self.onOpenDisplayOptions = onOpenDisplayOptions
    }

    private var isLiveMode: Bool {
        !store.isVerificationMode || store.isLiveBackendConnected
    }

    private var isAuthExpired: Bool {
        store.isAutomationsAuthExpired || store.connectionStatusText == "Google Sign-In Expired"
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 10) {
                    topFilterToolbar
                    Text("Automations")
                        .font(.system(size: 32, weight: .bold))
                        .tracking(-0.5)
                        .foregroundStyle(Color.white)

                    quickCreateCapsuleBar

                    if isLiveMode {
                        liveAutomationsBody
                    } else {
                        scheduledSection
                        alwaysOnSection
                        pausedSection
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 96)
            }
            .refreshable {
                await store.reconnectNow(userInitiated: true, includeAutomations: true)
            }

            LinearGradient(
                colors: [
                    AntigravityTheme.canvasObsidian.opacity(0.0),
                    AntigravityTheme.canvasObsidian.opacity(0.84),
                    AntigravityTheme.canvasObsidian
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 82)
            .allowsHitTesting(false)

            AntigravityFloatingTabBar(
                selectedTab: .automations,
                tabBarAccessibilityId: "floating-tab-bar",
                fabAccessibilityId: "fab-add-automation",
                onSelectTab: { tab in
                    onSelectTab?(tab)
                },
                onTapFAB: {
                    if isLiveMode {
                        editingAutomation = nil
                        isShowingEditorSheet = true
                    } else {
                        createInlineAutomation()
                    }
                }
            )
        }
        .background(AntigravityTheme.canvasObsidian.ignoresSafeArea())
        .task {
            guard isLiveMode else { return }
            store.selectedTab = .automations
            await store.refreshAutomations()
        }
        .sheet(isPresented: $isShowingEditorSheet) {
            AutomationEditorSheetView(
                store: store,
                editingItem: editingAutomation,
                initialPromptSeed: editingAutomation == nil ? quickPromptText : "",
                onRequestSignIn: {
                    isShowingEditorSheet = false
                    isShowingGoogleSignIn = true
                },
                onDismiss: {
                    isShowingEditorSheet = false
                    editingAutomation = nil
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isShowingGoogleSignIn) {
            let targetURL = store.lastScannedRelayURL.isEmpty
                ? store.activeHost.endpointURL.absoluteString
                : store.lastScannedRelayURL
            CloudRelaySignInSheet(
                targetRelayURLString: targetURL.isEmpty ? SAPISIDHashGenerator.defaultOrigin : targetURL,
                onAuthenticated: { cookieHeader, finalURL, detectedAuthUser in
                    isShowingGoogleSignIn = false
                    let effectiveURL = RemoteHostInstance.resolveEffectiveRelayTarget(
                        scannedInput: targetURL,
                        webViewFinalURL: finalURL
                    )
                    Task {
                        let ok = await store.connectCloudRelay(
                            relayURLString: effectiveURL,
                            sessionCookie: cookieHeader,
                            authUser: detectedAuthUser
                        )
                        if ok {
                            await store.refreshAutomations()
                        }
                    }
                },
                onDismiss: {
                    isShowingGoogleSignIn = false
                }
            )
        }
        .alert(
            "Delete Automation?",
            isPresented: Binding(
                get: { deletingAutomation != nil },
                set: { if !$0 { deletingAutomation = nil } }
            ),
            presenting: deletingAutomation
        ) { target in
            Button("Delete", role: .destructive) {
                store.deleteAutomation(target.id)
                deletingAutomation = nil
            }
            Button("Cancel", role: .cancel) {
                deletingAutomation = nil
            }
        } message: { target in
            Text("This removes \"\(target.title)\" from \(store.activeHost.hostname). Existing conversation history will remain intact.")
        }
    }

    // MARK: - 1. Top Filter Button

    private var topFilterToolbar: some View {
        HStack {
            if isLiveMode && sectionFilter != .all {
                Button {
                    sectionFilter = .all
                } label: {
                    HStack(spacing: 6) {
                        Text(sectionFilter.rawValue)
                            .font(.system(size: 13, weight: .semibold))
                        Image(systemName: "xmark")
                            .font(.system(size: 10.5, weight: .bold))
                    }
                    .foregroundStyle(AntigravityTheme.accentPeriwinkle)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 34)
                    .background(
                        Capsule()
                            .fill(AntigravityTheme.accentPeriwinkle.opacity(0.14))
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(AntigravityTheme.accentPeriwinkle.opacity(0.28), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }

            Spacer()

            if isLiveMode {
                Menu {
                    ForEach(AutomationSectionFilter.allCases) { option in
                        Button {
                            sectionFilter = option
                        } label: {
                            if sectionFilter == option {
                                Label(option.rawValue, systemImage: "checkmark")
                            } else {
                                Text(option.rawValue)
                            }
                        }
                    }
                    Divider()
                    Button {
                        Task { await store.refreshAutomations() }
                    } label: {
                        Label("Refresh Automations", systemImage: "arrow.clockwise")
                    }
                    Button {
                        let seed = quickPromptText
                        quickPromptText = ""
                        store.openAutomationPromptDraft(prompt: seed)
                    } label: {
                        Label("Create with Prompt", systemImage: "sparkles")
                    }
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "line.3.horizontal.decrease")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(sectionFilter == .all ? AntigravityTheme.textPrimary : AntigravityTheme.accentPeriwinkle)
                            .frame(width: AntigravityTheme.minTouchTargetPt, height: AntigravityTheme.minTouchTargetPt)
                            .background(Circle().fill(AntigravityTheme.surfacePill))
                            .overlay(Circle().strokeBorder(AntigravityTheme.cardBorder, lineWidth: 1))
                        if sectionFilter != .all {
                            Circle()
                                .fill(AntigravityTheme.accentPeriwinkle)
                                .frame(width: 8, height: 8)
                                .offset(x: -2, y: 2)
                        }
                    }
                }
                .accessibilityIdentifier("btn-automations-filter")
            } else {
                Button {
                    onOpenDisplayOptions?()
                } label: {
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AntigravityTheme.textPrimary)
                        .frame(width: AntigravityTheme.minTouchTargetPt, height: AntigravityTheme.minTouchTargetPt)
                        .background(Circle().fill(AntigravityTheme.surfacePill))
                        .overlay(Circle().strokeBorder(AntigravityTheme.cardBorder, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("btn-automations-filter")
            }
        }
    }

    // MARK: - 2. Natural-Language Quick Create Bar

    private var quickCreateCapsuleBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 9) {
                Image(systemName: "bolt")
                    .font(.system(size: 14.5, weight: .medium))
                    .foregroundStyle(AntigravityTheme.textSecondary)

                TextField("Every weekday at 9, summarize", text: $quickPromptText)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(AntigravityTheme.textPrimary)
                    .tint(AntigravityTheme.accentPeriwinkle)
                    .lineLimit(1)
                    .submitLabel(.done)
                    .onSubmit {
                        createInlineAutomation()
                    }
            }
            .frame(maxWidth: .infinity, minHeight: AntigravityTheme.minTouchTargetPt, alignment: .leading)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("automation-prompt-input")

            Button {
                createInlineAutomation()
            } label: {
                Group {
                    if isLiveMode && store.isMutatingAutomation {
                        ProgressView()
                            .tint(Color.white)
                            .scaleEffect(0.8)
                    } else {
                        Text("Create")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.white)
                    }
                }
                .padding(.horizontal, 16)
                .frame(minWidth: 74, minHeight: AntigravityTheme.minTouchTargetPt)
                .background(
                    Capsule()
                        .fill(Color(red: 0x26 / 255.0, green: 0x28 / 255.0, blue: 0x30 / 255.0))
                )
                .overlay(
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .disabled(isLiveMode && store.isMutatingAutomation)
            .accessibilityIdentifier("btn-create-automation-inline")
        }
        .padding(.leading, 15)
        .padding(.trailing, 5)
        .frame(minHeight: 52)
        .background(
            Capsule()
                .fill(AntigravityTheme.surfaceCard)
        )
        .overlay(
            Capsule()
                .strokeBorder(Color.white.opacity(0.09), lineWidth: 1)
        )
    }

    // MARK: - 3. SCHEDULED · 2 Section

    private var scheduledSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SCHEDULED · \(scheduledAutomations.count)")
                .font(.system(size: 11.5, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(AntigravityTheme.textMuted)
                .padding(.leading, 2)
                .padding(.top, 2)

            ForEach(scheduledAutomations.indices, id: \.self) { index in
                let item = scheduledAutomations[index]
                VStack(alignment: .leading, spacing: 9) {
                    HStack(alignment: .center, spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Color.white)
                            Text(item.subtitle)
                                .font(.system(size: 13, weight: .regular))
                                .foregroundStyle(AntigravityTheme.textSecondary)
                        }

                        Spacer()

                        Button {
                            scheduledAutomations[index].lastRunText = "Running · just now"
                            scheduledAutomations[index].needsReview = false
                        } label: {
                            Image(systemName: "play.fill")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(AntigravityTheme.accentPeriwinkle)
                                .frame(
                                    width: AntigravityTheme.minTouchTargetPt,
                                    height: AntigravityTheme.minTouchTargetPt
                                )
                                .background(
                                    Circle()
                                        .fill(Color(red: 0x1E / 255.0, green: 0x24 / 255.0, blue: 0x33 / 255.0))
                                )
                                .overlay(
                                    Circle()
                                        .strokeBorder(AntigravityTheme.accentPeriwinkle.opacity(0.20), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier(item.playAccessibilityId)
                    }

                    HStack(spacing: 9) {
                        // NEXT RUN Stat Box
                        VStack(alignment: .leading, spacing: 3) {
                            Text("NEXT RUN")
                                .font(.system(size: 10.5, weight: .semibold))
                                .tracking(0.5)
                                .foregroundStyle(AntigravityTheme.textMuted)
                            Text(item.nextRunText)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(AntigravityTheme.textPrimary)
                        }
                        .padding(.horizontal, 11)
                        .padding(.vertical, 9)
                        .frame(maxWidth: .infinity, minHeight: 50, alignment: .topLeading)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(AntigravityTheme.surfaceSubtleBox)
                        )

                        // LAST RUN Stat Box
                        VStack(alignment: .leading, spacing: 3) {
                            Text("LAST RUN")
                                .font(.system(size: 10.5, weight: .semibold))
                                .tracking(0.5)
                                .foregroundStyle(
                                    item.needsReview ? AntigravityTheme.statusWaiting : AntigravityTheme.textMuted
                                )

                            HStack(alignment: .firstTextBaseline, spacing: 5) {
                                if !item.needsReview {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10.5, weight: .bold))
                                        .foregroundStyle(AntigravityTheme.statusDone)
                                }
                                Text(item.lastRunText)
                                    .font(.system(size: 13.5, weight: .medium))
                                    .foregroundStyle(
                                        item.needsReview ? AntigravityTheme.statusWaiting : AntigravityTheme.textPrimary
                                    )
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                            }
                        }
                        .padding(.horizontal, 11)
                        .padding(.vertical, 9)
                        .frame(maxWidth: .infinity, minHeight: 50, alignment: .topLeading)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(
                                    item.needsReview
                                        ? AntigravityTheme.statusWaiting.opacity(0.14)
                                        : AntigravityTheme.surfaceSubtleBox
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(
                                    item.needsReview ? AntigravityTheme.statusWaiting.opacity(0.24) : Color.clear,
                                    lineWidth: 1
                                )
                        )
                    }
                }
                .padding(13)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(AntigravityTheme.surfaceCard)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(AntigravityTheme.cardBorder, lineWidth: 1)
                )
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier(item.cardAccessibilityId)
            }
        }
    }

    // MARK: - 4. ALWAYS ON · 1 Section

    private var alwaysOnSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("ALWAYS ON · 1")
                .font(.system(size: 11.5, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(AntigravityTheme.textMuted)
                .padding(.leading, 2)
                .padding(.top, 2)

            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(AntigravityTheme.statusDone.opacity(0.22))
                        .frame(width: 20, height: 20)
                    Circle()
                        .fill(AntigravityTheme.statusDone)
                        .frame(width: 9.5, height: 9.5)
                }

                VStack(alignment: .leading, spacing: 2.5) {
                    Text("Triage new pull requests")
                        .font(.system(size: 15.5, weight: .semibold))
                        .foregroundStyle(Color.white)
                    Text("web-console · On PR opened · Flash Lite")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(AntigravityTheme.textSecondary)
                    Text("Last run 14m ago")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(AntigravityTheme.textBody)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(AntigravityTheme.textMuted)
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
            .accessibilityIdentifier("automation-card-always-on")
        }
    }

    // MARK: - 5. PAUSED · 1 Section

    private var pausedSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("PAUSED · \(isPausedResumed ? 0 : 1)")
                .font(.system(size: 11.5, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(AntigravityTheme.textMuted)
                .padding(.leading, 2)
                .padding(.top, 2)

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Bundle size watch")
                        .font(.system(size: 15.5, weight: .semibold))
                        .foregroundStyle(
                            isPausedResumed
                                ? Color.white
                                : Color(red: 0xA0 / 255.0, green: 0xA5 / 255.0, blue: 0xB4 / 255.0)
                        )
                    Text("web-console · Daily at 08:00 · Flash")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(AntigravityTheme.textMuted)
                }

                Spacer()

                Button {
                    isPausedResumed.toggle()
                } label: {
                    Text(isPausedResumed ? "Active" : "Resume")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AntigravityTheme.textPrimary)
                        .padding(.horizontal, 16)
                        .frame(minHeight: AntigravityTheme.minTouchTargetPt)
                        .background(
                            Capsule()
                                .fill(Color(red: 0x23 / 255.0, green: 0x25 / 255.0, blue: 0x2D / 255.0))
                        )
                        .overlay(
                            Capsule()
                                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("btn-resume-paused")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(AntigravityTheme.surfaceCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(AntigravityTheme.cardBorder, lineWidth: 1)
            )
        }
    }

    // MARK: - Live Backend Automations View

    @ViewBuilder
    private var liveAutomationsBody: some View {
        if let err = store.automationsErrorText, !err.isEmpty {
            automationErrorBanner(err)
        }

        if store.automations.isEmpty {
            if store.isLoadingAutomations {
                VStack(spacing: 12) {
                    ProgressView()
                        .tint(AntigravityTheme.accentPeriwinkle)
                    Text("Loading automations from \(store.activeHost.hostname)...")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AntigravityTheme.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 36)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(AntigravityTheme.surfaceCard)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(AntigravityTheme.cardBorder, lineWidth: 1)
                )
            } else if !store.hasPairedBackend && !store.isLiveBackendConnected {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        Image(systemName: "bolt.slash")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(AntigravityTheme.statusWaiting)
                        Text("Pair a Host to Use Automations")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.white)
                    }
                    Text("Connect to Antigravity Desktop via Cloud Relay or Direct LAN in Settings to view, create, and trigger scheduled Automations.")
                        .font(.system(size: 13.5, weight: .regular))
                        .foregroundStyle(AntigravityTheme.textSecondary)
                        .lineSpacing(2)

                    Button {
                        onSelectTab?(.settings)
                    } label: {
                        Text("Open Settings")
                            .font(.system(size: 14.5, weight: .semibold))
                            .foregroundStyle(AntigravityTheme.inkOnPrimaryCTA)
                            .frame(maxWidth: .infinity, minHeight: AntigravityTheme.minTouchTargetPt)
                            .background(
                                Capsule().fill(AntigravityTheme.accentPeriwinkle)
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(AntigravityTheme.surfaceCard)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(AntigravityTheme.cardBorder, lineWidth: 1)
                )
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(AntigravityTheme.accentPeriwinkle.opacity(0.14))
                                .frame(width: 36, height: 36)
                            Image(systemName: "clock.badge.checkmark")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(AntigravityTheme.accentPeriwinkle)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("No automations yet")
                                .font(.system(size: 16.5, weight: .semibold))
                                .foregroundStyle(Color.white)
                            Text("Running on \(store.activeHost.hostname)")
                                .font(.system(size: 12.5, weight: .regular))
                                .foregroundStyle(AntigravityTheme.textMuted)
                        }
                    }

                    Text("Run a prompt on a schedule, like a morning summary of yesterday's changes. Runs show up here.")
                        .font(.system(size: 13.5, weight: .regular))
                        .foregroundStyle(AntigravityTheme.textSecondary)
                        .lineSpacing(2)

                    HStack(spacing: 10) {
                        Button {
                            let seed = quickPromptText
                            quickPromptText = ""
                            store.openAutomationPromptDraft(prompt: seed)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 13, weight: .semibold))
                                Text("Create with Prompt")
                                    .font(.system(size: 14, weight: .semibold))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.88)
                            }
                            .foregroundStyle(AntigravityTheme.textPrimary)
                            .padding(.horizontal, 14)
                            .frame(maxWidth: .infinity, minHeight: AntigravityTheme.minTouchTargetPt)
                            .background(
                                Capsule().fill(AntigravityTheme.surfaceSheetGroup)
                            )
                            .overlay(
                                Capsule().strokeBorder(AntigravityTheme.cardBorder, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("btn-empty-agent-automation")

                        Button {
                            editingAutomation = nil
                            isShowingEditorSheet = true
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "plus")
                                    .font(.system(size: 13, weight: .bold))
                                Text("New")
                                    .font(.system(size: 14, weight: .semibold))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(AntigravityTheme.inkOnPrimaryCTA)
                            .padding(.horizontal, 20)
                            .frame(minWidth: 96, minHeight: AntigravityTheme.minTouchTargetPt)
                            .background(
                                Capsule().fill(AntigravityTheme.accentPeriwinkle)
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("btn-empty-new-automation")
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(AntigravityTheme.surfaceCard)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(AntigravityTheme.cardBorder, lineWidth: 1)
                )
            }
        } else {
            let showScheduled = (sectionFilter == .all || sectionFilter == .scheduled) && !store.scheduledAutomations.isEmpty
            let showAlwaysOn = (sectionFilter == .all || sectionFilter == .alwaysOn) && !store.alwaysOnAutomations.isEmpty
            let showPaused = (sectionFilter == .all || sectionFilter == .paused) && !store.pausedAutomations.isEmpty

            if !showScheduled && !showAlwaysOn && !showPaused {
                HStack {
                    Text("No \(sectionFilter.rawValue.lowercased()) automations.")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(AntigravityTheme.textSecondary)
                    Spacer()
                    Button("Show All") {
                        sectionFilter = .all
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AntigravityTheme.accentPeriwinkle)
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(AntigravityTheme.surfaceCard)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(AntigravityTheme.cardBorder, lineWidth: 1)
                )
            }

            if showScheduled {
                VStack(alignment: .leading, spacing: 8) {
                    Text("SCHEDULED · \(store.scheduledAutomations.count)")
                        .font(.system(size: 11.5, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(AntigravityTheme.textMuted)
                        .padding(.leading, 2)
                        .padding(.top, 2)

                    ForEach(store.scheduledAutomations) { item in
                        liveScheduledCard(item)
                    }
                }
            }

            if showAlwaysOn {
                VStack(alignment: .leading, spacing: 8) {
                    Text("ALWAYS ON · \(store.alwaysOnAutomations.count)")
                        .font(.system(size: 11.5, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(AntigravityTheme.textMuted)
                        .padding(.leading, 2)
                        .padding(.top, 2)

                    ForEach(store.alwaysOnAutomations) { item in
                        liveAlwaysOnCard(item)
                    }
                }
            }

            if showPaused {
                VStack(alignment: .leading, spacing: 8) {
                    Text("PAUSED · \(store.pausedAutomations.count)")
                        .font(.system(size: 11.5, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(AntigravityTheme.textMuted)
                        .padding(.leading, 2)
                        .padding(.top, 2)

                    ForEach(store.pausedAutomations) { item in
                        livePausedCard(item)
                    }
                }
            }
        }
    }

    private func automationErrorBanner(_ message: String) -> some View {
        let authExpired = isAuthExpired && store.activeHost.channel == .cloudRelay
        let accentColor = authExpired ? AntigravityTheme.statusWaiting : AntigravityTheme.statusError
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: authExpired ? "person.crop.circle.badge.exclamationmark" : "exclamationmark.triangle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(accentColor)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 8) {
                Text(message)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(AntigravityTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    if authExpired {
                        Button {
                            isShowingGoogleSignIn = true
                        } label: {
                            Text("重新登录 Google")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(AntigravityTheme.inkOnPrimaryCTA)
                                .padding(.horizontal, 12)
                                .frame(minHeight: 32)
                                .background(
                                    Capsule().fill(AntigravityTheme.statusWaiting)
                                )
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button {
                            Task { await store.refreshAutomations() }
                        } label: {
                            Text("Retry")
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(AntigravityTheme.accentPeriwinkle)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Spacer(minLength: 4)

            Button {
                store.automationsErrorText = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AntigravityTheme.textMuted)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(accentColor.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(accentColor.opacity(0.32), lineWidth: 1)
        )
    }

    private func liveScheduledCard(_ item: AutomationItem) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .lineLimit(2)
                    Text(item.scheduleSummary)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(AntigravityTheme.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                Button {
                    store.triggerAutomationNow(item.id)
                } label: {
                    Group {
                        if item.isRunningNow {
                            ProgressView()
                                .tint(AntigravityTheme.accentPeriwinkle)
                                .scaleEffect(0.75)
                        } else {
                            Image(systemName: "play.fill")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(AntigravityTheme.accentPeriwinkle)
                        }
                    }
                    .frame(
                        width: AntigravityTheme.minTouchTargetPt,
                        height: AntigravityTheme.minTouchTargetPt
                    )
                    .background(
                        Circle()
                            .fill(Color(red: 0x1E / 255.0, green: 0x24 / 255.0, blue: 0x33 / 255.0))
                    )
                    .overlay(
                        Circle()
                            .strokeBorder(AntigravityTheme.accentPeriwinkle.opacity(0.20), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .disabled(item.isRunningNow)

                Menu {
                    Button {
                        store.triggerAutomationNow(item.id)
                    } label: {
                        Label("Run Now", systemImage: "play.fill")
                    }
                    if item.isScheduleBuiltin {
                        Button {
                            editingAutomation = item
                            isShowingEditorSheet = true
                        } label: {
                            Label("Edit Schedule & Prompt", systemImage: "pencil")
                        }
                    }
                    if let cid = item.lastRunCascadeId, !cid.isEmpty {
                        Button {
                            store.selectCascade(cid)
                        } label: {
                            Label("Open Last Run", systemImage: "bubble.left.and.text.bubble.right")
                        }
                    }
                    Button {
                        store.pauseAutomation(item.id)
                    } label: {
                        Label("Pause", systemImage: "pause.circle")
                    }
                    Divider()
                    Button(role: .destructive) {
                        deletingAutomation = item
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AntigravityTheme.textSecondary)
                        .frame(width: 34, height: AntigravityTheme.minTouchTargetPt)
                }
            }

            HStack(spacing: 9) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("NEXT RUN")
                        .font(.system(size: 10.5, weight: .semibold))
                        .tracking(0.5)
                        .foregroundStyle(AntigravityTheme.textMuted)
                    Text(item.nextRunText)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AntigravityTheme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, minHeight: 50, alignment: .topLeading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(AntigravityTheme.surfaceSubtleBox)
                )

                liveLastRunBox(item)
            }
        }
        .padding(13)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AntigravityTheme.surfaceCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(AntigravityTheme.cardBorder, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func liveLastRunBox(_ item: AutomationItem) -> some View {
        let boxContent = VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text("LAST RUN")
                    .font(.system(size: 10.5, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(item.needsReview ? AntigravityTheme.statusWaiting : AntigravityTheme.textMuted)
                Spacer(minLength: 2)
                if let cid = item.lastRunCascadeId, !cid.isEmpty {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(AntigravityTheme.textMuted)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 5) {
                if item.isRunningNow {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundStyle(AntigravityTheme.statusRunning)
                } else if item.needsReview {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundStyle(AntigravityTheme.statusWaiting)
                } else {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundStyle(AntigravityTheme.statusDone)
                }
                Text(item.lastRunText)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(item.needsReview ? AntigravityTheme.statusWaiting : AntigravityTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, minHeight: 50, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    item.needsReview
                        ? AntigravityTheme.statusWaiting.opacity(0.14)
                        : AntigravityTheme.surfaceSubtleBox
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    item.needsReview ? AntigravityTheme.statusWaiting.opacity(0.24) : Color.clear,
                    lineWidth: 1
                )
        )

        if let cid = item.lastRunCascadeId, !cid.isEmpty {
            Button {
                store.selectCascade(cid)
            } label: {
                boxContent
            }
            .buttonStyle(.plain)
        } else {
            boxContent
        }
    }

    private func liveAlwaysOnCard(_ item: AutomationItem) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill((item.needsReview ? AntigravityTheme.statusWaiting : AntigravityTheme.statusDone).opacity(0.22))
                    .frame(width: 20, height: 20)
                Circle()
                    .fill(item.needsReview ? AntigravityTheme.statusWaiting : AntigravityTheme.statusDone)
                    .frame(width: 9.5, height: 9.5)
            }

            VStack(alignment: .leading, spacing: 2.5) {
                Text(item.title)
                    .font(.system(size: 15.5, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .lineLimit(2)
                Text(item.scheduleSummary)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(AntigravityTheme.textSecondary)
                    .lineLimit(1)
                Text(item.lastRunText)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(item.needsReview ? AntigravityTheme.statusWaiting : AntigravityTheme.textBody)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if let cid = item.lastRunCascadeId, !cid.isEmpty {
                    store.selectCascade(cid)
                }
            }

            Spacer(minLength: 4)

            Menu {
                if let cid = item.lastRunCascadeId, !cid.isEmpty {
                    Button {
                        store.selectCascade(cid)
                    } label: {
                        Label("Open Last Run", systemImage: "bubble.left.and.text.bubble.right")
                    }
                }
                Button {
                    store.restartAutomation(item.id)
                } label: {
                    Label("Restart", systemImage: "arrow.clockwise")
                }
                Button {
                    store.pauseAutomation(item.id)
                } label: {
                    Label("Pause", systemImage: "pause.circle")
                }
                Divider()
                Button(role: .destructive) {
                    deletingAutomation = item
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AntigravityTheme.textSecondary)
                    .frame(width: 34, height: AntigravityTheme.minTouchTargetPt)
            }
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
    }

    private func livePausedCard(_ item: AutomationItem) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 15.5, weight: .semibold))
                    .foregroundStyle(Color(red: 0xA0 / 255.0, green: 0xA5 / 255.0, blue: 0xB4 / 255.0))
                    .lineLimit(2)
                Text(item.scheduleSummary)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(AntigravityTheme.textMuted)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)

            Button {
                store.resumeAutomation(item.id)
            } label: {
                Text("Resume")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AntigravityTheme.textPrimary)
                    .padding(.horizontal, 16)
                    .frame(minHeight: AntigravityTheme.minTouchTargetPt)
                    .background(
                        Capsule()
                            .fill(Color(red: 0x23 / 255.0, green: 0x25 / 255.0, blue: 0x2D / 255.0))
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)

            Menu {
                Button {
                    store.resumeAutomation(item.id)
                } label: {
                    Label("Resume", systemImage: "play.circle")
                }
                if item.isScheduleBuiltin {
                    Button {
                        editingAutomation = item
                        isShowingEditorSheet = true
                    } label: {
                        Label("Edit Schedule & Prompt", systemImage: "pencil")
                    }
                }
                Divider()
                Button(role: .destructive) {
                    deletingAutomation = item
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AntigravityTheme.textMuted)
                    .frame(width: 30, height: AntigravityTheme.minTouchTargetPt)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AntigravityTheme.surfaceCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(AntigravityTheme.cardBorder, lineWidth: 1)
        )
    }

    private func createInlineAutomation() {
        let trimmed = quickPromptText.trimmingCharacters(in: .whitespacesAndNewlines)
        if isLiveMode {
            if trimmed.isEmpty {
                editingAutomation = nil
                isShowingEditorSheet = true
                return
            }
            _ = store.createAutomationFromPrompt(trimmed)
            quickPromptText = ""
            return
        }
        let title = trimmed.isEmpty ? "Weekday morning summary" : trimmed
        let newCard = ScheduledAutomationCardModel(
            id: "auto-\(scheduledAutomations.count + 1)",
            title: title,
            subtitle: "ledger-svc · Weekdays at 09:00 · Flash",
            nextRunText: "Tomorrow, 09:00",
            lastRunText: "Scheduled · Ready",
            needsReview: false,
            cardAccessibilityId: "automation-card-custom-\(scheduledAutomations.count + 1)",
            playAccessibilityId: "btn-run-custom-\(scheduledAutomations.count + 1)"
        )
        scheduledAutomations.insert(newCard, at: 0)
        quickPromptText = ""
    }
}

// MARK: - PC-Style Minimal Create / Edit Automation Sheet

private struct AutomationEditorSheetView: View {
    @Bindable var store: AntigravitySessionStore
    let editingItem: AutomationItem?
    let onRequestSignIn: () -> Void
    let onDismiss: () -> Void

    private enum TriggerFrequency: String, CaseIterable, Identifiable {
        case daily = "Every day"
        case weekdays = "Weekdays"
        case weekly = "Every week"
        case hourly = "Every hour"

        var id: String { rawValue }
    }

    private struct TimeSlot: Hashable, Identifiable {
        let hour: Int
        let minute: Int

        var id: Int { hour * 60 + minute }

        var label: String {
            let period = hour < 12 ? "AM" : "PM"
            let displayHour = (hour % 12 == 0) ? 12 : (hour % 12)
            return String(format: "%d:%02d %@", displayHour, minute, period)
        }
    }

    private static let weekdayItems: [(Int, String)] = [
        (1, "Mon"), (2, "Tue"), (3, "Wed"), (4, "Thu"), (5, "Fri"), (6, "Sat"), (0, "Sun")
    ]

    private static let defaultProjectToken = "__default__"
    private static let allProjectsToken = "__all__"

    @State private var displayName: String
    @State private var promptText: String
    @State private var frequency: TriggerFrequency
    @State private var selectedHour: Int
    @State private var selectedMinute: Int
    @State private var selectedWeekday: Int
    @State private var selectedProjectToken: String
    @State private var selectedModelArg: String?
    @State private var selectedModelLabel: String
    @State private var isSubmitting: Bool = false
    @State private var submitError: String? = nil

    init(
        store: AntigravitySessionStore,
        editingItem: AutomationItem?,
        initialPromptSeed: String = "",
        onRequestSignIn: @escaping () -> Void = {},
        onDismiss: @escaping () -> Void
    ) {
        self.store = store
        self.editingItem = editingItem
        self.onRequestSignIn = onRequestSignIn
        self.onDismiss = onDismiss

        var initName = ""
        var initPrompt = ""
        var initFrequency: TriggerFrequency = .daily
        var initHour = 9
        var initMinute = 0
        var initWeekday = 1
        var initProjectToken = Self.defaultProjectToken
        var initModelArg: String? = nil
        var initModelLabel = store.selectedModelConfig.displayName

        if let item = editingItem {
            initName = item.title
            initPrompt = item.prompt.isEmpty ? item.title : item.prompt
            if let badge = item.modelLabel, !badge.isEmpty {
                initModelLabel = badge
            }
            if item.allProjects {
                initProjectToken = Self.allProjectsToken
            } else if !item.projectSlug.isEmpty
                && item.projectSlug != "This Computer"
                && item.projectSlug != "This computer"
                && item.projectSlug != "All projects" {
                initProjectToken = item.projectSlug
            }

            let (_, expr) = AutomationScheduleCodec.splitCronAndTimeZone(item.cronExpression)
            let parts = expr.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            if parts.count == 5 {
                let minF = parts[0], hourF = parts[1], dowF = parts[4]
                if hourF == "*", let m = Int(minF) {
                    initFrequency = .hourly
                    initMinute = m
                } else if let m = Int(minF), let h = Int(hourF) {
                    initMinute = m
                    initHour = h
                    if dowF == "1-5" {
                        initFrequency = .weekdays
                    } else if let wd = Int(dowF), (0...7).contains(wd) {
                        initFrequency = .weekly
                        initWeekday = wd == 7 ? 0 : wd
                    } else {
                        initFrequency = .daily
                    }
                }
            }
        } else {
            let trimmedSeed = initialPromptSeed.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedSeed.isEmpty {
                let parsed = AutomationScheduleCodec.parseNaturalLanguagePrompt(trimmedSeed)
                initName = parsed.displayName
                initPrompt = parsed.prompt
                let (_, expr) = AutomationScheduleCodec.splitCronAndTimeZone(parsed.cronExpression)
                let parts = expr.split(whereSeparator: { $0.isWhitespace }).map(String.init)
                if parts.count == 5 {
                    if parts[1] == "*", let m = Int(parts[0]) {
                        initFrequency = .hourly
                        initMinute = m
                    } else if let m = Int(parts[0]), let h = Int(parts[1]) {
                        initMinute = m
                        initHour = h
                        if parts[4] == "1-5" {
                            initFrequency = .weekdays
                        } else if let wd = Int(parts[4]), (0...7).contains(wd) {
                            initFrequency = .weekly
                            initWeekday = wd == 7 ? 0 : wd
                        } else {
                            initFrequency = .daily
                        }
                    }
                }
            }
        }

        _displayName = State(initialValue: initName)
        _promptText = State(initialValue: initPrompt)
        _frequency = State(initialValue: initFrequency)
        _selectedHour = State(initialValue: initHour)
        _selectedMinute = State(initialValue: initMinute)
        _selectedWeekday = State(initialValue: initWeekday)
        _selectedProjectToken = State(initialValue: initProjectToken)
        _selectedModelArg = State(initialValue: initModelArg)
        _selectedModelLabel = State(initialValue: initModelLabel)
    }

    private var localProjects: [ProjectWorkspace] {
        store.projects.filter { $0.runtime != .cloud && !$0.isNoProject }
    }

    private var targetDisplayLabel: String {
        if selectedProjectToken == Self.defaultProjectToken {
            return "This computer"
        }
        if selectedProjectToken == Self.allProjectsToken {
            return "All projects"
        }
        return selectedProjectToken
    }

    private var timeZoneShortLabel: String {
        let offsetSec = TimeZone.current.secondsFromGMT()
        let hours = offsetSec / 3600
        let mins = abs(offsetSec % 3600) / 60
        if mins == 0 {
            return hours >= 0 ? "GMT+\(hours)" : "GMT\(hours)"
        }
        return String(format: "GMT%+d:%02d", hours, mins)
    }

    private var timeSlots: [TimeSlot] {
        var set = Set<TimeSlot>()
        for h in 0..<24 {
            set.insert(TimeSlot(hour: h, minute: 0))
            set.insert(TimeSlot(hour: h, minute: 30))
        }
        set.insert(TimeSlot(hour: selectedHour, minute: selectedMinute))
        return set.sorted { $0.id < $1.id }
    }

    private var currentTimeLabel: String {
        if frequency == .hourly {
            return String(format: ":%02d", selectedMinute)
        }
        return TimeSlot(hour: selectedHour, minute: selectedMinute).label
    }

    private var computedCronExpression: String {
        let tzId = TimeZone.current.identifier
        switch frequency {
        case .hourly:
            return "CRON_TZ=\(tzId) \(selectedMinute) * * * *"
        case .daily:
            return "CRON_TZ=\(tzId) \(selectedMinute) \(selectedHour) * * *"
        case .weekdays:
            return "CRON_TZ=\(tzId) \(selectedMinute) \(selectedHour) * * 1-5"
        case .weekly:
            return "CRON_TZ=\(tzId) \(selectedMinute) \(selectedHour) * * \(selectedWeekday)"
        }
    }

    private var resolvedProjectParams: (slug: String, projectId: String?, allProjects: Bool) {
        if selectedProjectToken == Self.allProjectsToken {
            return ("All projects", nil, true)
        }
        if selectedProjectToken == Self.defaultProjectToken {
            return ("This Computer", nil, false)
        }
        let preservedId = (editingItem?.projectSlug == selectedProjectToken) ? editingItem?.projectId : nil
        return (selectedProjectToken, preservedId, false)
    }

    private var canSubmit: Bool {
        !isSubmitting && !promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                headerBar
                contextBar
                submitErrorBanner
                triggerSection
                instructionsSection
            }
            .padding(.horizontal, 18)
            .padding(.top, 20)
            .padding(.bottom, 28)
        }
        .background(AntigravityTheme.canvasObsidian.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    private var headerBar: some View {
        HStack(alignment: .center, spacing: 10) {
            TextField("Untitled", text: $displayName)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Color.white)
                .tint(AntigravityTheme.accentPeriwinkle)
                .lineLimit(1)

            Button {
                onDismiss()
            } label: {
                Text("Cancel")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AntigravityTheme.textBody)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 36)
                    .background(
                        Capsule()
                            .fill(Color(red: 0x24 / 255.0, green: 0x26 / 255.0, blue: 0x2E / 255.0))
                    )
            }
            .buttonStyle(.plain)

            Button {
                Task { await submit() }
            } label: {
                Group {
                    if isSubmitting {
                        ProgressView()
                            .tint(AntigravityTheme.inkOnPrimaryCTA)
                            .scaleEffect(0.8)
                    } else {
                        Text(editingItem == nil ? "Create" : "Save")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(canSubmit ? AntigravityTheme.inkOnPrimaryCTA : AntigravityTheme.textMuted)
                    }
                }
                .padding(.horizontal, 16)
                .frame(minWidth: 74, minHeight: 36)
                .background(
                    Capsule()
                        .fill(canSubmit ? AntigravityTheme.accentPeriwinkle : Color(red: 0x1D / 255.0, green: 0x2C / 255.0, blue: 0x45 / 255.0))
                )
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit)
        }
    }

    private var contextBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Menu {
                    Button("This computer") {
                        selectedProjectToken = Self.defaultProjectToken
                    }
                    Button("All projects") {
                        selectedProjectToken = Self.allProjectsToken
                    }
                    if !localProjects.isEmpty {
                        Divider()
                        ForEach(localProjects) { proj in
                            Button(proj.name) {
                                selectedProjectToken = proj.name
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(targetDisplayLabel)
                            .font(.system(size: 14.5, weight: .medium))
                            .foregroundStyle(AntigravityTheme.textBody)
                            .lineLimit(1)
                        if !localProjects.isEmpty {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(AntigravityTheme.textMuted)
                        }
                    }
                }

                Menu {
                    Button {
                        selectedModelArg = nil
                        selectedModelLabel = store.selectedModelConfig.displayName
                    } label: {
                        Text("\(store.selectedModelConfig.displayName) (Default)")
                    }
                    Divider()
                    if !store.availableModels.isEmpty {
                        ForEach(store.availableModels) { model in
                            Button {
                                selectedModelArg = model.modelId
                                selectedModelLabel = model.displayName
                            } label: {
                                Text(model.displayName)
                            }
                        }
                    } else {
                        Button("Gemini 3 Flash") {
                            selectedModelArg = "gemini-3-flash"
                            selectedModelLabel = "Gemini 3 Flash"
                        }
                        Button("Gemini 3 Flash Lite") {
                            selectedModelArg = "gemini-3-flash-lite"
                            selectedModelLabel = "Gemini 3 Flash Lite"
                        }
                        Button("Gemini 3.1 Pro") {
                            selectedModelArg = "gemini-3.1-pro"
                            selectedModelLabel = "Gemini 3.1 Pro"
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(selectedModelLabel)
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(AntigravityTheme.textPrimary)
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(AntigravityTheme.textMuted)
                    }
                    .padding(.horizontal, 11)
                    .frame(minHeight: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(AntigravityTheme.surfaceCard)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(AntigravityTheme.cardBorder, lineWidth: 1)
                    )
                }

                Spacer(minLength: 0)
            }

            Text("Uses your local files and tools. Schedules only.")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(AntigravityTheme.textMuted)
        }
    }

    @ViewBuilder
    private var submitErrorBanner: some View {
        if let err = submitError, !err.isEmpty {
            let authExpired = store.isAutomationsAuthExpired && store.activeHost.channel == .cloudRelay
            let color = authExpired ? AntigravityTheme.statusWaiting : AntigravityTheme.statusError
            HStack(spacing: 10) {
                Image(systemName: authExpired ? "person.crop.circle.badge.exclamationmark" : "exclamationmark.triangle.fill")
                    .foregroundStyle(color)
                Text(err)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AntigravityTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                if authExpired {
                    Button("重新登录") {
                        onRequestSignIn()
                    }
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(AntigravityTheme.inkOnPrimaryCTA)
                    .padding(.horizontal, 10)
                    .frame(minHeight: 28)
                    .background(Capsule().fill(AntigravityTheme.statusWaiting))
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(color.opacity(0.14))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(color.opacity(0.32), lineWidth: 1)
            )
        }
    }

    private var triggerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Trigger")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AntigravityTheme.textSecondary)

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 7) {
                    Image(systemName: "clock")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AntigravityTheme.textSecondary)
                    Text("Scheduled")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(AntigravityTheme.textPrimary)
                }

                HStack(spacing: 8) {
                    Menu {
                        ForEach(TriggerFrequency.allCases) { option in
                            Button {
                                frequency = option
                            } label: {
                                if frequency == option {
                                    Label(option.rawValue, systemImage: "checkmark")
                                } else {
                                    Text(option.rawValue)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(frequency.rawValue)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(AntigravityTheme.textPrimary)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(AntigravityTheme.textMuted)
                        }
                        .padding(.horizontal, 12)
                        .frame(minHeight: 36)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(AntigravityTheme.surfaceSubtleBox)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(AntigravityTheme.cardBorder, lineWidth: 1)
                        )
                    }

                    Text("at")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(AntigravityTheme.textSecondary)

                    Menu {
                        if frequency == .hourly {
                            ForEach(Array(Set([0, 15, 30, 45, selectedMinute])).sorted(), id: \.self) { m in
                                Button(String(format: ":%02d", m)) {
                                    selectedMinute = m
                                }
                            }
                        } else {
                            ForEach(timeSlots) { slot in
                                Button(slot.label) {
                                    selectedHour = slot.hour
                                    selectedMinute = slot.minute
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(currentTimeLabel)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(AntigravityTheme.textPrimary)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(AntigravityTheme.textMuted)
                        }
                        .padding(.horizontal, 12)
                        .frame(minHeight: 36)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(AntigravityTheme.surfaceSubtleBox)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(AntigravityTheme.cardBorder, lineWidth: 1)
                        )
                    }

                    Text(timeZoneShortLabel)
                        .font(.system(size: 13.5, weight: .regular))
                        .foregroundStyle(AntigravityTheme.textMuted)

                    Spacer(minLength: 0)
                }

                if frequency == .weekly {
                    HStack(spacing: 6) {
                        ForEach(Self.weekdayItems, id: \.0) { dayNum, label in
                            let active = (selectedWeekday == dayNum)
                            Button {
                                selectedWeekday = dayNum
                            } label: {
                                Text(label)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(active ? AntigravityTheme.inkOnPrimaryCTA : AntigravityTheme.textSecondary)
                                    .frame(maxWidth: .infinity, minHeight: 30)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(active ? AntigravityTheme.accentPeriwinkle : AntigravityTheme.surfaceSubtleBox)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AntigravityTheme.surfaceCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(AntigravityTheme.cardBorder, lineWidth: 1)
            )
        }
    }

    private var instructionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Instructions")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AntigravityTheme.textSecondary)

            ZStack(alignment: .topLeading) {
                if promptText.isEmpty {
                    Text("What should the agent do on each run? For example: summarize new bugs assigned to me and anything that changed overnight.")
                        .font(.system(size: 14.5, weight: .regular))
                        .foregroundStyle(AntigravityTheme.textMuted)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 13)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $promptText)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(AntigravityTheme.textPrimary)
                    .tint(AntigravityTheme.accentPeriwinkle)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 136, maxHeight: 220)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
            }
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AntigravityTheme.surfaceCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(AntigravityTheme.cardBorder, lineWidth: 1)
            )
        }
    }

    private func submit() async {
        guard canSubmit else { return }
        isSubmitting = true
        submitError = nil
        defer { isSubmitting = false }

        let trimmedPrompt = promptText.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawTitle = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveTitle: String = {
            if !rawTitle.isEmpty && rawTitle.caseInsensitiveCompare("Untitled") != .orderedSame {
                return rawTitle
            }
            let firstLine = trimmedPrompt.split(separator: "\n").first.map(String.init) ?? trimmedPrompt
            return String(firstLine.prefix(48))
        }()

        let target = resolvedProjectParams
        let humanSched = AutomationScheduleCodec.humanReadableSchedule(from: computedCronExpression)
        let desc = "\(humanSched): \(trimmedPrompt)"

        let success: Bool
        if let existing = editingItem {
            success = await store.updateAutomation(
                automationId: existing.id,
                displayName: effectiveTitle,
                prompt: trimmedPrompt,
                cronExpression: computedCronExpression,
                projectSlug: target.slug,
                projectId: target.projectId,
                allProjects: target.allProjects,
                modelArg: selectedModelArg,
                description: desc
            )
        } else {
            success = await store.createAutomation(
                displayName: effectiveTitle,
                prompt: trimmedPrompt,
                cronExpression: computedCronExpression,
                projectSlug: target.slug,
                projectId: target.projectId,
                allProjects: target.allProjects,
                modelArg: selectedModelArg,
                description: desc,
                enableImmediately: true
            )
        }
        if success {
            onDismiss()
        } else {
            submitError = store.automationsErrorText ?? "Failed to save automation."
        }
    }
}
