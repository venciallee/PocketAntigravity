import SwiftUI
import AntigravityData

// MARK: - Antigravity 2.0 (v2.33) Step Cards (Subagent, Workflow, Swarm, MCP, Voice Summary, PR Pills, Extended Approvals)

internal struct SubagentStepCardView: View {
    let subagent: SubagentPayload
    let onStop: () -> Void
    @Environment(\.appLanguage) private var lang

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "person.2.wave.2.fill")
                    .foregroundStyle(AntigravityTheme.accentPeriwinkle)
                VStack(alignment: .leading, spacing: 2) {
                    Text(subagent.role)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(AntigravityTheme.inkReading)
                    Text("\(subagent.typeName) · \(subagent.modelLabel)")
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(AntigravityTheme.inkSecondary)
                }
                Spacer()
                Text(subagent.status.localizedTitle(for: lang))
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(AntigravityTheme.accentPeriwinkle.opacity(0.16), in: Capsule())
                    .foregroundStyle(subagent.status == .done ? AntigravityTheme.statusDone : AntigravityTheme.accentPeriwinkle)
            }
            if !subagent.summary.isEmpty {
                Text(subagent.summary)
                    .font(.system(size: 12.5))
                    .foregroundStyle(AntigravityTheme.inkLabel)
                    .lineLimit(3)
            }
            if subagent.status == .inProgress || subagent.status == .waiting {
                Button(lang.t("Stop Subagent", "停止子代理"), action: onStop)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AntigravityTheme.statusError)
            }
        }
        .padding(12)
        .background(AntigravityTheme.surfaceCard, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AntigravityTheme.glassHairline, lineWidth: 1))
    }
}

internal struct DynamicWorkflowStepCardView: View {
    let workflow: DynamicWorkflowPayload
    @Environment(\.appLanguage) private var lang
    @State private var showScript: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(lang.t("Dynamic Workflow · \(workflow.currentPhase)", "动态工作流 · \(workflow.currentPhase)"), systemImage: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AntigravityTheme.accentPeriwinkle)
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
                        .foregroundStyle(phase.isCompleted ? AntigravityTheme.statusDone : AntigravityTheme.accentPeriwinkle)
                    Text(phase.name)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(AntigravityTheme.inkLabel)
                }
            }
            if !workflow.pythonScript.isEmpty {
                Button(showScript ? lang.t("Hide Python Orchestrator", "隐藏 Python 编排脚本") : lang.t("Inspect Python Orchestrator", "查看 Python 编排脚本")) {
                    showScript.toggle()
                }
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(AntigravityTheme.accentPeriwinkle)
                if showScript {
                    Text(workflow.pythonScript)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(AntigravityTheme.inkSecondary)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AntigravityTheme.surfaceCodeBlock, in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding(12)
        .background(AntigravityTheme.surfaceCard, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AntigravityTheme.glassHairline, lineWidth: 1))
    }
}

internal struct SwarmStepCardView: View {
    let board: SwarmBoardPayload
    let onOpenBoard: () -> Void
    @Environment(\.appLanguage) private var lang

