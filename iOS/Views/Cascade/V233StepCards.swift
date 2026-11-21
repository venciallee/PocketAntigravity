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

internal struct V233InlineApprovalCardView: View {
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
