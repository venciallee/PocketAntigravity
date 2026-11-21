import SwiftUI
import AntigravityData

// MARK: - Antigravity 2.0 (v2.33) Step Cards (Subagent, Workflow, Swarm, MCP, Voice Summary, PR Pills, Extended Approvals)

internal struct SubagentStepCardView: View {
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

internal struct DynamicWorkflowStepCardView: View {
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

internal struct SwarmStepCardView: View {
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

internal struct McpToolStepCardView: View {
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

internal struct VoiceCallSummaryCardView: View {
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

internal struct GitHubPRStatusPillsRow: View {
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

public struct StepInlineApprovalCardView: View {
    @Bindable public var store: AntigravitySessionStore
    public let step: CascadeStep
    public let requested: RequestedInteraction

    public init(
        store: AntigravitySessionStore,
        step: CascadeStep,
        requested: RequestedInteraction
    ) {
        self.store = store
        self.step = step
        self.requested = requested
    }

    private struct CardDescriptor {
        let icon: String
        let title: String
        let detail: String
        let secondaryNote: String?
        let primaryLabel: String
        let supportsScopedAllow: Bool
    }

    private var descriptor: CardDescriptor {
        switch requested.kind {
        case .permission:
            let action = requested.permission?.action ?? "action"
            let target = requested.permission?.target ?? "*"
            let plugin = requested.permission?.pluginName.map { " [\($0)]" } ?? ""
            let allowScopes = (requested.permission?.persistSuggestionType != .blocked)
            return CardDescriptor(
                icon: "exclamationmark.shield.fill",
                title: "Permission Request\(plugin)",
                detail: "\(action)(\(target))",
                secondaryNote: requested.permission?.reason,
                primaryLabel: "Allow Once",
                supportsScopedAllow: allowScopes
            )
        case .filePermission:
            let rawPath = requested.filePermission?.absolutePathUri
                ?? step.viewFile?.fileUri
                ?? step.codeAction?.targetFileUri
                ?? ""
            let cleanedPath = rawPath.replacingOccurrences(of: "file://", with: "")
            let isDir = requested.filePermission?.isDirectory ?? (step.type == .listDirectory)
            return CardDescriptor(
                icon: isDir ? "folder.badge.questionmark" : "doc.badge.gearshape",
                title: isDir ? "Folder Access Approval" : "File Access Approval",
                detail: cleanedPath.isEmpty ? "Confirm access to workspace or external file" : cleanedPath,
                secondaryNote: requested.filePermission?.blockReason,
                primaryLabel: "Allow Once",
                supportsScopedAllow: true
            )
        case .executeUrl, .openBrowserUrl, .browserAction, .executeBrowserJavascript,
             .captureBrowserScreenshot, .clickBrowserPixel, .openBrowserSetup, .confirmBrowserSetup:
            let domain = requested.executeUrl?.domain ?? "Browser"
            let detail = requested.executeUrl?.url
                ?? requested.rawSummary
                ?? "Allow agent to continue browser action"
            return CardDescriptor(
                icon: "safari.fill",
                title: "Browser Action · \(domain)",
                detail: detail.isEmpty ? "Allow agent to continue browser action" : detail,
                secondaryNote: nil,
                primaryLabel: "Allow Once",
                supportsScopedAllow: true
            )
        case .downloadUrl:
            let file = requested.downloadUrl?.fileName ?? "file"
            let origin = requested.downloadUrl?.origin ?? ""
            return CardDescriptor(
                icon: "arrow.down.circle.fill",
                title: "Browser Download · \(file)",
                detail: "From \(origin) → \(requested.downloadUrl?.destinationFolder ?? "~/Downloads")",
                secondaryNote: nil,
                primaryLabel: "Allow Once",
                supportsScopedAllow: true
            )
        case .browserUpload:
            let files = requested.browserUpload?.fileNames.joined(separator: ", ") ?? "files"
            return CardDescriptor(
                icon: "arrow.up.doc.fill",
                title: "One-Time Upload Confirmation",
                detail: "Upload \(files) to \(requested.browserUpload?.origin ?? "site")",
                secondaryNote: nil,
                primaryLabel: "Allow Once",
                supportsScopedAllow: false
            )
        case .workflowScript:
            return CardDescriptor(
                icon: "flowchart.fill",
                title: "Approve Dynamic Workflow Script",
                detail: requested.workflowScript?.title ?? "Python orchestrator script",
                secondaryNote: nil,
                primaryLabel: "Approve",
                supportsScopedAllow: false
            )
        case .mcp:
            let server = requested.mcpServerName ?? step.mcpToolCall?.serverName ?? "MCP"
            let tool = requested.mcpToolName ?? step.mcpToolCall?.toolName ?? "tool"
            return CardDescriptor(
                icon: "wrench.and.screwdriver.fill",
                title: "MCP Tool Approval · \(server)",
                detail: "Invoke \(tool)",
                secondaryNote: requested.rawSummary,
                primaryLabel: "Allow Once",
                supportsScopedAllow: true
            )
        case .sendCommandInput:
            let stdinText = requested.rawSummary ?? step.runCommand?.commandLine ?? "Send input to running terminal process"
            return CardDescriptor(
                icon: "terminal.fill",
                title: "Send Terminal Input?",
                detail: stdinText,
                secondaryNote: nil,
                primaryLabel: "Approve",
                supportsScopedAllow: false
            )
        case .readUrlContent:
            return CardDescriptor(
                icon: "globe",
                title: "Fetch External URL?",
                detail: requested.rawSummary ?? "Allow agent to fetch external web content",
                secondaryNote: nil,
                primaryLabel: "Allow Once",
                supportsScopedAllow: true
            )
        case .deploy:
            return CardDescriptor(
                icon: "paperplane.fill",
                title: "Confirm Deployment?",
                detail: requested.rawSummary ?? "Allow agent to proceed with deployment",
                secondaryNote: nil,
                primaryLabel: "Approve",
                supportsScopedAllow: false
            )
        case .runExtensionCode:
            return CardDescriptor(
                icon: "puzzlepiece.extension.fill",
                title: "Run Extension Action?",
                detail: requested.rawSummary ?? "Allow agent to execute IDE extension action",
                secondaryNote: nil,
                primaryLabel: "Allow Once",
                supportsScopedAllow: false
            )
        default:
            let fallbackCandidates: [String?] = [
                requested.rawSummary,
                requested.filePermission?.absolutePathUri,
                step.viewFile?.fileUri,
                step.codeAction?.targetFileUri,
                step.search?.query,
                step.runCommand?.commandLine
            ]
            let fallbackDetail = fallbackCandidates
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first(where: { !$0.isEmpty })
                ?? "Step \(step.stepIndex + 1) is waiting for your approval to continue."
            let title: String = {
                if step.type == .notifyUser {
                    return "Waiting for Your Review"
                }
                if let key = requested.rawMemberKey, !key.isEmpty, key != "approvalInteraction" {
                    return "Approval Required · \(key)"
                }
                return "Approval Required · Step \(step.stepIndex + 1)"
            }()
            return CardDescriptor(
                icon: "exclamationmark.shield.fill",
                title: title,
                detail: fallbackDetail,
                secondaryNote: nil,
                primaryLabel: "Approve",
                supportsScopedAllow: false
            )
        }
    }

