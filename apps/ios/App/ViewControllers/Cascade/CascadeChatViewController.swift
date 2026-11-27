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
    @State private var visibleTailLimit: Int = 60
    @State private var isLoadingOlderMessages: Bool = false
    @State private var hasSettledInitialScroll: Bool = false
    @State private var olderMessagesLoadTask: Task<Void, Never>?

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
                ?? store.projects.first(where: { $0.name == draft.projectSlug && ($0.runtime == .cloud) == draft.isCloud })
                ?? store.projects.first(where: { $0.name == draft.projectSlug })
        }
        if let summary = store.activeSummary {
            let summaryIsCloud = store.isSummaryCloudRuntime(summary)
            return store.projects.first(where: { $0.id == summary.projectSlug })
                ?? store.projects.first(where: { $0.name == summary.projectSlug && ($0.runtime == .cloud) == summaryIsCloud })
                ?? store.projects.first(where: { $0.name == summary.projectSlug })
        }
        return store.selectedProject
    }

    private var isActiveSessionCloud: Bool {
        if let draft = activePendingDraft {
            return draft.isCloud
        }
        if let summary = store.activeSummary {
            return store.isSummaryCloudRuntime(summary)
        }
        return store.isActiveSessionCloud
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

    private var lang: AppLanguage { store.appearancePreferences.language }

    private var effectiveHeaderHostLabel: String {
        if isActiveSessionCloud {
            return (store.hasPairedBackend || store.isLiveBackendConnected) ? "Antigravity" : lang.t("Cloud", "云端")
        }
        let originUuid = store.activeSummary?.originInstanceUuid ?? activeProjectWorkspace?.originInstanceUuid
        let hostTitle = store.resolvedHostName(
            forInstanceUuid: originUuid,
            fallback: store.activeSummary?.originHostName ?? activeProjectWorkspace?.hostName
        )
        if store.hasPairedBackend && !isActiveSessionHostOnline {
            if !store.isLiveBackendConnected && (store.isConnectingToBackend || store.connectionLifecyclePhase == .connecting) {
                return lang.t("Connecting · \(hostTitle)", "连接中 · \(hostTitle)")
            }
            return lang.t("Offline · \(hostTitle)", "离线 · \(hostTitle)")
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

    private var isShowingHistoryLoadPill: Bool {
        guard activePendingDraft == nil, !isStaticESDDFixtureView else { return false }
        guard store.hasPairedBackend || store.isLiveBackendConnected else { return false }
        if store.displayItems.isEmpty {
            return store.isLoadingSteps
                || (!store.isLiveBackendConnected && (store.isConnectingToBackend || store.connectionLifecyclePhase == .connecting))
        }
        return store.isLoadingSteps && !store.isCascadeStreaming
    }

    private var floatingHistoryLoadingPillState: (title: String, accessibilityId: String)? {
        if isLoadingOlderMessages {
            return (
                lang.t("Loading older messages...", "正在加载更早消息..."),
                "chat-loading-older-pill"
            )
        }
        guard isShowingHistoryLoadPill else { return nil }
        if !store.isLiveBackendConnected && (store.isConnectingToBackend || store.connectionLifecyclePhase == .connecting) {
            let cleanHost = effectiveHeaderHostLabel
                .replacingOccurrences(of: "Connecting · ", with: "")
                .replacingOccurrences(of: "连接中 · ", with: "")
            return (
                lang.t("Connecting to \(cleanHost)...", "正在连接 \(cleanHost)..."),
                "chat-loading-steps"
            )
        }
        return (
            lang.t("Loading older messages...", "正在加载历史消息..."),
            "chat-loading-steps"
        )
    }

    @MainActor
    private func loadOlderMessages(scrollProxy: ScrollViewProxy, anchorItemId: String?) {
        guard !isLoadingOlderMessages else { return }
        let hiddenCount = max(0, store.displayItems.count - visibleTailLimit)
        guard hiddenCount > 0 else { return }

        isLoadingOlderMessages = true
        olderMessagesLoadTask?.cancel()
        olderMessagesLoadTask = Task { @MainActor in
            if shouldAnimateLive {
                try? await Task.sleep(for: .milliseconds(280))
            }
            guard !Task.isCancelled else { return }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                visibleTailLimit += 60
            }
            if let anchorItemId {
                DispatchQueue.main.async {
                    scrollProxy.scrollTo(anchorItemId, anchor: .top)
                }
            }
            isLoadingOlderMessages = false
        }
    }

    public var body: some View {
        let allDisplayItems = store.displayItems
        let hiddenPrefixCount = (store.isVerificationMode && !store.isLiveBackendConnected)
            ? 0
            : max(0, allDisplayItems.count - visibleTailLimit)
        let renderedItems = hiddenPrefixCount > 0
            ? Array(allDisplayItems.suffix(visibleTailLimit))
            : allDisplayItems
        let floatingPill = floatingHistoryLoadingPillState

        VStack(spacing: 0) {
            chatTopNavigationBar

            Divider()
                .overlay(AntigravityTheme.subtleDivider)

            ScrollViewReader { scrollProxy in
                ZStack(alignment: .top) {
                    ScrollView {
                        Group {
                            if isStaticESDDFixtureView {
                                VStack(alignment: .leading, spacing: 9) {
                                    staticRateLimiterShowcaseBody
                                    Color.clear
                                        .frame(height: 1)
                                        .id("chat-bottom-anchor")
                                }
                            } else if allDisplayItems.isEmpty {
                                VStack(alignment: .leading, spacing: 9) {
                                    emptyOrLoadingSessionCard
                                }
                            } else {
                                LazyVStack(alignment: .leading, spacing: 9) {
                                    if hiddenPrefixCount > 0 {
                                        Button {
                                            loadOlderMessages(
                                                scrollProxy: scrollProxy,
                                                anchorItemId: renderedItems.first?.id
                                            )
                                        } label: {
                                            Color.clear
                                                .frame(maxWidth: .infinity)
                                                .frame(height: 12)
                                                .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel(lang.t("Load earlier messages", "加载更早消息"))
                                        .accessibilityIdentifier("btn-load-earlier-messages")
                                        .onAppear {
                                            if hasSettledInitialScroll && !isLoadingOlderMessages {
                                                loadOlderMessages(
                                                    scrollProxy: scrollProxy,
                                                    anchorItemId: renderedItems.first?.id
                                                )
                                            }
                                        }
                                    }

                                    ForEach(renderedItems) { item in
                                        switch item {
                                        case .single(let step):
                                            CascadeStepCellView(store: store, step: step)
                                                .contextMenu {
                                                    if let text = step.plannerResponse?.response ?? step.userInput, !text.isEmpty {
                                                        Button {
                                                            store.composerDraftText += (store.composerDraftText.isEmpty ? "" : "\n") + "> \(String(text.prefix(240)))\n"
                                                        } label: {
                                                            Label(lang.t("Quote in Reply", "引用回复"), systemImage: "text.quote")
                                                        }
                                                    }
                                                    Button(role: .destructive) {
                                                        store.revertConversationToStep(step.stepIndex)
                                                    } label: {
                                                        Label(lang.t("Revert to This Step", "回退到此步骤"), systemImage: "arrow.uturn.backward")
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

                                    if store.isCascadeStreaming {
                                        HStack(spacing: 10) {
                                            AntigravityFourDotLoadingView(
                                                isAnimated: shouldAnimateLive,
                                                dotSize: 4.5,
                                                spacing: 3.5,
                                                tint: AntigravityTheme.accentPeriwinkle
                                            )
                                            Text(lang.t("Agent is thinking and executing steps...", "Agent 正在思考并执行步骤..."))
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
                    .defaultScrollAnchor((isStaticESDDFixtureView || allDisplayItems.isEmpty) ? nil : .bottom)
                    .scrollDismissesKeyboard(.interactively)
                    .onAppear {
                        if isStaticESDDFixtureView {
                            scrollProxy.scrollTo("chat-bottom-anchor", anchor: .bottom)
                            DispatchQueue.main.async {
                                scrollProxy.scrollTo("chat-bottom-anchor", anchor: .bottom)
                            }
                            return
                        }
                        guard !allDisplayItems.isEmpty else { return }
                        if let waiting = store.pendingWaitingStep {
                            scrollProxy.scrollTo(scrollTargetId(forStepIndex: waiting.stepIndex), anchor: .bottom)
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

                    if let floatingPill {
                        AntigravityFloatingLoadingPill(
                            title: floatingPill.title,
                            isAnimated: shouldAnimateLive
                        )
                        .padding(.top, 10)
                        .allowsHitTesting(false)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .accessibilityIdentifier(floatingPill.accessibilityId)
                    }
                }
                .animation(.easeOut(duration: 0.2), value: floatingPill?.title)

                if !allDisplayItems.isEmpty, let errText = store.stepLoadErrorText {
                    HStack(alignment: .center, spacing: 8) {
                        Circle()
                            .fill(AntigravityTheme.statusError)
                            .frame(width: 7, height: 7)
                        Text(errText)
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(AntigravityTheme.statusError)
                            .lineLimit(4)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 4)
                        HStack(spacing: 10) {
                            Button(lang.t("Retry", "重试")) {
                                if store.activeFailedSend != nil {
                                    store.retryLastFailedSend()
                                } else {
                                    store.stepLoadErrorText = nil
                                    store.syncStepsForCascade(store.activeCascadeId, pollUntilIdle: true, forceRefresh: true)
                                }
                            }
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AntigravityTheme.accentPeriwinkle)
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("chat-inline-error-retry")

                            Button(lang.t("Dismiss", "关闭")) {
                                store.stepLoadErrorText = nil
                            }
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AntigravityTheme.textSecondary)
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("chat-inline-error-dismiss")
                        }
                        .fixedSize()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(AntigravityTheme.surfaceCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(AntigravityTheme.statusError.opacity(0.35), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.horizontal, 14)
                    .padding(.top, 4)
                }

                // Above-Composer Status Strip (shown in ESDD fixture or when an explicit approval/question gate awaits user action;
                // ordinary streaming Stop is handled directly inside ChatComposerView's adaptive primary button)
                if isStaticESDDFixtureView || (activePendingDraft == nil && store.pendingWaitingStep != nil) {
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
            ChatComposerView(
                store: store,
                isRemoteSessionOverride: isActiveSessionCloud
            )
                .padding(.horizontal, 12)
                .padding(.top, 4)
                .padding(.bottom, 8)
        }
        .background(AntigravityTheme.canvasObsidian)
        .onChange(of: store.isCascadeStreaming) { _, streaming in
            if streaming {
                isTurnStopped = false
            }
        }
        .task(id: store.activeCascadeId) {
            isTurnStopped = false
            olderMessagesLoadTask?.cancel()
            olderMessagesLoadTask = nil
            isLoadingOlderMessages = false
            hasSettledInitialScroll = false
            visibleTailLimit = 60
            if (store.hasPairedBackend || store.isLiveBackendConnected)
                && !store.activeCascadeId.isEmpty
                && !store.hasActiveStepSync(for: store.activeCascadeId) {
                store.syncStepsForCascade(store.activeCascadeId, pollUntilIdle: true)
            }
            if shouldAnimateLive {
                try? await Task.sleep(for: .milliseconds(350))
            }
            if !Task.isCancelled {
                hasSettledInitialScroll = true
            }
        }
        .onDisappear {
            olderMessagesLoadTask?.cancel()
            olderMessagesLoadTask = nil
            isLoadingOlderMessages = false
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
                    Text(isAutomationDraft ? lang.t("Create Automation with Prompt", "用提示词创建自动化") : lang.t("New Conversation", "新建对话"))
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(AntigravityTheme.inkReading)
                }
                Text(
                    isAutomationDraft
                        ? lang.t(
                            "Review or edit the prompt below, then tap Send. Antigravity on \(effectiveHeaderHostLabel) will guide you through setting up the schedule and instructions.",
                            "检查或编辑下方提示词后点击发送。\(effectiveHeaderHostLabel) 上的 Antigravity 将引导你完成计划与指令配置。"
                        )
                        : lang.t(
                            "Draft ready on \(effectiveHeaderHostLabel). Edit your message below and tap Send to start.",
                            "草稿已在 \(effectiveHeaderHostLabel) 就绪。编辑下方消息并点击发送即可开始。"
                        )
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
        } else if isShowingHistoryLoadPill {
            EmptyView()
        } else if (store.hasPairedBackend || store.isLiveBackendConnected), let err = store.stepLoadErrorText {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(AntigravityTheme.statusError)
                        .frame(width: 8, height: 8)
                    Text(lang.t("Could not load trajectory steps", "无法加载对话轨迹步骤"))
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
                                    store.syncStepsForCascade(store.activeCascadeId, pollUntilIdle: true, forceRefresh: true)
                                }
                            } else {
                                await store.reconnectNow(userInitiated: true)
                            }
                        }
                    } else {
                        store.syncStepsForCascade(store.activeCascadeId, pollUntilIdle: true, forceRefresh: true)
                    }
                } label: {
                    Text(lang.t("Retry", "重试"))
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
            if isNoInternet || isOfflinePaired {
                HStack(spacing: 7) {
                    Circle()
                        .fill(AntigravityTheme.statusError)
                        .frame(width: 7, height: 7)
                    Text(
                        isNoInternet
                            ? lang.t("No internet · Messages will queue", "无网络 · 消息将排队等待发送")
                            : (store.pendingOutboxCount > 0
                                ? lang.t("Host offline · \(store.pendingOutboxCount) queued", "主机离线 · \(store.pendingOutboxCount) 条排队中")
                                : lang.t("Host offline · Messages will send on reconnect", "主机离线 · 重连后自动发送"))
                    )
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(AntigravityTheme.inkSecondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(AntigravityTheme.surfaceCard)
                .overlay(
                    Capsule()
                        .stroke(AntigravityTheme.cardBorder, lineWidth: 1)
                )
                .clipShape(Capsule())
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 16)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("chat-offline-status-pill")
            }
        }
    }

    private func draftTargetSelectorBar(draft: PendingDraftConversation) -> some View {
        let isNoProj = AntigravityCloudDetector.isNoProjectSlug(draft.projectSlug)
        let localizedNoProject = lang.t(AntigravityCloudDetector.noProjectDisplayName, "无项目")
        let currentLabel = isNoProj
            ? localizedNoProject
            : (activeProjectWorkspace?.name ?? AntigravityCloudDetector.stripProjectScopePrefix(draft.projectSlug))

        return HStack(spacing: 8) {
            Menu {
                Button {
                    store.updatePendingDraftProject(AntigravityCloudDetector.noProjectDisplayName)
                } label: {
                    if isNoProj {
                        Label(localizedNoProject, systemImage: "checkmark")
                    } else {
                        Text(localizedNoProject)
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
        let isNavTitleLoading: Bool = {
            guard activePendingDraft == nil, let activeSummary = store.activeSummary else { return false }
            return store.isSummaryTitleLoading(activeSummary)
        }()
        let navTitle = activePendingDraft?.title
            ?? store.activeSummary.map { store.displayTitle(for: $0) }
            ?? (isLiveOrPaired ? lang.t("Conversation", "对话") : "Add rate limiter to /transfers")
        let rawProjectLabel = activeProjectWorkspace?.name
            ?? activePendingDraft?.projectSlug
            ?? store.activeSummary?.projectSlug
            ?? (isLiveOrPaired ? AntigravityCloudDetector.noProjectDisplayName : "ledger-svc")
        let strippedProjectLabel = AntigravityCloudDetector.stripProjectScopePrefix(rawProjectLabel)
        let isNoProjChat = (activePendingDraft != nil || isLiveOrPaired)
            && ((activeProjectWorkspace?.isNoProject == true) || AntigravityCloudDetector.isNoProjectSlug(strippedProjectLabel))
        let projectLabel = isNoProjChat ? lang.t(AntigravityCloudDetector.noProjectDisplayName, "无项目") : strippedProjectLabel
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
                    store.activeRoute = .tabRoot
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AntigravityTheme.accentPeriwinkle)
                    .frame(width: AntigravityTheme.minTouchTargetPt, height: AntigravityTheme.minTouchTargetPt)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(lang.t("Back", "返回"))
            .accessibilityIdentifier("btn-back-sessions")

            VStack(alignment: .leading, spacing: 2) {
                if isNavTitleLoading {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(AntigravityTheme.inkSecondary)
                        Text(lang.t("Loading...", "加载中..."))
                            .font(.system(size: 15.5, weight: .semibold))
                            .foregroundStyle(AntigravityTheme.inkSecondary)
                            .lineLimit(1)
                    }
                    .accessibilityIdentifier("chat-nav-title")
                } else {
                    Text(navTitle)
                        .font(.system(size: 15.5, weight: .bold))
                        .foregroundStyle(AntigravityTheme.inkReading)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .accessibilityIdentifier("chat-nav-title")
                }

                Text(subtitleLine)
                    .font(.system(size: 12))
                    .foregroundStyle(AntigravityTheme.inkSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
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
                    .frame(minWidth: AntigravityTheme.minTouchTargetPt, minHeight: 34)
                    .background(AntigravityTheme.surfacePill)
                    .overlay(
                        Capsule()
                            .stroke(AntigravityTheme.cardBorder, lineWidth: 1)
                    )
                    .clipShape(Capsule())
                    .frame(minHeight: AntigravityTheme.minTouchTargetPt)
                }
                .buttonStyle(.plain)
                .fixedSize()
                .accessibilityIdentifier("chat-diff-pill")
            }

            // `•••` Overflow Menu
            Menu {
                Button {
                    store.presentedSheet = .conversationOverview
                } label: {
                    Label(lang.t("Conversation Overview", "对话概览"), systemImage: "sidebar.right")
                }
                Button {
                    store.startVoiceMode()
                } label: {
                    Label(lang.t("Start Voice Mode", "启动语音模式"), systemImage: "waveform")
                }
                Divider()
                Button(lang.t("Open Implementation Plan", "打开实施方案")) {
                    store.currentRoute = .planReview
                }
                Button(lang.t("Review Turn Changes", "审查本轮变更")) {
                    store.currentRoute = .turnDiffReview
                }
                Button {
                    store.activeRoute = .rulesAndSkills
                } label: {
                    Label(lang.t("Rules & Skills", "规则与技能"), systemImage: "doc.text")
                }
                Button {
                    store.presentedSheet = .permissionsPreset
                } label: {
                    Label(lang.t("Permissions", "权限设置"), systemImage: "shield.lefthalf.filled")
                }
                Button(lang.t("Refresh Trajectory Steps", "刷新执行轨迹")) {
                    store.syncStepsForCascade(store.activeCascadeId, pollUntilIdle: true, forceRefresh: true)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AntigravityTheme.inkReading)
                    .frame(width: AntigravityTheme.minTouchTargetPt, height: AntigravityTheme.minTouchTargetPt)
            }
            .accessibilityIdentifier("btn-chat-more")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
    }

    // MARK: - Above-Composer Status Strip

    private func scrollTargetId(forStepIndex stepIndex: Int) -> String {
        for item in store.displayItems {
            switch item {
            case .single(let step) where step.stepIndex == stepIndex:
                return item.id
            case .evidenceGroup(_, let grouped) where grouped.contains(where: { $0.stepIndex == stepIndex }):
                return item.id
            default:
                continue
            }
        }
        return "chat-bottom-anchor"
    }

    private func openPendingApproval(for waiting: CascadeStep, scrollProxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) {
            scrollProxy.scrollTo(scrollTargetId(forStepIndex: waiting.stepIndex), anchor: .bottom)
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
                return lang.t("Turn stopped", "已停止本轮执行")
            }
            if isStaticESDDFixtureView {
                return lang.t("Waiting for your approval · Step 5 of 7", "等待你的审批 · 第 5/7 步")
            }
            if let waitingStep {
                return lang.t("Approval needed · Step \(waitingStep.stepIndex + 1)", "需要审批 · 第 \(waitingStep.stepIndex + 1) 步")
            }
            if store.isCascadeStreaming {
                let sourceTitle = isActiveSessionCloud
                    ? lang.t("Antigravity Cloud", "Antigravity 云端")
                    : store.resolvedHostName(
                        forInstanceUuid: store.activeSummary?.originInstanceUuid,
                        fallback: store.activeSummary?.originHostName
                    )
                return lang.t("Streaming from \(sourceTitle) · \(store.activeSteps.count) steps", "正从 \(sourceTitle) 接收 · \(store.activeSteps.count) 步")
            }
            return lang.t("Waiting for your approval · Step 5 of 7", "等待你的审批 · 第 5/7 步")
        }()

        let isQuestionGate = (waitingStep?.effectiveRequestedInteraction?.kind == .askQuestion
            || waitingStep?.effectiveRequestedInteraction?.kind == .elicitation)

        return HStack(spacing: 8) {
            if let waiting = waitingStep, !isStaticESDDFixtureView {
                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        scrollProxy.scrollTo(scrollTargetId(forStepIndex: waiting.stepIndex), anchor: .bottom)
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
                        Text(isQuestionGate ? lang.t("Answer", "回答") : lang.t("Approve", "批准"))
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
                    Text(lang.t("Stop", "停止"))
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
