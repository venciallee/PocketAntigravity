import SwiftUI
import AntigravityData

/// State `UE06B_AUTOMATION_DETAIL`: Automation detail screen (`docs/ue/ios/ios-automation-detail.png`).
/// Shows status badge, Run Now / Pause actions, Prompt card, Schedule metadata card,
/// and Recent Runs history with inline Retry for failed executions.
public struct AutomationDetailView: View {
    @Bindable public var store: AntigravitySessionStore
    public var automationId: String?
    public var onBack: (() -> Void)?
    public var onEdit: ((String) -> Void)?

    @State private var isPresentingEditSheet: Bool = false

    public init(
        store: AntigravitySessionStore,
        automationId: String? = nil,
        onBack: (() -> Void)? = nil,
        onEdit: ((String) -> Void)? = nil
    ) {
        self.store = store
        self.automationId = automationId
        self.onBack = onBack
        self.onEdit = onEdit
    }

    private var item: AutomationItem {
        if let automationId,
           let match = store.automations.first(where: { $0.id == automationId }) {
            return match
        }
        if let selected = store.selectedAutomation {
            return selected
        }
        return AutomationItem(
            id: "auto-nightly-audit",
            title: "Nightly dependency audit",
            projectSlug: "ledger-svc",
            scheduleSummary: "ledger-svc · Daily at 02:00 · Flash",
            section: .scheduled,
            nextRunText: "Tonight, 2:00 AM (GMT+8:00)",
            lastRunText: "Succeeded · 22h ago",
            prompt: "Check go.mod for outdated or vulnerable modules. Open a PR for patch bumps only and summarize the rest.",
            modelLabel: "Flash",
            repeatsLabel: "Every day · 2:00 AM",
            timeLabel: "2:00 AM",
            timezoneLabel: "GMT+8:00",
            recentRuns: [
                AutomationRunRecord(
                    id: "run-1",
                    status: .succeeded,
                    relativeTimeLabel: "22h ago",
                    summaryText: "No vulnerable modules · 2 patch bumps",
                    cascadeId: "cas-rate-limiter"
                ),
                AutomationRunRecord(
                    id: "run-2",
                    status: .needsReview,
                    relativeTimeLabel: "2d ago",
                    summaryText: "PR for golang.org/x/net waiting",
                    cascadeId: "cas-flaky-settlement"
                ),
                AutomationRunRecord(
                    id: "run-3",
                    status: .failed,
                    relativeTimeLabel: "3d ago",
                    summaryText: "Google sign-in expired",
                    cascadeId: nil
                )
            ]
        )
    }

    private var isPaused: Bool {
        item.section == .paused || !item.isEnabled
    }

    private var triggerLabel: String {
        item.section == .alwaysOn ? "Always on" : "Schedule"
    }

    private var statusBadgeTitle: String {
        if isPaused {
            return "Paused"
        }
        return item.section == .alwaysOn ? "Always on · Active" : "Scheduled · Active"
    }

    private var displayNextRun: String {
        if item.nextRunText.contains("GMT") || item.nextRunText.contains("PDT") || item.nextRunText == "Paused" {
            return item.nextRunText
        }
        if item.nextRunText == "Tonight, 02:00" {
            return "Tonight, 2:00 AM (GMT+8:00)"
        }
        return "\(item.nextRunText) (\(item.timezoneLabel))"
    }

    private var displayRepeats: String {
        if item.repeatsLabel.contains("·") {
            return item.repeatsLabel
        }
        if item.repeatsLabel.caseInsensitiveCompare("Daily") == .orderedSame {
            return "Every day · 2:00 AM"
        }
        return "\(item.repeatsLabel) · \(item.timeLabel)"
    }

