import SwiftUI
import AntigravityData
#if canImport(LocalAuthentication)
import LocalAuthentication
#endif
#if canImport(UIKit)
import UIKit
#endif
#if canImport(WebKit)
import WebKit
#endif

// MARK: - UE07 Native Chat Stream Cards (`StepCellViews.swift`)

private enum StepCardPalette {
    static let periwinkle = Color(red: 0x8E / 255.0, green: 0xB4 / 255.0, blue: 0xFF / 255.0) // #8EB4FF
    static let warmAmber = Color(red: 0xEB / 255.0, green: 0xB3 / 255.0, blue: 0x65 / 255.0) // #EBB365
    static let emeraldDone = Color(red: 0x57 / 255.0, green: 0xC8 / 255.0, blue: 0x8A / 255.0) // #57C88A
    static let coralError = Color(red: 0xF0 / 255.0, green: 0x71 / 255.0, blue: 0x67 / 255.0) // #F07167
    static let softViolet = Color(red: 0xA7 / 255.0, green: 0x8B / 255.0, blue: 0xFA / 255.0) // #A78BFA
    static let inlineCodeInk = Color(red: 0xDC / 255.0, green: 0xE6 / 255.0, blue: 0xFF / 255.0)
    static let inkOnCTA = Color(red: 0x0A / 255.0, green: 0x0E / 255.0, blue: 0x17 / 255.0) // #0A0E17
    static let cardSurface = Color(red: 0x14 / 255.0, green: 0x15 / 255.0, blue: 0x19 / 255.0) // #141519
    static let amberCardSurface = Color(red: 0x1A / 255.0, green: 0x16 / 255.0, blue: 0x0E / 255.0)
    static let errorCardSurface = Color(red: 0x1E / 255.0, green: 0x11 / 255.0, blue: 0x13 / 255.0)
    static let codeBlockBg = Color(red: 0x0C / 255.0, green: 0x0D / 255.0, blue: 0x10 / 255.0)
    static let neutralButtonBg = Color(red: 0x24 / 255.0, green: 0x24 / 255.0, blue: 0x28 / 255.0)
    static let darkTrack = Color(red: 0x26 / 255.0, green: 0x29 / 255.0, blue: 0x32 / 255.0)
}

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
                                    .background(Color.white.opacity(0.08))
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
                            Text("Thinking · \(max(1, elapsed))s…")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(StepCardPalette.periwinkle)
                        }
                    } else {
                        Image(systemName: "eye")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(AntigravityTheme.inkSecondary)
                        Text("Thought for \(durationSeconds)s")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(AntigravityTheme.inkSecondary)
                    }
                    Image(systemName: effectiveExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isStreaming ? StepCardPalette.periwinkle : AntigravityTheme.inkSecondary)
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
                        .background(StepCardPalette.cardSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else if isStreaming {
                    Text("Analyzing workspace context and planning next steps…")
                        .font(.system(size: 13.5))
                        .foregroundStyle(AntigravityTheme.inkSecondary)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(StepCardPalette.cardSurface)
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
                        .fill(StepCardPalette.periwinkle.opacity(0.14))
                        .frame(width: 38, height: 38)
                    Image(systemName: "doc.text")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(StepCardPalette.periwinkle)
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
            .background(StepCardPalette.cardSurface)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
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
        return "Task · \(completedCount) of \(totalCount) done"
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
                            .foregroundStyle(StepCardPalette.emeraldDone)
                            .frame(width: 12)
                        Text("Wire limiter into router")
                            .font(.system(size: 13.5))
                            .foregroundStyle(AntigravityTheme.inkSecondary)
                        Spacer()
                    }

                    HStack(spacing: 9) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(StepCardPalette.emeraldDone)
                            .frame(width: 12)
                        Text("go test ./internal/...")
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(AntigravityTheme.inkSecondary)
                        Spacer()
                        Text("42 passed")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(StepCardPalette.emeraldDone)
                    }

                    HStack(spacing: 9) {
                        Circle()
                            .fill(StepCardPalette.warmAmber)
                            .frame(width: 8, height: 8)
                            .frame(width: 12)
                        Text("Load test with vegeta")
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(StepCardPalette.warmAmber)
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
                                    .foregroundStyle(StepCardPalette.emeraldDone)
                            }
                        }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    if let status = taskStatus?.trimmingCharacters(in: .whitespacesAndNewlines), !status.isEmpty {
                        HStack(spacing: 7) {
                            Circle()
                                .fill(StepCardPalette.periwinkle)
                                .frame(width: 6, height: 6)
                            Text(status)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(StepCardPalette.periwinkle)
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
        .background(StepCardPalette.cardSurface)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("card-task-progress-7seg")
    }

    private func segmentColor(at index: Int) -> Color {
        if index < completedCount {
            return StepCardPalette.periwinkle
        }
        if index == completedCount {
            return StepCardPalette.warmAmber
        }
        return StepCardPalette.darkTrack
    }

    @ViewBuilder
    private func checklistStatusIcon(for status: TaskChecklistStatus) -> some View {
        switch status {
        case .done:
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(StepCardPalette.emeraldDone)
                .frame(width: 12)
        case .waiting:
            Circle()
                .fill(StepCardPalette.warmAmber)
                .frame(width: 8, height: 8)
                .frame(width: 12)
        case .inProgress:
            Circle()
                .fill(StepCardPalette.periwinkle)
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
        case .waiting: return StepCardPalette.warmAmber
        case .inProgress: return AntigravityTheme.inkReading
        case .done, .pending: return AntigravityTheme.inkSecondary
        }
    }
}

/// **Inline `Run this command?` Amber Approval Card** (`card-command-approval`):
/// Displays monospaced command with left `Deny` (`btn-command-deny`)
/// and right warm amber `#EBB365` Face ID `Allow` (`btn-command-allow-faceid`).
public struct InlineCommandApprovalCardView: View {
    @Bindable public var store: AntigravitySessionStore
    public let commandLine: String
    @State private var resolutionState: String? = nil

    public init(
        store: AntigravitySessionStore,
        commandLine: String = "vegeta attack -rate=2000/s -duration=30s \\\n  -targets=load/transfers.txt | vegeta\nreport"
    ) {
        self.store = store
        self.commandLine = commandLine
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "terminal")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(StepCardPalette.warmAmber)
                Text(resolutionState ?? "Run this command?")
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(StepCardPalette.warmAmber)
                Spacer()
            }

            Text(commandLine)
                .font(.system(size: 12.5, design: .monospaced))
                .foregroundStyle(AntigravityTheme.inkReading)
                .lineSpacing(2)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(StepCardPalette.codeBlockBg)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            HStack(spacing: 10) {
                Button {
                    resolutionState = "Command denied"
                    if let waiting = store.pendingWaitingStep {
                        store.resolveWaitingStep(stepIndex: waiting.stepIndex, decision: .reject)
                    }
                } label: {
                    Text("Deny")
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(AntigravityTheme.inkReading)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(StepCardPalette.neutralButtonBg)
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
                        Text("Allow")
                            .font(.system(size: 14.5, weight: .bold))
                    }
                    .foregroundStyle(StepCardPalette.inkOnCTA)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(StepCardPalette.warmAmber)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("btn-command-allow-faceid")
            }
        }
        .padding(14)
        .background(StepCardPalette.amberCardSurface)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(StepCardPalette.warmAmber.opacity(0.30), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("card-command-approval")
    }

    private func authenticateWithFaceIDAndApprove() {
        Task {
            let outcome = await StepBiometricGate.evaluate(
                reason: "Approve command execution on paired Antigravity host",
                cancelTitle: "Cancel"
            )
            if outcome == .verified || outcome == .unavailable {
                commitFaceIDApproval()
            }
        }
    }

    private func commitFaceIDApproval() {
        resolutionState = "Approved with Face ID"
        store.approveWaitingCommandWithFaceID()
    }
}

private enum StepBiometricGate {
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
                return "Editing \(editCount) workspace file\(editCount == 1 ? "" : "s")…"
            } else if editCount > 0 {
                return "Inspecting & editing \(steps.count) workspace items…"
            } else {
                return "Inspecting \(steps.count) workspace file\(steps.count == 1 ? "" : "s")…"
            }
        }
        if editCount == steps.count && editCount > 0 {
            return "Edited \(editCount) workspace file\(editCount == 1 ? "" : "s")"
        } else if editCount > 0 {
            return "Inspected & edited \(steps.count) workspace items"
        } else {
            return "Inspected \(steps.count) workspace file\(steps.count == 1 ? "" : "s")"
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
                            .foregroundStyle(StepCardPalette.periwinkle)
                    }
                    Text(summaryTitle)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(isActivelyRunning ? StepCardPalette.periwinkle : AntigravityTheme.inkReading)
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
                                    .foregroundStyle(StepCardPalette.periwinkle)
                                Text(ca.fileName)
                                    .font(.system(size: 13, design: .monospaced))
                                    .foregroundStyle(AntigravityTheme.inkReading)
                                    .lineLimit(1)
                                Spacer()
                                if ca.additions > 0 || ca.deletions > 0 {
                                    Text("+\(ca.additions) -\(ca.deletions)")
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundStyle(StepCardPalette.emeraldDone)
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
                                Text("\(sc.matchCount) matches")
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
        .background(StepCardPalette.cardSurface)
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

    private var shouldAnimateLive: Bool {
        !store.isVerificationMode || store.isLiveBackendConnected
    }

    public var body: some View {
        Group {
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
                                    .foregroundStyle(StepCardPalette.coralError)
                                    .padding(.top, 2)
                                AntigravityMarkdownView(markdown: prose, variant: .assistant, store: store)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(StepCardPalette.errorCardSurface)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(StepCardPalette.coralError.opacity(0.32), lineWidth: 1)
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
                                    tint: StepCardPalette.periwinkle
                                )
                                Text("Generating…")
                                    .font(.system(size: 12.5, weight: .medium))
                                    .foregroundStyle(StepCardPalette.periwinkle)
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
                if let cmd = step.runCommand {
                    if step.status == .waiting {
                        InlineCommandApprovalCardView(store: store, commandLine: cmd.commandLine)
                    } else {
                        let isExpanded = store.expandedTerminalStepIds.contains(step.id)
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                Image(systemName: "terminal")
                                    .font(.system(size: 12.5, weight: .semibold))
                                    .foregroundStyle(StepCardPalette.periwinkle)
                                Text(cmd.commandLine)
                                    .font(.system(size: 12.5, design: .monospaced))
                                    .foregroundStyle(AntigravityTheme.inkReading)
                                    .lineLimit(isExpanded ? nil : 2)
                                Spacer()
                                if let code = cmd.exitCode {
                                    Text(code == 0 ? "exit 0" : "exit \(code)")
                                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                                        .foregroundStyle(code == 0 ? StepCardPalette.emeraldDone : AntigravityTheme.statusError)
                                } else if (step.status == .inProgress || step.status == .pending) && shouldAnimateLive {
                                    HStack(spacing: 5) {
                                        AntigravityRunningArcIndicatorView(isAnimated: true)
                                            .scaleEffect(0.82)
                                        Text("running")
                                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                                            .foregroundStyle(StepCardPalette.periwinkle)
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
                                        .background(StepCardPalette.codeBlockBg)
                                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(11)
                        .background(StepCardPalette.cardSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
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
                                .foregroundStyle(StepCardPalette.periwinkle)
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
                                    .foregroundStyle(StepCardPalette.emeraldDone)
                            } else if ca.isArtifactFile || ca.fileContent != nil {
                                Image(systemName: "arrow.up.right.square")
                                    .font(.system(size: 12.5, weight: .medium))
                                    .foregroundStyle(StepCardPalette.periwinkle)
                            }
                        }
                        .padding(12)
                        .background(StepCardPalette.cardSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
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
                        .foregroundStyle(StepCardPalette.periwinkle)
                    Text(step.plannerResponse?.response ?? (step.type == .browserSubagent ? "Browser subagent activity" : "Read web page"))
                        .font(.system(size: 13, design: step.type == .readUrlContent ? .monospaced : .default))
                        .foregroundStyle(AntigravityTheme.inkSecondary)
                        .lineLimit(2)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(StepCardPalette.cardSurface)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            default:
                if step.status == .waiting, let reqInt = step.requestedInteraction {
                    if reqInt.kind == .askQuestion {
                        InlineGenericInteractionCardView(store: store, step: step, interaction: reqInt)
                    } else {
                        V233InlineApprovalCardView(store: store, step: step, requested: reqInt)
                    }
                } else if let prose = step.plannerResponse?.response, !prose.isEmpty {
                    AntigravityMarkdownView(markdown: prose, variant: .assistant, store: store)
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("step-prose-\(step.stepIndex)")
                }
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

// MARK: - Antigravity 2.0 (v2.33) Step Cards (Subagent, Workflow, Swarm, MCP, Voice Summary, PR Pills, Extended Approvals)

private struct SubagentStepCardView: View {
    let subagent: SubagentPayload
    let onStop: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "person.2.wave.2.fill")
                    .foregroundStyle(StepCardPalette.periwinkle)
                VStack(alignment: .leading, spacing: 2) {
                    Text(subagent.role)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(AntigravityTheme.inkReading)
                    Text("\(subagent.typeName) · \(subagent.modelLabel)")
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(AntigravityTheme.inkSecondary)
                }
                Spacer()
                Text(subagent.status.displayBadgeText)
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(StepCardPalette.periwinkle.opacity(0.16), in: Capsule())
                    .foregroundStyle(subagent.status == .done ? StepCardPalette.emeraldDone : StepCardPalette.periwinkle)
            }
            if !subagent.summary.isEmpty {
                Text(subagent.summary)
                    .font(.system(size: 12.5))
                    .foregroundStyle(AntigravityTheme.inkLabel)
                    .lineLimit(3)
            }
            if subagent.status == .inProgress || subagent.status == .waiting {
                Button("Stop Subagent", action: onStop)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AntigravityTheme.statusError)
            }
        }
        .padding(12)
        .background(StepCardPalette.cardSurface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AntigravityTheme.glassHairline, lineWidth: 1))
    }
}

private struct DynamicWorkflowStepCardView: View {
    let workflow: DynamicWorkflowPayload
    @State private var showScript: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Dynamic Workflow · \(workflow.currentPhase)", systemImage: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(StepCardPalette.periwinkle)
                Spacer()
                Text("\(workflow.completedAgents)/\(max(1, workflow.totalAgents))")
                    .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(AntigravityTheme.inkSecondary)
            }
            Text(workflow.description)
                .font(.system(size: 13))
                .foregroundStyle(AntigravityTheme.inkReading)
            ForEach(workflow.phases) { phase in
                HStack(spacing: 6) {
                    Image(systemName: phase.isCompleted ? "checkmark.circle.fill" : "circle.dashed")
                        .font(.system(size: 12))
                        .foregroundStyle(phase.isCompleted ? StepCardPalette.emeraldDone : StepCardPalette.periwinkle)
                    Text(phase.name)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(AntigravityTheme.inkLabel)
                }
            }
            if !workflow.pythonScript.isEmpty {
                Button(showScript ? "Hide Python Orchestrator" : "Inspect Python Orchestrator") {
                    showScript.toggle()
                }
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(StepCardPalette.periwinkle)
                if showScript {
                    Text(workflow.pythonScript)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(AntigravityTheme.inkSecondary)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(StepCardPalette.codeBlockBg, in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding(12)
        .background(StepCardPalette.cardSurface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AntigravityTheme.glassHairline, lineWidth: 1))
    }
}

private struct SwarmStepCardView: View {
    let board: SwarmBoardPayload
    let onOpenBoard: () -> Void

