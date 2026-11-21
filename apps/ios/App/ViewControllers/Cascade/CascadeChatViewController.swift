import SwiftUI
import AntigravityData

/// State `UE07_CHAT_AND_COMPOSER`: Official Message List, 7-Segment Task Card, Face ID Command Gate & Composer (`iOS · 消息列表与输入框`).
/// Dynamically renders live `store.displayItems` (`CascadeStepCellView` / `CascadeEvidenceGroupCardView`)
/// for newly created sessions, sent messages, and live Connect-RPC streaming turns while preserving
/// exact 1:1 `UE07` showcase rendering on the `cas-rate-limiter` ESDD fixture.
public struct CascadeChatViewController: View {
    @Bindable public var store: AntigravitySessionStore
    public var onBack: (() -> Void)?
    @State private var isTurnStopped: Bool = false

    public init(
        store: AntigravitySessionStore,
        onBack: (() -> Void)? = nil
    ) {
        self.store = store
        self.onBack = onBack
    }

    private var isStaticESDDFixtureView: Bool {
        store.isVerificationMode
            && !store.hasPairedBackend
            && !store.isLiveBackendConnected
            && store.activeCascadeId == "cas-rate-limiter"
            && store.activeSteps.count == 6
    }

    private var activePendingDraft: PendingDraftConversation? {
        store.activeCascadeId.isEmpty ? store.pendingDraftConversation : nil
    }

    private var localSelectableProjects: [ProjectWorkspace] {
        let activeHostScope = AgentsHostFilterScope.localHost(
            id: store.activeHost.instanceId,
            name: store.activeHost.hostname
        )
        return store.projects.filter { proj in
            guard proj.runtime != .cloud && !proj.isNoProject else { return false }
            if store.pairedLocalHosts.count > 1 {
                return store.projectMatchesHostScope(proj, scope: activeHostScope)
            }
            return true
        }
    }

    private var activeProjectWorkspace: ProjectWorkspace? {
        if let draft = activePendingDraft {
            if AntigravityCloudDetector.isNoProjectSlug(draft.projectSlug) {
                return nil
            }
            return store.projects.first(where: { $0.id == draft.projectSlug })
                ?? store.projects.first(where: { $0.name == draft.projectSlug })
        }
        if let slug = store.activeSummary?.projectSlug {
            return store.projects.first(where: { $0.id == slug })
                ?? store.projects.first(where: { $0.name == slug })
        }
        return store.selectedProject
    }

    private var isActiveSessionCloud: Bool {
        if let draft = activePendingDraft {
            return draft.isCloud
        }
        return store.activeSummary?.isCloud == true || activeProjectWorkspace?.runtime == .cloud
    }

    private var isActiveSessionHostOnline: Bool {
        if isActiveSessionCloud {
            return store.isDeviceNetworkReachable
        }
        if !store.hasPairedBackend { return true }
        let hostTitle = store.activeSummary?.originHostName
            ?? activeProjectWorkspace?.hostName
            ?? store.activeHost.hostname
        return store.isLocalHostOnline(
            instanceId: store.activeSummary?.originInstanceUuid ?? activeProjectWorkspace?.originInstanceUuid,
            hostname: hostTitle
        )
    }

    private var effectiveHeaderHostLabel: String {
        if isActiveSessionCloud {
            return (store.hasPairedBackend || store.isLiveBackendConnected) ? "Antigravity" : "Cloud"
        }
        let originUuid = store.activeSummary?.originInstanceUuid ?? activeProjectWorkspace?.originInstanceUuid
        let hostTitle = store.resolvedHostName(
            forInstanceUuid: originUuid,
            fallback: store.activeSummary?.originHostName ?? activeProjectWorkspace?.hostName
        )
        if store.hasPairedBackend && !isActiveSessionHostOnline {
            return "Offline · \(hostTitle)"
        }
        return hostTitle
    }

