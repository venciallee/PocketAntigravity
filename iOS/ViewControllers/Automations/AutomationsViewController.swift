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
                onDismiss: {
                    isShowingEditorSheet = false
                    editingAutomation = nil
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
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
                        store.createAutomationWithAgent(prompt: quickPromptText)
                    } label: {
                        Label("Create with /automation", systemImage: "sparkles")
                    }
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "line.3.horizontal.decrease")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(sectionFilter == .all ? UEChromePalette.textPrimary : AntigravityTheme.accentPeriwinkle)
                            .frame(width: AntigravityTheme.minTouchTargetPt, height: AntigravityTheme.minTouchTargetPt)
                            .background(Circle().fill(UEChromePalette.surfacePill))
                            .overlay(Circle().strokeBorder(UEChromePalette.cardBorder, lineWidth: 1))
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
                        .foregroundStyle(UEChromePalette.textPrimary)
                        .frame(width: AntigravityTheme.minTouchTargetPt, height: AntigravityTheme.minTouchTargetPt)
                        .background(Circle().fill(UEChromePalette.surfacePill))
                        .overlay(Circle().strokeBorder(UEChromePalette.cardBorder, lineWidth: 1))
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
                    .foregroundStyle(UEChromePalette.textSecondary)

                TextField("Every weekday at 9, summarize", text: $quickPromptText)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(UEChromePalette.textPrimary)
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
                .foregroundStyle(UEChromePalette.textMuted)
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
                                .foregroundStyle(UEChromePalette.textSecondary)
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
                                .foregroundStyle(UEChromePalette.textMuted)
                            Text(item.nextRunText)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(UEChromePalette.textPrimary)
                        }
                        .padding(.horizontal, 11)
                        .padding(.vertical, 9)
                        .frame(maxWidth: .infinity, minHeight: 50, alignment: .topLeading)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(UEChromePalette.surfaceSubtleBox)
                        )

                        // LAST RUN Stat Box
                        VStack(alignment: .leading, spacing: 3) {
                            Text("LAST RUN")
                                .font(.system(size: 10.5, weight: .semibold))
                                .tracking(0.5)
                                .foregroundStyle(
                                    item.needsReview ? AntigravityTheme.statusWaiting : UEChromePalette.textMuted
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
                                        item.needsReview ? AntigravityTheme.statusWaiting : UEChromePalette.textPrimary
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
                                        : UEChromePalette.surfaceSubtleBox
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
                        .strokeBorder(UEChromePalette.cardBorder, lineWidth: 1)
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
                .foregroundStyle(UEChromePalette.textMuted)
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
                        .foregroundStyle(UEChromePalette.textSecondary)
                    Text("Last run 14m ago")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(UEChromePalette.textBody)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(UEChromePalette.textMuted)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(AntigravityTheme.surfaceCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(UEChromePalette.cardBorder, lineWidth: 1)
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
                .foregroundStyle(UEChromePalette.textMuted)
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
                        .foregroundStyle(UEChromePalette.textMuted)
                }

                Spacer()

                Button {
                    isPausedResumed.toggle()
                } label: {
                    Text(isPausedResumed ? "Active" : "Resume")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(UEChromePalette.textPrimary)
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
                    .strokeBorder(UEChromePalette.cardBorder, lineWidth: 1)
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
                        .foregroundStyle(UEChromePalette.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 36)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(AntigravityTheme.surfaceCard)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(UEChromePalette.cardBorder, lineWidth: 1)
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
                        .foregroundStyle(UEChromePalette.textSecondary)
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
                        .strokeBorder(UEChromePalette.cardBorder, lineWidth: 1)
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
                            Text("No Automations Yet")
                                .font(.system(size: 16.5, weight: .semibold))
                                .foregroundStyle(Color.white)
                            Text("Running on \(store.activeHost.hostname)")
                                .font(.system(size: 12.5, weight: .regular))
                                .foregroundStyle(UEChromePalette.textMuted)
                        }
                    }

                    Text("Create a recurring schedule directly, type a natural-language schedule above, or let Antigravity build one interactively with /automation.")
                        .font(.system(size: 13.5, weight: .regular))
                        .foregroundStyle(UEChromePalette.textSecondary)
                        .lineSpacing(2)

                    HStack(spacing: 10) {
                        Button {
                            editingAutomation = nil
                            isShowingEditorSheet = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "plus")
                                    .font(.system(size: 13, weight: .bold))
                                Text("New Automation")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .foregroundStyle(AntigravityTheme.inkOnPrimaryCTA)
                            .frame(maxWidth: .infinity, minHeight: AntigravityTheme.minTouchTargetPt)
                            .background(
                                Capsule().fill(AntigravityTheme.accentPeriwinkle)
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("btn-empty-new-automation")

                        Button {
                            store.createAutomationWithAgent(prompt: quickPromptText)
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 12.5, weight: .semibold))
                                Text("/automation")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .foregroundStyle(UEChromePalette.textPrimary)
                            .padding(.horizontal, 14)
                            .frame(minHeight: AntigravityTheme.minTouchTargetPt)
                            .background(
                                Capsule().fill(UEChromePalette.surfaceSheetGroup)
                            )
                            .overlay(
                                Capsule().strokeBorder(UEChromePalette.cardBorder, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("btn-empty-agent-automation")
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
                        .strokeBorder(UEChromePalette.cardBorder, lineWidth: 1)
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
                        .foregroundStyle(UEChromePalette.textSecondary)
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
                        .strokeBorder(UEChromePalette.cardBorder, lineWidth: 1)
                )
            }

            if showScheduled {
                VStack(alignment: .leading, spacing: 8) {
                    Text("SCHEDULED · \(store.scheduledAutomations.count)")
                        .font(.system(size: 11.5, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(UEChromePalette.textMuted)
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
                        .foregroundStyle(UEChromePalette.textMuted)
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
                        .foregroundStyle(UEChromePalette.textMuted)
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
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AntigravityTheme.statusError)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(message)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(UEChromePalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    Task { await store.refreshAutomations() }
                } label: {
                    Text("Retry")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(AntigravityTheme.accentPeriwinkle)
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 4)

            Button {
                store.automationsErrorText = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(UEChromePalette.textMuted)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AntigravityTheme.statusError.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(AntigravityTheme.statusError.opacity(0.32), lineWidth: 1)
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
                        .foregroundStyle(UEChromePalette.textSecondary)
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
                        .foregroundStyle(UEChromePalette.textSecondary)
                        .frame(width: 34, height: AntigravityTheme.minTouchTargetPt)
                }
            }

            HStack(spacing: 9) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("NEXT RUN")
                        .font(.system(size: 10.5, weight: .semibold))
                        .tracking(0.5)
                        .foregroundStyle(UEChromePalette.textMuted)
                    Text(item.nextRunText)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(UEChromePalette.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, minHeight: 50, alignment: .topLeading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(UEChromePalette.surfaceSubtleBox)
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
                .strokeBorder(UEChromePalette.cardBorder, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func liveLastRunBox(_ item: AutomationItem) -> some View {
        let boxContent = VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text("LAST RUN")
                    .font(.system(size: 10.5, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(item.needsReview ? AntigravityTheme.statusWaiting : UEChromePalette.textMuted)
                Spacer(minLength: 2)
                if let cid = item.lastRunCascadeId, !cid.isEmpty {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(UEChromePalette.textMuted)
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
                    .foregroundStyle(item.needsReview ? AntigravityTheme.statusWaiting : UEChromePalette.textPrimary)
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
                        : UEChromePalette.surfaceSubtleBox
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
                    .foregroundStyle(UEChromePalette.textSecondary)
                    .lineLimit(1)
                Text(item.lastRunText)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(item.needsReview ? AntigravityTheme.statusWaiting : UEChromePalette.textBody)
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
                    .foregroundStyle(UEChromePalette.textSecondary)
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
                .strokeBorder(UEChromePalette.cardBorder, lineWidth: 1)
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
                    .foregroundStyle(UEChromePalette.textMuted)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)

            Button {
                store.resumeAutomation(item.id)
            } label: {
                Text("Resume")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(UEChromePalette.textPrimary)
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
                    .foregroundStyle(UEChromePalette.textMuted)
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
                .strokeBorder(UEChromePalette.cardBorder, lineWidth: 1)
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

// MARK: - Structured Create / Edit Automation Sheet

private struct AutomationEditorSheetView: View {
    @Bindable var store: AntigravitySessionStore
    let editingItem: AutomationItem?
    let onDismiss: () -> Void

    private enum SchedulePreset: String, CaseIterable, Identifiable {
        case hourly = "Hourly"
        case daily = "Daily"
        case weekdays = "Weekdays"
        case weekly = "Weekly"
        case custom = "Custom"

        var id: String { rawValue }
    }

    private enum ModelOption: String, CaseIterable, Identifiable {
        case defaultModel = "Default"
        case flash = "Flash"
        case flashLite = "Flash Lite"
        case pro = "Pro"

        var id: String { rawValue }

        var modelArg: String? {
            switch self {
            case .defaultModel: return nil
            case .flash: return "gemini-3-flash"
            case .flashLite: return "gemini-3-flash-lite"
            case .pro: return "gemini-3.1-pro"
            }
        }

        static func fromBadge(_ badge: String?) -> ModelOption {
            guard let b = badge?.lowercased() else { return .defaultModel }
            if b.contains("lite") { return .flashLite }
            if b.contains("pro") { return .pro }
            if b.contains("flash") { return .flash }
            return .defaultModel
        }
    }

    private static let weekdayItems: [(Int, String)] = [
        (1, "Mon"), (2, "Tue"), (3, "Wed"), (4, "Thu"), (5, "Fri"), (6, "Sat"), (0, "Sun")
    ]

    private static let defaultProjectToken = "__default__"
    private static let allProjectsToken = "__all__"

    @State private var displayName: String
    @State private var promptText: String
    @State private var preset: SchedulePreset
    @State private var selectedHour: Int
    @State private var selectedMinute: Int
    @State private var selectedWeekday: Int
    @State private var customCronText: String
    @State private var selectedProjectToken: String
    @State private var selectedModel: ModelOption
    @State private var enableImmediately: Bool
    @State private var isSubmitting: Bool = false

    init(
        store: AntigravitySessionStore,
        editingItem: AutomationItem?,
        initialPromptSeed: String = "",
        onDismiss: @escaping () -> Void
    ) {
        self.store = store
        self.editingItem = editingItem
        self.onDismiss = onDismiss

        var initName = ""
        var initPrompt = ""
        var initPreset: SchedulePreset = .weekdays
        var initHour = 9
        var initMinute = 0
        var initWeekday = 1
        var initCustomCron = "0 9 * * 1-5"
        var initProjectToken = Self.defaultProjectToken
        var initModel: ModelOption = .defaultModel
        var initEnable = true

        if let item = editingItem {
            initName = item.title
            initPrompt = item.prompt.isEmpty ? item.title : item.prompt
            initModel = ModelOption.fromBadge(item.modelLabel)
            initEnable = item.isEnabled
            if item.allProjects {
                initProjectToken = Self.allProjectsToken
            } else if !item.projectSlug.isEmpty
                && item.projectSlug != "This Computer"
                && item.projectSlug != "All projects" {
                initProjectToken = item.projectSlug
            }

            let (_, expr) = AutomationScheduleCodec.splitCronAndTimeZone(item.cronExpression)
            if !expr.isEmpty {
                initCustomCron = expr
                let parts = expr.split(whereSeparator: { $0.isWhitespace }).map(String.init)
                if parts.count == 5 {
                    let minF = parts[0], hourF = parts[1], domF = parts[2], monF = parts[3], dowF = parts[4]
                    if hourF == "*", domF == "*", monF == "*", dowF == "*", let m = Int(minF) {
                        initPreset = .hourly
                        initMinute = m
                    } else if let m = Int(minF), let h = Int(hourF), domF == "*", monF == "*" {
                        initMinute = m
                        initHour = h
                        if dowF == "*" {
                            initPreset = .daily
                        } else if dowF == "1-5" {
                            initPreset = .weekdays
                        } else if let wd = Int(dowF), (0...7).contains(wd) {
                            initPreset = .weekly
                            initWeekday = wd == 7 ? 0 : wd
                        } else {
                            initPreset = .custom
                        }
                    } else {
                        initPreset = .custom
                    }
                } else {
                    initPreset = .custom
                }
            }
        } else {
            let trimmedSeed = initialPromptSeed.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedSeed.isEmpty {
                let parsed = AutomationScheduleCodec.parseNaturalLanguagePrompt(trimmedSeed)
                initName = parsed.displayName
                initPrompt = parsed.prompt
                let (_, expr) = AutomationScheduleCodec.splitCronAndTimeZone(parsed.cronExpression)
                initCustomCron = expr
                let parts = expr.split(whereSeparator: { $0.isWhitespace }).map(String.init)
                if parts.count == 5 {
                    if parts[1] == "*", let m = Int(parts[0]) {
                        initPreset = .hourly
                        initMinute = m
                    } else if let m = Int(parts[0]), let h = Int(parts[1]) {
                        initMinute = m
                        initHour = h
                        if parts[4] == "*" {
                            initPreset = .daily
                        } else if parts[4] == "1-5" {
                            initPreset = .weekdays
                        } else if let wd = Int(parts[4]), (0...7).contains(wd) {
                            initPreset = .weekly
                            initWeekday = wd == 7 ? 0 : wd
                        } else {
                            initPreset = .custom
                        }
                    }
                }
            }
            if let selected = store.selectedProject, selected.runtime != .cloud, !selected.isNoProject {
                initProjectToken = selected.name
            }
        }

        _displayName = State(initialValue: initName)
        _promptText = State(initialValue: initPrompt)
        _preset = State(initialValue: initPreset)
        _selectedHour = State(initialValue: initHour)
        _selectedMinute = State(initialValue: initMinute)
        _selectedWeekday = State(initialValue: initWeekday)
        _customCronText = State(initialValue: initCustomCron)
        _selectedProjectToken = State(initialValue: initProjectToken)
        _selectedModel = State(initialValue: initModel)
        _enableImmediately = State(initialValue: initEnable)
    }

    private var localProjects: [ProjectWorkspace] {
        store.projects.filter { $0.runtime != .cloud && !$0.isNoProject }
    }

    private var computedCronExpression: String {
        let tzId = TimeZone.current.identifier
        switch preset {
        case .hourly:
            return "CRON_TZ=\(tzId) \(selectedMinute) * * * *"
        case .daily:
            return "CRON_TZ=\(tzId) \(selectedMinute) \(selectedHour) * * *"
        case .weekdays:
            return "CRON_TZ=\(tzId) \(selectedMinute) \(selectedHour) * * 1-5"
        case .weekly:
            return "CRON_TZ=\(tzId) \(selectedMinute) \(selectedHour) * * \(selectedWeekday)"
        case .custom:
            let trimmed = customCronText.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("CRON_TZ=") || trimmed.hasPrefix("TZ=") || trimmed.isEmpty {
                return trimmed
            }
            return "CRON_TZ=\(tzId) \(trimmed)"
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
        !isSubmitting
            && !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !computedCronExpression.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    errorSection
                    nameSection
                    promptSection
                    scheduleSection
                    projectScopeSection
                    modelSection
                    enableToggleSection
                    submitSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 28)
            }
            .background(UEChromePalette.surfaceSheet.ignoresSafeArea())
            .navigationTitle(editingItem == nil ? "New Automation" : "Edit Automation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onDismiss()
                    }
                    .foregroundStyle(UEChromePalette.textSecondary)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var errorSection: some View {
        if let err = store.automationsErrorText, !err.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(AntigravityTheme.statusError)
                Text(err)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(UEChromePalette.textPrimary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AntigravityTheme.statusError.opacity(0.14))
            )
        }
    }

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("NAME")
            TextField("e.g. Nightly dependency audit", text: $displayName)
                .font(.system(size: 15.5, weight: .regular))
                .foregroundStyle(UEChromePalette.textPrimary)
                .tint(AntigravityTheme.accentPeriwinkle)
                .padding(.horizontal, 14)
                .frame(minHeight: 46)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(UEChromePalette.surfaceSheetGroup)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(UEChromePalette.cardBorder, lineWidth: 1)
                )
        }
    }

    private var promptSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("AGENT PROMPT")
            ZStack(alignment: .topLeading) {
                if promptText.isEmpty {
                    Text("Describe what the agent should inspect, run, or report each time this automation fires...")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(UEChromePalette.textMuted)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $promptText)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(UEChromePalette.textPrimary)
                    .tint(AntigravityTheme.accentPeriwinkle)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 96, maxHeight: 150)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
            }
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(UEChromePalette.surfaceSheetGroup)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(UEChromePalette.cardBorder, lineWidth: 1)
            )
        }
    }

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("SCHEDULE")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(SchedulePreset.allCases) { option in
                        let isSelected = (preset == option)
                        Button {
                            preset = option
                        } label: {
                            Text(option.rawValue)
                                .font(.system(size: 13.5, weight: .semibold))
                                .foregroundStyle(isSelected ? AntigravityTheme.inkOnPrimaryCTA : UEChromePalette.textBody)
                                .padding(.horizontal, 14)
                                .frame(minHeight: 36)
                                .background(
                                    Capsule()
                                        .fill(isSelected ? AntigravityTheme.accentPeriwinkle : UEChromePalette.surfaceSheetGroup)
                                )
                                .overlay(
                                    Capsule()
                                        .strokeBorder(isSelected ? Color.clear : UEChromePalette.cardBorder, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                scheduleControls
                Divider().overlay(UEChromePalette.subtleDivider)
                schedulePreviewRow
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(UEChromePalette.surfaceSheetGroup)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(UEChromePalette.cardBorder, lineWidth: 1)
            )
        }
    }

    @ViewBuilder
    private var scheduleControls: some View {
        if preset == .weekly {
            HStack(spacing: 6) {
                ForEach(Self.weekdayItems, id: \.0) { dayNum, label in
                    let active = (selectedWeekday == dayNum)
                    Button {
                        selectedWeekday = dayNum
                    } label: {
                        Text(label)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(active ? AntigravityTheme.inkOnPrimaryCTA : UEChromePalette.textSecondary)
                            .frame(maxWidth: .infinity, minHeight: 34)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(active ? AntigravityTheme.accentPeriwinkle : UEChromePalette.surfaceSubtleBox)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }

        if preset == .custom {
            TextField("0 9 * * 1-5", text: $customCronText)
                .font(.system(size: 14.5, weight: .medium, design: .monospaced))
                .foregroundStyle(UEChromePalette.textPrimary)
                .tint(AntigravityTheme.accentPeriwinkle)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.horizontal, 12)
                .frame(minHeight: 42)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(UEChromePalette.surfaceSubtleBox)
                )
        } else {
            HStack(spacing: 12) {
                if preset != .hourly {
                    HStack(spacing: 6) {
                        Text("Hour")
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(UEChromePalette.textSecondary)
                        Picker("Hour", selection: $selectedHour) {
                            ForEach(0..<24, id: \.self) { h in
                                Text(String(format: "%02d", h)).tag(h)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(AntigravityTheme.accentPeriwinkle)
                    }
                }

                HStack(spacing: 6) {
                    Text("Minute")
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(UEChromePalette.textSecondary)
                    Picker("Minute", selection: $selectedMinute) {
                        ForEach(Array(Set([0, 5, 10, 15, 20, 30, 45, selectedMinute])).sorted(), id: \.self) { m in
                            Text(String(format: ":%02d", m)).tag(m)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(AntigravityTheme.accentPeriwinkle)
                }

                Spacer()
            }
        }
    }

    private var schedulePreviewRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(AutomationScheduleCodec.humanReadableSchedule(from: computedCronExpression))
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(UEChromePalette.textPrimary)
                Text(computedCronExpression)
                    .font(.system(size: 11.5, weight: .regular, design: .monospaced))
                    .foregroundStyle(UEChromePalette.textMuted)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("NEXT RUN")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(UEChromePalette.textMuted)
                Text(AutomationScheduleCodec.nextFireDescription(from: computedCronExpression))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AntigravityTheme.accentPeriwinkle)
            }
        }
    }

    private var projectScopeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("PROJECT SCOPE")
            HStack {
                Text("Target")
                    .font(.system(size: 14.5, weight: .medium))
                    .foregroundStyle(UEChromePalette.textPrimary)
                Spacer()
                Picker("Target Project", selection: $selectedProjectToken) {
                    Text("This Computer (Default)").tag(Self.defaultProjectToken)
                    Text("All projects").tag(Self.allProjectsToken)
                    ForEach(localProjects) { proj in
                        Text(proj.name).tag(proj.name)
                    }
                    if selectedProjectToken != Self.defaultProjectToken
                        && selectedProjectToken != Self.allProjectsToken
                        && !localProjects.contains(where: { $0.name == selectedProjectToken }) {
                        Text(selectedProjectToken).tag(selectedProjectToken)
                    }
                }
                .pickerStyle(.menu)
                .tint(AntigravityTheme.accentPeriwinkle)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 46)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(UEChromePalette.surfaceSheetGroup)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(UEChromePalette.cardBorder, lineWidth: 1)
            )

            Text("Scheduled Automations run locally on \(store.activeHost.hostname).")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(UEChromePalette.textMuted)
                .padding(.leading, 4)
        }
    }

    private var modelSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("MODEL")
            HStack(spacing: 8) {
                ForEach(ModelOption.allCases) { option in
                    let active = (selectedModel == option)
                    Button {
                        selectedModel = option
                    } label: {
                        Text(option.rawValue)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(active ? AntigravityTheme.inkOnPrimaryCTA : UEChromePalette.textBody)
                            .frame(maxWidth: .infinity, minHeight: 38)
                            .background(
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .fill(active ? AntigravityTheme.accentPeriwinkle : UEChromePalette.surfaceSheetGroup)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .strokeBorder(active ? Color.clear : UEChromePalette.cardBorder, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var enableToggleSection: some View {
        if editingItem == nil {
            Toggle(isOn: $enableImmediately) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Enable immediately")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(UEChromePalette.textPrimary)
                    Text("Start scheduling on \(store.activeHost.hostname) as soon as created")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(UEChromePalette.textMuted)
                }
            }
            .tint(AntigravityTheme.accentPeriwinkle)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(UEChromePalette.surfaceSheetGroup)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(UEChromePalette.cardBorder, lineWidth: 1)
            )
        }
    }

    @ViewBuilder
    private var submitSection: some View {
        Button {
            Task { await submit() }
        } label: {
            HStack(spacing: 8) {
                if isSubmitting {
                    ProgressView()
                        .tint(AntigravityTheme.inkOnPrimaryCTA)
                }
                Text(editingItem == nil ? "Create Automation" : "Save Changes")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AntigravityTheme.inkOnPrimaryCTA)
            }
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(
                Capsule()
                    .fill(canSubmit ? AntigravityTheme.accentPeriwinkle : AntigravityTheme.accentPeriwinkle.opacity(0.35))
            )
        }
        .buttonStyle(.plain)
        .disabled(!canSubmit)
        .padding(.top, 4)

        if editingItem == nil {
            Button {
                let targetSlug = (selectedProjectToken == Self.defaultProjectToken || selectedProjectToken == Self.allProjectsToken)
                    ? nil
                    : selectedProjectToken
                let seed = promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                    : promptText.trimmingCharacters(in: .whitespacesAndNewlines)
                onDismiss()
                store.createAutomationWithAgent(prompt: seed, projectSlug: targetSlug)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 13.5, weight: .semibold))
                    Text("Or build interactively with /automation")
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundStyle(AntigravityTheme.accentPeriwinkle)
                .frame(maxWidth: .infinity, minHeight: 40)
            }
            .buttonStyle(.plain)
        }
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11.5, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(UEChromePalette.textMuted)
            .padding(.leading, 4)
    }

    private func submit() async {
        guard canSubmit else { return }
        isSubmitting = true
        defer { isSubmitting = false }

        let target = resolvedProjectParams
        let humanSched = AutomationScheduleCodec.humanReadableSchedule(from: computedCronExpression)
        let desc = "\(humanSched): \(promptText.trimmingCharacters(in: .whitespacesAndNewlines))"

        let success: Bool
        if let existing = editingItem {
            success = await store.updateAutomation(
                automationId: existing.id,
                displayName: displayName,
                prompt: promptText,
                cronExpression: computedCronExpression,
                projectSlug: target.slug,
                projectId: target.projectId,
                allProjects: target.allProjects,
                modelArg: selectedModel.modelArg,
                description: desc
            )
        } else {
            success = await store.createAutomation(
                displayName: displayName,
                prompt: promptText,
                cronExpression: computedCronExpression,
                projectSlug: target.slug,
                projectId: target.projectId,
                allProjects: target.allProjects,
                modelArg: selectedModel.modelArg,
                description: desc,
                enableImmediately: enableImmediately
            )
        }
        if success {
            onDismiss()
        }
    }
}