    var body: some View {
        Button(action: onOpenBoard) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Agent Swarm · \(board.title)", systemImage: "hexagon.fill")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(StepCardPalette.periwinkle)
                    Spacer()
                    Text("\(board.members.count) specialists")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(AntigravityTheme.inkSecondary)
                }
                HStack(spacing: 6) {
                    ForEach(board.members.prefix(4)) { member in
                        Text("@\(member.name)")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(AntigravityTheme.inkReading)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(AntigravityTheme.surfaceElevated, in: Capsule())
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12))
                        .foregroundStyle(AntigravityTheme.inkMuted)
                }
            }
            .padding(12)
            .background(StepCardPalette.cardSurface, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(AntigravityTheme.glassHairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

private struct McpToolStepCardView: View {
    let mcp: McpToolCallPayload

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "server.rack")
                    .foregroundStyle(mcp.isError ? AntigravityTheme.statusError : StepCardPalette.periwinkle)
                Text("\(mcp.serverName) · \(mcp.toolName)")
                    .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(AntigravityTheme.inkReading)
                Spacer()
                if let plugin = mcp.pluginName {
                    Text(plugin)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(StepCardPalette.periwinkle)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(StepCardPalette.periwinkle.opacity(0.14), in: Capsule())
                }
            }
            if !mcp.argumentsPreview.isEmpty {
                Text(mcp.argumentsPreview)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(AntigravityTheme.inkSecondary)
                    .lineLimit(2)
            }
            if let res = mcp.resultPreview, !res.isEmpty {
                Text(res)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(mcp.isError ? AntigravityTheme.statusError : AntigravityTheme.inkLabel)
                    .lineLimit(3)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(StepCardPalette.codeBlockBg, in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(11)
        .background(StepCardPalette.cardSurface, in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct VoiceCallSummaryCardView: View {
    let summary: VoiceCallTranscriptSummary
    @State private var isExpanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                isExpanded.toggle()
            } label: {
                HStack {
                    Image(systemName: "waveform.circle.fill")
                        .foregroundStyle(StepCardPalette.periwinkle)
                    Text(summary.summaryText)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AntigravityTheme.inkReading)
                        .multilineTextAlignment(.leading)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11))
                        .foregroundStyle(AntigravityTheme.inkMuted)
                }
            }
            .buttonStyle(.plain)
            if isExpanded {
                ForEach(summary.turns) { turn in
                    Text("\(turn.isUser ? "You" : "Gemini"): \(turn.transcript)")
                        .font(.system(size: 12))
                        .foregroundStyle(AntigravityTheme.inkSecondary)
                }
            }
        }
        .padding(11)
        .background(StepCardPalette.cardSurface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(StepCardPalette.periwinkle.opacity(0.25), lineWidth: 1))
    }
}

private struct GitHubPRStatusPillsRow: View {
    let pullRequests: [GitHubPullRequestInfo]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(pullRequests) { pr in
                    if let url = URL(string: pr.url) {
                        Link(destination: url) {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.triangle.pull")
                                    .font(.system(size: 11, weight: .semibold))
                                Text("\(pr.ownerRepo) #\(pr.number)")
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                Text(pr.state.rawValue.uppercased())
                                    .font(.system(size: 9.5, weight: .bold))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(StepCardPalette.emeraldDone.opacity(0.18), in: Capsule())
                            }
                            .foregroundStyle(StepCardPalette.emeraldDone)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(StepCardPalette.cardSurface, in: Capsule())
                            .overlay(Capsule().stroke(StepCardPalette.emeraldDone.opacity(0.32), lineWidth: 1))
                        }
                    }
                }
            }
        }
    }
}

private struct V233InlineApprovalCardView: View {
    let store: AntigravitySessionStore
    let step: CascadeStep
    let requested: RequestedInteraction

    private var titleAndDetail: (String, String, Bool) {
        switch requested.kind {
        case .executeUrl:
            let domain = requested.executeUrl?.domain ?? "external site"
            let url = requested.executeUrl?.url ?? ""
            return ("Browser Action Approval · \(domain)", url, true)
        case .downloadUrl:
            let file = requested.downloadUrl?.fileName ?? "file"
            let origin = requested.downloadUrl?.origin ?? ""
            return ("Browser Download · \(file)", "From \(origin) → \(requested.downloadUrl?.destinationFolder ?? "~/Downloads")", true)
        case .browserUpload:
            let files = requested.browserUpload?.fileNames.joined(separator: ", ") ?? "files"
            return ("One-Time Upload Confirmation", "Upload \(files) to \(requested.browserUpload?.origin ?? "site")", false)
        case .workflowScript:
            return ("Approve Dynamic Workflow Script", requested.workflowScript?.title ?? "Python orchestrator script", false)
        case .mcp:
            return ("MCP Tool Approval · \(requested.mcpServerName ?? "Server")", "Invoke \(requested.mcpToolName ?? "tool")", true)
        case .permission:
            let action = requested.permission?.action ?? "action"
            let target = requested.permission?.target ?? "*"
            let plugin = requested.permission?.pluginName.map { " [\($0)]" } ?? ""
            return ("Permission Request\(plugin)", "\(action)(\(target))", true)
        default:
            return ("Approval Required", requested.filePermission?.absolutePathUri ?? "Confirm pending agent action", true)
        }
    }

    var body: some View {
        let info = titleAndDetail
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.shield.fill")
                    .foregroundStyle(AntigravityTheme.statusWaiting)
                Text(info.0)
                    .font(.system(size: 13.5, weight: .bold))
                    .foregroundStyle(AntigravityTheme.inkReading)
            }
            Text(info.1)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(AntigravityTheme.inkSecondary)
                .lineLimit(3)