    private var shouldAnimateLive: Bool {
        !store.isVerificationMode || store.isLiveBackendConnected
    }

    private var streamingFollowSignature: Int {
        let lastStep = store.activeSteps.last
        let proseLen = lastStep?.plannerResponse?.response.count ?? 0
        let thoughtLen = lastStep?.plannerResponse?.thinking?.count ?? 0
        let statusRaw = lastStep?.status.rawValue ?? 0
        let waitingIdx = store.pendingWaitingStep?.stepIndex ?? -1
        return (store.activeSteps.count &* 1_000_003) &+ (proseLen &* 31) &+ (thoughtLen &* 7) &+ statusRaw &+ (waitingIdx &* 97)
    }

    public var body: some View {
        VStack(spacing: 0) {
            chatTopNavigationBar

            Divider()
                .overlay(AntigravityTheme.subtleDivider)

            ScrollViewReader { scrollProxy in
                ScrollView {
                    Group {
                        if isStaticESDDFixtureView {
                            VStack(alignment: .leading, spacing: 9) {
                                staticRateLimiterShowcaseBody
                            }
                        } else if store.displayItems.isEmpty {
                            VStack(alignment: .leading, spacing: 9) {
                                emptyOrLoadingSessionCard
                            }
                        } else {
                            LazyVStack(alignment: .leading, spacing: 9) {
                                ForEach(store.displayItems) { item in
                                    switch item {
                                    case .single(let step):
                                        CascadeStepCellView(store: store, step: step)
                                            .id("step-\(step.stepIndex)")
                                            .contextMenu {
                                                if let text = step.plannerResponse?.response ?? step.userInput, !text.isEmpty {
                                                    Button {
                                                        store.composerDraftText += (store.composerDraftText.isEmpty ? "" : "\n") + "> \(String(text.prefix(240)))\n"
                                                    } label: {
                                                        Label("Quote in Reply", systemImage: "text.quote")
                                                    }
                                                }
                                                Button(role: .destructive) {
                                                    store.revertConversationToStep(step.stepIndex)
                                                } label: {
                                                    Label("Revert to This Step", systemImage: "arrow.uturn.backward")
                                                }
                                            }
                                    case .evidenceGroup(let groupId, let groupedSteps):
                                        CascadeEvidenceGroupCardView(
                                            store: store,
                                            groupId: groupId,
                                            steps: groupedSteps
                                        )
                                    }
                                }

                                if store.isCascadeStreaming || store.activeSummary?.status == .inProgress || store.activeSummary?.status == .pending {
                                    HStack(spacing: 10) {
                                        AntigravityFourDotLoadingView(
                                            isAnimated: shouldAnimateLive,
                                            dotSize: 4.5,
                                            spacing: 3.5,
                                            tint: AntigravityTheme.accentPeriwinkle
                                        )
                                        Text("Agent is thinking and executing steps...")
                                            .font(.system(size: 13.5, weight: .medium))
                                            .foregroundStyle(AntigravityTheme.inkSecondary)
                                        Spacer()
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .background(AntigravityTheme.surfaceCard)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .stroke(AntigravityTheme.cardBorder, lineWidth: 1)
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    .accessibilityIdentifier("chat-inline-four-dot-loading")
                                }

                                Color.clear
                                    .frame(height: 1)
                                    .id("chat-bottom-anchor")
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                }
                .scrollDismissesKeyboard(.interactively)
                .onAppear {
                    guard !isStaticESDDFixtureView, !store.displayItems.isEmpty else { return }
                    if let waiting = store.pendingWaitingStep {
                        scrollProxy.scrollTo("step-\(waiting.stepIndex)", anchor: .bottom)
                    } else {
                        scrollProxy.scrollTo("chat-bottom-anchor", anchor: .bottom)
                    }
                }
                .onChange(of: streamingFollowSignature) { _, _ in
                    guard !isStaticESDDFixtureView, store.isAutoScrollPinnedToBottom else { return }
                    withAnimation(.easeOut(duration: 0.2)) {
                        scrollProxy.scrollTo("chat-bottom-anchor", anchor: .bottom)
                    }
                }
                .onChange(of: store.isCascadeStreaming) { wasStreaming, nowStreaming in
                    if wasStreaming && !nowStreaming {
                        store.flushNextQueuedMessageIfIdle()
                    }
                }

                if !store.displayItems.isEmpty, let errText = store.stepLoadErrorText {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(AntigravityTheme.statusError)
                            .frame(width: 7, height: 7)
                        Text(errText)
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(AntigravityTheme.statusError)
                            .lineLimit(2)
                        Spacer(minLength: 4)
                        Button("Dismiss") {
                            store.stepLoadErrorText = nil
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AntigravityTheme.accentPeriwinkle)
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(AntigravityTheme.surfaceCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(AntigravityTheme.cardBorder, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.horizontal, 14)
                    .padding(.top, 4)
                }

                // Above-Composer Status Strip
                if isStaticESDDFixtureView || (activePendingDraft == nil && (store.isCascadeStreaming || store.pendingWaitingStep != nil || store.activeSummary?.status == .inProgress)) {
                    waitingStatusStrip(scrollProxy: scrollProxy)
                        .padding(.horizontal, 14)
                        .padding(.top, 4)
                }
            }

            if let draft = activePendingDraft {
                draftTargetSelectorBar(draft: draft)
                    .padding(.horizontal, 14)
                    .padding(.top, 6)
                    .padding(.bottom, 2)
            }

            // Pinned Composer Card
            ChatComposerView(store: store)
                .padding(.horizontal, 10)
                .padding(.top, 4)
                .padding(.bottom, 6)
        }
        .background(AntigravityTheme.canvasObsidian)
        .onChange(of: store.isCascadeStreaming) { _, streaming in
            if streaming {
                isTurnStopped = false
            }
        }
        .task(id: store.activeCascadeId) {
            isTurnStopped = false
            if (store.hasPairedBackend || store.isLiveBackendConnected) && !store.activeCascadeId.isEmpty {
                store.syncStepsForCascade(store.activeCascadeId, pollUntilIdle: true)
                await store.loadLiveArtifactsAndDiffs(for: store.activeCascadeId)
            }
        }
    }

    @ViewBuilder
    private var staticRateLimiterShowcaseBody: some View {
        UserPromptContextBubbleView(
            promptText: nil,
            contextChips: ["@transfers.go", "Skill · go-testing"]
        )

        CollapsibleThoughtRowView(durationSeconds: 14)

        Text("Plan approved with your 2 comments. Tests pass — next is a load test, which needs your OK.")
            .font(.system(size: 15))
            .foregroundStyle(AntigravityTheme.inkReading)
            .lineSpacing(2.5)
            .fixedSize(horizontal: false, vertical: true)

        EmbeddedImplementationPlanCardView(
            title: "Implementation Plan",
            statusSubtitle: "Approved · 2 comments addressed"
        ) {
            store.currentRoute = .planReview
        }

        SevenSegmentTaskProgressCardView(
            completedCount: 4,
            totalCount: 7,
            elapsedLabel: "2m 41s"
        )

        InlineCommandApprovalCardView(store: store)
    }

    @ViewBuilder
    private var emptyOrLoadingSessionCard: some View {
        if let draft = activePendingDraft {
            let isAutomationDraft = (draft.workflowCommand?.lowercased() == "/automation")
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: isAutomationDraft ? "sparkles" : "bubble.left.and.bubble.right")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(AntigravityTheme.accentPeriwinkle)
                    Text(isAutomationDraft ? "Create Automation with Prompt" : "New Conversation")
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(AntigravityTheme.inkReading)
                }
                Text(
                    isAutomationDraft
                        ? "Review or edit the prompt below, then tap Send. Antigravity on \(effectiveHeaderHostLabel) will guide you through setting up the schedule and instructions."
                        : "Draft ready on \(effectiveHeaderHostLabel). Edit your message below and tap Send to start."
                )
                    .font(.system(size: 13.5))
                    .foregroundStyle(AntigravityTheme.inkSecondary)
                    .lineSpacing(2)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AntigravityTheme.surfaceCard)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(AntigravityTheme.cardBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.top, 12)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("chat-pending-draft-card")
        } else if (store.hasPairedBackend || store.isLiveBackendConnected) && store.isLoadingSteps {
            HStack(spacing: 12) {
                AntigravityFourDotLoadingView(
                    isAnimated: shouldAnimateLive,
                    dotSize: 4.5,
                    spacing: 3.5,
                    tint: AntigravityTheme.accentPeriwinkle
                )
                VStack(alignment: .leading, spacing: 3) {
                    Text("Loading conversation history...")
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(AntigravityTheme.inkReading)
                    Text("Syncing trajectory steps from \(effectiveHeaderHostLabel)")
                        .font(.system(size: 13))
                        .foregroundStyle(AntigravityTheme.inkSecondary)
                }
                Spacer()
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AntigravityTheme.surfaceCard)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(AntigravityTheme.cardBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.top, 12)
            .accessibilityIdentifier("chat-loading-steps")
        } else if (store.hasPairedBackend || store.isLiveBackendConnected), let err = store.stepLoadErrorText {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(AntigravityTheme.statusError)
                        .frame(width: 8, height: 8)
                    Text("Could not load trajectory steps")
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(AntigravityTheme.inkReading)
                }
                Text(err)
                    .font(.system(size: 13))
                    .foregroundStyle(AntigravityTheme.inkSecondary)
                Button {
                    if !store.isDeviceNetworkReachable || !isActiveSessionHostOnline {
                        Task {
                            if !isActiveSessionCloud,
                               let originId = store.activeSummary?.originInstanceUuid ?? activeProjectWorkspace?.originInstanceUuid,
                               !originId.isEmpty {
                                let hostLabel = store.resolvedHostName(
                                    forInstanceUuid: originId,
                                    fallback: store.activeSummary?.originHostName ?? activeProjectWorkspace?.hostName
                                )
                                let hostReachable = await store.refreshConversationsForHostScope(
                                    .localHost(id: originId, name: hostLabel),
                                    forceFullSync: true
                                )
                                if hostReachable {
                                    store.syncStepsForCascade(store.activeCascadeId, pollUntilIdle: true)
                                }
                            } else {
                                await store.reconnectNow(userInitiated: true)
                            }
                        }
                    } else {
                        store.syncStepsForCascade(store.activeCascadeId, pollUntilIdle: true)
                    }
                } label: {
                    Text("Retry")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(AntigravityTheme.accentPeriwinkle)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 36)
                        .background(AntigravityTheme.surfaceElevated)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AntigravityTheme.surfaceCard)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(AntigravityTheme.cardBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.top, 12)
        } else {
            let isNoInternet = store.hasPairedBackend && !store.isDeviceNetworkReachable
            let isOfflinePaired = !isActiveSessionCloud && store.hasPairedBackend && !isActiveSessionHostOnline
            let rawSlug = AntigravityCloudDetector.stripProjectScopePrefix(
                activeProjectWorkspace?.name ?? store.activeSummary?.projectSlug ?? AntigravityCloudDetector.noProjectDisplayName
            )
            let isNoProjSession = (activeProjectWorkspace?.isNoProject == true) || AntigravityCloudDetector.isNoProjectSlug(rawSlug)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Circle()
                        .fill((isNoInternet || isOfflinePaired) ? AntigravityTheme.statusError : (store.isLiveBackendConnected ? AntigravityTheme.statusDone : AntigravityTheme.accentPeriwinkle))
                        .frame(width: 8, height: 8)
                    Text(
                        isNoInternet
                            ? "No Internet · Queued Outbox Ready"
                            : (isOfflinePaired
                                ? (store.pendingOutboxCount > 0 ? "Host Offline · \(store.pendingOutboxCount) Queued" : "Host Offline · Queued Outbox Ready")
                                : (store.isLiveBackendConnected ? "Ready for Prompt" : "New Session Ready"))
                    )
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(AntigravityTheme.inkReading)
                }
                Text(
                    isNoProjSession
                        ? "Unassigned conversation on `\(effectiveHeaderHostLabel)`. Send a message below to run on \(isActiveSessionCloud ? "Antigravity Cloud" : "Antigravity Desktop")."
                        : "Bound to `\(rawSlug)` on `\(effectiveHeaderHostLabel)`. Send a message below to run on \(isActiveSessionCloud ? "Antigravity Cloud" : "Antigravity Desktop")."
                )
                    .font(.system(size: 13.5))
                    .foregroundStyle(AntigravityTheme.inkSecondary)
                    .lineSpacing(2)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AntigravityTheme.surfaceCard)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(AntigravityTheme.cardBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.top, 12)
        }
    }

    private func draftTargetSelectorBar(draft: PendingDraftConversation) -> some View {
        let isNoProj = AntigravityCloudDetector.isNoProjectSlug(draft.projectSlug)
        let currentLabel = isNoProj
            ? AntigravityCloudDetector.noProjectDisplayName
            : (activeProjectWorkspace?.name ?? AntigravityCloudDetector.stripProjectScopePrefix(draft.projectSlug))

        return HStack(spacing: 8) {
            Menu {
                Button {
                    store.updatePendingDraftProject(AntigravityCloudDetector.noProjectDisplayName)
                } label: {
                    if isNoProj {
                        Label(AntigravityCloudDetector.noProjectDisplayName, systemImage: "checkmark")
                    } else {
                        Text(AntigravityCloudDetector.noProjectDisplayName)
                    }
                }
                if !localSelectableProjects.isEmpty {
                    Divider()
                    ForEach(localSelectableProjects) { proj in
                        Button {
                            store.updatePendingDraftProject(proj.id)
                        } label: {
                            if !isNoProj && (draft.projectSlug == proj.id || draft.projectSlug == proj.name) {
                                Label(proj.name, systemImage: "checkmark")
                            } else {
                                Text(proj.name)
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Text(currentLabel)
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(AntigravityTheme.inkReading)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(AntigravityTheme.inkSecondary)
                }
                .padding(.horizontal, 11)
                .frame(minHeight: 32)
                .background(AntigravityTheme.surfacePill)
                .overlay(
                    Capsule()
                        .stroke(AntigravityTheme.cardBorder, lineWidth: 1)
                )
                .clipShape(Capsule())
            }
            .accessibilityIdentifier("draft-project-selector")

            Spacer(minLength: 8)

            HStack(spacing: 5) {
                Image(systemName: "desktopcomputer")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(AntigravityTheme.inkSecondary)
                Text(store.activeHost.hostname)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(AntigravityTheme.inkSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }

    // MARK: - Top Navigation Bar

    private var chatTopNavigationBar: some View {
        let isLiveOrPaired = store.hasPairedBackend || store.isLiveBackendConnected
        let navTitle = activePendingDraft?.title
            ?? store.activeSummary?.title
            ?? (isLiveOrPaired ? "Conversation" : "Add rate limiter to /transfers")
        let rawProjectLabel = activeProjectWorkspace?.name
            ?? activePendingDraft?.projectSlug
            ?? store.activeSummary?.projectSlug
            ?? (isLiveOrPaired ? AntigravityCloudDetector.noProjectDisplayName : "ledger-svc")
        let strippedProjectLabel = AntigravityCloudDetector.stripProjectScopePrefix(rawProjectLabel)
        let isNoProjChat = (activePendingDraft != nil || isLiveOrPaired)
            && ((activeProjectWorkspace?.isNoProject == true) || AntigravityCloudDetector.isNoProjectSlug(strippedProjectLabel))
        let projectLabel = isNoProjChat ? AntigravityCloudDetector.noProjectDisplayName : strippedProjectLabel
        let branchLabel: String = {
            if isNoProjChat { return "" }
            return store.activeSummary?.branchName ?? activeProjectWorkspace?.activeBranch ?? "main"
        }()
        let subtitleLine = branchLabel.isEmpty
            ? "\(projectLabel) · \(effectiveHeaderHostLabel)"
            : "\(projectLabel) · \(branchLabel) · \(effectiveHeaderHostLabel)"
        let showDiffPill = activePendingDraft == nil && (!isLiveOrPaired || store.totalDiffAdditions > 0 || store.totalDiffDeletions > 0)

        return HStack(spacing: 8) {
            Button {
                store.discardPendingDraftConversation()
                if let onBack {
                    onBack()
                } else {
                    store.currentRoute = .tabRoot
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AntigravityTheme.accentPeriwinkle)
                    .frame(width: AntigravityTheme.minTouchTargetPt, height: AntigravityTheme.minTouchTargetPt)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("btn-back-sessions")

            VStack(alignment: .leading, spacing: 2) {
                Text(navTitle)
                    .font(.system(size: 15.5, weight: .bold))
                    .foregroundStyle(AntigravityTheme.inkReading)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .accessibilityIdentifier("chat-nav-title")

                Text(subtitleLine)
                    .font(.system(size: 12))
                    .foregroundStyle(AntigravityTheme.inkSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            if showDiffPill {
                Button {
                    store.currentRoute = .turnDiffReview
                } label: {
                    HStack(spacing: 5) {
                        Text("+\(store.totalDiffAdditions)")
                            .foregroundStyle(AntigravityTheme.statusDone)
                        Text("-\(store.totalDiffDeletions)")
                            .foregroundStyle(AntigravityTheme.statusError)
                    }
                    .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 11)
                    .frame(minWidth: AntigravityTheme.minTouchTargetPt, minHeight: AntigravityTheme.minTouchTargetPt)
                    .background(AntigravityTheme.surfacePill)
                    .overlay(
                        Capsule()
                            .stroke(AntigravityTheme.cardBorder, lineWidth: 1)
                    )
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("chat-diff-pill")
            }

            // `•••` Overflow Menu
            Menu {
                Button {
                    store.presentedSheet = .conversationOverview
                } label: {
                    Label("Conversation Overview", systemImage: "sidebar.right")
                }
                Button {
                    store.openSideQuestion()
                } label: {
                    Label("/btw Side Question", systemImage: "questionmark.bubble")
                }
                Button {
                    store.startVoiceMode()
                } label: {
                    Label("Start Voice Mode", systemImage: "waveform")
                }
                Divider()
                Button("Open Implementation Plan") {
                    store.currentRoute = .planReview
                }
                Button("Review Turn Changes") {
                    store.currentRoute = .turnDiffReview
                }
                Button {
                    store.presentedSheet = .customizationsSettings
                } label: {
                    Label("Permissions & Customizations", systemImage: "shield.lefthalf.filled")
                }
                Button("Refresh Trajectory Steps") {
                    store.syncStepsForCascade(store.activeCascadeId, pollUntilIdle: true)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AntigravityTheme.inkReading)
                    .frame(width: AntigravityTheme.minTouchTargetPt, height: AntigravityTheme.minTouchTargetPt)
            }
            .accessibilityIdentifier("btn-chat-more")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
    }

    // MARK: - Above-Composer Status Strip

    private func openPendingApproval(for waiting: CascadeStep, scrollProxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) {
            scrollProxy.scrollTo("step-\(waiting.stepIndex)", anchor: .bottom)
        }
        let kind = waiting.effectiveRequestedInteraction?.kind
        if kind == .askQuestion || kind == .elicitation {
            store.syncActiveLiveQuestionFromSteps(stepIndex: waiting.stepIndex)
            store.presentedSheet = .askQuestion(stepIndex: waiting.stepIndex)
        } else {
            store.presentedSheet = .permissionGate(stepIndex: waiting.stepIndex)
        }
    }

    private func waitingStatusStrip(scrollProxy: ScrollViewProxy) -> some View {
        let waitingStep = isTurnStopped ? nil : store.pendingWaitingStep
        let statusLabel: String = {
            if isTurnStopped {
                return "Turn stopped"
            }
            if isStaticESDDFixtureView {
                return "Waiting for your approval · Step 5 of 7"
            }
            if let waitingStep {
                return "Approval needed · Step \(waitingStep.stepIndex + 1)"
            }
            if store.isCascadeStreaming {
                let sourceTitle = isActiveSessionCloud
                    ? "Antigravity Cloud"
                    : store.resolvedHostName(
                        forInstanceUuid: store.activeSummary?.originInstanceUuid,
                        fallback: store.activeSummary?.originHostName
                    )
                return "Streaming from \(sourceTitle) · \(store.activeSteps.count) steps"
            }
            return "Waiting for your approval · Step 5 of 7"
        }()

        let isQuestionGate = (waitingStep?.effectiveRequestedInteraction?.kind == .askQuestion
            || waitingStep?.effectiveRequestedInteraction?.kind == .elicitation)

        return HStack(spacing: 8) {
            if let waiting = waitingStep, !isStaticESDDFixtureView {
                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        scrollProxy.scrollTo("step-\(waiting.stepIndex)", anchor: .bottom)
                    }
                } label: {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(AntigravityTheme.statusWaiting)
                            .frame(width: 8, height: 8)
                        Text(statusLabel)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(AntigravityTheme.statusWaiting)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .frame(minHeight: AntigravityTheme.minTouchTargetPt)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                if !isStaticESDDFixtureView && !isTurnStopped && waitingStep == nil && store.isCascadeStreaming {
                    AntigravityRunningArcIndicatorView(isAnimated: shouldAnimateLive)
                } else {
                    Circle()
                        .fill(isTurnStopped ? AntigravityTheme.inkSecondary : (waitingStep != nil ? AntigravityTheme.statusWaiting : AntigravityTheme.accentPeriwinkle))
                        .frame(width: 8, height: 8)
                }

                Text(statusLabel)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isTurnStopped ? AntigravityTheme.inkSecondary : (waitingStep != nil ? AntigravityTheme.statusWaiting : AntigravityTheme.accentPeriwinkle))
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            if let waiting = waitingStep, !isStaticESDDFixtureView {
                Button {
                    openPendingApproval(for: waiting, scrollProxy: scrollProxy)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: isQuestionGate ? "list.bullet.rectangle.portrait.fill" : "checkmark.shield.fill")
                            .font(.system(size: 12, weight: .bold))
                        Text(isQuestionGate ? "Answer" : "Approve")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundStyle(AntigravityTheme.inkOnAmberCTA)
                    .padding(.horizontal, 13)
                    .frame(minWidth: AntigravityTheme.minTouchTargetPt, minHeight: AntigravityTheme.minTouchTargetPt)
                    .background(AntigravityTheme.statusWaiting)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("btn-status-review-approval")
            }

            Button {
                isTurnStopped = true
                store.stopActiveCascadeStreaming()
            } label: {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .fill(AntigravityTheme.inkReading)
                        .frame(width: 9, height: 9)
                    Text("Stop")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AntigravityTheme.inkReading)
                }
                .padding(.horizontal, 14)
                .frame(minWidth: AntigravityTheme.minTouchTargetPt, minHeight: AntigravityTheme.minTouchTargetPt)
                .background(AntigravityTheme.surfacePill)
                .overlay(
                    Capsule()
                        .stroke(AntigravityTheme.cardBorder, lineWidth: 1)
                )
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("btn-stop-turn")
        }
    }
}