    var body: some View {
        Button(action: onOpenBoard) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label(lang.t("Agent Swarm · \(board.title)", "多代理协作 · \(board.title)"), systemImage: "hexagon.fill")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(AntigravityTheme.accentPeriwinkle)
                    Spacer()
                    Text(lang.t("\(board.members.count) specialists", "\(board.members.count) 位专家"))
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
            .background(AntigravityTheme.surfaceCard, in: RoundedRectangle(cornerRadius: 14))
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
                    .foregroundStyle(mcp.isError ? AntigravityTheme.statusError : AntigravityTheme.accentPeriwinkle)
                Text("\(mcp.serverName) · \(mcp.toolName)")
                    .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(AntigravityTheme.inkReading)
                Spacer()
                if let plugin = mcp.pluginName {
                    Text(plugin)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(AntigravityTheme.accentPeriwinkle)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(AntigravityTheme.accentPeriwinkle.opacity(0.14), in: Capsule())
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
                    .background(AntigravityTheme.surfaceCodeBlock, in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(11)
        .background(AntigravityTheme.surfaceCard, in: RoundedRectangle(cornerRadius: 14))
    }
}

internal struct VoiceCallSummaryCardView: View {
    let summary: VoiceCallTranscriptSummary
    @Environment(\.appLanguage) private var lang
    @State private var isExpanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                isExpanded.toggle()
            } label: {
                HStack {
                    Image(systemName: "waveform.circle.fill")
                        .foregroundStyle(AntigravityTheme.accentPeriwinkle)
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
                    Text("\(turn.isUser ? lang.t("You", "我") : "Gemini"): \(turn.transcript)")
                        .font(.system(size: 12))
                        .foregroundStyle(AntigravityTheme.inkSecondary)
                }
            }
        }
        .padding(11)
        .background(AntigravityTheme.surfaceCard, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AntigravityTheme.accentPeriwinkle.opacity(0.25), lineWidth: 1))
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
                                    .background(AntigravityTheme.statusDone.opacity(0.18), in: Capsule())
                            }
                            .foregroundStyle(AntigravityTheme.statusDone)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(AntigravityTheme.surfaceCard, in: Capsule())
                            .overlay(Capsule().stroke(AntigravityTheme.statusDone.opacity(0.32), lineWidth: 1))
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

    private var lang: AppLanguage { store.appearancePreferences.language }

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
                title: lang.t("Permission Request\(plugin)", "权限请求\(plugin)"),
                detail: "\(action)(\(target))",
                secondaryNote: requested.permission?.reason,
                primaryLabel: lang.t("Allow Once", "仅允许一次"),
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
                title: isDir ? lang.t("Folder Access Approval", "文件夹访问审批") : lang.t("File Access Approval", "文件访问审批"),
                detail: cleanedPath.isEmpty ? lang.t("Confirm access to workspace or external file", "确认访问工作区或外部文件") : cleanedPath,
                secondaryNote: requested.filePermission?.blockReason,
                primaryLabel: lang.t("Allow Once", "仅允许一次"),
                supportsScopedAllow: true
            )
        case .executeUrl, .openBrowserUrl, .browserAction, .executeBrowserJavascript,
             .captureBrowserScreenshot, .clickBrowserPixel, .openBrowserSetup, .confirmBrowserSetup:
            let domain = requested.executeUrl?.domain ?? lang.t("Browser", "浏览器")
            let detail = requested.executeUrl?.url
                ?? requested.rawSummary
                ?? lang.t("Allow agent to continue browser action", "允许 Agent 继续执行浏览器操作")
            return CardDescriptor(
                icon: "safari.fill",
                title: lang.t("Browser Action · \(domain)", "浏览器操作 · \(domain)"),
                detail: detail.isEmpty ? lang.t("Allow agent to continue browser action", "允许 Agent 继续执行浏览器操作") : detail,
                secondaryNote: nil,
                primaryLabel: lang.t("Allow Once", "仅允许一次"),
                supportsScopedAllow: true
            )
        case .downloadUrl:
            let file = requested.downloadUrl?.fileName ?? "file"
            let origin = requested.downloadUrl?.origin ?? ""
            return CardDescriptor(
                icon: "arrow.down.circle.fill",
                title: lang.t("Browser Download · \(file)", "浏览器下载 · \(file)"),
                detail: lang.t("From \(origin) → \(requested.downloadUrl?.destinationFolder ?? "~/Downloads")", "从 \(origin) → \(requested.downloadUrl?.destinationFolder ?? "~/Downloads")"),
                secondaryNote: nil,
                primaryLabel: lang.t("Allow Once", "仅允许一次"),
                supportsScopedAllow: true
            )
        case .browserUpload:
            let files = requested.browserUpload?.fileNames.joined(separator: ", ") ?? "files"
            return CardDescriptor(
                icon: "arrow.up.doc.fill",
                title: lang.t("One-Time Upload Confirmation", "单次文件上传确认"),
                detail: lang.t("Upload \(files) to \(requested.browserUpload?.origin ?? "site")", "上传 \(files) 至 \(requested.browserUpload?.origin ?? "站点")"),
                secondaryNote: nil,
                primaryLabel: lang.t("Allow Once", "仅允许一次"),
                supportsScopedAllow: false
            )
        case .workflowScript:
            return CardDescriptor(
                icon: "flowchart.fill",
                title: lang.t("Approve Dynamic Workflow Script", "批准动态工作流脚本"),
                detail: requested.workflowScript?.title ?? lang.t("Python orchestrator script", "Python 编排脚本"),
                secondaryNote: nil,
                primaryLabel: lang.t("Approve", "批准"),
                supportsScopedAllow: false
            )
        case .mcp:
            let server = requested.mcpServerName ?? step.mcpToolCall?.serverName ?? "MCP"
            let tool = requested.mcpToolName ?? step.mcpToolCall?.toolName ?? "tool"
            return CardDescriptor(
                icon: "wrench.and.screwdriver.fill",
                title: lang.t("MCP Tool Approval · \(server)", "MCP 工具审批 · \(server)"),
                detail: lang.t("Invoke \(tool)", "调用 \(tool)"),
                secondaryNote: requested.rawSummary,
                primaryLabel: lang.t("Allow Once", "仅允许一次"),
                supportsScopedAllow: true
            )
        case .sendCommandInput:
            let stdinText = requested.rawSummary ?? step.runCommand?.commandLine ?? lang.t("Send input to running terminal process", "向运行中的终端进程发送输入")
            return CardDescriptor(
                icon: "terminal.fill",
                title: lang.t("Send Terminal Input?", "发送终端输入？"),
                detail: stdinText,
                secondaryNote: nil,
                primaryLabel: lang.t("Approve", "批准"),
                supportsScopedAllow: false
            )
        case .readUrlContent:
            return CardDescriptor(
                icon: "globe",
                title: lang.t("Fetch External URL?", "读取外部网页？"),
                detail: requested.rawSummary ?? lang.t("Allow agent to fetch external web content", "允许 Agent 读取外部网页内容"),
                secondaryNote: nil,
                primaryLabel: lang.t("Allow Once", "仅允许一次"),
                supportsScopedAllow: true
            )
        case .deploy:
            return CardDescriptor(
                icon: "paperplane.fill",
                title: lang.t("Confirm Deployment?", "确认部署？"),
                detail: requested.rawSummary ?? lang.t("Allow agent to proceed with deployment", "允许 Agent 执行部署"),
                secondaryNote: nil,
                primaryLabel: lang.t("Approve", "批准"),
                supportsScopedAllow: false
            )
        case .runExtensionCode:
            return CardDescriptor(
                icon: "puzzlepiece.extension.fill",
                title: lang.t("Run Extension Action?", "运行扩展操作？"),
                detail: requested.rawSummary ?? lang.t("Allow agent to execute IDE extension action", "允许 Agent 执行 IDE 扩展操作"),
                secondaryNote: nil,
                primaryLabel: lang.t("Allow Once", "仅允许一次"),
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
                ?? lang.t("Step \(step.stepIndex + 1) is waiting for your approval to continue.", "第 \(step.stepIndex + 1) 步正等待你的审批以继续。")
            let title: String = {
                if step.type == .notifyUser {
                    return lang.t("Waiting for Your Review", "等待你的审查")
                }
                if let key = requested.rawMemberKey, !key.isEmpty, key != "approvalInteraction" {
                    return lang.t("Approval Required · \(key)", "需要审批 · \(key)")
                }
                return lang.t("Approval Required · Step \(step.stepIndex + 1)", "需要审批 · 第 \(step.stepIndex + 1) 步")
            }()
            return CardDescriptor(
                icon: "exclamationmark.shield.fill",
                title: title,
                detail: fallbackDetail,
                secondaryNote: nil,
                primaryLabel: lang.t("Approve", "批准"),
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
                        .foregroundStyle(AntigravityTheme.statusWaiting)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(lang.t("Structured Question Pending", "待回答结构化问题"))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(AntigravityTheme.statusWaiting)
                        Text(requested.askQuestion?.question ?? requested.rawSummary ?? lang.t("Tap to answer agent question", "点击回答 Agent 的问题"))
                            .font(.system(size: 13))
                            .foregroundStyle(AntigravityTheme.inkReading)
                            .lineLimit(3)
                    }
                    Spacer(minLength: 6)
                    Text(lang.t("Answer", "回答"))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(AntigravityTheme.inkOnAmberCTA)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 36)
                        .background(AntigravityTheme.statusWaiting, in: Capsule())
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
                        .stroke(AntigravityTheme.statusWaiting.opacity(0.35), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("card-step-approval-\(step.stepIndex)")
        } else if requested.isUnrecognizedWireMember && (requested.rawMemberKey?.isEmpty != false) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "desktopcomputer.and.arrow.down")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(AntigravityTheme.statusWaiting)
                    Text(lang.t("New Approval Type · Approve on Desktop", "新审批类型 · 请在桌面端处理"))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(AntigravityTheme.statusWaiting)
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
                        .background(AntigravityTheme.surfaceCodeBlock, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                Text(
                    lang.t(
                        "This Antigravity Desktop host requested an interaction schema newer than this iOS build. Approve or deny it directly in Antigravity Desktop, then refresh.",
                        "此 Antigravity 桌面端请求了较新版协议的审批类型。请直接在桌面端批准或拒绝后点击刷新。"
                    )
                )
                    .font(.system(size: 12))
                    .foregroundStyle(AntigravityTheme.inkSecondary)

                Button {
                    store.syncStepsForCascade(step.cascadeId, pollUntilIdle: false)
                } label: {
                    Label(lang.t("Refresh Status", "刷新状态"), systemImage: "arrow.clockwise")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(AntigravityTheme.inkReading)
                        .frame(maxWidth: .infinity, minHeight: AntigravityTheme.minTouchTargetPt)
                        .background(AntigravityTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("btn-step-approval-refresh-\(step.stepIndex)")
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
                    .stroke(AntigravityTheme.statusWaiting.opacity(0.35), lineWidth: 1)
            )
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("card-step-approval-desktop-required-\(step.stepIndex)")
        } else {
            let info = descriptor
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: info.icon)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(AntigravityTheme.statusWaiting)
                    Text(info.title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(AntigravityTheme.statusWaiting)
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
                    .background(AntigravityTheme.surfaceCodeBlock)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(AntigravityTheme.glassHairline, lineWidth: 1)
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
                        Text(lang.t("Deny", "拒绝"))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AntigravityTheme.inkReading)
                            .padding(.horizontal, 16)
                            .frame(maxWidth: info.supportsScopedAllow ? nil : CGFloat.infinity, minHeight: AntigravityTheme.minTouchTargetPt)
                            .background(AntigravityTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("btn-step-deny-\(step.stepIndex)")

                    Button {
                        store.resolveWaitingStep(stepIndex: step.stepIndex, decision: .allowOnce)
                    } label: {
                        Text(info.primaryLabel)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(AntigravityTheme.inkOnAmberCTA)
                            .frame(maxWidth: .infinity, minHeight: AntigravityTheme.minTouchTargetPt)
                            .background(AntigravityTheme.statusWaiting, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("btn-step-approve-\(step.stepIndex)")
                }

                if info.supportsScopedAllow {
                    HStack(spacing: 8) {
                        Button {
                            store.resolveWaitingStep(stepIndex: step.stepIndex, decision: .allowInConversation)
                        } label: {
                            Text(lang.t("Allow in Chat", "本对话允许"))
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(AntigravityTheme.inkReading)
                                .frame(maxWidth: .infinity, minHeight: 38)
                                .background(AntigravityTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        Button {
                            store.resolveWaitingStep(stepIndex: step.stepIndex, decision: .alwaysAllow)
                        } label: {
                            Text(lang.t("Always Allow", "始终允许"))
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(AntigravityTheme.accentPeriwinkle)
                                .frame(maxWidth: .infinity, minHeight: 38)
                                .background(AntigravityTheme.accentPeriwinkle.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
                            Text(lang.t("Review Plan & Comment", "审查方案并批注"))
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundStyle(AntigravityTheme.accentPeriwinkle)
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .background(AntigravityTheme.accentPeriwinkle.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
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
                    .stroke(AntigravityTheme.statusWaiting.opacity(0.32), lineWidth: 1)
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

    private var lang: AppLanguage { store.appearancePreferences.language }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: interaction.kind == .askQuestion ? "questionmark.bubble.fill" : "hand.raised.fill")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(AntigravityTheme.statusWaiting)
                Text(interaction.kind == .askQuestion ? lang.t("Agent needs your input", "Agent 需要你的输入") : lang.t("Permission required", "需要权限审批"))
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(AntigravityTheme.statusWaiting)
                Spacer()
            }

            if let qa = interaction.askQuestion {
                Text(qa.question)
                    .font(.system(size: 13.5))
                    .foregroundStyle(AntigravityTheme.inkReading)
                Button {
                    store.presentedSheet = .askQuestion(stepIndex: step.stepIndex)
                } label: {
                    Text(lang.t("Review & Answer", "查看并回答"))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(AntigravityTheme.inkOnAmberCTA)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(AntigravityTheme.statusWaiting)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            } else {
                let targetText = interaction.filePermission?.absolutePathUri
                    ?? interaction.permission?.target
                    ?? lang.t("Workspace action", "工作区操作")
                Text(targetText)
                    .font(.system(size: 12.5, design: .monospaced))
                    .foregroundStyle(AntigravityTheme.inkLabel)
                    .lineLimit(3)
                HStack(spacing: 10) {
                    Button {
                        store.resolveWaitingStep(stepIndex: step.stepIndex, decision: .reject)
                    } label: {
                        Text(lang.t("Deny", "拒绝"))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AntigravityTheme.inkReading)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(AntigravityTheme.surfaceElevated)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Button {
                        store.resolveWaitingStep(stepIndex: step.stepIndex, decision: .allowOnce)
                    } label: {
                        Text(lang.t("Allow Once", "仅允许一次"))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(AntigravityTheme.inkOnAmberCTA)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(AntigravityTheme.statusWaiting)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
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
                        .foregroundStyle(AntigravityTheme.accentPeriwinkle)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(AntigravityTheme.accentPeriwinkle.opacity(0.12))
                        .overlay(
                            Capsule()
                                .stroke(AntigravityTheme.accentPeriwinkle.opacity(0.26), lineWidth: 1)
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