            HStack(spacing: 8) {
                Button("Allow Once") {
                    store.resolveWaitingStep(stepIndex: step.stepIndex, decision: .allowOnce)
                }
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(AntigravityTheme.inkOnPrimaryCTA)
                .frame(maxWidth: .infinity, minHeight: 38)
                .background(AntigravityTheme.statusWaiting, in: RoundedRectangle(cornerRadius: 10))

                if info.2 {
                    Button("In Chat") {
                        store.resolveWaitingStep(stepIndex: step.stepIndex, decision: .allowInConversation)
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AntigravityTheme.inkReading)
                    .padding(.horizontal, 10)
                    .frame(minHeight: 38)
                    .background(AntigravityTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: 10))

                    Button("Always") {
                        store.resolveWaitingStep(stepIndex: step.stepIndex, decision: .alwaysAllow)
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(StepCardPalette.periwinkle)
                    .padding(.horizontal, 10)
                    .frame(minHeight: 38)
                    .background(StepCardPalette.periwinkle.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
                }

                Button("Deny") {
                    store.resolveWaitingStep(stepIndex: step.stepIndex, decision: .reject)
                }
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(AntigravityTheme.statusError)
                .padding(.horizontal, 12)
                .frame(minHeight: 38)
                .background(AntigravityTheme.statusError.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(12)
        .background(StepCardPalette.cardSurface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AntigravityTheme.statusWaiting.opacity(0.45), lineWidth: 1))
    }
}

private struct InlineGenericInteractionCardView: View {
    @Bindable var store: AntigravitySessionStore
    let step: CascadeStep
    let interaction: RequestedInteraction

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: interaction.kind == .askQuestion ? "questionmark.bubble.fill" : "hand.raised.fill")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(StepCardPalette.warmAmber)
                Text(interaction.kind == .askQuestion ? "Agent needs your input" : "Permission required")
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(StepCardPalette.warmAmber)
                Spacer()
            }

            if let qa = interaction.askQuestion {
                Text(qa.question)
                    .font(.system(size: 13.5))
                    .foregroundStyle(AntigravityTheme.inkReading)
                Button {
                    store.presentedSheet = .askQuestion(stepIndex: step.stepIndex)
                } label: {
                    Text("Review & Answer")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(StepCardPalette.inkOnCTA)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(StepCardPalette.warmAmber)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            } else {
                let targetText = interaction.filePermission?.absolutePathUri
                    ?? interaction.permission?.target
                    ?? "Workspace action"
                Text(targetText)
                    .font(.system(size: 12.5, design: .monospaced))
                    .foregroundStyle(AntigravityTheme.inkLabel)
                    .lineLimit(3)
                HStack(spacing: 10) {
                    Button {
                        store.resolveWaitingStep(stepIndex: step.stepIndex, decision: .reject)
                    } label: {
                        Text("Deny")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AntigravityTheme.inkReading)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(StepCardPalette.neutralButtonBg)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Button {
                        store.resolveWaitingStep(stepIndex: step.stepIndex, decision: .allowOnce)
                    } label: {
                        Text("Allow Once")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(StepCardPalette.inkOnCTA)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(StepCardPalette.warmAmber)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .background(StepCardPalette.amberCardSurface)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(StepCardPalette.warmAmber.opacity(0.30), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

// MARK: - Referenced Artifact / File Pills

private struct ReferencedFilePillsRow: View {
    let paths: [String]
    let onTap: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(paths, id: \.self) { rawPath in
                    Button {
                        onTap(rawPath)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: iconName(for: rawPath))
                                .font(.system(size: 11, weight: .semibold))
                            Text(MarkdownLinkFormatting.shortFileBadge(rawPath))
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .lineLimit(1)
                        }
                        .foregroundStyle(StepCardPalette.periwinkle)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(StepCardPalette.periwinkle.opacity(0.12))
                        .overlay(
                            Capsule()
                                .stroke(StepCardPalette.periwinkle.opacity(0.26), lineWidth: 1)
                        )
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func iconName(for rawPath: String) -> String {
        let lower = rawPath.lowercased()
        if lower.hasSuffix(".html") || lower.hasSuffix(".htm") { return "sparkles.rectangle.stack" }
        if lower.hasSuffix(".png") || lower.hasSuffix(".jpg") || lower.hasSuffix(".webp") || lower.hasSuffix(".svg") { return "photo" }
        if lower.hasSuffix(".md") { return "doc.richtext" }
        return "doc.text"
    }
}

// MARK: - Native Matte Obsidian Universal Markdown + Rich Embed Renderer (`AntigravityMarkdownView`)

public enum MarkdownRenderVariant: Sendable, Equatable {
    case assistant
    case userBubble
    case thought
    case blockquote

    var baseFontSize: CGFloat {
        switch self {
        case .assistant: return 15.5
        case .userBubble: return 15.0
        case .thought: return 13.0
        case .blockquote: return 14.5
        }
    }

    var textColor: Color {
        switch self {
        case .assistant, .userBubble:
            return AntigravityTheme.inkReading
        case .thought:
            return AntigravityTheme.inkSecondary
        case .blockquote:
            return AntigravityTheme.inkLabel
        }
    }

    var lineSpacing: CGFloat {
        switch self {
        case .assistant: return 4.0
        case .userBubble: return 2.8
        case .thought: return 2.8
        case .blockquote: return 3.2
        }
    }

    var blockSpacing: CGFloat {
        switch self {
        case .assistant: return 9.0
        case .userBubble: return 6.0
        case .thought: return 6.0
        case .blockquote: return 6.0
        }
    }

    var expandsParagraphWidth: Bool {
        self != .userBubble
    }
}

public struct AntigravityMarkdownView: View {
    public let markdown: String
    public let variant: MarkdownRenderVariant
    public let store: AntigravitySessionStore?

    @State private var copiedRefLabel: String? = nil
    @State private var copyGeneration: Int = 0
    @State private var inspectedArtifactURI: String? = nil

    public init(
        markdown: String,
        variant: MarkdownRenderVariant = .assistant,
        store: AntigravitySessionStore? = nil
    ) {
        self.markdown = markdown
        self.variant = variant
        self.store = store
    }

    public var body: some View {
        let blocks = AntigravityMarkdownParser.parse(markdown)
        VStack(alignment: .leading, spacing: 6) {
            if blocks.isEmpty {
                Text(markdown)
                    .font(.system(size: variant.baseFontSize))
                    .foregroundStyle(variant.textColor)
                    .lineSpacing(variant.lineSpacing)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            } else {
                AntigravityMarkdownBlocksView(blocks: blocks, variant: variant, store: store)
            }

            if let copiedRefLabel {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(StepCardPalette.emeraldDone)
                    Text("Copied \(copiedRefLabel)")
                        .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(AntigravityTheme.inkLabel)
                        .lineLimit(1)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(AntigravityTheme.surfaceElevated)
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )
                .clipShape(Capsule())
                .transition(.opacity)
            }
        }
        .tint(StepCardPalette.periwinkle)
        .environment(\.openURL, OpenURLAction { url in
            if url.scheme == "antigravity-ref" {
                let targetRef = MarkdownLinkFormatting.extractCopiedReference(from: url)
                let shortBadge = MarkdownLinkFormatting.shortFileBadge(targetRef)
                let isPreviewableArtifact = ResolvedEmbedResource.isEmbeddableTextArtifactPath(targetRef)
                    || MarkdownEmbedKind.detect(from: targetRef) == .image
                let lowerRef = targetRef.lowercased()
                let isInteractiveDoc = lowerRef.hasSuffix(".html") || lowerRef.hasSuffix(".htm") || lowerRef.hasSuffix(".svg")
                Task { @MainActor in
                    if isPreviewableArtifact,
                       let store,
                       (store.cachedEmbedResource(for: targetRef) != nil || isInteractiveDoc) {
                        inspectedArtifactURI = targetRef
                        return
                    }
                    MarkdownClipboardHelper.copyText(targetRef)
                    copyGeneration += 1
                    let currentGen = copyGeneration
                    withAnimation(.easeInOut(duration: 0.16)) {
                        copiedRefLabel = shortBadge
                    }
                    try? await Task.sleep(for: .seconds(1.8))
                    if copyGeneration == currentGen {
                        withAnimation(.easeInOut(duration: 0.16)) {
                            copiedRefLabel = nil
                        }
                    }
                }
                return .handled
            }
            return .systemAction
        })
        .sheet(
            isPresented: Binding(
                get: { inspectedArtifactURI != nil },
                set: { if !$0 { inspectedArtifactURI = nil } }
            )
        ) {
            if let uri = inspectedArtifactURI {
                RemoteArtifactPreviewSheet(uri: uri, store: store)
            }
        }
    }
}

private struct AntigravityMarkdownBlocksView: View {
    let blocks: [MarkdownBlock]
    let variant: MarkdownRenderVariant
    let store: AntigravitySessionStore?

    var body: some View {
        VStack(alignment: .leading, spacing: variant.blockSpacing) {
            ForEach(blocks) { block in
                blockView(for: block)
            }
        }
    }

    @ViewBuilder
    private func blockView(for block: MarkdownBlock) -> some View {
        switch block {
        case .frontmatter(_, let entries):
            VStack(alignment: .leading, spacing: 4) {
                Text("FRONTMATTER")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(StepCardPalette.periwinkle)
                ForEach(entries) { entry in
                    HStack(alignment: .top, spacing: 8) {
                        Text(entry.key)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(AntigravityTheme.inkSecondary)
                        Text(entry.value)
                            .font(.system(size: 12))
                            .foregroundStyle(AntigravityTheme.inkReading)
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(StepCardPalette.cardSurface, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(AntigravityTheme.glassHairline, lineWidth: 1))

        case .heading(_, let level, let inlines):
            let size = headingFontSize(for: level)
            let weight: Font.Weight = level <= 2 ? .bold : .semibold
            let color = level <= 4 ? AntigravityTheme.inkReading : AntigravityTheme.inkLabel
            RichMarkdownInlineBlockView(
                inlines: inlines,
                baseSize: size,
                baseWeight: weight,
                defaultColor: color,
                lineSpacing: 2.5,
                expandsToProposedWidth: variant.expandsParagraphWidth
            )
            .padding(.top, level <= 2 ? 4 : 2)

        case .paragraph(_, let inlines):
            RichMarkdownInlineBlockView(
                inlines: inlines,
                baseSize: variant.baseFontSize,
                baseWeight: .regular,
                defaultColor: variant.textColor,
                lineSpacing: variant.lineSpacing,
                expandsToProposedWidth: variant.expandsParagraphWidth
            )

        case .listItem(_, let indentLevel, let marker, let inlines):
            let firstLineHeight = ceil(variant.baseFontSize * 1.32)
            HStack(alignment: .top, spacing: 7) {
                listMarkerView(marker: marker, indentLevel: indentLevel)
                    .frame(height: firstLineHeight, alignment: .center)
                    .padding(.top, 2)
                RichMarkdownInlineBlockView(
                    inlines: inlines,
                    baseSize: variant.baseFontSize,
                    baseWeight: .regular,
                    defaultColor: isCompletedTask(marker) ? AntigravityTheme.inkSecondary : variant.textColor,
                    lineSpacing: max(2.0, variant.lineSpacing - 0.5),
                    expandsToProposedWidth: variant.expandsParagraphWidth
                )
            }
            .padding(.leading, CGFloat(indentLevel) * 16)

        case .codeBlock(_, let language, let code):
            VStack(alignment: .leading, spacing: 4) {
                if block.isSVGDiagram {
                    HStack(spacing: 6) {
                        Image(systemName: "scribble.variable")
                            .font(.system(size: 11, weight: .semibold))
                        Text("SVG Graphic")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(StepCardPalette.periwinkle)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(StepCardPalette.periwinkle.opacity(0.14), in: Capsule())
                }
                MarkdownCodeBlockCardView(language: language, code: code)
            }

        case .blockquote(_, let alert, let innerBlocks):
            MarkdownBlockquoteCardView(alert: alert, innerBlocks: innerBlocks, store: store)

        case .table(_, let headers, let alignments, let rows):
            MarkdownTableCardView(headers: headers, alignments: alignments, rows: rows)

        case .thematicBreak:
            Rectangle()
                .fill(Color.white.opacity(0.09))
                .frame(height: 1)
                .padding(.vertical, 4)

        case .mathBlock(_, let latex):
            MarkdownMathBlockCardView(latex: latex)

        case .agentEmbed(_, let src, let title, let kind, _, let isStreamingIncomplete):
            MarkdownAgentEmbedCardView(
                src: src,
                explicitTitle: title,
                kind: kind,
                isStreamingIncomplete: isStreamingIncomplete,
                store: store
            )

        case .pluginCard(_, let catalogId, let title):
            MarkdownPluginCardView(catalogId: catalogId, explicitTitle: title)

        case .image(_, let alt, let src, let title):
            MarkdownImageBlockView(alt: alt, src: src, title: title, store: store)

        case .details(_, let summary, let innerBlocks, let isOpenByDefault):
            MarkdownDetailsCardView(
                summary: summary,
                innerBlocks: innerBlocks,
                isOpenByDefault: isOpenByDefault,
                store: store
            )

        case .carousel(_, let slides):
            MarkdownCarouselCardView(slides: slides, variant: variant, store: store)

        case .mermaid(_, let source):
            MarkdownMermaidCardView(source: source)

        case .footnoteSection(_, let items):
            MarkdownFootnoteSectionView(items: items)
        }
    }

    private func headingFontSize(for level: Int) -> CGFloat {
        switch level {
        case 1: return variant == .thought ? 15.5 : 19.5
        case 2: return variant == .thought ? 14.5 : 17.5
        case 3: return variant == .thought ? 14.0 : 16.0
        case 4: return variant == .thought ? 13.5 : 15.2
        default: return variant == .thought ? 13.0 : 14.5
        }
    }

    private func isCompletedTask(_ marker: MarkdownListMarker) -> Bool {
        if case .task(let checked) = marker {
            return checked
        }
        return false
    }

    @ViewBuilder
    private func listMarkerView(marker: MarkdownListMarker, indentLevel: Int) -> some View {
        switch marker {
        case .bullet:
            let symbol = indentLevel == 0 ? "•" : (indentLevel == 1 ? "◦" : "▪")
            Text(symbol)
                .font(.system(size: variant.baseFontSize, weight: .bold))
                .foregroundStyle(indentLevel == 0 ? StepCardPalette.periwinkle : AntigravityTheme.inkSecondary)
                .frame(minWidth: 12, alignment: .center)

        case .ordered(let number):
            Text("\(number).")
                .font(.system(size: max(12.5, variant.baseFontSize - 1.0), weight: .semibold, design: .monospaced))
                .foregroundStyle(StepCardPalette.periwinkle)
                .frame(minWidth: 20, alignment: .trailing)

        case .task(let checked):
            Image(systemName: checked ? "checkmark.square.fill" : "square")
                .font(.system(size: max(13.0, variant.baseFontSize - 1.5), weight: .medium))
                .foregroundStyle(checked ? StepCardPalette.emeraldDone : AntigravityTheme.inkSecondary)
                .frame(minWidth: 16, alignment: .center)
        }
    }
}

// MARK: - TextKit Rounded Inline Code Pill Renderer (`RichMarkdownInlineBlockView`)
// Eliminates U+200A hair-space line-wrap orphan boxes, renders crisp rounded pills with
// subtle borders, supports true iOS range selection & clean copy, and routes link taps via `openURL`.

private struct RichMarkdownInlineBlockView: View {
    let inlines: [MarkdownInline]
    let baseSize: CGFloat
    let baseWeight: Font.Weight
    let defaultColor: Color
    let lineSpacing: CGFloat
    let textAlignment: TextAlignment
    let expandsToProposedWidth: Bool

    init(
        inlines: [MarkdownInline],
        baseSize: CGFloat,
        baseWeight: Font.Weight,
        defaultColor: Color,
        lineSpacing: CGFloat,
        textAlignment: TextAlignment = .leading,
        expandsToProposedWidth: Bool = true
    ) {
        self.inlines = inlines
        self.baseSize = baseSize
        self.baseWeight = baseWeight
        self.defaultColor = defaultColor
        self.lineSpacing = lineSpacing
        self.textAlignment = textAlignment
        self.expandsToProposedWidth = expandsToProposedWidth
    }

    var body: some View {
        #if canImport(UIKit)
        RichMarkdownTextViewRepresentable(
            inlines: inlines,
            baseSize: baseSize,
            baseWeight: baseWeight,
            defaultColor: defaultColor,
            lineSpacing: lineSpacing,
            textAlignment: textAlignment,
            expandsToProposedWidth: expandsToProposedWidth
        )
        #else
        Text(
            MarkdownInlineBuilder.build(
                inlines,
                baseSize: baseSize,
                baseWeight: baseWeight,
                defaultColor: defaultColor
            )
        )
        .multilineTextAlignment(textAlignment)
        .lineSpacing(lineSpacing)
        .fixedSize(horizontal: false, vertical: true)
        .textSelection(.enabled)
        #endif
    }
}

#if canImport(UIKit)
private extension NSAttributedString.Key {
    static let agyInlinePillStyle = NSAttributedString.Key("dev.antigravity.inlinePillStyle")
}

private final class InlinePillVisualStyle: NSObject, @unchecked Sendable {
    let fillColor: UIColor
    let borderColor: UIColor
    let cornerRadius: CGFloat
    let leftOutset: CGFloat
    let rightOutset: CGFloat
    let verticalOutset: CGFloat
    let borderWidth: CGFloat

    init(
        fillColor: UIColor,
        borderColor: UIColor,
        cornerRadius: CGFloat = 5.0,
        leftOutset: CGFloat = 2.6,
        rightOutset: CGFloat = 2.6,
        verticalOutset: CGFloat = 0.8,
        borderWidth: CGFloat = 0.75
    ) {
        self.fillColor = fillColor
        self.borderColor = borderColor
        self.cornerRadius = cornerRadius
        self.leftOutset = leftOutset
        self.rightOutset = rightOutset
        self.verticalOutset = verticalOutset
        self.borderWidth = borderWidth
        super.init()
    }
}

/// Custom `NSLayoutManager` that draws crisp rounded-pill backgrounds strictly around visible
/// non-whitespace glyphs of inline code, `<kbd>` keys, and `<mark>` highlights — mathematically
/// preventing orphaned background rectangles on line wraps without injecting fake space characters.
private final class InlineCodePillLayoutManager: NSLayoutManager {
    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        guard let storage = textStorage, let container = textContainers.first else { return }

        let visibleCharRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        guard visibleCharRange.location != NSNotFound, visibleCharRange.length > 0 else { return }

        let fullString = storage.string as NSString
        storage.enumerateAttribute(.agyInlinePillStyle, in: visibleCharRange, options: []) { value, attrRange, _ in
            guard let pillStyle = value as? InlinePillVisualStyle, attrRange.length > 0 else { return }

            // Trim any leading/trailing whitespace or newlines in the run so wrapped spaces never paint orphan boxes
            var start = attrRange.location
            var end = attrRange.location + attrRange.length
            let wsSet = CharacterSet.whitespacesAndNewlines
            while start < end, let scalar = UnicodeScalar(fullString.character(at: start)), wsSet.contains(scalar) {
                start += 1
            }
            while end > start, let scalar = UnicodeScalar(fullString.character(at: end - 1)), wsSet.contains(scalar) {
                end -= 1
            }
            guard end > start else { return }

            let trimmedCharRange = NSRange(location: start, length: end - start)
            let pillGlyphRange = glyphRange(forCharacterRange: trimmedCharRange, actualCharacterRange: nil)
            guard pillGlyphRange.length > 0 else { return }

            enumerateEnclosingRects(
                forGlyphRange: pillGlyphRange,
                withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
                in: container
            ) { rect, _ in
                guard rect.width > 1.0, rect.height > 1.0 else { return }
                let shifted = rect.offsetBy(dx: origin.x, dy: origin.y)
                let minX = shifted.minX - pillStyle.leftOutset
                let maxX = shifted.maxX + pillStyle.rightOutset
                let pillRect = CGRect(
                    x: minX,
                    y: shifted.minY - pillStyle.verticalOutset,
                    width: max(1.0, maxX - minX),
                    height: shifted.height + pillStyle.verticalOutset * 2.0
                )
                let path = UIBezierPath(roundedRect: pillRect, cornerRadius: pillStyle.cornerRadius)
                pillStyle.fillColor.setFill()
                path.fill()
                if pillStyle.borderWidth > 0 {
                    pillStyle.borderColor.setStroke()
                    path.lineWidth = pillStyle.borderWidth
                    path.stroke()
                }
            }
        }
    }
}

private final class RichMarkdownUITextView: UITextView {
    let pillLayoutManager: InlineCodePillLayoutManager

    init() {
        let storage = NSTextStorage()
        let layoutMgr = InlineCodePillLayoutManager()
        let container = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = false
        container.lineFragmentPadding = 0
        layoutMgr.addTextContainer(container)
        storage.addLayoutManager(layoutMgr)
        self.pillLayoutManager = layoutMgr

        super.init(frame: .zero, textContainer: container)

        backgroundColor = .clear
        isOpaque = false
        isEditable = false
        isSelectable = true
        isScrollEnabled = false
        clipsToBounds = false
        textContainerInset = UIEdgeInsets(top: 2, left: 0, bottom: 2, right: 0)
        dataDetectorTypes = []
        adjustsFontForContentSizeCategory = false
        linkTextAttributes = [
            .foregroundColor: UIColor(red: 0x8E / 255.0, green: 0xB4 / 255.0, blue: 0xFF / 255.0, alpha: 1.0)
        ]
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        setContentHuggingPriority(.required, for: .vertical)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let horizontalInset = textContainerInset.left + textContainerInset.right
        let targetWidth = max(1.0, bounds.width - horizontalInset)
        if abs(textContainer.size.width - targetWidth) > 0.5 {
            textContainer.size = CGSize(width: targetWidth, height: CGFloat.greatestFiniteMagnitude)
            pillLayoutManager.ensureLayout(for: textContainer)
            setNeedsDisplay()
        }
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let horizontalInset = textContainerInset.left + textContainerInset.right
        let verticalInset = textContainerInset.top + textContainerInset.bottom
        let availableWidth: CGFloat
        if size.width.isFinite && size.width > horizontalInset {
            availableWidth = size.width - horizontalInset
        } else {
            availableWidth = CGFloat.greatestFiniteMagnitude
        }
        let previousSize = textContainer.size
        defer {
            if bounds.width > horizontalInset + 1 {
                textContainer.size = CGSize(width: bounds.width - horizontalInset, height: CGFloat.greatestFiniteMagnitude)
            } else {
                textContainer.size = previousSize
            }
        }
        textContainer.size = CGSize(width: availableWidth, height: CGFloat.greatestFiniteMagnitude)
        pillLayoutManager.ensureLayout(for: textContainer)
        let usedRect = pillLayoutManager.usedRect(for: textContainer)
        let finalWidth = min(availableWidth, ceil(usedRect.width)) + horizontalInset
        let finalHeight = ceil(usedRect.height) + verticalInset
        return CGSize(width: max(1.0, finalWidth), height: max(1.0, finalHeight))
    }
}

private struct RichMarkdownTextViewRepresentable: UIViewRepresentable {
    let inlines: [MarkdownInline]
    let baseSize: CGFloat
    let baseWeight: Font.Weight
    let defaultColor: Color
    let lineSpacing: CGFloat
    let textAlignment: TextAlignment
    let expandsToProposedWidth: Bool

    @Environment(\.openURL) private var openURL

    struct RenderKey: Equatable {
        let inlines: [MarkdownInline]
        let baseSize: CGFloat
        let weightTag: Int
        let colorHex: UInt32
        let lineSpacing: CGFloat
        let alignmentTag: Int
    }

    private var currentRenderKey: RenderKey {
        RenderKey(
            inlines: inlines,
            baseSize: baseSize,
            weightTag: UIKitInlineAttributedBuilder.weightTag(baseWeight),
            colorHex: UIKitInlineAttributedBuilder.colorSignature(defaultColor),
            lineSpacing: lineSpacing,
            alignmentTag: UIKitInlineAttributedBuilder.alignmentTag(textAlignment)
        )
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onOpenURL: { url in
            openURL(url)
        })
    }

    func makeUIView(context: Context) -> RichMarkdownUITextView {
        let textView = RichMarkdownUITextView()
        textView.delegate = context.coordinator
        let attributed = UIKitInlineAttributedBuilder.build(
            inlines,
            baseSize: baseSize,
            baseWeight: baseWeight,
            defaultColor: defaultColor,
            lineSpacing: lineSpacing,
            textAlignment: textAlignment
        )
        textView.attributedText = attributed
        context.coordinator.lastRenderKey = currentRenderKey
        return textView
    }

    func updateUIView(_ uiView: RichMarkdownUITextView, context: Context) {
        context.coordinator.onOpenURL = { url in
            openURL(url)
        }
        let key = currentRenderKey
        if context.coordinator.lastRenderKey != key {
            uiView.attributedText = UIKitInlineAttributedBuilder.build(
                inlines,
                baseSize: baseSize,
                baseWeight: baseWeight,
                defaultColor: defaultColor,
                lineSpacing: lineSpacing,
                textAlignment: textAlignment
            )
            context.coordinator.lastRenderKey = key
            uiView.invalidateIntrinsicContentSize()
            uiView.setNeedsDisplay()
        }
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: RichMarkdownUITextView,
        context: Context
    ) -> CGSize? {
        let proposedW = proposal.width
        if let proposedW, proposedW.isFinite && proposedW > 0 {
            let measured = uiView.sizeThatFits(CGSize(width: proposedW, height: CGFloat.greatestFiniteMagnitude))
            let finalW = expandsToProposedWidth ? proposedW : min(proposedW, ceil(measured.width))
            return CGSize(width: finalW, height: ceil(measured.height))
        }
        let measured = uiView.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
        return CGSize(width: ceil(measured.width), height: ceil(measured.height))
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        var onOpenURL: @MainActor (URL) -> Void
        var lastRenderKey: RenderKey?

        init(onOpenURL: @escaping @MainActor (URL) -> Void) {
            self.onOpenURL = onOpenURL
        }

        func textView(
            _ textView: UITextView,
            primaryActionFor textItem: UITextItem,
            defaultAction: UIAction
        ) -> UIAction? {
            if case .link(let url) = textItem.content {
                return UIAction { [weak self] _ in
                    self?.onOpenURL(url)
                }
            }
            return defaultAction
        }
    }
}

private enum UIKitInlineAttributedBuilder {
    private static let periwinkleUI = UIColor(red: 0x8E / 255.0, green: 0xB4 / 255.0, blue: 0xFF / 255.0, alpha: 1.0)
    private static let inlineCodeInkUI = UIColor(red: 0xDC / 255.0, green: 0xE6 / 255.0, blue: 0xFF / 255.0, alpha: 1.0)
    private static let warmAmberUI = UIColor(red: 0xEB / 255.0, green: 0xB3 / 255.0, blue: 0x65 / 255.0, alpha: 1.0)

    private struct StyleState {
        var isBold: Bool = false
        var isItalic: Bool = false
        var isStrikethrough: Bool = false
        var isUnderline: Bool = false
        var isHighlight: Bool = false
        var isCode: Bool = false
        var isKeyboardKey: Bool = false
        var isMath: Bool = false
        var isSuperscript: Bool = false
        var isSubscript: Bool = false
        var baseWeight: UIFont.Weight = .regular
        var linkDestination: String? = nil

        func resolvedFont(baseSize: CGFloat) -> UIFont {
            if isKeyboardKey {
                return UIFont.monospacedSystemFont(ofSize: max(11.0, baseSize - 2.5), weight: .semibold)
            }
            if isCode {
                let codeSize = max(11.5, baseSize - 1.7)
                let codeWeight: UIFont.Weight = isBold ? .semibold : .medium
                return UIFont.monospacedSystemFont(ofSize: codeSize, weight: codeWeight)
            }
            if isSuperscript || isSubscript {
                return UIFont.systemFont(ofSize: max(10.0, baseSize * 0.72), weight: isBold ? .semibold : .medium)
            }
            if isMath {
                let mathSize = max(12.5, baseSize - 0.5)
                let base = UIFont.systemFont(ofSize: mathSize, weight: isBold ? .semibold : .regular)
                if let serifDesc = base.fontDescriptor.withDesign(.serif),
                   let italicDesc = serifDesc.withSymbolicTraits(.traitItalic) {
                    return UIFont(descriptor: italicDesc, size: mathSize)
                }
                return UIFont.italicSystemFont(ofSize: mathSize)
            }
            let weight: UIFont.Weight = isBold ? .bold : baseWeight
            let base = UIFont.systemFont(ofSize: baseSize, weight: weight)
            if isItalic {
                var traits = base.fontDescriptor.symbolicTraits
                traits.insert(.traitItalic)
                if let italicDesc = base.fontDescriptor.withSymbolicTraits(traits) {
                    return UIFont(descriptor: italicDesc, size: baseSize)
                }
                return UIFont.italicSystemFont(ofSize: baseSize)
            }
            return base
        }

        func resolvedForeground(defaultUI: UIColor) -> UIColor {
            if linkDestination != nil {
                return UIKitInlineAttributedBuilder.periwinkleUI
            }
            if isKeyboardKey {
                return UIColor(white: 0.94, alpha: 1.0)
            }
            if isCode || isMath {
                return UIKitInlineAttributedBuilder.inlineCodeInkUI
            }
            if isHighlight {
                return UIColor(red: 0xFF / 255.0, green: 0xF3 / 255.0, blue: 0xD6 / 255.0, alpha: 1.0)
            }
            return defaultUI
        }

        func resolvedPillStyle(tightLeading: Bool, tightTrailing: Bool) -> InlinePillVisualStyle? {
            if isKeyboardKey {
                return InlinePillVisualStyle(
                    fillColor: UIColor(red: 0x1D / 255.0, green: 0x1F / 255.0, blue: 0x26 / 255.0, alpha: 1.0),
                    borderColor: UIColor.white.withAlphaComponent(0.22),
                    cornerRadius: 5.0,
                    leftOutset: tightLeading ? 2.0 : 3.2,
                    rightOutset: tightTrailing ? 2.0 : 3.2,
                    verticalOutset: 1.0,
                    borderWidth: 1.0
                )
            }
            if isCode {
                if linkDestination != nil {
                    return InlinePillVisualStyle(
                        fillColor: UIKitInlineAttributedBuilder.periwinkleUI.withAlphaComponent(0.14),
                        borderColor: UIKitInlineAttributedBuilder.periwinkleUI.withAlphaComponent(0.26),
                        cornerRadius: 5.0,
                        leftOutset: tightLeading ? 1.8 : 2.6,
                        rightOutset: tightTrailing ? 1.8 : 2.6,
                        verticalOutset: 0.8,
                        borderWidth: 0.75
                    )
                }
                return InlinePillVisualStyle(
                    fillColor: UIColor.white.withAlphaComponent(0.085),
                    borderColor: UIColor.white.withAlphaComponent(0.09),
                    cornerRadius: 5.0,
                    leftOutset: tightLeading ? 1.8 : 2.6,
                    rightOutset: tightTrailing ? 1.8 : 2.6,
                    verticalOutset: 0.8,
                    borderWidth: 0.75
                )
            }
            if isHighlight {
                return InlinePillVisualStyle(
                    fillColor: UIKitInlineAttributedBuilder.warmAmberUI.withAlphaComponent(0.22),
                    borderColor: UIKitInlineAttributedBuilder.warmAmberUI.withAlphaComponent(0.32),
                    cornerRadius: 4.0,
                    leftOutset: 1.6,
                    rightOutset: 1.6,
                    verticalOutset: 0.5,
                    borderWidth: 0.0
                )
            }
            return nil
        }
    }

    static func build(
        _ nodes: [MarkdownInline],
        baseSize: CGFloat,
        baseWeight: Font.Weight,
        defaultColor: Color,
        lineSpacing: CGFloat,
        textAlignment: TextAlignment
    ) -> NSAttributedString {
        let output = NSMutableAttributedString()
        let defaultUI = UIColor(defaultColor)
        let initial = StyleState(baseWeight: uiFontWeight(baseWeight))
        appendNodes(nodes, style: initial, baseSize: baseSize, defaultUI: defaultUI, into: output)

        // Apply subtle kerning before tight inline code/kbd pills so adjacent CJK/Latin never collides with pill outset
        applyTightPillSpacingKerns(on: output)

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = lineSpacing
        paragraphStyle.lineBreakMode = .byWordWrapping
        paragraphStyle.alignment = nsAlignment(textAlignment)
        if output.length > 0 {
            output.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: output.length))
        }
        return output
    }

    private static func appendNodes(
        _ nodes: [MarkdownInline],
        style: StyleState,
        baseSize: CGFloat,
        defaultUI: UIColor,
        into output: NSMutableAttributedString
    ) {
        for (idx, node) in nodes.enumerated() {
            switch node {
            case .text(let s):
                output.append(makeSegment(s, style: style, baseSize: baseSize, defaultUI: defaultUI, tightLeading: false, tightTrailing: false))

            case .softBreak:
                output.append(makeSegment("\n", style: style, baseSize: baseSize, defaultUI: defaultUI, tightLeading: false, tightTrailing: false))

            case .code(let codeText):
                guard !codeText.isEmpty else { continue }
                var codeStyle = style
                codeStyle.isCode = true
                let prevChar = lastCharacter(of: output)
                let nextChar = firstCharacter(of: idx + 1 < nodes.count ? nodes[idx + 1] : nil)
                let tightLead = prevChar.map { !$0.isWhitespace } ?? false
                let tightTrail = nextChar.map { !$0.isWhitespace } ?? false
                // Pure code text — ZERO injected U+200A padding spaces!
                output.append(makeSegment(codeText, style: codeStyle, baseSize: baseSize, defaultUI: defaultUI, tightLeading: tightLead, tightTrailing: tightTrail))

            case .keyboardKey(let keyText):
                guard !keyText.isEmpty else { continue }
                var kbdStyle = style
                kbdStyle.isKeyboardKey = true
                let prevChar = lastCharacter(of: output)
                let nextChar = firstCharacter(of: idx + 1 < nodes.count ? nodes[idx + 1] : nil)
                let tightLead = prevChar.map { !$0.isWhitespace } ?? false
                let tightTrail = nextChar.map { !$0.isWhitespace } ?? false
                output.append(makeSegment(keyText, style: kbdStyle, baseSize: baseSize, defaultUI: defaultUI, tightLeading: tightLead, tightTrailing: tightTrail))

            case .strong(let children):
                var boldStyle = style
                boldStyle.isBold = true
                appendNodes(children, style: boldStyle, baseSize: baseSize, defaultUI: defaultUI, into: output)

            case .emphasis(let children):
                var italicStyle = style
                italicStyle.isItalic = true
                appendNodes(children, style: italicStyle, baseSize: baseSize, defaultUI: defaultUI, into: output)

            case .strikethrough(let children):
                var strikeStyle = style
                strikeStyle.isStrikethrough = true
                appendNodes(children, style: strikeStyle, baseSize: baseSize, defaultUI: defaultUI, into: output)

            case .underline(let children):
                var underStyle = style
                underStyle.isUnderline = true
                appendNodes(children, style: underStyle, baseSize: baseSize, defaultUI: defaultUI, into: output)

            case .highlight(let children):
                var hiStyle = style
                hiStyle.isHighlight = true
                appendNodes(children, style: hiStyle, baseSize: baseSize, defaultUI: defaultUI, into: output)

            case .superscript(let text):
                var supStyle = style
                supStyle.isSuperscript = true
                output.append(makeSegment(text, style: supStyle, baseSize: baseSize, defaultUI: defaultUI, tightLeading: false, tightTrailing: false))

            case .subscriptText(let text):
                var subStyle = style
                subStyle.isSubscript = true
                output.append(makeSegment(text, style: subStyle, baseSize: baseSize, defaultUI: defaultUI, tightLeading: false, tightTrailing: false))

            case .link(let labelNodes, let destination):
                var linkStyle = style
                linkStyle.linkDestination = destination
                appendNodes(labelNodes, style: linkStyle, baseSize: baseSize, defaultUI: defaultUI, into: output)

            case .inlineMath(let latex):
                var mathStyle = style
                mathStyle.isMath = true
                let rendered = MarkdownMathNormalizer.prettify(latex)
                output.append(makeSegment(rendered, style: mathStyle, baseSize: baseSize, defaultUI: defaultUI, tightLeading: false, tightTrailing: false))

            case .inlineImage(let alt, let src):
                var linkStyle = style
                linkStyle.linkDestination = src
                linkStyle.isCode = true
                let label = alt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? MarkdownLinkFormatting.shortFileBadge(src)
                    : alt
                output.append(makeSegment("🖼 \(label)", style: linkStyle, baseSize: baseSize, defaultUI: defaultUI, tightLeading: false, tightTrailing: false))

            case .footnoteRef(let label):
                var fnStyle = style
                fnStyle.isSuperscript = true
                var attrs = makeAttributes(style: fnStyle, baseSize: baseSize, defaultUI: defaultUI, tightLeading: false, tightTrailing: false)
                attrs[.foregroundColor] = periwinkleUI
                output.append(NSAttributedString(string: "[\(label)]", attributes: attrs))
            }
        }
    }

    private static func makeSegment(
        _ string: String,
        style: StyleState,
        baseSize: CGFloat,
        defaultUI: UIColor,
        tightLeading: Bool,
        tightTrailing: Bool
    ) -> NSAttributedString {
        let attrs = makeAttributes(
            style: style,
            baseSize: baseSize,
            defaultUI: defaultUI,
            tightLeading: tightLeading,
            tightTrailing: tightTrailing
        )
        return NSAttributedString(string: string, attributes: attrs)
    }

    private static func makeAttributes(
        style: StyleState,
        baseSize: CGFloat,
        defaultUI: UIColor,
        tightLeading: Bool,
        tightTrailing: Bool
    ) -> [NSAttributedString.Key: Any] {
        var attrs: [NSAttributedString.Key: Any] = [
            .font: style.resolvedFont(baseSize: baseSize),
            .foregroundColor: style.resolvedForeground(defaultUI: defaultUI)
        ]
        if style.isStrikethrough {
            attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        }
        if style.isUnderline {
            attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        if style.isSuperscript {
            attrs[.baselineOffset] = baseSize * 0.28
        } else if style.isSubscript {
            attrs[.baselineOffset] = -(baseSize * 0.16)
        }
        if let pill = style.resolvedPillStyle(tightLeading: tightLeading, tightTrailing: tightTrailing) {
            attrs[.agyInlinePillStyle] = pill
        }
        if let dest = style.linkDestination,
           let url = MarkdownLinkFormatting.resolvedActionURL(for: dest) {
            attrs[.link] = url
        }
        return attrs
    }

    /// Adds a tiny non-breaking `.kern` on the character immediately preceding a tight pill
    /// (zero extra characters inserted into text storage -> clipboard stays 100% pure).
    private static func applyTightPillSpacingKerns(on attributed: NSMutableAttributedString) {
        let nsStr = attributed.string as NSString
        guard nsStr.length > 1 else { return }
        let fullRange = NSRange(location: 0, length: nsStr.length)
        let wsSet = CharacterSet.whitespacesAndNewlines

        attributed.enumerateAttribute(.agyInlinePillStyle, in: fullRange, options: []) { value, range, _ in
            guard value is InlinePillVisualStyle else { return }
            if range.location > 0 {
                let prevIdx = range.location - 1
                let prevUnit = nsStr.character(at: prevIdx)
                if let scalar = UnicodeScalar(prevUnit), !wsSet.contains(scalar) {
                    let existingPill = attributed.attribute(.agyInlinePillStyle, at: prevIdx, effectiveRange: nil)
                    if existingPill == nil {
                        attributed.addAttribute(.kern, value: CGFloat(2.5), range: NSRange(location: prevIdx, length: 1))
                    }
                }
            }
        }
    }

    private static func lastCharacter(of attributed: NSMutableAttributedString) -> Character? {
        attributed.string.last
    }

    private static func firstCharacter(of node: MarkdownInline?) -> Character? {
        guard let node else { return nil }
        return node.plainText.first
    }

    static func uiFontWeight(_ weight: Font.Weight) -> UIFont.Weight {
        switch weight {
        case .ultraLight: return .ultraLight
        case .thin: return .thin
        case .light: return .light
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        case .heavy: return .heavy
        case .black: return .black
        default: return .regular
        }
    }

    static func weightTag(_ weight: Font.Weight) -> Int {
        switch weight {
        case .ultraLight: return 1
        case .thin: return 2
        case .light: return 3
        case .medium: return 5
        case .semibold: return 6
        case .bold: return 7
        case .heavy: return 8
        case .black: return 9
        default: return 4
        }
    }

    static func nsAlignment(_ alignment: TextAlignment) -> NSTextAlignment {
        switch alignment {
        case .leading: return .left
        case .center: return .center
        case .trailing: return .right
        }
    }

    static func alignmentTag(_ alignment: TextAlignment) -> Int {
        switch alignment {
        case .leading: return 0
        case .center: return 1
        case .trailing: return 2
        }
    }

    static func colorSignature(_ color: Color) -> UInt32 {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        let ri = UInt32(max(0, min(255, Int(r * 255))))
        let gi = UInt32(max(0, min(255, Int(g * 255))))
        let bi = UInt32(max(0, min(255, Int(b * 255))))
        let ai = UInt32(max(0, min(255, Int(a * 255))))
        return (ri << 24) | (gi << 16) | (bi << 8) | ai
    }
}
#endif

// MARK: - Antigravity `<agent-embed>` Interactive Widget Card & Sandboxed WKWebView

private struct MarkdownAgentEmbedCardView: View {
    let src: String
    let explicitTitle: String?
    let kind: MarkdownEmbedKind
    let isStreamingIncomplete: Bool
    let store: AntigravitySessionStore?

    @State private var resolved: ResolvedEmbedResource? = nil
    @State private var isLoading: Bool = false
    @State private var webViewHeight: CGFloat = 260
    @State private var showFullScreenSheet: Bool = false
    @State private var showSourceCode: Bool = false
    @State private var didCopyPath: Bool = false

    private var displayTitle: String {
        AntigravityMarkdownParser.humanReadableEmbedTitle(src: src, explicitTitle: explicitTitle)
    }

    private var shortFilename: String {
        MarkdownLinkFormatting.shortFileBadge(src)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Card Header
            HStack(spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(StepCardPalette.periwinkle.opacity(0.14))
                        .frame(width: 30, height: 30)
                    Image(systemName: kind.sfSymbolName)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(StepCardPalette.periwinkle)
                }

                VStack(alignment: .leading, spacing: 1.5) {
                    Text(displayTitle)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(AntigravityTheme.inkReading)
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        Text(kind.displayBadge)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(StepCardPalette.periwinkle)
                        if !shortFilename.isEmpty {
                            Text("· \(shortFilename)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(AntigravityTheme.inkSecondary)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer(minLength: 4)

                if resolved?.textContent != nil && (resolved?.isHTML == true || resolved?.isSVG == true) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.16)) {
                            showSourceCode.toggle()
                        }
                    } label: {
                        Image(systemName: showSourceCode ? "eye" : "chevron.left.forwardslash.chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AntigravityTheme.inkLabel)
                            .frame(width: 30, height: 30)
                            .background(Color.white.opacity(0.06))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }

                if canPresentInteractivePreview {
                    Button {
                        showFullScreenSheet = true
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(StepCardPalette.periwinkle)
                            .frame(width: 30, height: 30)
                            .background(StepCardPalette.periwinkle.opacity(0.14))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Color.white.opacity(0.03))

            Rectangle()
                .fill(Color.white.opacity(0.07))
                .frame(height: 1)

            // Body Content
            if isStreamingIncomplete {
                HStack(spacing: 10) {
                    AntigravityFourDotLoadingView(isAnimated: true, dotSize: 4.0, spacing: 3.0, tint: StepCardPalette.periwinkle)
                    Text("Streaming interactive embed…")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AntigravityTheme.inkSecondary)
                    Spacer()
                }
                .padding(14)
            } else if isLoading {
                HStack(spacing: 10) {
                    ProgressView()
                        .tint(StepCardPalette.periwinkle)
                        .scaleEffect(0.85)
                    Text("Loading \(shortFilename.isEmpty ? "artifact" : shortFilename)…")
                        .font(.system(size: 13))
                        .foregroundStyle(AntigravityTheme.inkSecondary)
                    Spacer()
                }
                .padding(14)
            } else if showSourceCode, let rawText = resolved?.textContent {
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(String(rawText.prefix(6000)))
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(AntigravityTheme.inkLabel)
                        .padding(12)
                }
                .frame(maxHeight: 280)
                .background(StepCardPalette.codeBlockBg)
            } else if let res = resolved, res.isHTML || res.isSVG, let htmlText = res.textContent {
                #if canImport(WebKit) && canImport(UIKit)
                let documentHTML = res.isSVG
                    ? AntigravityEmbedHTMLWrapper.wrapSVG(htmlText)
                    : AntigravityEmbedHTMLWrapper.wrapHTML(htmlText)
                SandboxedHTMLWidgetWebView(
                    htmlContent: documentHTML,
                    remoteURL: nil,
                    allowInternalScroll: false,
                    measuredHeight: $webViewHeight
                )
                .frame(height: min(500, max(160, webViewHeight)))
                .background(AntigravityTheme.canvasObsidian)
                #else
                unavailableEmbedFooter(reason: "Interactive HTML preview is available on iOS.")
                #endif
            } else if let res = resolved, res.source == .directNetwork, let url = URL(string: res.uri) {
                #if canImport(WebKit) && canImport(UIKit)
                SandboxedHTMLWidgetWebView(
                    htmlContent: nil,
                    remoteURL: url,
                    allowInternalScroll: false,
                    measuredHeight: $webViewHeight
                )
                .frame(height: min(460, max(200, webViewHeight)))
                .background(AntigravityTheme.canvasObsidian)
                #else
                unavailableEmbedFooter(reason: res.uri)
                #endif
            } else if let res = resolved, res.isImage, let data = res.binaryData {
                #if canImport(UIKit)
                if let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 360)
                        .background(StepCardPalette.codeBlockBg)
                        .onTapGesture { showFullScreenSheet = true }
                } else {
                    unavailableEmbedFooter(reason: "Could not decode image data.")
                }
                #else
                unavailableEmbedFooter(reason: "Image preview is available on iOS.")
                #endif
            } else if let res = resolved, let mdText = res.textContent, kind == .markdown {
                AntigravityMarkdownView(markdown: mdText, variant: .blockquote, store: store)
                    .padding(12)
            } else {
                unavailableEmbedFooter(reason: nil)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(StepCardPalette.cardSurface)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(StepCardPalette.periwinkle.opacity(0.22), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .task(id: src) {
            guard !isStreamingIncomplete, !src.isEmpty else { return }
            await loadEmbedResource()
        }
        .sheet(isPresented: $showFullScreenSheet) {
            EmbedFullScreenModalView(
                title: displayTitle,
                src: src,
                resolved: resolved
            )
        }
    }

    private var canPresentInteractivePreview: Bool {
        guard let res = resolved else { return false }
        return (res.textContent != nil && (res.isHTML || res.isSVG))
            || res.source == .directNetwork
            || (res.isImage && res.binaryData != nil)
    }

    private func loadEmbedResource() async {
        if let cached = store?.cachedEmbedResource(for: src) {
            resolved = cached
            return
        }
        isLoading = true
        defer {
            isLoading = false
        }
        if let store {
            resolved = await store.resolveEmbedResource(uri: src)
        } else if src.lowercased().hasPrefix("data:") {
            resolved = ResolvedEmbedResource.decodeDataURI(src)
        } else if src.lowercased().hasPrefix("https://") || src.lowercased().hasPrefix("http://") {
            resolved = ResolvedEmbedResource(
                uri: src,
                mimeType: ResolvedEmbedResource.inferredMimeType(for: src),
                source: .directNetwork
            )
        }
    }

    @ViewBuilder
    private func unavailableEmbedFooter(reason: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(
                reason ?? (
                    src.lowercased().hasPrefix("file://")
                        ? "Host-local interactive artifact on your paired Mac. Tap Retry when Desktop or Companion Bridge is online, or copy the file path."
                        : "Interactive embed preview unavailable."
                )
            )
            .font(.system(size: 12.5))
            .foregroundStyle(AntigravityTheme.inkSecondary)
            .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                if store != nil {
                    Button {
                        Task { await loadEmbedResource() }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11, weight: .semibold))
                            Text("Retry")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(StepCardPalette.periwinkle)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background(StepCardPalette.periwinkle.opacity(0.14))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    MarkdownClipboardHelper.copyText(MarkdownLinkFormatting.cleanDisplayPath(src))
                    withAnimation(.easeInOut(duration: 0.15)) {
                        didCopyPath = true
                    }
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(1.5))
                        withAnimation(.easeInOut(duration: 0.15)) {
                            didCopyPath = false
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: didCopyPath ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11, weight: .semibold))
                        Text(didCopyPath ? "Path Copied" : "Copy Path")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(didCopyPath ? StepCardPalette.emeraldDone : AntigravityTheme.inkLabel)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.07))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Spacer()
            }
        }
        .padding(12)
    }
}