    public var body: some View {
        if requested.kind == .runCommand {
            let resolvedCmd = requested.runCommand?.proposedCommandLine
                ?? step.runCommand?.proposedCommandLine
                ?? step.runCommand?.commandLine
                ?? ""
            InlineCommandApprovalCardView(
                store: store,
                commandLine: resolvedCmd,
                stepIndex: step.stepIndex,
                hostName: store.activeSummary?.originHostName ?? store.activeHost.hostname
            )
        } else if requested.kind == .askQuestion || requested.kind == .elicitation {
            Button {
                store.syncActiveLiveQuestionFromSteps(stepIndex: step.stepIndex)
                store.presentedSheet = .askQuestion(stepIndex: step.stepIndex)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "list.bullet.rectangle.portrait.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(StepCardPalette.warmAmber)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Structured Question Pending")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(StepCardPalette.warmAmber)
                        Text(requested.askQuestion?.question ?? requested.rawSummary ?? "Tap to answer agent question")
                            .font(.system(size: 13))
                            .foregroundStyle(AntigravityTheme.inkReading)
                            .lineLimit(3)
                    }
                    Spacer(minLength: 6)
                    Text("Answer")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(StepCardPalette.inkOnCTA)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 36)
                        .background(StepCardPalette.warmAmber, in: Capsule())
                }
                .padding(14)
                .background(StepCardPalette.amberCardSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(StepCardPalette.warmAmber.opacity(0.35), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("card-step-approval-\(step.stepIndex)")
        } else if requested.isUnrecognizedWireMember && (requested.rawMemberKey?.isEmpty != false) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "desktopcomputer.and.arrow.down")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(StepCardPalette.warmAmber)
                    Text("New Approval Type · Approve on Desktop")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(StepCardPalette.warmAmber)
                        .lineLimit(2)
                    Spacer()
                    if let fieldNum = requested.rawWireFieldNumber {
                        Text("#\(fieldNum)")
                            .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(AntigravityTheme.inkSecondary)
                    }
                }

