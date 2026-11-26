import SwiftUI
import AntigravityData
#if canImport(LocalAuthentication)
import LocalAuthentication
#endif

// MARK: - UE07 Native Chat Stream Cards (`StepCellViews.swift`)

/// Previous user prompt bubble with context chips `[@transfers.go]` `[Skill · go-testing]`.
public struct UserPromptContextBubbleView: View {
    public let promptText: String?
    public let contextChips: [String]
    public let store: AntigravitySessionStore?

    public init(
        promptText: String? = nil,
        contextChips: [String] = ["@transfers.go", "Skill · go-testing"],
        store: AntigravitySessionStore? = nil
    ) {
        self.promptText = promptText
        self.contextChips = contextChips
        self.store = store
    }

    public var body: some View {
        HStack {
            Spacer(minLength: 36)
            VStack(alignment: .leading, spacing: 6) {
                if let promptText, !promptText.isEmpty {
                    AntigravityMarkdownView(markdown: promptText, variant: .userBubble, store: store)
                }

                if !contextChips.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(contextChips, id: \.self) { chip in
                                Text(chip)
                                    .font(.system(size: 12, weight: .medium, design: chip.hasPrefix("@") ? .monospaced : .default))
                                    .foregroundStyle(AntigravityTheme.inkLabel)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(AntigravityTheme.surfacePopover)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(AntigravityTheme.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }
}

/// Collapsible `👁 Thought for 14s ›` reasoning row (`row-thought-14s`) with live streaming timer & reasoning preview.
public struct CollapsibleThoughtRowView: View {
    public let durationSeconds: Int
    public let reasoningSummary: String
    public let isStreaming: Bool
    public let startedAt: Date?
    public let store: AntigravitySessionStore?
    @Environment(\.appLanguage) private var lang
    @State private var isExpanded: Bool = false
    @State private var userCollapsedDuringStream: Bool = false

    public init(
        durationSeconds: Int = 14,
        reasoningSummary: String = "Inspected internal/middleware router chain, verified token-bucket concurrency lock contention, and prepared vegeta load profile.",
        isStreaming: Bool = false,
        startedAt: Date? = nil,
        store: AntigravitySessionStore? = nil
    ) {
        self.durationSeconds = durationSeconds
        self.reasoningSummary = reasoningSummary
        self.isStreaming = isStreaming
        self.startedAt = startedAt
        self.store = store
    }

    private var effectiveExpanded: Bool {
        if isStreaming {
            return !userCollapsedDuringStream
        }
        return isExpanded
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    if isStreaming {
                        userCollapsedDuringStream.toggle()
                    } else {
                        isExpanded.toggle()
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    if isStreaming {
                        AntigravityRunningArcIndicatorView(isAnimated: true)
                        TimelineView(.periodic(from: .now, by: 1.0)) { context in
                            let elapsed = Int(max(Double(durationSeconds), context.date.timeIntervalSince(startedAt ?? context.date)))
                            let sec = max(1, elapsed)
                            Text(lang.t("Thinking · \(sec)s…", "思考中 · \(sec)秒…"))
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(AntigravityTheme.accentPeriwinkle)
                        }
                    } else {
                        Image(systemName: "eye")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(AntigravityTheme.inkSecondary)
                        Text(lang.t("Thought for \(durationSeconds)s", "思考了 \(durationSeconds) 秒"))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(AntigravityTheme.inkSecondary)
                    }
                    Image(systemName: effectiveExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isStreaming ? AntigravityTheme.accentPeriwinkle : AntigravityTheme.inkSecondary)
                    Spacer()
                }
                .frame(minHeight: AntigravityTheme.minTouchTargetPt)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("row-thought-14s")

            if effectiveExpanded {
                let trimmed = reasoningSummary.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    AntigravityMarkdownView(markdown: reasoningSummary, variant: .thought, store: store)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AntigravityTheme.surfaceCard)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else if isStreaming {
                    Text(lang.t("Analyzing workspace context and planning next steps…", "正在分析工作区上下文并规划下一步…"))
                        .font(.system(size: 13.5))
                        .foregroundStyle(AntigravityTheme.inkSecondary)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AntigravityTheme.surfaceCard)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
    }
}

/// Embedded **Implementation Plan** artifact card (`card-artifact-plan`), navigating to `.planReview`.
public struct EmbeddedImplementationPlanCardView: View {
    public let title: String
    public let statusSubtitle: String
    public let onTap: () -> Void

    public init(
        title: String = "Implementation Plan",
        statusSubtitle: String = "Approved · 2 comments addressed",
        onTap: @escaping () -> Void
    ) {
        self.title = title
        self.statusSubtitle = statusSubtitle
        self.onTap = onTap
    }

    public var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(AntigravityTheme.accentPeriwinkle.opacity(0.14))
                        .frame(width: 38, height: 38)
                    Image(systemName: "doc.text")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(AntigravityTheme.accentPeriwinkle)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AntigravityTheme.inkReading)
                    Text(statusSubtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(AntigravityTheme.inkSecondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AntigravityTheme.inkSecondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(minHeight: 58)
            .background(AntigravityTheme.surfaceCard)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(AntigravityTheme.glassHairline, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("card-artifact-plan")
    }
}

/// **7-Segment Task Progress Card** (`card-task-progress-7seg`):
/// Renders exact UE07 showcase fixture when initialized with defaults, and renders real live
/// `TaskBoundaryPayload` (`taskName`, `taskStatus`, `taskSummary`, `checklist`) on live sessions.
public struct SevenSegmentTaskProgressCardView: View {
    public let completedCount: Int
    public let totalCount: Int
    public let elapsedLabel: String
    public let taskName: String?
    public let taskStatus: String?
    public let taskSummary: String?
    public let checklist: [TaskChecklistItem]?
    @Environment(\.appLanguage) private var lang

    public init(
        completedCount: Int = 4,
        totalCount: Int = 7,
        elapsedLabel: String = "2m 41s",
        taskName: String? = nil,
        taskStatus: String? = nil,
        taskSummary: String? = nil,
        checklist: [TaskChecklistItem]? = nil
    ) {
        self.completedCount = completedCount
        self.totalCount = totalCount
        self.elapsedLabel = elapsedLabel
        self.taskName = taskName
        self.taskStatus = taskStatus
        self.taskSummary = taskSummary
        self.checklist = checklist
    }

    private var isStaticShowcaseMode: Bool {
        taskName == nil && taskStatus == nil && taskSummary == nil && checklist == nil
    }

    private var headerTitle: String {
        if let taskName, !taskName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if totalCount > 0 {
                return "\(taskName) · \(completedCount)/\(totalCount)"
            }
            return taskName
        }
        return lang.t(
            "Task · \(completedCount) of \(totalCount) done",
            "任务 · 已完成 \(completedCount)/\(totalCount)"
        )
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(headerTitle)
                    .font(.system(size: 14.5, weight: .bold))
                    .foregroundStyle(AntigravityTheme.inkReading)
                    .lineLimit(2)
                Spacer(minLength: 6)
                if !elapsedLabel.isEmpty {
                    Text(elapsedLabel)
                        .font(.system(size: 13, weight: .regular, design: .monospaced))
                        .foregroundStyle(AntigravityTheme.inkSecondary)
                }
            }

            if totalCount > 0 {
                let cappedSegments = min(12, totalCount)
                HStack(spacing: 5) {
                    ForEach(0..<cappedSegments, id: \.self) { index in
                        Capsule()
                            .fill(segmentColor(at: index))
                            .frame(height: 4)
                    }
                }
            }

            if isStaticShowcaseMode {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 9) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(AntigravityTheme.statusDone)
                            .frame(width: 12)
                        Text("Wire limiter into router")
                            .font(.system(size: 13.5))
                            .foregroundStyle(AntigravityTheme.inkSecondary)
                        Spacer()
                    }

                    HStack(spacing: 9) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(AntigravityTheme.statusDone)
                            .frame(width: 12)
                        Text("go test ./internal/...")
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(AntigravityTheme.inkSecondary)
                        Spacer()
                        Text("42 passed")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(AntigravityTheme.statusDone)
                    }

                    HStack(spacing: 9) {
                        Circle()
                            .fill(AntigravityTheme.statusWaiting)
                            .frame(width: 8, height: 8)
                            .frame(width: 12)
                        Text("Load test with vegeta")
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(AntigravityTheme.statusWaiting)
                        Spacer()
                    }
                }
            } else if let checklist, !checklist.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(checklist) { item in
                        HStack(spacing: 9) {
                            checklistStatusIcon(for: item.status)
                            Text(item.title)
                                .font(.system(size: 13.5, weight: item.status == .waiting ? .medium : .regular))
                                .foregroundStyle(checklistTextColor(for: item.status))
                                .lineLimit(2)
                            Spacer()
                            if let badge = item.trailingBadge, !badge.isEmpty {
                                Text(badge)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(AntigravityTheme.statusDone)
                            }
                        }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    if let status = taskStatus?.trimmingCharacters(in: .whitespacesAndNewlines), !status.isEmpty {
                        HStack(spacing: 7) {
                            Circle()
                                .fill(AntigravityTheme.accentPeriwinkle)
                                .frame(width: 6, height: 6)
                            Text(status)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(AntigravityTheme.accentPeriwinkle)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if let summary = taskSummary?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !summary.isEmpty,
                       summary != taskStatus?.trimmingCharacters(in: .whitespacesAndNewlines) {
                        Text(summary)
                            .font(.system(size: 13))
                            .foregroundStyle(AntigravityTheme.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(14)
        .background(AntigravityTheme.surfaceCard)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AntigravityTheme.glassHairline, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("card-task-progress-7seg")
    }

    private func segmentColor(at index: Int) -> Color {
        if index < completedCount {
            return AntigravityTheme.accentPeriwinkle
        }
        if index == completedCount {
            return AntigravityTheme.statusWaiting
        }
        return AntigravityTheme.ringTrack
    }

    @ViewBuilder
    private func checklistStatusIcon(for status: TaskChecklistStatus) -> some View {
        switch status {
        case .done:
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(AntigravityTheme.statusDone)
                .frame(width: 12)
        case .waiting:
            Circle()
                .fill(AntigravityTheme.statusWaiting)
                .frame(width: 8, height: 8)
                .frame(width: 12)
        case .inProgress:
            Circle()
                .fill(AntigravityTheme.accentPeriwinkle)
                .frame(width: 8, height: 8)
                .frame(width: 12)
        case .pending:
            Circle()
                .stroke(AntigravityTheme.inkSecondary.opacity(0.5), lineWidth: 1.2)
                .frame(width: 8, height: 8)
                .frame(width: 12)
        }
    }

    private func checklistTextColor(for status: TaskChecklistStatus) -> Color {
        switch status {
        case .waiting: return AntigravityTheme.statusWaiting
        case .inProgress: return AntigravityTheme.inkReading
        case .done, .pending: return AntigravityTheme.inkSecondary
        }
    }
}

/// **Inline `Run this command?` Amber Approval Card** (`card-command-approval`):
/// Displays monospaced command with left `Deny` (`btn-command-deny`)
/// and right warm amber `#EBB365` Face ID `Allow` (`btn-command-allow-faceid`).
public struct InlineCommandApprovalCardView: View {
    private enum ResolutionOutcome {
        case denied
        case approvedFaceID
    }

    @Bindable public var store: AntigravitySessionStore
    public let commandLine: String
    public let stepIndex: Int?
    public let hostName: String?
    @State private var resolutionState: ResolutionOutcome? = nil

    public init(
        store: AntigravitySessionStore,
        commandLine: String = "vegeta attack -rate=2000/s -duration=30s \\\n  -targets=load/transfers.txt | vegeta\nreport",
        stepIndex: Int? = nil,
        hostName: String? = nil
    ) {
        self.store = store
        self.commandLine = commandLine
        self.stepIndex = stepIndex
        self.hostName = hostName
    }

    private var lang: AppLanguage { store.appearancePreferences.language }

    private var headerTitle: String {
        switch resolutionState {
        case .denied:
            return lang.t("Command denied", "已拒绝执行")
        case .approvedFaceID:
            return lang.t("Approved with Face ID", "已通过 Face ID 批准")
        case nil:
            return lang.t("Run this command?", "运行此命令？")
        }
    }

    private var displayCommandLine: String {
        let trimmed = commandLine.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? lang.t("Confirm pending terminal command", "确认待执行的终端命令") : commandLine
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "terminal")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AntigravityTheme.statusWaiting)
                Text(headerTitle)
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(AntigravityTheme.statusWaiting)
                Spacer()
            }

            Text(displayCommandLine)
                .font(.system(size: 12.5, design: .monospaced))
                .foregroundStyle(AntigravityTheme.inkReading)
                .lineSpacing(2)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AntigravityTheme.surfaceCodeBlock)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(AntigravityTheme.glassHairline, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            HStack(spacing: 10) {
                Button {
                    resolutionState = .denied
                    if let targetIdx = stepIndex ?? store.pendingWaitingStep?.stepIndex {
                        store.resolveWaitingStep(stepIndex: targetIdx, decision: .reject)
                    }
                } label: {
                    Text(lang.t("Deny", "拒绝"))
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(AntigravityTheme.inkReading)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(AntigravityTheme.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("btn-command-deny")

                Button {
                    authenticateWithFaceIDAndApprove()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "faceid")
                            .font(.system(size: 15, weight: .semibold))
                        Text(lang.t("Allow", "允许"))
                            .font(.system(size: 14.5, weight: .bold))
                    }
                    .foregroundStyle(AntigravityTheme.inkOnAmberCTA)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(AntigravityTheme.statusWaiting)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("btn-command-allow-faceid")
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AntigravityTheme.surfaceCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(AntigravityTheme.surfaceAmberTint)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AntigravityTheme.statusWaiting.opacity(0.30), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("card-command-approval")
    }

    private func authenticateWithFaceIDAndApprove() {
        let targetHost = hostName ?? store.activeHost.hostname
        let promptReason: String = store.isVerificationMode
            ? lang.t("Approve vegeta load-test command on MacBook Pro", "在 MacBook Pro 上批准 vegeta 压测命令")
            : lang.t("Approve command on \(targetHost)", "在 \(targetHost) 上批准执行命令")
        let cancelLabel = lang.t("Cancel", "取消")
        Task {
            let outcome = await StepBiometricGate.evaluate(
                reason: promptReason,
                cancelTitle: cancelLabel
            )
            if outcome == .verified || outcome == .unavailable {
                commitFaceIDApproval()
            }
        }
    }

    private func commitFaceIDApproval() {
        resolutionState = .approvedFaceID
        store.approveWaitingCommandWithFaceID(stepIndex: stepIndex)
    }
}

internal enum StepBiometricGate {
    enum Outcome: Sendable {
        case verified
        case unavailable
        case failedOrCancelled
    }

    static func evaluate(reason: String, cancelTitle: String? = nil) async -> Outcome {
        #if canImport(LocalAuthentication)
        return await withCheckedContinuation { (continuation: CheckedContinuation<Outcome, Never>) in
            let context = LAContext()
            if let cancelTitle {
                context.localizedCancelTitle = cancelTitle
            }
            var authError: NSError?
            guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &authError) else {
                continuation.resume(returning: .unavailable)
                return
            }
            context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            ) { success, _ in
                continuation.resume(returning: success ? .verified : .failedOrCancelled)
            }
        }
        #else
        return .unavailable
        #endif
    }
}

// MARK: - Live Trajectory Step Cell Views (Preserved & Expanded for Full Compatibility)

public struct CascadeEvidenceGroupCardView: View {
    @Bindable public var store: AntigravitySessionStore
    public let groupId: String
    public let steps: [CascadeStep]