private struct EmbedFullScreenModalView: View {
    let title: String
    let src: String
    let resolved: ResolvedEmbedResource?
    @Environment(\.dismiss) private var dismiss
    @State private var dummyHeight: CGFloat = 600

    var body: some View {
        NavigationStack {
            Group {
                if let res = resolved, (res.isHTML || res.isSVG), let htmlText = res.textContent {
                    #if canImport(WebKit) && canImport(UIKit)
                    let doc = res.isSVG
                        ? AntigravityEmbedHTMLWrapper.wrapSVG(htmlText)
                        : AntigravityEmbedHTMLWrapper.wrapHTML(htmlText)
                    SandboxedHTMLWidgetWebView(
                        htmlContent: doc,
                        remoteURL: nil,
                        allowInternalScroll: true,
                        measuredHeight: $dummyHeight
                    )
                    #else
                    Text(htmlText)
                    #endif
                } else if let res = resolved, res.source == .directNetwork, let url = URL(string: res.uri) {
                    #if canImport(WebKit) && canImport(UIKit)
                    SandboxedHTMLWidgetWebView(
                        htmlContent: nil,
                        remoteURL: url,
                        allowInternalScroll: true,
                        measuredHeight: $dummyHeight
                    )
                    #else
                    Text(res.uri)
                    #endif
                } else if let res = resolved, res.isImage, let data = res.binaryData {
                    #if canImport(UIKit)
                    if let img = UIImage(data: data) {
                        ScrollView([.horizontal, .vertical]) {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFit()
                                .padding(12)
                        }
                    }
                    #endif
                } else {
                    Text(src)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(AntigravityTheme.inkSecondary)
                        .padding(16)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AntigravityTheme.canvasObsidian.ignoresSafeArea())
            .navigationTitle(title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(StepCardPalette.periwinkle)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

private struct RemoteArtifactPreviewSheet: View {
    let uri: String
    let store: AntigravitySessionStore?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                MarkdownAgentEmbedCardView(
                    src: uri,
                    explicitTitle: nil,
                    kind: MarkdownEmbedKind.detect(from: uri),
                    isStreamingIncomplete: false,
                    store: store
                )
                .padding(14)
            }
            .background(AntigravityTheme.canvasObsidian.ignoresSafeArea())
            .navigationTitle(AntigravityMarkdownParser.humanReadableEmbedTitle(src: uri))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(StepCardPalette.periwinkle)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

/// Injects Antigravity Matte Obsidian theme CSS variables, responsive mobile viewport meta,
/// and `ResizeObserver` height bridge into agent-generated HTML/SVG widgets.
private enum AntigravityEmbedHTMLWrapper {
    private static let themeBridgeInjection = """
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=3.0">
    <style>
      :root {
        --background: #090A0D;
        --card: #141519;
        --card-foreground: #F5F7FA;
        --popover: #1D1F26;
        --popover-foreground: #F5F7FA;
        --foreground: #F5F7FA;
        --primary: #8EB4FF;
        --primary-foreground: #0A0E17;
        --secondary: #1D1F26;
        --secondary-foreground: #DCE6FF;
        --muted: #1D1F26;
        --muted-foreground: #8E93A2;
        --accent: #1D1F26;
        --accent-foreground: #F5F7FA;
        --destructive: #F07167;
        --border: rgba(255,255,255,0.10);
        --input: rgba(255,255,255,0.12);
        --ring: #8EB4FF;
        color-scheme: dark;
      }
      html, body {
        margin: 0;
        padding: 0;
        background: var(--background);
        color: var(--foreground);
        font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
        max-width: 100%;
        overflow-x: auto;
        -webkit-text-size-adjust: 100%;
      }
      svg, img, canvas { max-width: 100%; height: auto; }
    </style>
    <script>
      (function() {
        function postHeight() {
          try {
            var h = Math.max(
              document.documentElement ? document.documentElement.scrollHeight : 0,
              document.body ? document.body.scrollHeight : 0
            );
            if (h > 0 && window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.embedHeight) {
              window.webkit.messageHandlers.embedHeight.postMessage(h);
            }
          } catch (e) {}
        }
        window.addEventListener('load', postHeight);
        window.addEventListener('resize', postHeight);
        if (typeof ResizeObserver !== 'undefined') {
          var ro = new ResizeObserver(postHeight);
          document.addEventListener('DOMContentLoaded', function() {
            if (document.body) ro.observe(document.body);
            postHeight();
          });
        }
        setTimeout(postHeight, 120);
        setTimeout(postHeight, 450);
      })();
    </script>
    """

    static func wrapHTML(_ rawHTML: String) -> String {
        if let headRange = rawHTML.range(of: "<head>", options: .caseInsensitive) {
            var out = rawHTML
            out.insert(contentsOf: "\n" + themeBridgeInjection + "\n", at: headRange.upperBound)
            return out
        }
        if rawHTML.lowercased().contains("<html") {
            return themeBridgeInjection + "\n" + rawHTML
        }
        return """
        <!doctype html>
        <html>
        <head><meta charset="utf-8">\(themeBridgeInjection)</head>
        <body>\(rawHTML)</body>
        </html>
        """
    }

    static func wrapSVG(_ rawSVG: String) -> String {
        return """
        <!doctype html>
        <html>
        <head><meta charset="utf-8">\(themeBridgeInjection)</head>
        <body style="display:flex;justify-content:center;align-items:center;padding:12px;box-sizing:border-box;">
          \(rawSVG)
        </body>
        </html>
        """
    }
}

#if canImport(WebKit) && canImport(UIKit)
private struct SandboxedHTMLWidgetWebView: UIViewRepresentable {
    let htmlContent: String?
    let remoteURL: URL?
    let allowInternalScroll: Bool
    @Binding var measuredHeight: CGFloat
    @Environment(\.openURL) private var openURL

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onHeightChange: { newHeight in
                if abs(measuredHeight - newHeight) > 2.0 {
                    measuredHeight = newHeight
                }
            },
            onExternalLink: { url in
                openURL(url)
            }
        )
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.allowsInlineMediaPlayback = true
        config.userContentController.add(context.coordinator, name: "embedHeight")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = UIColor(red: 0x09 / 255.0, green: 0x0A / 255.0, blue: 0x0D / 255.0, alpha: 1.0)
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = allowInternalScroll
        webView.scrollView.bounces = allowInternalScroll
        loadContent(into: webView, coordinator: context.coordinator)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        context.coordinator.onHeightChange = { newHeight in
            if abs(measuredHeight - newHeight) > 2.0 {
                measuredHeight = newHeight
            }
        }
        context.coordinator.onExternalLink = { url in
            openURL(url)
        }
        uiView.scrollView.isScrollEnabled = allowInternalScroll
        loadContent(into: uiView, coordinator: context.coordinator)
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.navigationDelegate = nil
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "embedHeight")
    }

    private func loadContent(into webView: WKWebView, coordinator: Coordinator) {
        let signature = "\(htmlContent ?? "")|\(remoteURL?.absoluteString ?? "")"
        guard coordinator.lastLoadedSignature != signature else { return }
        coordinator.lastLoadedSignature = signature
        if let htmlContent {
            webView.loadHTMLString(htmlContent, baseURL: URL(string: "https://antigravity.local/"))
        } else if let remoteURL {
            webView.load(URLRequest(url: remoteURL))
        }
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var onHeightChange: @MainActor (CGFloat) -> Void
        var onExternalLink: @MainActor (URL) -> Void
        var lastLoadedSignature: String = ""

        init(
            onHeightChange: @escaping @MainActor (CGFloat) -> Void,
            onExternalLink: @escaping @MainActor (URL) -> Void
        ) {
            self.onHeightChange = onHeightChange
            self.onExternalLink = onExternalLink
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "embedHeight" else { return }
            if let num = message.body as? NSNumber {
                let h = CGFloat(num.doubleValue)
                if h.isFinite && h >= 40 && h <= 2400 {
                    let targetHeight = ceil(h) + 4
                    Task { @MainActor [weak self] in
                        self?.onHeightChange(targetHeight)
                    }
                }
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction
        ) async -> WKNavigationActionPolicy {
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url,
               let scheme = url.scheme?.lowercased(),
               (scheme == "https" || scheme == "http" || scheme == "mailto") {
                onExternalLink(url)
                return .cancel
            }
            return .allow
        }
    }
}
#endif

// MARK: - Offline Interactive Mermaid Diagram Card (` ```mermaid `)

private struct MarkdownMermaidCardView: View {
    let source: String
    @State private var showCode: Bool = false
    @State private var didCopy: Bool = false
    @State private var diagramHeight: CGFloat = 240
    @State private var showFullScreen: Bool = false

    private var offlineDiagramHTML: String? {
        OfflineMermaidSVGRenderer.renderHTML(from: source)
    }

    var body: some View {
        let renderedHTML = offlineDiagramHTML
        let displayingCode = showCode || renderedHTML == nil

        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(StepCardPalette.periwinkle)
                    Text("mermaid")
                        .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(AntigravityTheme.inkSecondary)
                }

                Spacer()

                if renderedHTML != nil {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            showCode.toggle()
                        }
                    } label: {
                        Text(showCode ? "Diagram" : "Code")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(AntigravityTheme.inkLabel)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.06))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    Button {
                        showFullScreen = true
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(StepCardPalette.periwinkle)
                            .padding(6)
                            .background(StepCardPalette.periwinkle.opacity(0.12))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    MarkdownClipboardHelper.copyText(source)
                    withAnimation(.easeInOut(duration: 0.15)) { didCopy = true }
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(1.6))
                        withAnimation(.easeInOut(duration: 0.15)) { didCopy = false }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 10.5, weight: .semibold))
                        Text(didCopy ? "Copied" : "Copy")
                            .font(.system(size: 11.5, weight: .semibold))
                    }
                    .foregroundStyle(didCopy ? StepCardPalette.emeraldDone : StepCardPalette.periwinkle)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.05))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.03))

            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)

            if displayingCode {
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(source.isEmpty ? " " : source)
                        .font(.system(size: 12.5, design: .monospaced))
                        .foregroundStyle(AntigravityTheme.inkReading)
                        .lineSpacing(2.5)
                        .textSelection(.enabled)
                        .padding(12)
                }
            } else if let html = renderedHTML {
                #if canImport(WebKit) && canImport(UIKit)
                SandboxedHTMLWidgetWebView(
                    htmlContent: html,
                    remoteURL: nil,
                    allowInternalScroll: false,
                    measuredHeight: $diagramHeight
                )
                .frame(height: min(460, max(160, diagramHeight)))
                #else
                Text(source)
                    .font(.system(size: 12.5, design: .monospaced))
                    .padding(12)
                #endif
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(StepCardPalette.codeBlockBg)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .sheet(isPresented: $showFullScreen) {
            if let html = renderedHTML {
                EmbedFullScreenModalView(
                    title: "Mermaid Diagram",
                    src: "mermaid://diagram",
                    resolved: ResolvedEmbedResource(
                        uri: "mermaid://diagram",
                        mimeType: "text/html",
                        textContent: html,
                        source: .inlineDataURI
                    )
                )
            }
        }
    }
}