                if let summary = requested.rawSummary?.trimmingCharacters(in: .whitespacesAndNewlines), !summary.isEmpty {
                    Text(summary)
                        .font(.system(size: 12.5, design: .monospaced))
                        .foregroundStyle(AntigravityTheme.inkReading)
                        .lineSpacing(2)
                        .lineLimit(4)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(StepCardPalette.codeBlockBg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                Text("This Antigravity Desktop host requested an interaction schema newer than this iOS build. Approve or deny it directly in Antigravity Desktop, then refresh.")
                    .font(.system(size: 12))
                    .foregroundStyle(AntigravityTheme.inkSecondary)

                Button {
                    store.syncStepsForCascade(step.cascadeId, pollUntilIdle: false)
                } label: {
                    Label("Refresh Status", systemImage: "arrow.clockwise")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(AntigravityTheme.inkReading)
                        .frame(maxWidth: .infinity, minHeight: AntigravityTheme.minTouchTargetPt)
                        .background(StepCardPalette.neutralButtonBg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("btn-step-approval-refresh-\(step.stepIndex)")
            }
            .padding(14)
            .background(StepCardPalette.amberCardSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(StepCardPalette.warmAmber.opacity(0.35), lineWidth: 1)
            )
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("card-step-approval-desktop-required-\(step.stepIndex)")
        } else {
            let info = descriptor
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: info.icon)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(StepCardPalette.warmAmber)
                    Text(info.title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(StepCardPalette.warmAmber)
                        .lineLimit(2)
                    Spacer()
                }

                Text(info.detail)
                    .font(.system(size: 12.5, design: .monospaced))
                    .foregroundStyle(AntigravityTheme.inkReading)
                    .lineSpacing(2)
                    .lineLimit(4)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(StepCardPalette.codeBlockBg)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.06), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                if let note = info.secondaryNote, !note.isEmpty {
                    Text(note)
                        .font(.system(size: 12))
                        .foregroundStyle(AntigravityTheme.inkSecondary)
                        .lineLimit(2)
                }

                HStack(spacing: 8) {
                    Button {
                        store.resolveWaitingStep(stepIndex: step.stepIndex, decision: .reject)
                    } label: {
                        Text("Deny")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AntigravityTheme.inkReading)
                            .padding(.horizontal, 16)
                            .frame(maxWidth: info.supportsScopedAllow ? nil : CGFloat.infinity, minHeight: AntigravityTheme.minTouchTargetPt)
                            .background(StepCardPalette.neutralButtonBg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("btn-step-deny-\(step.stepIndex)")

                    Button {
                        store.resolveWaitingStep(stepIndex: step.stepIndex, decision: .allowOnce)
                    } label: {
                        Text(info.primaryLabel)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(StepCardPalette.inkOnCTA)
                            .frame(maxWidth: .infinity, minHeight: AntigravityTheme.minTouchTargetPt)
                            .background(StepCardPalette.warmAmber, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("btn-step-approve-\(step.stepIndex)")
                }

                if info.supportsScopedAllow {
                    HStack(spacing: 8) {
                        Button {
                            store.resolveWaitingStep(stepIndex: step.stepIndex, decision: .allowInConversation)
                        } label: {
                            Text("Allow in Chat")
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(AntigravityTheme.inkReading)
                                .frame(maxWidth: .infinity, minHeight: 38)
                                .background(AntigravityTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        Button {
                            store.resolveWaitingStep(stepIndex: step.stepIndex, decision: .alwaysAllow)
                        } label: {
                            Text("Always Allow")
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(StepCardPalette.periwinkle)
                                .frame(maxWidth: .infinity, minHeight: 38)
                                .background(StepCardPalette.periwinkle.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                } else if step.type == .notifyUser && !store.activeArtifacts.isEmpty {
                    Button {
                        store.currentRoute = .planReview
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.text.magnifyingglass")
                                .font(.system(size: 12.5, weight: .semibold))
                            Text("Review Plan & Comment")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundStyle(StepCardPalette.periwinkle)
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .background(StepCardPalette.periwinkle.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(14)
            .background(StepCardPalette.amberCardSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(StepCardPalette.warmAmber.opacity(0.32), lineWidth: 1)
            )
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("card-step-approval-\(step.stepIndex)")
        }
    }
}

internal struct InlineGenericInteractionCardView: View {
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

internal struct ReferencedFilePillsRow: View {
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