    public init(store: AntigravitySessionStore, groupId: String, steps: [CascadeStep]) {
        self.store = store
        self.groupId = groupId
        self.steps = steps
    }

    private var lang: AppLanguage { store.appearancePreferences.language }

    private var isExpanded: Bool {
        store.expandedEvidenceGroupIds.contains(groupId)
    }

    private var isActivelyRunning: Bool {
        (!store.isVerificationMode || store.isLiveBackendConnected)
            && steps.contains(where: { $0.status == .inProgress || $0.status == .pending })
    }

    private var summaryTitle: String {
        let editCount = steps.filter { $0.codeAction != nil }.count
        if isActivelyRunning {
            if editCount == steps.count && editCount > 0 {
                return lang.t(
                    "Editing \(editCount) workspace file\(editCount == 1 ? "" : "s")…",
                    "正在编辑 \(editCount) 个工作区文件…"
                )
            } else if editCount > 0 {
                return lang.t(
                    "Inspecting & editing \(steps.count) workspace items…",
                    "正在查看并编辑 \(steps.count) 个工作区项目…"
                )
            } else {
                return lang.t(
                    "Inspecting \(steps.count) workspace file\(steps.count == 1 ? "" : "s")…",
                    "正在查看 \(steps.count) 个工作区文件…"
                )
            }
        }
        if editCount == steps.count && editCount > 0 {
            return lang.t(
                "Edited \(editCount) workspace file\(editCount == 1 ? "" : "s")",
                "已编辑 \(editCount) 个工作区文件"
            )
        } else if editCount > 0 {
            return lang.t(
                "Inspected & edited \(steps.count) workspace items",
                "已查看并编辑 \(steps.count) 个工作区项目"
            )
        } else {
            return lang.t(
                "Inspected \(steps.count) workspace file\(steps.count == 1 ? "" : "s")",
                "已查看 \(steps.count) 个工作区文件"
            )
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    store.toggleEvidenceGroupExpanded(groupId: groupId)
                }
            } label: {
                HStack(spacing: 10) {
                    if isActivelyRunning {
                        AntigravityRunningArcIndicatorView(isAnimated: true)
                    } else {
                        Image(systemName: "doc.on.doc")
                            .foregroundStyle(AntigravityTheme.accentPeriwinkle)
                    }
                    Text(summaryTitle)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(isActivelyRunning ? AntigravityTheme.accentPeriwinkle : AntigravityTheme.inkReading)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AntigravityTheme.inkSecondary)
                }
                .frame(minHeight: AntigravityTheme.minTouchTargetPt)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                ForEach(steps) { step in
                    if let ca = step.codeAction {
                        Button {
                            store.selectedDiffFilePath = ca.fileName
                            store.currentRoute = .turnDiffReview
                        } label: {
                            HStack {
                                Image(systemName: ca.isArtifactFile ? "sparkles.rectangle.stack" : "pencil")
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(AntigravityTheme.accentPeriwinkle)
                                Text(ca.fileName)
                                    .font(.system(size: 13, design: .monospaced))
                                    .foregroundStyle(AntigravityTheme.inkReading)
                                    .lineLimit(1)
                                Spacer()
                                if ca.additions > 0 || ca.deletions > 0 {
                                    Text("+\(ca.additions) -\(ca.deletions)")
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundStyle(AntigravityTheme.statusDone)
                                }
                            }
                            .frame(minHeight: 34)
                        }
                        .buttonStyle(.plain)
                    } else if let vf = step.viewFile {
                        HStack(spacing: 8) {
                            Image(systemName: "doc.text.magnifyingglass")
                                .font(.system(size: 11.5))
                                .foregroundStyle(AntigravityTheme.inkSecondary)
                            Text(vf.fileName)
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundStyle(AntigravityTheme.inkReading)
                                .lineLimit(1)
                            Spacer()
                            Text("L\(vf.startLine)–\(vf.endLine)")
                                .font(.system(size: 11.5, design: .monospaced))
                                .foregroundStyle(AntigravityTheme.inkSecondary)
                        }
                        .frame(minHeight: 30)
                    } else if let sc = step.search {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 11.5))
                                .foregroundStyle(AntigravityTheme.inkSecondary)
                            Text(sc.query)
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundStyle(AntigravityTheme.inkReading)
                                .lineLimit(1)
                            Spacer()
                            if sc.matchCount > 0 {
                                Text(lang.t("\(sc.matchCount) matches", "\(sc.matchCount) 处匹配"))
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(AntigravityTheme.inkSecondary)
                            }
                        }
                        .frame(minHeight: 30)
                    }
                }
            }
        }
        .padding(12)
        .background(AntigravityTheme.surfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

public struct CascadeStepCellView: View {
    @Bindable public var store: AntigravitySessionStore
    public let step: CascadeStep
    @State private var previewArtifactURI: String? = nil

    public init(store: AntigravitySessionStore, step: CascadeStep) {
        self.store = store
        self.step = step
    }

    private var lang: AppLanguage { store.appearancePreferences.language }

    private var shouldAnimateLive: Bool {
        !store.isVerificationMode || store.isLiveBackendConnected
    }

    public var body: some View {
        let effectiveWaitingReq = step.isWaitingForUser ? step.effectiveRequestedInteraction : nil
        VStack(alignment: .leading, spacing: 8) {
            switch step.type {
            case .userInput:
                UserPromptContextBubbleView(
                    promptText: step.userInput,
                    contextChips: step.attachedMentions,
                    store: store
                )
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("step-user-\(step.stepIndex)")

            case .plannerResponse, .notifyUser:
                let stepIsActive = (step.status == .inProgress || step.status == .pending)
                let thinking = step.plannerResponse?.thinking ?? ""
                let prose = step.plannerResponse?.response ?? ""
                let isStreamingThought = stepIsActive
                    && prose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && shouldAnimateLive

                VStack(alignment: .leading, spacing: 8) {
                    if !thinking.isEmpty || isStreamingThought {
                        CollapsibleThoughtRowView(
                            durationSeconds: max(1, Int(step.plannerResponse?.thinkingDurationSeconds ?? 1)),
                            reasoningSummary: thinking,
                            isStreaming: isStreamingThought,
                            startedAt: step.createdAt,
                            store: store
                        )
                    }
                    if !prose.isEmpty {
                        if step.status == .error {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(AntigravityTheme.statusError)
                                    .padding(.top, 2)
                                AntigravityMarkdownView(markdown: prose, variant: .assistant, store: store)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(AntigravityTheme.surfaceCard)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .fill(AntigravityTheme.surfaceDiffRemove)
                                    )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(AntigravityTheme.statusError.opacity(0.32), lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .accessibilityIdentifier("step-error-\(step.stepIndex)")
                        } else {
                            AntigravityMarkdownView(markdown: prose, variant: .assistant, store: store)
                                .accessibilityElement(children: .contain)
                                .accessibilityIdentifier("step-prose-\(step.stepIndex)")
                        }

                        if stepIsActive && shouldAnimateLive {
                            HStack(spacing: 7) {
                                AntigravityFourDotLoadingView(
                                    isAnimated: true,
                                    dotSize: 4.0,
                                    spacing: 3.0,
                                    tint: AntigravityTheme.accentPeriwinkle
                                )
                                Text(lang.t("Generating…", "正在生成…"))
                                    .font(.system(size: 12.5, weight: .medium))
                                    .foregroundStyle(AntigravityTheme.accentPeriwinkle)
                            }
                            .padding(.top, 2)
                        }
                    }
                    if !store.isVerificationMode,
                       let refs = step.plannerResponse?.referencedFiles,
                       !refs.isEmpty {
                        ReferencedFilePillsRow(paths: refs) { tappedPath in
                            let lower = tappedPath.lowercased()
                            if lower.contains("plan") && lower.hasSuffix(".md") {
                                store.currentRoute = .planReview
                            } else if store.activeArtifacts.contains(where: { $0.artifactPath == tappedPath }) {
                                store.presentedSheet = .richArtifactViewer(artifactPath: tappedPath)
                            } else if ResolvedEmbedResource.isEmbeddableTextArtifactPath(tappedPath)
                                || MarkdownEmbedKind.detect(from: tappedPath) == .image {
                                previewArtifactURI = tappedPath
                            } else {
                                MarkdownClipboardHelper.copyText(MarkdownLinkFormatting.cleanDisplayPath(tappedPath))
                            }
                        }
                    }
                    if !store.isVerificationMode, let voice = step.voiceSummary {
                        VoiceCallSummaryCardView(summary: voice)
                    }
                    if !store.isVerificationMode {
                        let prs = AntigravityMarkdownParser.extractGitHubPRLinks(from: prose)
                        if !prs.isEmpty {
                            GitHubPRStatusPillsRow(pullRequests: prs)
                        }
                    }
                }

            case .taskBoundary:
                if let tb = step.taskBoundary {
                    SevenSegmentTaskProgressCardView(
                        completedCount: tb.completedCount,
                        totalCount: tb.totalCount,
                        elapsedLabel: tb.elapsedLabel,
                        taskName: tb.taskName,
                        taskStatus: tb.taskStatus,
                        taskSummary: tb.taskSummary,
                        checklist: tb.checklist
                    )
                }

            case .runCommand:
                if let cmd = step.runCommand,
                   !(step.isWaitingForUser && effectiveWaitingReq?.kind == .runCommand) {
                    let isExpanded = store.expandedTerminalStepIds.contains(step.id)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Image(systemName: "terminal")
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(AntigravityTheme.accentPeriwinkle)
                            Text(cmd.commandLine)
                                .font(.system(size: 12.5, design: .monospaced))
                                .foregroundStyle(AntigravityTheme.inkReading)
                                .lineLimit(isExpanded ? nil : 2)
                            Spacer()
                            if let code = cmd.exitCode {
                                Text(code == 0 ? "exit 0" : "exit \(code)")
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundStyle(code == 0 ? AntigravityTheme.statusDone : AntigravityTheme.statusError)
                            } else if (step.status == .inProgress || step.status == .pending) && shouldAnimateLive {
                                HStack(spacing: 5) {
                                    AntigravityRunningArcIndicatorView(isAnimated: true)
                                        .scaleEffect(0.82)
                                    Text(lang.t("running", "运行中"))
                                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                                        .foregroundStyle(AntigravityTheme.accentPeriwinkle)
                                }
                            }
                        }
                        if let out = cmd.outputPreview, !out.isEmpty {
                            Button {
                                withAnimation(.easeInOut(duration: 0.16)) {
                                    store.toggleTerminalOutputExpanded(stepId: step.id)
                                }
                            } label: {
                                Text(out)
                                    .font(.system(size: 11.5, design: .monospaced))
                                    .foregroundStyle(AntigravityTheme.inkSecondary)
                                    .lineLimit(isExpanded ? nil : 4)
                                    .multilineTextAlignment(.leading)
                                    .padding(8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(AntigravityTheme.surfaceCodeBlock)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(11)
                    .background(AntigravityTheme.surfaceCard)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

            case .codeAction:
                if let ca = step.codeAction {
                    Button {
                        if ca.isArtifactFile || ca.fileContent != nil {
                            previewArtifactURI = ca.targetFileUri
                        } else {
                            store.selectedDiffFilePath = ca.fileName
                            store.currentRoute = .turnDiffReview
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: ca.isArtifactFile ? "sparkles.rectangle.stack" : "doc.badge.gearshape")
                                .font(.system(size: 14))
                                .foregroundStyle(AntigravityTheme.accentPeriwinkle)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(ca.fileName)
                                    .font(.system(size: 13.5, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(AntigravityTheme.inkReading)
                                    .lineLimit(1)
                                Text(ca.description)
                                    .font(.system(size: 12.5))
                                    .foregroundStyle(AntigravityTheme.inkSecondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            if ca.additions > 0 || ca.deletions > 0 {
                                Text("+\(ca.additions) -\(ca.deletions)")
                                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                                    .foregroundStyle(AntigravityTheme.statusDone)
                            } else if ca.isArtifactFile || ca.fileContent != nil {
                                Image(systemName: "arrow.up.right.square")
                                    .font(.system(size: 12.5, weight: .medium))
                                    .foregroundStyle(AntigravityTheme.accentPeriwinkle)
                            }
                        }
                        .padding(12)
                        .background(AntigravityTheme.surfaceCard)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

            case .viewFile, .listDirectory, .viewContentChunk:
                if let vf = step.viewFile, !step.isWaitingForUser {
                    HStack(spacing: 8) {
                        Image(systemName: step.type == .listDirectory ? "folder" : "doc.text.magnifyingglass")
                            .font(.system(size: 12))
                            .foregroundStyle(AntigravityTheme.inkSecondary)
                        Text(vf.fileName)
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(AntigravityTheme.inkReading)
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(10)
                    .background(AntigravityTheme.surfaceCard)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

            case .search:
                if let sc = step.search, !step.isWaitingForUser {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 12))
                            .foregroundStyle(AntigravityTheme.inkSecondary)
                        Text(sc.query)
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(AntigravityTheme.inkReading)
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(10)
                    .background(AntigravityTheme.surfaceCard)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

            case .subagentInvocation:
                if let sub = step.subagent {
                    SubagentStepCardView(subagent: sub, onStop: {
                        store.stopSubagent(sub.subagentId)
                    })
                }

            case .dynamicWorkflow:
                if let wf = step.dynamicWorkflow {
                    DynamicWorkflowStepCardView(workflow: wf)
                }

            case .swarmBoard:
                if let board = step.swarmBoard {
                    SwarmStepCardView(board: board) {
                        store.presentedSheet = .swarmBoard(stepIndex: step.stepIndex)
                    }
                }

            case .mcpToolCall:
                if let mcp = step.mcpToolCall {
                    McpToolStepCardView(mcp: mcp)
                }

            case .generateImage:
                if let prose = step.plannerResponse?.response, !prose.isEmpty {
                    AntigravityMarkdownView(markdown: prose, variant: .assistant, store: store)
                }

            case .readUrlContent, .browserSubagent:
                HStack(spacing: 9) {
                    Image(systemName: step.type == .browserSubagent ? "safari" : "globe")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AntigravityTheme.accentPeriwinkle)
                    Text(
                        step.plannerResponse?.response
                            ?? (step.type == .browserSubagent
                                ? lang.t("Browser subagent activity", "浏览器子代理活动")
                                : lang.t("Read web page", "读取网页"))
                    )
                        .font(.system(size: 13, design: step.type == .readUrlContent ? .monospaced : .default))
                        .foregroundStyle(AntigravityTheme.inkSecondary)
                        .lineLimit(2)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(AntigravityTheme.surfaceCard)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            default:
                if let prose = step.plannerResponse?.response, !prose.isEmpty {
                    AntigravityMarkdownView(markdown: prose, variant: .assistant, store: store)
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("step-prose-\(step.stepIndex)")
                } else if step.isUnrecognizedForwardStep {
                    UnknownStepFallbackCardView(
                        stepIndex: step.stepIndex,
                        rawTypeName: step.rawTypeName,
                        fallbackSummary: step.fallbackSummary,
                        status: step.status
                    )
                }
            }

            // Guarantee EVERY waiting/blocked step renders its interactive approval or question entry point.
            if let waitingReq = effectiveWaitingReq {
                StepInlineApprovalCardView(store: store, step: step, requested: waitingReq)
            }
        }
        .sheet(
            isPresented: Binding(
                get: { previewArtifactURI != nil },
                set: { if !$0 { previewArtifactURI = nil } }
            )
        ) {
            if let uri = previewArtifactURI {
                RemoteArtifactPreviewSheet(uri: uri, store: store)
            }
        }
    }
}

/// Forward-compatible fallback card rendered when a newer Antigravity Desktop emits a `CortexStepType`
/// unrecognized by this iOS build, preserving visibility instead of silently dropping the step.
private struct UnknownStepFallbackCardView: View {
    let stepIndex: Int
    let rawTypeName: String?
    let fallbackSummary: String?
    let status: CortexStepStatus
    @Environment(\.appLanguage) private var lang

    private var formattedTypeLabel: String {
        let raw = (rawTypeName ?? "Unknown Step")
            .replacingOccurrences(of: "CORTEX_STEP_TYPE_", with: "")
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.isEmpty ? lang.t("Newer Desktop Step", "新版桌面端步骤") : raw.capitalized
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles.rectangle.stack")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AntigravityTheme.accentPeriwinkle)
                Text(formattedTypeLabel)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AntigravityTheme.inkReading)
                    .lineLimit(1)
                Spacer()
                Text(status.localizedTitle(for: lang))
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(AntigravityTheme.inkSecondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(AntigravityTheme.surfaceBadge, in: Capsule())
            }
            if let summary = fallbackSummary?.trimmingCharacters(in: .whitespacesAndNewlines), !summary.isEmpty {
                Text(summary)
                    .font(.system(size: 12.5))
                    .foregroundStyle(AntigravityTheme.inkSecondary)
                    .lineLimit(4)
            }
            Text(lang.t(
                "Synced from a newer Antigravity Desktop version · Update iOS app for full view",
                "来自更新版本 Antigravity 桌面端的步骤 · 请更新 iOS 客户端以查看完整内容"
            ))
                .font(.system(size: 11))
                .foregroundStyle(AntigravityTheme.inkMuted)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(AntigravityTheme.surfaceCard, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AntigravityTheme.glassHairline, lineWidth: 1)
        )
        .accessibilityIdentifier("card-unknown-forward-step-\(stepIndex)")
    }
}