/// Zero-CDN offline SVG diagram generator for Mermaid `flowchart` / `graph` / `stateDiagram` / `sequenceDiagram`.
private enum OfflineMermaidSVGRenderer {
    static func renderHTML(from rawSource: String) -> String? {
        let lines = rawSource
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("%%") }

        guard let header = lines.first?.lowercased() else { return nil }
        if header.hasPrefix("flowchart") || header.hasPrefix("graph") {
            let isHorizontal = header.contains("lr") || header.contains("rl")
            return renderFlowchartSVG(lines: Array(lines.dropFirst()), isHorizontal: isHorizontal)
        }
        if header.hasPrefix("statediagram") {
            return renderFlowchartSVG(lines: Array(lines.dropFirst()), isHorizontal: false)
        }
        if header.hasPrefix("sequencediagram") {
            return renderSequenceSVG(lines: Array(lines.dropFirst()))
        }
        return nil
    }

    private static func escapeXML(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func parseNodeToken(_ raw: String) -> (id: String, label: String, shape: String) {
        let t = raw.trimmingCharacters(in: .whitespaces)
        let delimiters: [(open: String, close: String, shape: String)] = [
            ("([", "])", "pill"),
            ("((", "))", "circle"),
            ("[", "]", "rect"),
            ("(", ")", "round"),
            ("{", "}", "diamond"),
        ]
        for delim in delimiters {
            if let openRange = t.range(of: delim.open),
               t.hasSuffix(delim.close),
               openRange.lowerBound > t.startIndex {
                let id = String(t[..<openRange.lowerBound]).trimmingCharacters(in: .whitespaces)
                let labelRaw = String(t[openRange.upperBound..<t.index(t.endIndex, offsetBy: -delim.close.count)])
                let cleanLabel = labelRaw.trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
                return (id, cleanLabel.isEmpty ? id : cleanLabel, delim.shape)
            }
        }
        if t == "[*]" {
            return ("__start__", "●", "circle")
        }
        return (t, t, "rect")
    }

    private static func renderFlowchartSVG(lines: [String], isHorizontal: Bool) -> String? {
        var nodeOrder: [String] = []
        var nodeLabels: [String: String] = [:]
        var nodeShapes: [String: String] = [:]
        var edges: [(from: String, to: String, label: String)] = []

        func registerNode(_ raw: String) -> String {
            let parsed = parseNodeToken(raw)
            if nodeLabels[parsed.id] == nil {
                nodeOrder.append(parsed.id)
                nodeLabels[parsed.id] = parsed.label
                nodeShapes[parsed.id] = parsed.shape
            } else if parsed.label != parsed.id {
                nodeLabels[parsed.id] = parsed.label
                nodeShapes[parsed.id] = parsed.shape
            }
            return parsed.id
        }

        let arrowTokens = ["-->", "-.->", "==>", "---", "->"]
        for line in lines {
            let lower = line.lowercased()
            if lower.hasPrefix("subgraph") || lower == "end" || lower.hasPrefix("classdef") || lower.hasPrefix("style ") || lower.hasPrefix("direction ") {
                continue
            }
            var matchedArrow: String? = nil
            for tok in arrowTokens where line.contains(tok) {
                matchedArrow = tok
                break
            }
            if let arrow = matchedArrow, let range = line.range(of: arrow) {
                let lhs = String(line[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                var rhs = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                var edgeLabel = ""
                if rhs.hasPrefix("|"), let secondPipe = rhs.dropFirst().firstIndex(of: "|") {
                    edgeLabel = String(rhs[rhs.index(after: rhs.startIndex)..<secondPipe]).trimmingCharacters(in: .whitespaces)
                    rhs = String(rhs[rhs.index(after: secondPipe)...]).trimmingCharacters(in: .whitespaces)
                } else if let colonRange = rhs.range(of: ":") {
                    let potentialTarget = String(rhs[..<colonRange.lowerBound]).trimmingCharacters(in: .whitespaces)
                    if !potentialTarget.contains("[") && !potentialTarget.contains("(") {
                        edgeLabel = String(rhs[colonRange.upperBound...]).trimmingCharacters(in: .whitespaces)
                        rhs = potentialTarget
                    }
                }
                if !lhs.isEmpty && !rhs.isEmpty {
                    let fromId = registerNode(lhs)
                    let toId = registerNode(rhs)
                    edges.append((fromId, toId, edgeLabel))
                }
            }
        }

        guard !nodeOrder.isEmpty else { return nil }

        // Assign topological layers via BFS relaxation
        var depthByNode: [String: Int] = [:]
        for id in nodeOrder { depthByNode[id] = 0 }
        for _ in 0..<min(16, nodeOrder.count) {
            for e in edges {
                let nextD = (depthByNode[e.from] ?? 0) + 1
                if nextD > (depthByNode[e.to] ?? 0) && nextD < nodeOrder.count {
                    depthByNode[e.to] = nextD
                }
            }
        }

        var layers: [Int: [String]] = [:]
        for id in nodeOrder {
            let d = depthByNode[id] ?? 0
            layers[d, default: []].append(id)
        }
        let maxLayer = layers.keys.max() ?? 0
        let nodeW: CGFloat = 152
        let nodeH: CGFloat = 44
        let gapX: CGFloat = isHorizontal ? 54 : 24
        let gapY: CGFloat = isHorizontal ? 24 : 48
        let pad: CGFloat = 18

        var positions: [String: CGRect] = [:]
        var maxX: CGFloat = 0
        var maxY: CGFloat = 0

        for layerIdx in 0...maxLayer {
            let nodes = layers[layerIdx] ?? []
            for (slotIdx, id) in nodes.enumerated() {
                let x = isHorizontal
                    ? pad + CGFloat(layerIdx) * (nodeW + gapX)
                    : pad + CGFloat(slotIdx) * (nodeW + gapX)
                let y = isHorizontal
                    ? pad + CGFloat(slotIdx) * (nodeH + gapY)
                    : pad + CGFloat(layerIdx) * (nodeH + gapY)
                let rect = CGRect(x: x, y: y, width: nodeW, height: nodeH)
                positions[id] = rect
                maxX = max(maxX, rect.maxX + pad)
                maxY = max(maxY, rect.maxY + pad)
            }
        }

        var svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 \(Int(maxX)) \(Int(maxY))" width="\(Int(maxX))" height="\(Int(maxY))">
        <defs>
          <marker id="agy-arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse">
            <path d="M 0 1 L 10 5 L 0 9 z" fill="#8EB4FF" />
          </marker>
        </defs>
        """

        for e in edges {
            guard let r1 = positions[e.from], let r2 = positions[e.to] else { continue }
            let x1 = isHorizontal ? r1.maxX : r1.midX
            let y1 = isHorizontal ? r1.midY : r1.maxY
            let x2 = isHorizontal ? r2.minX : r2.midX
            let y2 = isHorizontal ? r2.midY : r2.minY
            let cx1 = isHorizontal ? (x1 + x2) / 2 : x1
            let cy1 = isHorizontal ? y1 : (y1 + y2) / 2
            let cx2 = isHorizontal ? (x1 + x2) / 2 : x2
            let cy2 = isHorizontal ? y2 : (y1 + y2) / 2
            svg += "<path d=\"M \(Int(x1)) \(Int(y1)) C \(Int(cx1)) \(Int(cy1)), \(Int(cx2)) \(Int(cy2)), \(Int(x2)) \(Int(y2))\" fill=\"none\" stroke=\"rgba(142,180,255,0.65)\" stroke-width=\"1.6\" marker-end=\"url(#agy-arrow)\" />"
            if !e.label.isEmpty {
                let lx = Int((x1 + x2) / 2)
                let ly = Int((y1 + y2) / 2) - 4
                svg += "<text x=\"\(lx)\" y=\"\(ly)\" text-anchor=\"middle\" fill=\"#EBB365\" font-size=\"10.5\" font-family=\"-apple-system,sans-serif\">\(escapeXML(String(e.label.prefix(24))))</text>"
            }
        }

        for id in nodeOrder {
            guard let r = positions[id] else { continue }
            let label = String((nodeLabels[id] ?? id).prefix(22))
            let shape = nodeShapes[id] ?? "rect"
            let rx = (shape == "pill" || shape == "circle") ? 22 : (shape == "diamond" ? 6 : 10)
            let stroke = shape == "diamond" ? "#EBB365" : "rgba(142,180,255,0.45)"
            svg += "<rect x=\"\(Int(r.minX))\" y=\"\(Int(r.minY))\" width=\"\(Int(r.width))\" height=\"\(Int(r.height))\" rx=\"\(rx)\" fill=\"#141519\" stroke=\"\(stroke)\" stroke-width=\"1.25\" />"
            svg += "<text x=\"\(Int(r.midX))\" y=\"\(Int(r.midY + 4))\" text-anchor=\"middle\" fill=\"#F5F7FA\" font-size=\"12\" font-weight=\"600\" font-family=\"-apple-system,sans-serif\">\(escapeXML(label))</text>"
        }

        svg += "</svg>"
        return AntigravityEmbedHTMLWrapper.wrapSVG(svg)
    }

    private static func renderSequenceSVG(lines: [String]) -> String? {
        var participants: [String] = []
        var messages: [(from: String, to: String, text: String, dashed: Bool)] = []

        func addParticipant(_ name: String) {
            let clean = name.trimmingCharacters(in: .whitespaces)
            if !clean.isEmpty && !participants.contains(clean) {
                participants.append(clean)
            }
        }

        for line in lines {
            if line.lowercased().hasPrefix("participant ") || line.lowercased().hasPrefix("actor ") {
                let rest = line.split(separator: " ", maxSplits: 1).dropFirst().first.map(String.init) ?? ""
                let name = rest.components(separatedBy: " as ").first ?? rest
                addParticipant(name)
                continue
            }
            for arrow in ["-->>", "->>", "-->", "->"] {
                if let range = line.range(of: arrow) {
                    let from = String(line[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                    let rhs = String(line[range.upperBound...])
                    let parts = rhs.split(separator: ":", maxSplits: 1)
                    let to = String(parts[0]).trimmingCharacters(in: .whitespaces)
                    let msg = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespaces) : ""
                    if !from.isEmpty && !to.isEmpty {
                        addParticipant(from)
                        addParticipant(to)
                        messages.append((from, to, msg, arrow.hasPrefix("--")))
                    }
                    break
                }
            }
        }

        guard participants.count >= 2, !messages.isEmpty else { return nil }
        let colW: CGFloat = 118
        let pad: CGFloat = 18
        let topBoxH: CGFloat = 32
        let rowH: CGFloat = 38
        let totalW = pad * 2 + CGFloat(participants.count) * colW
        let totalH = pad * 2 + topBoxH + CGFloat(messages.count + 1) * rowH

        var colCenterX: [String: CGFloat] = [:]
        for (idx, p) in participants.enumerated() {
            colCenterX[p] = pad + CGFloat(idx) * colW + colW / 2
        }

        var svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 \(Int(totalW)) \(Int(totalH))" width="\(Int(totalW))" height="\(Int(totalH))">
        <defs>
          <marker id="seq-arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse">
            <path d="M 0 1 L 10 5 L 0 9 z" fill="#8EB4FF" />
          </marker>
        </defs>
        """

        for p in participants {
            let cx = colCenterX[p] ?? 0
            svg += "<line x1=\"\(Int(cx))\" y1=\"\(Int(pad + topBoxH))\" x2=\"\(Int(cx))\" y2=\"\(Int(totalH - pad))\" stroke=\"rgba(255,255,255,0.14)\" stroke-dasharray=\"4 4\" />"
            svg += "<rect x=\"\(Int(cx - 48))\" y=\"\(Int(pad))\" width=\"96\" height=\"\(Int(topBoxH))\" rx=\"8\" fill=\"#141519\" stroke=\"rgba(142,180,255,0.45)\" stroke-width=\"1.2\" />"
            svg += "<text x=\"\(Int(cx))\" y=\"\(Int(pad + 20))\" text-anchor=\"middle\" fill=\"#F5F7FA\" font-size=\"11.5\" font-weight=\"600\" font-family=\"-apple-system,sans-serif\">\(escapeXML(String(p.prefix(14))))</text>"
        }

        for (idx, m) in messages.enumerated() {
            guard let x1 = colCenterX[m.from], let x2 = colCenterX[m.to] else { continue }
            let y = pad + topBoxH + CGFloat(idx + 1) * rowH
            let dashAttr = m.dashed ? " stroke-dasharray=\"5 3\"" : ""
            svg += "<line x1=\"\(Int(x1))\" y1=\"\(Int(y))\" x2=\"\(Int(x2))\" y2=\"\(Int(y))\" stroke=\"#8EB4FF\" stroke-width=\"1.5\"\(dashAttr) marker-end=\"url(#seq-arrow)\" />"
            if !m.text.isEmpty {
                let lx = Int((x1 + x2) / 2)
                svg += "<text x=\"\(lx)\" y=\"\(Int(y - 6))\" text-anchor=\"middle\" fill=\"#DCE6FF\" font-size=\"10.5\" font-family=\"-apple-system,sans-serif\">\(escapeXML(String(m.text.prefix(26))))</text>"
            }
        }

        svg += "</svg>"
        return AntigravityEmbedHTMLWrapper.wrapSVG(svg)
    }
}

// MARK: - Carousel Card (` ````carousel ... <!-- slide --> ... ```` `)

private struct MarkdownCarouselCardView: View {
    let slides: [[MarkdownBlock]]
    let variant: MarkdownRenderVariant
    let store: AntigravitySessionStore?
    @State private var activeIndex: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "rectangle.stack")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(StepCardPalette.periwinkle)
                Text("Carousel")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AntigravityTheme.inkLabel)
                Spacer()
                Text("\(min(activeIndex + 1, max(1, slides.count))) / \(slides.count)")
                    .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(AntigravityTheme.inkSecondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color.white.opacity(0.03))

            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)

            if !slides.isEmpty {
                let safeIdx = min(max(0, activeIndex), slides.count - 1)
                AnyView(AntigravityMarkdownBlocksView(blocks: slides[safeIdx], variant: variant, store: store))
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if slides.count > 1 {
                    HStack(spacing: 12) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.16)) {
                                activeIndex = max(0, activeIndex - 1)
                            }
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(activeIndex > 0 ? StepCardPalette.periwinkle : AntigravityTheme.inkSecondary.opacity(0.4))
                                .frame(width: 30, height: 28)
                                .background(Color.white.opacity(0.05))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .disabled(activeIndex == 0)

                        Spacer()

                        HStack(spacing: 5) {
                            ForEach(0..<slides.count, id: \.self) { idx in
                                Circle()
                                    .fill(idx == activeIndex ? StepCardPalette.periwinkle : Color.white.opacity(0.22))
                                    .frame(width: idx == activeIndex ? 7 : 5, height: idx == activeIndex ? 7 : 5)
                            }
                        }

                        Spacer()

                        Button {
                            withAnimation(.easeInOut(duration: 0.16)) {
                                activeIndex = min(slides.count - 1, activeIndex + 1)
                            }
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(activeIndex + 1 < slides.count ? StepCardPalette.periwinkle : AntigravityTheme.inkSecondary.opacity(0.4))
                                .frame(width: 30, height: 28)
                                .background(Color.white.opacity(0.05))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .disabled(activeIndex + 1 >= slides.count)
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
                }
            }
        }
        .background(StepCardPalette.cardSurface)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - Collapsible `<details>` Disclosure Card