    private var displayedRecentRuns: [AutomationRunRecord] {
        if !item.recentRuns.isEmpty {
            return item.recentRuns
        }
        return [
            AutomationRunRecord(
                id: "run-1",
                status: .succeeded,
                relativeTimeLabel: "22h ago",
                summaryText: "No vulnerable modules · 2 patch bumps",
                cascadeId: item.lastRunCascadeId ?? "cas-rate-limiter"
            ),
            AutomationRunRecord(
                id: "run-2",
                status: .needsReview,
                relativeTimeLabel: "2d ago",
                summaryText: "PR for golang.org/x/net waiting",
                cascadeId: "cas-flaky-settlement"
            ),
            AutomationRunRecord(
                id: "run-3",
                status: .failed,
                relativeTimeLabel: "3d ago",
                summaryText: "Google sign-in expired",
                cascadeId: nil
            )
        ]
    }

    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                topNavBar
                headerSection
                actionButtonsRow
                promptCard
                scheduleMetadataCard
                recentRunsSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 28)
        }
        .background(AntigravityTheme.canvasObsidian.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("automation-detail-screen")
        .sheet(isPresented: $isPresentingEditSheet) {
            AutomationEditSheetView(
                store: store,
                automationId: item.id,
                onDismiss: {
                    isPresentingEditSheet = false
                },
                onDeleted: {
                    isPresentingEditSheet = false
                    if let onBack {
                        onBack()
                    } else {
                        store.activeRoute = .tabRoot
                    }
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    private var topNavBar: some View {
        HStack {
            Button {
                if let onBack {
                    onBack()
                } else {
                    store.selectedTab = .automations
                    store.activeRoute = .tabRoot
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Automations")
                        .font(.system(size: 17, weight: .regular))
                }
                .foregroundStyle(AntigravityTheme.accentPeriwinkle)
                .frame(minHeight: AntigravityTheme.minTouchTargetPt)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("btn-back-automations")

            Spacer()

            Button {
                if let onEdit {
                    onEdit(item.id)
                } else {
                    isPresentingEditSheet = true
                }
            } label: {
                Text("Edit")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AntigravityTheme.accentPeriwinkle)
                    .frame(minWidth: 44, minHeight: AntigravityTheme.minTouchTargetPt, alignment: .trailing)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("btn-edit-automation")
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(item.title)
                .font(.system(size: 29, weight: .bold))
                .tracking(-0.4)
                .foregroundStyle(AntigravityTheme.textPrimary)
                .accessibilityIdentifier("automation-detail-title")

            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(isPaused ? AntigravityTheme.textSecondary : AntigravityTheme.statusDone)
                        .frame(width: 7, height: 7)
                    Text(statusBadgeTitle)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(isPaused ? AntigravityTheme.textSecondary : AntigravityTheme.statusDone)
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(isPaused ? AntigravityTheme.surfaceElevated : AntigravityTheme.statusDone.opacity(0.14))
                )
                .accessibilityIdentifier("automation-detail-status-badge")

                Text("\(item.projectSlug) · \(item.modelLabel ?? "Flash")")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(AntigravityTheme.textSecondary)
                    .lineLimit(1)
            }
        }
    }

    private var actionButtonsRow: some View {
        HStack(spacing: 10) {
            Button {
                store.triggerAutomationNow(item.id)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 12, weight: .bold))
                    Text(item.isRunningNow ? "Running..." : "Run Now")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundStyle(AntigravityTheme.inkOnPrimaryCTA)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(Capsule().fill(AntigravityTheme.accentPeriwinkle))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("btn-automation-run-now")

            Button {
                if isPaused {
                    store.resumeAutomation(item.id)
                } else {
                    store.pauseAutomation(item.id)
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isPaused ? "play.fill" : "pause")
                        .font(.system(size: 12, weight: .bold))
                    Text(isPaused ? "Resume" : "Pause")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundStyle(AntigravityTheme.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(Capsule().fill(AntigravityTheme.surfacePopover))
                .overlay(
                    Capsule()
                        .strokeBorder(AntigravityTheme.cardBorder, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("btn-automation-pause-toggle")
        }
        .padding(.top, 2)
    }

    private var promptCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PROMPT")
                .font(.system(size: 11.5, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(AntigravityTheme.textMuted)

            Text(item.prompt)
                .font(.system(size: 15.5, weight: .regular))
                .foregroundStyle(AntigravityTheme.textPrimary)
                .lineSpacing(3.5)
                .fixedSize(horizontal: false, vertical: true)
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
        .accessibilityIdentifier("automation-detail-prompt-card")
    }

    private var scheduleMetadataCard: some View {
        VStack(spacing: 0) {
            metadataRow(label: "Trigger", value: triggerLabel)
            Divider()
                .overlay(AntigravityTheme.subtleDivider)
                .padding(.horizontal, 16)
            metadataRow(label: "Repeats", value: displayRepeats)
            Divider()
                .overlay(AntigravityTheme.subtleDivider)
                .padding(.horizontal, 16)
            metadataRow(label: "Next run", value: displayNextRun)
        }
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AntigravityTheme.surfaceCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(AntigravityTheme.cardBorder, lineWidth: 1)
        )
        .accessibilityIdentifier("automation-detail-schedule-card")
    }

    private func metadataRow(label: String, value: String) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 15.5, weight: .regular))
                .foregroundStyle(AntigravityTheme.textPrimary)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 15.5, weight: .regular))
                .foregroundStyle(AntigravityTheme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 48)
    }

    private var recentRunsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("RECENT RUNS")
                    .font(.system(size: 11.5, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(AntigravityTheme.textMuted)
                Spacer()
                Text("Each run opens a new conversation")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(AntigravityTheme.textMuted)
            }
            .padding(.horizontal, 2)
            .padding(.top, 2)

            VStack(spacing: 0) {
                ForEach(Array(displayedRecentRuns.enumerated()), id: \.element.id) { idx, run in
                    recentRunRow(run)
                    if idx < displayedRecentRuns.count - 1 {
                        Divider()
                            .overlay(AntigravityTheme.subtleDivider)
                            .padding(.leading, 46)
                    }
                }
            }
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

    @ViewBuilder
    private func recentRunRow(_ run: AutomationRunRecord) -> some View {
        let titleColor: Color = {
            switch run.status {
            case .succeeded: return AntigravityTheme.textPrimary
            case .needsReview: return AntigravityTheme.statusWaiting
            case .failed: return AntigravityTheme.statusError
            case .running: return AntigravityTheme.accentPeriwinkle
            }
        }()

        HStack(spacing: 12) {
            Group {
                switch run.status {
                case .succeeded:
                    Image(systemName: "checkmark")
                        .font(.system(size: 13.5, weight: .bold))
                        .foregroundStyle(AntigravityTheme.statusDone)
                case .needsReview:
                    Circle()
                        .fill(AntigravityTheme.statusWaiting)
                        .frame(width: 9, height: 9)
                case .failed:
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(AntigravityTheme.statusError)
                case .running:
                    ProgressView()
                        .controlSize(.mini)
                        .tint(AntigravityTheme.accentPeriwinkle)
                }
            }
            .frame(width: 22)

            VStack(alignment: .leading, spacing: 2.5) {
                Text("\(run.status.rawValue) · \(run.relativeTimeLabel)")
                    .font(.system(size: 15.5, weight: .medium))
                    .foregroundStyle(titleColor)
                Text(run.summaryText)
                    .font(.system(size: 13.5, weight: .regular))
                    .foregroundStyle(AntigravityTheme.textSecondary)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if let cid = run.cascadeId, !cid.isEmpty {
                    store.selectCascade(cid)
                }
            }

            Spacer(minLength: 8)

            if run.status == .failed {
                Button {
                    store.retryAutomationRun(automationId: item.id, runId: run.id)
                } label: {
                    Text("Retry")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AntigravityTheme.textPrimary)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 34)
                        .background(Capsule().fill(AntigravityTheme.surfacePopover))
                        .overlay(
                            Capsule()
                                .strokeBorder(AntigravityTheme.glassHairline, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("btn-retry-run-\(run.id)")
            } else {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(AntigravityTheme.textMuted)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("automation-run-row-\(run.id)")
    }
}

/// State `UE06C_AUTOMATION_EDIT`: Edit Schedule & Prompt bottom sheet (`docs/ue/ios/ios-automation-edit.png`).
public struct AutomationEditSheetView: View {
    @Bindable public var store: AntigravitySessionStore
    public var automationId: String?
    public var onDismiss: (() -> Void)?
    public var onDeleted: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    private let repeatOptions = ["Every hour", "Every day", "Weekdays", "Every week"]
    private let modelOptions = ["Flash Lite", "Flash", "Pro"]

    @State private var nameText: String
    @State private var promptText: String
    @State private var selectedProjectSlug: String
    @State private var isAlwaysOn: Bool
    @State private var selectedRepeat: String
    @State private var selectedTimeLabel: String
    @State private var selectedModel: String
    @State private var isShowingDeleteConfirm: Bool = false

    public init(
        store: AntigravitySessionStore,
        automationId: String? = nil,
        onDismiss: (() -> Void)? = nil,
        onDeleted: (() -> Void)? = nil
    ) {
        self.store = store
        self.automationId = automationId
        self.onDismiss = onDismiss
        self.onDeleted = onDeleted

        let target = (automationId.flatMap { id in store.automations.first(where: { $0.id == id }) })
            ?? store.selectedAutomation
        let initialName = target?.title ?? "Nightly dependency audit"
        let initialPrompt = target?.prompt
            ?? "Check go.mod for outdated or vulnerable modules. Open a PR for patch bumps only and summarize the rest."
        let initialProject = target?.projectSlug ?? "ledger-svc"
        let initialAlwaysOn = (target?.section == .alwaysOn)
        let initialRepeat: String = {
            let raw = target?.repeatsLabel.lowercased() ?? "every day"
            if raw.contains("hour") { return "Every hour" }
            if raw.contains("weekday") { return "Weekdays" }
            if raw.contains("week") { return "Every week" }
            return "Every day"
        }()
        let initialTime = target?.timeLabel.isEmpty == false ? (target?.timeLabel ?? "2:00 AM") : "2:00 AM"
        let normalizedTime = initialTime == "02:00" ? "2:00 AM" : initialTime
        let initialModel = target?.modelLabel ?? "Flash"

        self._nameText = State(initialValue: initialName)
        self._promptText = State(initialValue: initialPrompt)
        self._selectedProjectSlug = State(initialValue: initialProject)
        self._isAlwaysOn = State(initialValue: initialAlwaysOn)
        self._selectedRepeat = State(initialValue: initialRepeat)
        self._selectedTimeLabel = State(initialValue: normalizedTime)
        self._selectedModel = State(initialValue: ["Flash Lite", "Flash", "Pro"].contains(initialModel) ? initialModel : "Flash")
    }

    private var targetAutomationId: String {
        automationId ?? store.selectedAutomationId
    }

    private var selectableProjects: [String] {
        let names = store.projects.map(\.name).filter { !$0.isEmpty }
        if names.isEmpty {
            return ["ledger-svc", "acme/web-console"]
        }
        return names.contains(selectedProjectSlug) ? names : ([selectedProjectSlug] + names)
    }

    private var cronForSelection: String {
        switch selectedRepeat {
        case "Every hour": return "0 * * * *"
        case "Weekdays": return "0 2 * * 1-5"
        case "Every week": return "0 9 * * 1"
        default: return "0 2 * * *"
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Sheet Grabber
            Capsule()
                .fill(AntigravityTheme.inkMuted.opacity(0.6))
                .frame(width: 38, height: 4.5)
                .padding(.top, 10)
                .padding(.bottom, 8)

            // Header: Cancel | Edit Schedule & Prompt | Save
            HStack {
                Button {
                    closeSheet()
                } label: {
                    Text("Cancel")
                        .font(.system(size: 16.5, weight: .regular))
                        .foregroundStyle(AntigravityTheme.textBody)
                        .frame(minWidth: 64, minHeight: AntigravityTheme.minTouchTargetPt, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("btn-cancel-automation-edit")

                Spacer()

                Text("Edit Schedule & Prompt")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AntigravityTheme.textPrimary)

                Spacer()

                Button {
                    saveChanges()
                } label: {
                    Text("Save")
                        .font(.system(size: 16.5, weight: .semibold))
                        .foregroundStyle(AntigravityTheme.accentPeriwinkle)
                        .frame(minWidth: 64, minHeight: AntigravityTheme.minTouchTargetPt, alignment: .trailing)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("btn-save-automation-edit")
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 10)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    // Name & Prompt Card
                    VStack(spacing: 0) {
                        HStack(alignment: .center, spacing: 14) {
                            Text("Name")
                                .font(.system(size: 14.5, weight: .regular))
                                .foregroundStyle(AntigravityTheme.textSecondary)
                                .frame(width: 60, alignment: .leading)
                            TextField("Automation name", text: $nameText)
                                .font(.system(size: 15.5, weight: .regular))
                                .foregroundStyle(AntigravityTheme.textPrimary)
                                .accessibilityIdentifier("field-automation-name")
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 13)

                        Divider()
                            .overlay(AntigravityTheme.subtleDivider)
                            .padding(.horizontal, 14)

                        HStack(alignment: .top, spacing: 14) {
                            Text("Prompt")
                                .font(.system(size: 14.5, weight: .regular))
                                .foregroundStyle(AntigravityTheme.textSecondary)
                                .frame(width: 60, alignment: .leading)
                                .padding(.top, 2)
                            TextField("What should this automation do?", text: $promptText, axis: .vertical)
                                .lineLimit(3...6)
                                .font(.system(size: 15.5, weight: .regular))
                                .foregroundStyle(AntigravityTheme.textPrimary)
                                .lineSpacing(3)
                                .accessibilityIdentifier("field-automation-prompt")
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 13)
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(AntigravityTheme.surfaceElevated)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(AntigravityTheme.cardBorder, lineWidth: 1)
                    )

                    // Project & Trigger Card
                    VStack(spacing: 0) {
                        HStack {
                            Text("Project")
                                .font(.system(size: 15.5, weight: .regular))
                                .foregroundStyle(AntigravityTheme.textPrimary)
                            Spacer()
                            Menu {
                                ForEach(selectableProjects, id: \.self) { slug in
                                    Button {
                                        selectedProjectSlug = slug
                                    } label: {
                                        if slug == selectedProjectSlug {
                                            Label(slug, systemImage: "checkmark")
                                        } else {
                                            Text(slug)
                                        }
                                    }
                                }
                            } label: {
                                HStack(spacing: 5) {
                                    Text(selectedProjectSlug)
                                        .font(.system(size: 15.5, weight: .regular))
                                        .foregroundStyle(AntigravityTheme.textSecondary)
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(AntigravityTheme.textSecondary)
                                }
                            }
                            .accessibilityIdentifier("picker-automation-project")
                        }
                        .padding(.horizontal, 14)
                        .frame(minHeight: 48)

                        Divider()
                            .overlay(AntigravityTheme.subtleDivider)
                            .padding(.horizontal, 14)

                        HStack {
                            Text("Trigger")
                                .font(.system(size: 15.5, weight: .regular))
                                .foregroundStyle(AntigravityTheme.textPrimary)
                            Spacer()
                            HStack(spacing: 2) {
                                triggerSegmentButton(title: "Schedule", selected: !isAlwaysOn, testId: "segment-trigger-schedule") {
                                    isAlwaysOn = false
                                }
                                triggerSegmentButton(title: "Always on", selected: isAlwaysOn, testId: "segment-trigger-always-on") {
                                    isAlwaysOn = true
                                }
                            }
                            .padding(3)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(AntigravityTheme.surfaceCard)
                            )
                        }
                        .padding(.horizontal, 14)
                        .frame(minHeight: 52)
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(AntigravityTheme.surfaceElevated)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(AntigravityTheme.cardBorder, lineWidth: 1)
                    )

                    // REPEATS Pills
                    VStack(alignment: .leading, spacing: 8) {
                        Text("REPEATS")
                            .font(.system(size: 11.5, weight: .semibold))
                            .tracking(0.8)
                            .foregroundStyle(AntigravityTheme.textMuted)
                            .padding(.leading, 2)

                        HStack(spacing: 6) {
                            ForEach(repeatOptions, id: \.self) { opt in
                                let isSelected = (selectedRepeat == opt)
                                Button {
                                    selectedRepeat = opt
                                } label: {
                                    Text(opt)
                                        .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                                        .foregroundStyle(isSelected ? AntigravityTheme.textPrimary : AntigravityTheme.textSecondary)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.82)
                                        .frame(maxWidth: .infinity, minHeight: 40)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .fill(isSelected ? AntigravityTheme.surfaceSelectionTint : AntigravityTheme.surfaceElevated)
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .strokeBorder(
                                                    isSelected ? AntigravityTheme.accentPeriwinkle : AntigravityTheme.cardBorder,
                                                    lineWidth: isSelected ? 1.2 : 1
                                                )
                                        )
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("repeat-pill-\(opt.lowercased().replacingOccurrences(of: " ", with: "-"))")
                            }
                        }

                        // Time Row
                        HStack {
                            Text("Time")
                                .font(.system(size: 15.5, weight: .regular))
                                .foregroundStyle(AntigravityTheme.textPrimary)
                            Spacer()
                            Menu {
                                ForEach(["2:00 AM", "3:00 AM", "8:00 AM", "9:00 AM", "6:00 PM"], id: \.self) { t in
                                    Button(t) { selectedTimeLabel = t }
                                }
                            } label: {
                                Text(selectedTimeLabel)
                                    .font(.system(size: 14.5, weight: .medium))
                                    .foregroundStyle(AntigravityTheme.textPrimary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                                            .fill(AntigravityTheme.surfacePopover)
                                    )
                            }
                            .accessibilityIdentifier("picker-automation-time")

                            Text("GMT+8:00")
                                .font(.system(size: 13.5, weight: .regular))
                                .foregroundStyle(AntigravityTheme.textSecondary)
                        }
                        .padding(.horizontal, 14)
                        .frame(minHeight: 50)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(AntigravityTheme.surfaceElevated)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(AntigravityTheme.cardBorder, lineWidth: 1)
                        )
                    }

                    // MODEL 3-Segment Picker
                    VStack(alignment: .leading, spacing: 8) {
                        Text("MODEL")
                            .font(.system(size: 11.5, weight: .semibold))
                            .tracking(0.8)
                            .foregroundStyle(AntigravityTheme.textMuted)
                            .padding(.leading, 2)

                        HStack(spacing: 3) {
                            ForEach(modelOptions, id: \.self) { model in
                                let isSelected = (selectedModel == model)
                                Button {
                                    selectedModel = model
                                } label: {
                                    Text(model)
                                        .font(.system(size: 14.5, weight: isSelected ? .semibold : .regular))
                                        .foregroundStyle(isSelected ? AntigravityTheme.textPrimary : AntigravityTheme.textSecondary)
                                        .frame(maxWidth: .infinity, minHeight: 38)
                                        .background(
                                            Group {
                                                if isSelected {
                                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                        .fill(AntigravityTheme.surfaceActiveTabSlot)
                                                }
                                            }
                                        )
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("model-segment-\(model.lowercased().replacingOccurrences(of: " ", with: "-"))")
                            }
                        }
                        .padding(4)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(AntigravityTheme.surfaceElevated)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(AntigravityTheme.cardBorder, lineWidth: 1)
                        )
                    }

                    // Unattended Policy Footnote
                    Text("Runs unattended: anything that needs approval is denied automatically and the run shows up as Needs review.")
                        .font(.system(size: 13.5, weight: .regular))
                        .foregroundStyle(AntigravityTheme.textSecondary)
                        .lineSpacing(3)
                        .padding(.top, 2)

                    // Delete Automation CTA
                    Button {
                        isShowingDeleteConfirm = true
                    } label: {
                        Text("Delete Automation")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(AntigravityTheme.statusError)
                            .frame(maxWidth: .infinity, minHeight: AntigravityTheme.minTouchTargetPt)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)
                    .accessibilityIdentifier("btn-delete-automation")
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
        }
        .background(AntigravityTheme.surfaceSheet.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("automation-edit-sheet")
        .alert("Delete Automation?", isPresented: $isShowingDeleteConfirm) {
            Button("Delete", role: .destructive) {
                store.deleteAutomation(targetAutomationId)
                if let onDeleted {
                    onDeleted()
                } else {
                    closeSheet()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes \"\(nameText)\". Existing run conversations remain intact.")
        }
    }

    private func triggerSegmentButton(
        title: String,
        selected: Bool,
        testId: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13.5, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? AntigravityTheme.textPrimary : AntigravityTheme.textSecondary)
                .padding(.horizontal, 14)
                .frame(minHeight: 34)
                .background(
                    Group {
                        if selected {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(AntigravityTheme.surfaceActiveTabSlot)
                        }
                    }
                )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(testId)
    }

    private func saveChanges() {
        let id = targetAutomationId
        let repeatsCombined = "\(selectedRepeat) · \(selectedTimeLabel)"
        Task {
            _ = await store.updateAutomation(
                automationId: id,
                displayName: nameText,
                prompt: promptText,
                cronExpression: cronForSelection,
                projectSlug: selectedProjectSlug,
                modelArg: selectedModel
            )
            if let idx = store.automations.firstIndex(where: { $0.id == id }) {
                store.automations[idx].repeatsLabel = repeatsCombined
                store.automations[idx].timeLabel = selectedTimeLabel
                store.automations[idx].section = isAlwaysOn ? .alwaysOn : .scheduled
                store.automations[idx].isScheduleBuiltin = !isAlwaysOn
            }
            closeSheet()
        }
    }

    private func closeSheet() {
        store.presentedSheet = nil
        if let onDismiss {
            onDismiss()
        } else {
            dismiss()
        }
    }
}