private struct MarkdownDetailsCardView: View {
    let summary: [MarkdownInline]
    let innerBlocks: [MarkdownBlock]
    let store: AntigravitySessionStore?
    @State private var isExpanded: Bool

    init(
        summary: [MarkdownInline],
        innerBlocks: [MarkdownBlock],
        isOpenByDefault: Bool,
        store: AntigravitySessionStore?
    ) {
        self.summary = summary
        self.innerBlocks = innerBlocks
        self.store = store
        self._isExpanded = State(initialValue: isOpenByDefault)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(StepCardPalette.periwinkle)
                        .frame(width: 14)
                    Text(
                        MarkdownInlineBuilder.build(
                            summary,
                            baseSize: 14.0,
                            baseWeight: .semibold,
                            defaultColor: AntigravityTheme.inkReading
                        )
                    )
                    .multilineTextAlignment(.leading)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded && !innerBlocks.isEmpty {
                Rectangle()
                    .fill(Color.white.opacity(0.07))
                    .frame(height: 1)

                AnyView(AntigravityMarkdownBlocksView(blocks: innerBlocks, variant: .blockquote, store: store))
                    .padding(12)
            }
        }
        .background(StepCardPalette.cardSurface)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - `<plugin-card>` Connection Card

private struct MarkdownPluginCardView: View {
    let catalogId: String
    let explicitTitle: String?

    private var displayTitle: String {
        if let explicitTitle, !explicitTitle.isEmpty { return explicitTitle }
        return catalogId
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(StepCardPalette.softViolet.opacity(0.16))
                    .frame(width: 36, height: 36)
                Image(systemName: "puzzlepiece.extension.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(StepCardPalette.softViolet)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(displayTitle)
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(AntigravityTheme.inkReading)
                Text("Plugin · Connect in Antigravity Customizations")
                    .font(.system(size: 12))
                    .foregroundStyle(AntigravityTheme.inkSecondary)
            }

            Spacer()
        }
        .padding(12)
        .background(StepCardPalette.cardSurface)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(StepCardPalette.softViolet.opacity(0.28), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - Standalone Image Block (`![alt](url)` & `<img src="..." />`)

private struct MarkdownImageBlockView: View {
    let alt: String
    let src: String
    let title: String?
    let store: AntigravitySessionStore?

    @State private var resolved: ResolvedEmbedResource? = nil
    @State private var isLoading: Bool = false
    @State private var showFullScreen: Bool = false

    private var captionText: String {
        let primary = !alt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? alt
            : (title ?? MarkdownLinkFormatting.shortFileBadge(src))
        return primary.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        let lower = src.lowercased()
        VStack(alignment: .leading, spacing: 6) {
            if lower.hasPrefix("https://") || lower.hasPrefix("http://"), let url = URL(string: src) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: 360)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    case .failure:
                        fallbackImageCard
                    case .empty:
                        HStack(spacing: 8) {
                            ProgressView().tint(StepCardPalette.periwinkle)
                            Text("Loading image…")
                                .font(.system(size: 12.5))
                                .foregroundStyle(AntigravityTheme.inkSecondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 80)
                        .background(StepCardPalette.cardSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    @unknown default:
                        fallbackImageCard
                    }
                }
            } else if let res = resolved, res.isSVG, res.textContent != nil {
                MarkdownAgentEmbedCardView(
                    src: src,
                    explicitTitle: captionText,
                    kind: .svg,
                    isStreamingIncomplete: false,
                    store: store
                )
            } else if let data = resolved?.binaryData {
                #if canImport(UIKit)
                if let uiImg = UIImage(data: data) {
                    Image(uiImage: uiImg)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 360)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .onTapGesture { showFullScreen = true }
                } else {
                    fallbackImageCard
                }
                #else
                fallbackImageCard
                #endif
            } else if isLoading {
                HStack(spacing: 8) {
                    ProgressView().tint(StepCardPalette.periwinkle)
                    Text("Loading \(MarkdownLinkFormatting.shortFileBadge(src))…")
                        .font(.system(size: 12.5))
                        .foregroundStyle(AntigravityTheme.inkSecondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(StepCardPalette.cardSurface)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                fallbackImageCard
            }

            if !captionText.isEmpty {
                Text(captionText)
                    .font(.system(size: 12))
                    .foregroundStyle(AntigravityTheme.inkSecondary)
            }
        }
        .task(id: src) {
            guard !lower.hasPrefix("https://") && !lower.hasPrefix("http://") else { return }
            isLoading = true
            defer { isLoading = false }
            if let store {
                resolved = await store.resolveEmbedResource(uri: src)
            } else if lower.hasPrefix("data:") {
                resolved = ResolvedEmbedResource.decodeDataURI(src)
            }
        }
        .sheet(isPresented: $showFullScreen) {
            EmbedFullScreenModalView(title: captionText.isEmpty ? "Image" : captionText, src: src, resolved: resolved)
        }
    }

    private var fallbackImageCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "photo")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(StepCardPalette.periwinkle)
            VStack(alignment: .leading, spacing: 2) {
                Text(captionText.isEmpty ? "Host Image" : captionText)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(AntigravityTheme.inkReading)
                    .lineLimit(1)
                Text(MarkdownLinkFormatting.shortFileBadge(src))
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(AntigravityTheme.inkSecondary)
                    .lineLimit(1)
            }
            Spacer()
            Button("Copy") {
                MarkdownClipboardHelper.copyText(MarkdownLinkFormatting.cleanDisplayPath(src))
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(StepCardPalette.periwinkle)
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(StepCardPalette.cardSurface)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Footnote Section View

private struct MarkdownFootnoteSectionView: View {
    let items: [MarkdownFootnoteItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Rectangle()
                .fill(Color.white.opacity(0.09))
                .frame(height: 1)
                .padding(.vertical, 2)

            ForEach(items) { item in
                HStack(alignment: .top, spacing: 6) {
                    Text("[\(item.label)]")
                        .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(StepCardPalette.periwinkle)
                        .padding(.top, 2)
                    RichMarkdownInlineBlockView(
                        inlines: item.inlines,
                        baseSize: 12.5,
                        baseWeight: .regular,
                        defaultColor: AntigravityTheme.inkSecondary,
                        lineSpacing: 2.0
                    )
                }
            }
        }
    }
}

// MARK: - Fenced Code Block Card (Syntax Highlighting + Wrap Toggle + Copy + Diff Coloring)

private struct MarkdownCodeBlockCardView: View {
    let language: String?
    let code: String
    @State private var didCopy: Bool = false
    @State private var wrapLines: Bool = false

    private var normalizedLanguage: String {
        let trimmed = (language ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "code" : trimmed.lowercased()
    }

    private var isDiffBlock: Bool {
        normalizedLanguage == "diff" || normalizedLanguage == "patch"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(normalizedLanguage)
                    .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(AntigravityTheme.inkSecondary)

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.14)) {
                        wrapLines.toggle()
                    }
                } label: {
                    Text(wrapLines ? "Scroll" : "Wrap")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AntigravityTheme.inkSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.04))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    MarkdownClipboardHelper.copyText(code)
                    withAnimation(.easeInOut(duration: 0.15)) {
                        didCopy = true
                    }
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(1.6))
                        withAnimation(.easeInOut(duration: 0.15)) {
                            didCopy = false
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 10.5, weight: .semibold))
                        Text(didCopy ? "Copied" : "Copy")
                            .font(.system(size: 11.5, weight: .semibold))
                    }
                    .foregroundStyle(didCopy ? StepCardPalette.emeraldDone : StepCardPalette.periwinkle)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.05))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.03))

            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)

            if wrapLines {
                codeBodyView
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    codeBodyView
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(StepCardPalette.codeBlockBg)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private var codeBodyView: some View {
        if isDiffBlock {
            diffColoredCodeBody
                .padding(12)
        } else {
            Text(MarkdownSyntaxHighlighter.highlight(code: code.isEmpty ? " " : code, language: normalizedLanguage))
                .lineSpacing(2.5)
                .textSelection(.enabled)
                .padding(12)
        }
    }

    private var diffColoredCodeBody: some View {
        let lines = code.components(separatedBy: "\n")
        return VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line.isEmpty ? " " : line)
                    .font(.system(size: 12.5, weight: .regular, design: .monospaced))
                    .foregroundStyle(diffLineColor(line))
                    .textSelection(.enabled)
            }
        }
    }

    private func diffLineColor(_ line: String) -> Color {
        if line.hasPrefix("+++") || line.hasPrefix("---") {
            return AntigravityTheme.inkSecondary
        } else if line.hasPrefix("+") {
            return StepCardPalette.emeraldDone
        } else if line.hasPrefix("-") {
            return StepCardPalette.coralError
        } else if line.hasPrefix("@@") {
            return StepCardPalette.periwinkle
        }
        return AntigravityTheme.inkReading
    }
}

/// Zero-dependency Matte Obsidian single-pass syntax highlighter for common languages.
private enum MarkdownSyntaxHighlighter {
    private static let commentColor = Color(red: 0x6E / 255.0, green: 0x76 / 255.0, blue: 0x8A / 255.0)
    private static let monoFont = Font.system(size: 12.5, weight: .regular, design: .monospaced)

    private static let commonKeywords: Set<String> = [
        "func", "let", "var", "struct", "class", "enum", "actor", "protocol", "extension",
        "import", "public", "private", "internal", "fileprivate", "static", "final", "override",
        "async", "await", "throws", "throw", "try", "catch", "return", "guard", "if", "else",
        "switch", "case", "default", "for", "while", "in", "where", "do", "break", "continue",
        "defer", "init", "self", "Self", "nil", "true", "false", "some", "any", "nonisolated",
        "package", "type", "interface", "go", "chan", "select", "range", "map", "make", "new",
        "const", "function", "export", "from", "as", "typeof", "keyof", "readonly", "void",
        "def", "lambda", "with", "yield", "pass", "None", "True", "False", "and", "or", "not",
        "fn", "mut", "pub", "impl", "trait", "match", "use", "mod", "crate", "ref",
        "SELECT", "FROM", "WHERE", "INSERT", "INTO", "UPDATE", "DELETE", "CREATE", "TABLE",
        "JOIN", "LEFT", "INNER", "ON", "GROUP", "ORDER", "BY", "LIMIT", "AS", "AND", "OR", "NOT"
    ]

    static func highlight(code: String, language: String) -> AttributedString {
        guard code.count <= 12_000 else {
            var plain = AttributedString(code)
            plain.swiftUI.font = monoFont
            plain.swiftUI.foregroundColor = AntigravityTheme.inkReading
            return plain
        }

        let hashComments = ["python", "py", "bash", "sh", "zsh", "shell", "yaml", "yml", "ruby", "toml"].contains(language)
        let slashComments = !hashComments && language != "sql"
        let dashComments = (language == "sql")

        let chars = Array(code)
        var out = AttributedString()
        var i = 0

        func appendToken(_ str: String, color: Color, italic: Bool = false) {
            var seg = AttributedString(str)
            seg.swiftUI.font = italic ? monoFont.italic() : monoFont
            seg.swiftUI.foregroundColor = color
            out.append(seg)
        }

        while i < chars.count {
            let ch = chars[i]

            // Line comments (`//`, `#`, `--`)
            if (slashComments && ch == "/" && i + 1 < chars.count && chars[i + 1] == "/")
                || (hashComments && ch == "#")
                || (dashComments && ch == "-" && i + 1 < chars.count && chars[i + 1] == "-") {
                let start = i
                while i < chars.count && chars[i] != "\n" { i += 1 }
                appendToken(String(chars[start..<i]), color: commentColor, italic: true)
                continue
            }

            // Block comment (`/* ... */`)
            if slashComments && ch == "/" && i + 1 < chars.count && chars[i + 1] == "*" {
                let start = i
                i += 2
                while i + 1 < chars.count && !(chars[i] == "*" && chars[i + 1] == "/") { i += 1 }
                i = min(chars.count, i + 2)
                appendToken(String(chars[start..<i]), color: commentColor, italic: true)
                continue
            }

            // String literal (`"..."` or `'...'`)
            if ch == "\"" || ch == "'" {
                let quote = ch
                let start = i
                i += 1
                while i < chars.count && chars[i] != "\n" {
                    if chars[i] == "\\" && i + 1 < chars.count {
                        i += 2
                        continue
                    }
                    if chars[i] == quote {
                        i += 1
                        break
                    }
                    i += 1
                }
                appendToken(String(chars[start..<i]), color: StepCardPalette.emeraldDone)
                continue
            }

            // Decorator / Swift attribute (`@MainActor`, `@Observable`, `@testable`)
            if ch == "@" && i + 1 < chars.count && chars[i + 1].isLetter {
                let start = i
                i += 1
                while i < chars.count && (chars[i].isLetter || chars[i].isNumber || chars[i] == "_") { i += 1 }
                appendToken(String(chars[start..<i]), color: StepCardPalette.softViolet)
                continue
            }

            // Number literal
            if ch.isASCII && ch.isNumber {
                let start = i
                while i < chars.count && (chars[i].isHexDigit || chars[i] == "." || chars[i] == "_" || chars[i] == "x" || chars[i] == "X") {
                    i += 1
                }
                appendToken(String(chars[start..<i]), color: StepCardPalette.warmAmber)
                continue
            }

            // Identifier / Keyword / PascalCase Type
            if ch.isLetter || ch == "_" {
                let start = i
                while i < chars.count && (chars[i].isLetter || chars[i].isNumber || chars[i] == "_") { i += 1 }
                let word = String(chars[start..<i])
                if commonKeywords.contains(word) || (language == "sql" && commonKeywords.contains(word.uppercased())) {
                    appendToken(word, color: StepCardPalette.periwinkle)
                } else if let first = word.first, first.isASCII && first.isUppercase && word.count >= 2 {
                    appendToken(word, color: StepCardPalette.softViolet)
                } else {
                    appendToken(word, color: AntigravityTheme.inkReading)
                }
                continue
            }

            // Batch plain punctuation / whitespace
            let start = i
            i += 1
            while i < chars.count {
                let c = chars[i]
                if c.isLetter || c == "_" || (c.isASCII && c.isNumber) || c == "\"" || c == "'" || c == "/" || c == "#" || c == "@" || (dashComments && c == "-") {
                    break
                }
                i += 1
            }
            appendToken(String(chars[start..<i]), color: AntigravityTheme.inkReading)
        }

        return out
    }
}

// MARK: - Blockquote & GitHub Alert Callout Card (`[!NOTE]`, `[!TIP]`, `[!IMPORTANT]`, `[!WARNING]`, `[!CAUTION]`)

private struct MarkdownBlockquoteCardView: View {
    let alert: MarkdownAlertKind?
    let innerBlocks: [MarkdownBlock]
    let store: AntigravitySessionStore?

    var body: some View {
        if let alert {
            let accent = alertAccent(for: alert)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: alert.sfSymbolName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(accent)
                    Text(alert.displayTitle)
                        .font(.system(size: 13.5, weight: .bold))
                        .foregroundStyle(accent)
                }

                if !innerBlocks.isEmpty {
                    AnyView(AntigravityMarkdownBlocksView(blocks: innerBlocks, variant: .blockquote, store: store))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(accent.opacity(0.08))
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(accent)
                    .frame(width: 3)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(accent.opacity(0.24), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(StepCardPalette.periwinkle.opacity(0.55))
                    .frame(width: 3)

                AnyView(AntigravityMarkdownBlocksView(blocks: innerBlocks, variant: .blockquote, store: store))
                    .padding(.vertical, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func alertAccent(for kind: MarkdownAlertKind) -> Color {
        switch kind {
        case .note: return StepCardPalette.periwinkle
        case .tip: return StepCardPalette.emeraldDone
        case .important: return StepCardPalette.softViolet
        case .warning: return StepCardPalette.warmAmber
        case .caution: return StepCardPalette.coralError
        }
    }
}

// MARK: - GFM Pipe & HTML Table Card (Horizontal Scroll + Column Alignment + `<br>` Support)

private struct MarkdownTableCardView: View {
    let headers: [[MarkdownInline]]
    let alignments: [MarkdownTableAlignment]
    let rows: [[[MarkdownInline]]]

    private var columnCount: Int {
        headers.count
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(0..<columnCount, id: \.self) { colIdx in
                        RichMarkdownInlineBlockView(
                            inlines: headers[colIdx],
                            baseSize: 13.0,
                            baseWeight: .semibold,
                            defaultColor: AntigravityTheme.inkReading,
                            lineSpacing: 2.0,
                            textAlignment: textAlignment(for: colIdx),
                            expandsToProposedWidth: false
                        )
                        .frame(maxWidth: 260, alignment: frameAlignment(for: colIdx))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .gridColumnAlignment(horizontalAlignment(for: colIdx))
                    }
                }
                .background(Color.white.opacity(0.05))

                Rectangle()
                    .fill(Color.white.opacity(0.09))
                    .frame(height: 1)

                ForEach(0..<rows.count, id: \.self) { rowIdx in
                    GridRow {
                        ForEach(0..<columnCount, id: \.self) { colIdx in
                            let cellInlines: [MarkdownInline] = colIdx < rows[rowIdx].count ? rows[rowIdx][colIdx] : []
                            RichMarkdownInlineBlockView(
                                inlines: cellInlines,
                                baseSize: 13.0,
                                baseWeight: .regular,
                                defaultColor: AntigravityTheme.inkLabel,
                                lineSpacing: 2.0,
                                textAlignment: textAlignment(for: colIdx),
                                expandsToProposedWidth: false
                            )
                            .frame(maxWidth: 260, alignment: frameAlignment(for: colIdx))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                        }
                    }
                    .background(rowIdx.isMultiple(of: 2) ? Color.clear : Color.white.opacity(0.02))

                    if rowIdx + 1 < rows.count {
                        Rectangle()
                            .fill(Color.white.opacity(0.05))
                            .frame(height: 1)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(StepCardPalette.cardSurface)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func horizontalAlignment(for colIdx: Int) -> HorizontalAlignment {
        guard colIdx < alignments.count else { return .leading }
        switch alignments[colIdx] {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }

    private func textAlignment(for colIdx: Int) -> TextAlignment {
        guard colIdx < alignments.count else { return .leading }
        switch alignments[colIdx] {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }

    private func frameAlignment(for colIdx: Int) -> Alignment {
        guard colIdx < alignments.count else { return .leading }
        switch alignments[colIdx] {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }
}

// MARK: - Display Math Block Card (`$$ ... $$` / `\[ ... \]`)

private struct MarkdownMathBlockCardView: View {
    let latex: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(MarkdownMathNormalizer.prettify(latex))
                .font(.system(size: 13.5, weight: .regular, design: .serif).italic())
                .foregroundStyle(StepCardPalette.inlineCodeInk)
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(StepCardPalette.codeBlockBg)
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - SwiftUI `AttributedString` Fallback Builder (Zero `\u{200A}` Orphan Spaces)

private enum MarkdownInlineBuilder {
    struct StyleState {
        var isBold: Bool = false
        var isItalic: Bool = false
        var isStrikethrough: Bool = false
        var isUnderline: Bool = false
        var isHighlight: Bool = false
        var isCode: Bool = false
        var isKeyboardKey: Bool = false
        var isMath: Bool = false
        var baseWeight: Font.Weight = .regular
        var linkDestination: String? = nil

        func resolvedFont(baseSize: CGFloat) -> Font {
            if isKeyboardKey {
                return Font.system(size: max(11.0, baseSize - 2.5), weight: .semibold, design: .monospaced)
            }
            if isCode {
                let codeSize = max(11.5, baseSize - 1.7)
                let codeWeight: Font.Weight = isBold ? .semibold : .medium
                return Font.system(size: codeSize, weight: codeWeight, design: .monospaced)
            }
            if isMath {
                let mathFont = Font.system(size: max(12.5, baseSize - 0.5), weight: isBold ? .semibold : .regular, design: .serif)
                return mathFont.italic()
            }
            let weight: Font.Weight = isBold ? .bold : baseWeight
            let font = Font.system(size: baseSize, weight: weight, design: .default)
            return isItalic ? font.italic() : font
        }

        func resolvedForeground(defaultColor: Color) -> Color {
            if linkDestination != nil {
                return StepCardPalette.periwinkle
            }
            if isCode || isMath || isKeyboardKey {
                return StepCardPalette.inlineCodeInk
            }
            return defaultColor
        }

        var resolvedBackground: Color? {
            if isCode || isKeyboardKey {
                if linkDestination != nil {
                    return StepCardPalette.periwinkle.opacity(0.14)
                }
                return Color.white.opacity(0.09)
            }
            if isHighlight {
                return StepCardPalette.warmAmber.opacity(0.22)
            }
            return nil
        }

        var resolvedLinkURL: URL? {
            guard let dest = linkDestination else { return nil }
            return MarkdownLinkFormatting.resolvedActionURL(for: dest)
        }
    }

    static func build(
        _ nodes: [MarkdownInline],
        baseSize: CGFloat,
        baseWeight: Font.Weight,
        defaultColor: Color
    ) -> AttributedString {
        var output = AttributedString()
        let initial = StyleState(baseWeight: baseWeight)
        appendNodes(nodes, style: initial, baseSize: baseSize, defaultColor: defaultColor, into: &output)
        return output
    }

    private static func appendNodes(
        _ nodes: [MarkdownInline],
        style: StyleState,
        baseSize: CGFloat,
        defaultColor: Color,
        into output: inout AttributedString
    ) {
        for node in nodes {
            switch node {
            case .text(let s):
                output.append(makeSegment(s, style: style, baseSize: baseSize, defaultColor: defaultColor))
            case .softBreak:
                output.append(makeSegment("\n", style: style, baseSize: baseSize, defaultColor: defaultColor))
            case .code(let codeText):
                var codeStyle = style
                codeStyle.isCode = true
                output.append(makeSegment(codeText, style: codeStyle, baseSize: baseSize, defaultColor: defaultColor))
            case .keyboardKey(let keyText):
                var kbdStyle = style
                kbdStyle.isKeyboardKey = true
                output.append(makeSegment(keyText, style: kbdStyle, baseSize: baseSize, defaultColor: defaultColor))
            case .strong(let children):
                var boldStyle = style
                boldStyle.isBold = true
                appendNodes(children, style: boldStyle, baseSize: baseSize, defaultColor: defaultColor, into: &output)
            case .emphasis(let children):
                var italicStyle = style
                italicStyle.isItalic = true
                appendNodes(children, style: italicStyle, baseSize: baseSize, defaultColor: defaultColor, into: &output)
            case .strikethrough(let children):
                var strikeStyle = style
                strikeStyle.isStrikethrough = true
                appendNodes(children, style: strikeStyle, baseSize: baseSize, defaultColor: defaultColor, into: &output)
            case .underline(let children):
                var underStyle = style
                underStyle.isUnderline = true
                appendNodes(children, style: underStyle, baseSize: baseSize, defaultColor: defaultColor, into: &output)
            case .highlight(let children):
                var hiStyle = style
                hiStyle.isHighlight = true
                appendNodes(children, style: hiStyle, baseSize: baseSize, defaultColor: defaultColor, into: &output)
            case .superscript(let text):
                output.append(makeSegment(MarkdownMathNormalizer.toSuperscript(text), style: style, baseSize: baseSize, defaultColor: defaultColor))
            case .subscriptText(let text):
                output.append(makeSegment(MarkdownMathNormalizer.toSubscript(text), style: style, baseSize: baseSize, defaultColor: defaultColor))
            case .link(let labelNodes, let destination):
                var linkStyle = style
                linkStyle.linkDestination = destination
                appendNodes(labelNodes, style: linkStyle, baseSize: baseSize, defaultColor: defaultColor, into: &output)
            case .inlineMath(let latex):
                var mathStyle = style
                mathStyle.isMath = true
                output.append(makeSegment(MarkdownMathNormalizer.prettify(latex), style: mathStyle, baseSize: baseSize, defaultColor: defaultColor))
            case .inlineImage(let alt, let src):
                var imgStyle = style
                imgStyle.linkDestination = src
                let label = alt.isEmpty ? MarkdownLinkFormatting.shortFileBadge(src) : alt
                output.append(makeSegment("🖼 \(label)", style: imgStyle, baseSize: baseSize, defaultColor: defaultColor))
            case .footnoteRef(let label):
                output.append(makeSegment("[\(label)]", style: style, baseSize: max(10, baseSize - 3), defaultColor: StepCardPalette.periwinkle))
            }
        }
    }

    private static func makeSegment(
        _ string: String,
        style: StyleState,
        baseSize: CGFloat,
        defaultColor: Color
    ) -> AttributedString {
        var seg = AttributedString(string)
        seg.swiftUI.font = style.resolvedFont(baseSize: baseSize)
        seg.swiftUI.foregroundColor = style.resolvedForeground(defaultColor: defaultColor)
        if let bg = style.resolvedBackground {
            seg.swiftUI.backgroundColor = bg
        }
        if style.isStrikethrough {
            seg.swiftUI.strikethroughStyle = Text.LineStyle.single
        }
        if style.isUnderline {
            seg.swiftUI.underlineStyle = Text.LineStyle.single
        }
        if let url = style.resolvedLinkURL {
            seg.link = url
        }
        return seg
    }
}

// MARK: - Link & Clipboard Helpers

private enum MarkdownLinkFormatting {
    static func resolvedActionURL(for rawDestination: String) -> URL? {
        let trimmed = rawDestination.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lower = trimmed.lowercased()
        if lower.hasPrefix("https://") || lower.hasPrefix("http://") || lower.hasPrefix("mailto:") || lower.hasPrefix("antigravity://") {
            if let direct = URL(string: trimmed) {
                return direct
            }
        }
        var comps = URLComponents()
        comps.scheme = "antigravity-ref"
        comps.host = "copy"
        comps.queryItems = [URLQueryItem(name: "ref", value: cleanDisplayPath(trimmed))]
        return comps.url
    }

    static func extractCopiedReference(from url: URL) -> String {
        if let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let ref = comps.queryItems?.first(where: { $0.name == "ref" })?.value,
           !ref.isEmpty {
            return ref
        }
        return url.absoluteString
    }

    static func cleanDisplayPath(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.lowercased().hasPrefix("file://") {
            s = String(s.dropFirst("file://".count))
        }
        if let decoded = s.removingPercentEncoding {
            s = decoded
        }
        return s
    }

    static func shortFileBadge(_ raw: String) -> String {
        let cleaned = cleanDisplayPath(raw)
        let parts = cleaned.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        let pathPart = String(parts[0])
        let fragmentSuffix: String
        if parts.count > 1 && !parts[1].isEmpty {
            fragmentSuffix = "#\(parts[1])"
        } else {
            fragmentSuffix = ""
        }
        let base = (pathPart as NSString).lastPathComponent
        let chosen = base.isEmpty ? pathPart : base
        return chosen + fragmentSuffix
    }
}

private enum MarkdownClipboardHelper {
    @MainActor
    static func copyText(_ text: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        #endif
    }
}

private enum MarkdownMathNormalizer {
    private static let replacements: [(String, String)] = [
        ("\\leftrightarrow", "↔"),
        ("\\Leftrightarrow", "⇔"),
        ("\\rightarrow", "→"),
        ("\\Rightarrow", "⇒"),
        ("\\leftarrow", "←"),
        ("\\Leftarrow", "⇐"),
        ("\\implies", "⇒"),
        ("\\mapsto", "↦"),
        ("\\approx", "≈"),
        ("\\equiv", "≡"),
        ("\\propto", "∝"),
        ("\\times", "×"),
        ("\\cdot", "·"),
        ("\\div", "÷"),
        ("\\pm", "±"),
        ("\\mp", "∓"),
        ("\\leq", "≤"),
        ("\\le", "≤"),
        ("\\geq", "≥"),
        ("\\ge", "≥"),
        ("\\neq", "≠"),
        ("\\ne", "≠"),
        ("\\to", "→"),
        ("\\infty", "∞"),
        ("\\partial", "∂"),
        ("\\nabla", "∇"),
        ("\\forall", "∀"),
        ("\\exists", "∃"),
        ("\\notin", "∉"),
        ("\\in", "∈"),
        ("\\subseteq", "⊆"),
        ("\\subset", "⊂"),
        ("\\cup", "∪"),
        ("\\cap", "∩"),
        ("\\emptyset", "∅"),
        ("\\sum", "∑"),
        ("\\prod", "∏"),
        ("\\int", "∫"),
        ("\\sqrt", "√"),
        ("\\alpha", "α"),
        ("\\beta", "β"),
        ("\\gamma", "γ"),
        ("\\Gamma", "Γ"),
        ("\\delta", "δ"),
        ("\\Delta", "Δ"),
        ("\\epsilon", "ε"),
        ("\\theta", "θ"),
        ("\\Theta", "Θ"),
        ("\\lambda", "λ"),
        ("\\Lambda", "Λ"),
        ("\\mu", "μ"),
        ("\\pi", "π"),
        ("\\Pi", "Π"),
        ("\\rho", "ρ"),
        ("\\sigma", "σ"),
        ("\\Sigma", "Σ"),
        ("\\tau", "τ"),
        ("\\phi", "φ"),
        ("\\Phi", "Φ"),
        ("\\omega", "ω"),
        ("\\Omega", "Ω"),
        ("\\mathbb{R}", "ℝ"),
        ("\\mathbb{N}", "ℕ"),
        ("\\mathbb{Z}", "ℤ"),
        ("\\mathbb{Q}", "ℚ"),
        ("\\mathbb{C}", "ℂ"),
        ("\\ldots", "…"),
        ("\\cdots", "⋯"),
    ]

    private static let superscriptMap: [Character: Character] = [
        "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴",
        "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹",
        "+": "⁺", "-": "⁻", "=": "⁼", "(": "⁽", ")": "⁾",
        "n": "ⁿ", "i": "ⁱ"
    ]

    private static let subscriptMap: [Character: Character] = [
        "0": "₀", "1": "₁", "2": "₂", "3": "₃", "4": "₄",
        "5": "₅", "6": "₆", "7": "₇", "8": "₈", "9": "₉",
        "+": "₊", "-": "₋", "=": "₌", "(": "₍", ")": "₎",
        "i": "ᵢ", "j": "ⱼ", "n": "ₙ", "k": "ₖ", "x": "ₓ"
    ]

    static func toSuperscript(_ s: String) -> String {
        String(s.map { superscriptMap[$0] ?? $0 })
    }

    static func toSubscript(_ s: String) -> String {
        String(s.map { subscriptMap[$0] ?? $0 })
    }

    static func prettify(_ raw: String) -> String {
        var out = raw
        // Simplify `\frac{a}{b}` -> `(a)/(b)` and `\text{foo}` -> `foo`
        out = replaceFrac(in: out)
        out = stripUnaryMacro("\\text", in: out)
        out = stripUnaryMacro("\\mathrm", in: out)
        out = stripUnaryMacro("\\mathbf", in: out)
        for (token, symbol) in replacements {
            out = out.replacingOccurrences(of: token, with: symbol)
        }
        out = replaceScripts(in: out)
        return out
    }

    private static func replaceFrac(in text: String) -> String {
        var s = text
        while let range = s.range(of: "\\frac{") {
            let after = range.upperBound
            guard let firstClose = findMatchingBrace(in: s, from: after),
                  s.index(after: firstClose) < s.endIndex,
                  s[s.index(after: firstClose)] == "{",
                  let secondClose = findMatchingBrace(in: s, from: s.index(firstClose, offsetBy: 2)) else {
                break
            }
            let num = String(s[after..<firstClose])
            let den = String(s[s.index(firstClose, offsetBy: 2)..<secondClose])
            let replacement = "\(num)/\(den)"
            s.replaceSubrange(range.lowerBound...secondClose, with: replacement)
        }
        return s
    }

    private static func stripUnaryMacro(_ macro: String, in text: String) -> String {
        var s = text
        let token = "\(macro){"
        while let range = s.range(of: token) {
            guard let closeIdx = findMatchingBrace(in: s, from: range.upperBound) else { break }
            let inner = String(s[range.upperBound..<closeIdx])
            s.replaceSubrange(range.lowerBound...closeIdx, with: inner)
        }
        return s
    }

    private static func findMatchingBrace(in text: String, from start: String.Index) -> String.Index? {
        var depth = 1
        var idx = start
        while idx < text.endIndex {
            let ch = text[idx]
            if ch == "{" { depth += 1 }
            else if ch == "}" {
                depth -= 1
                if depth == 0 { return idx }
            }
            idx = text.index(after: idx)
        }
        return nil
    }

    private static func replaceScripts(in text: String) -> String {
        let chars = Array(text)
        var out = ""
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            if (ch == "^" || ch == "_"), i + 1 < chars.count {
                let isSup = (ch == "^")
                if chars[i + 1] == "{" {
                    var j = i + 2
                    while j < chars.count && chars[j] != "}" { j += 1 }
                    if j < chars.count {
                        let inner = String(chars[(i + 2)..<j])
                        let map = isSup ? superscriptMap : subscriptMap
                        if inner.allSatisfy({ map[$0] != nil }) {
                            out.append(isSup ? toSuperscript(inner) : toSubscript(inner))
                            i = j + 1
                            continue
                        }
                    }
                } else {
                    let next = chars[i + 1]
                    let map = isSup ? superscriptMap : subscriptMap
                    if let mapped = map[next] {
                        out.append(mapped)
                        i += 2
                        continue
                    }
                }
            }
            out.append(ch)
            i += 1
        }
        return out
    }
}
