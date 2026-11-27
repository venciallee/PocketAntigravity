import Foundation

// MARK: - Model Quota & Usage (v2.31 - v2.33)

/// Dual-pool model quota & usage telemetry surfaced in the Model Picker (`View Usage`).
public struct ModelUsageQuota: Codable, Sendable, Equatable {
    public var geminiWeeklyRemaining: Double
    public var geminiFiveHourRemaining: Double
    public var partnerWeeklyRemaining: Double
    public var partnerFiveHourRemaining: Double
    public var aiCreditOveragesEnabled: Bool
    public var planDisplayName: String
    public var updatedAt: Date

    public init(
        geminiWeeklyRemaining: Double = 1.0,
        geminiFiveHourRemaining: Double = 1.0,
        partnerWeeklyRemaining: Double = 1.0,
        partnerFiveHourRemaining: Double = 1.0,
        aiCreditOveragesEnabled: Bool = false,
        planDisplayName: String = "Google AI Pro",
        updatedAt: Date = Date()
    ) {
        self.geminiWeeklyRemaining = min(1.0, max(0.0, geminiWeeklyRemaining))
        self.geminiFiveHourRemaining = min(1.0, max(0.0, geminiFiveHourRemaining))
        self.partnerWeeklyRemaining = min(1.0, max(0.0, partnerWeeklyRemaining))
        self.partnerFiveHourRemaining = min(1.0, max(0.0, partnerFiveHourRemaining))
        self.aiCreditOveragesEnabled = aiCreditOveragesEnabled
        self.planDisplayName = planDisplayName
        self.updatedAt = updatedAt
    }

    public var geminiWeeklyPercent: Int { Int((geminiWeeklyRemaining * 100.0).rounded()) }
    public var geminiFiveHourPercent: Int { Int((geminiFiveHourRemaining * 100.0).rounded()) }
    public var partnerWeeklyPercent: Int { Int((partnerWeeklyRemaining * 100.0).rounded()) }
    public var partnerFiveHourPercent: Int { Int((partnerFiveHourRemaining * 100.0).rounded()) }
}

// MARK: - Fine-Grained Permission Rules (v2.23 - v2.33)
// Note: `AgentPermissionPreset` is unified in `WorkspaceModels.swift`.

public enum PermissionRuleListKind: String, ResilientStringEnum, CaseIterable {
    case deny = "Deny"
    case ask = "Ask"
    case allow = "Allow"

    public static var unknownFallback: PermissionRuleListKind { .ask }
}

public enum PermissionRuleAction: String, ResilientStringEnum, CaseIterable {
    case readFile = "read_file"
    case writeFile = "write_file"
    case readUrl = "read_url"
    case executeUrl = "execute_url"
    case downloadUrl = "download_url"
    case command = "command"
    case mcp = "mcp"

    public static var unknownFallback: PermissionRuleAction { .command }
}

public struct PermissionRuleEntry: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var list: PermissionRuleListKind
    public var action: PermissionRuleAction
    public var target: String

    public init(
        id: String = UUID().uuidString,
        list: PermissionRuleListKind,
        action: PermissionRuleAction,
        target: String
    ) {
        self.id = id
        self.list = list
        self.action = action
        self.target = target
    }

    public var formattedRule: String {
        "\(action.rawValue)(\(target))"
    }
}

// MARK: - Multi-Agent Orchestration: Subagents, Dynamic Workflows (/run-workflow), Swarms (/swarm), MCP & Overview

public struct SubagentPayload: Codable, Sendable, Equatable, Identifiable {
    public var id: String { subagentId }
    public var subagentId: String
    public var role: String
    public var typeName: String
    public var modelLabel: String
    public var status: CortexStepStatus
    public var summary: String
    public var waitingApprovalTitle: String?

    public init(
        subagentId: String,
        role: String,
        typeName: String = "self",
        modelLabel: String = "Gemini 4 Hydrogen",
        status: CortexStepStatus = .inProgress,
        summary: String = "",
        waitingApprovalTitle: String? = nil
    ) {
        self.subagentId = subagentId
        self.role = role
        self.typeName = typeName
        self.modelLabel = modelLabel
        self.status = status
        self.summary = summary
        self.waitingApprovalTitle = waitingApprovalTitle
    }
}

public struct WorkflowPhaseItem: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var logs: [String]
    public var agents: [SubagentPayload]
    public var isCompleted: Bool

    public init(
        id: String = UUID().uuidString,
        name: String,
        logs: [String] = [],
        agents: [SubagentPayload] = [],
        isCompleted: Bool = false
    ) {
        self.id = id
        self.name = name
        self.logs = logs
        self.agents = agents
        self.isCompleted = isCompleted
    }
}

/// Payload for Antigravity v2.32.0 Dynamic Workflows (`/run-workflow`).
public struct DynamicWorkflowPayload: Codable, Sendable, Equatable {
    public var workflowId: String
    public var description: String
    public var pythonScript: String
    public var currentPhase: String
    public var completedAgents: Int
    public var totalAgents: Int
    public var phases: [WorkflowPhaseItem]
    public var outputPreview: String?
    public var requiresScriptApproval: Bool

    public init(
        workflowId: String,
        description: String,
        pythonScript: String,
        currentPhase: String,
        completedAgents: Int = 0,
        totalAgents: Int = 0,
        phases: [WorkflowPhaseItem] = [],
        outputPreview: String? = nil,
        requiresScriptApproval: Bool = false
    ) {
        self.workflowId = workflowId
        self.description = description
        self.pythonScript = pythonScript
        self.currentPhase = currentPhase
        self.completedAgents = completedAgents
        self.totalAgents = totalAgents
        self.phases = phases
        self.outputPreview = outputPreview
        self.requiresScriptApproval = requiresScriptApproval
    }
}

public struct SwarmMemberItem: Codable, Sendable, Equatable, Identifiable {
    public var id: String { name }
    public var name: String
    public var role: String
    public var modelLabel: String
    public var status: CortexStepStatus
    public var conversationId: String?

    public init(
        name: String,
        role: String,
        modelLabel: String = "Gemini 4 Neon",
        status: CortexStepStatus = .inProgress,
        conversationId: String? = nil
    ) {
        self.name = name
        self.role = role
        self.modelLabel = modelLabel
        self.status = status
        self.conversationId = conversationId
    }
}

public struct SwarmBoardPost: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var authorName: String
    public var mentions: [String]
    public var bodyMarkdown: String
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        authorName: String,
        mentions: [String] = [],
        bodyMarkdown: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.authorName = authorName
        self.mentions = mentions
        self.bodyMarkdown = bodyMarkdown
        self.createdAt = createdAt
    }
}

/// Payload for Antigravity v2.31.0 Agent Swarms (`/swarm`).
public struct SwarmBoardPayload: Codable, Sendable, Equatable {
    public var swarmId: String
    public var title: String
    public var status: CortexStepStatus
    public var members: [SwarmMemberItem]
    public var posts: [SwarmBoardPost]

    public init(
        swarmId: String,
        title: String,
        status: CortexStepStatus = .inProgress,
        members: [SwarmMemberItem] = [],
        posts: [SwarmBoardPost] = []
    ) {
        self.swarmId = swarmId
        self.title = title
        self.status = status
        self.members = members
        self.posts = posts
    }
}

/// Structured MCP or custom tool invocation step (v2.26+).
public struct McpToolCallPayload: Codable, Sendable, Equatable {
    public var serverName: String
    public var toolName: String
    public var pluginName: String?
    public var argumentsPreview: String
    public var resultPreview: String?
    public var isError: Bool

    public init(
        serverName: String,
        toolName: String,
        pluginName: String? = nil,
        argumentsPreview: String = "{}",
        resultPreview: String? = nil,
        isError: Bool = false
    ) {
        self.serverName = serverName
        self.toolName = toolName
        self.pluginName = pluginName
        self.argumentsPreview = argumentsPreview
        self.resultPreview = resultPreview
        self.isError = isError
    }
}

public struct BackgroundTaskItem: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var commandSummary: String
    public var status: CortexStepStatus
    public var elapsedLabel: String
    public var canCancel: Bool

    public init(
        id: String,
        title: String,
        commandSummary: String,
        status: CortexStepStatus = .inProgress,
        elapsedLabel: String = "running",
        canCancel: Bool = true
    ) {
        self.id = id
        self.title = title
        self.commandSummary = commandSummary
        self.status = status
        self.elapsedLabel = elapsedLabel
        self.canCancel = canCancel
    }
}

public struct ConversationGoalItem: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var status: CortexStepStatus
    public var progressText: String

    public init(
        id: String,
        title: String,
        status: CortexStepStatus = .inProgress,
        progressText: String = "Active"
    ) {
        self.id = id
        self.title = title
        self.status = status
        self.progressText = progressText
    }
}

/// Live GitHub Pull Request pill & Overview card (Antigravity v2.33.0).
public struct GitHubPullRequestInfo: Codable, Sendable, Equatable, Identifiable {
    public enum PRState: String, ResilientStringEnum {
        case open
        case draft
        case merged
        case closed

        public static var unknownFallback: PRState { .open }
    }

    public var id: String { "\(ownerRepo)#\(number)" }
    public var ownerRepo: String
    public var number: Int
    public var title: String
    public var state: PRState
    public var checksSummary: String
    public var url: String
    public var additions: Int
    public var deletions: Int

    public init(
        ownerRepo: String,
        number: Int,
        title: String,
        state: PRState = .open,
        checksSummary: String = "Checks passing",
        url: String,
        additions: Int = 0,
        deletions: Int = 0
    ) {
        self.ownerRepo = ownerRepo
        self.number = number
        self.title = title
        self.state = state
        self.checksSummary = checksSummary
        self.url = url
        self.additions = additions
        self.deletions = deletions
    }
}

public struct ConversationOverviewSnapshot: Codable, Sendable, Equatable {
    public var reviewAdditions: Int
    public var reviewDeletions: Int
    public var modifiedFiles: [String]
    public var subagents: [SubagentPayload]
    public var backgroundTasks: [BackgroundTaskItem]
    public var goals: [ConversationGoalItem]
    public var artifacts: [ArtifactSnapshot]
    public var documentLinks: [String]
    public var pullRequests: [GitHubPullRequestInfo]

    public init(
        reviewAdditions: Int = 0,
        reviewDeletions: Int = 0,
        modifiedFiles: [String] = [],
        subagents: [SubagentPayload] = [],
        backgroundTasks: [BackgroundTaskItem] = [],
        goals: [ConversationGoalItem] = [],
        artifacts: [ArtifactSnapshot] = [],
        documentLinks: [String] = [],
        pullRequests: [GitHubPullRequestInfo] = []
    ) {
        self.reviewAdditions = reviewAdditions
        self.reviewDeletions = reviewDeletions
        self.modifiedFiles = modifiedFiles
        self.subagents = subagents
        self.backgroundTasks = backgroundTasks
        self.goals = goals
        self.artifacts = artifacts
        self.documentLinks = documentLinks
        self.pullRequests = pullRequests
    }
}

// MARK: - Multi-Turn /btw Side Question Thread (v2.32.2 - v2.33.0)

public struct SideQuestionMessage: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var isUser: Bool
    public var text: String
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        isUser: Bool,
        text: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.isUser = isUser
        self.text = text
        self.createdAt = createdAt
    }
}

public struct SideQuestionThread: Codable, Sendable, Equatable {
    public var threadId: String
    public var parentCascadeId: String
    public var messages: [SideQuestionMessage]
    public var isStreaming: Bool

    public init(
        threadId: String = UUID().uuidString.lowercased(),
        parentCascadeId: String = "",
        messages: [SideQuestionMessage] = [],
        isStreaming: Bool = false
    ) {
        self.threadId = threadId
        self.parentCascadeId = parentCascadeId
        self.messages = messages
        self.isStreaming = isStreaming
    }

    public var latestAssistantAnswer: String? {
        messages.last(where: { !$0.isUser })?.text
    }
}

// MARK: - Git VCS Review Extensions (v2.28 - v2.33)

public enum DiffCompareMode: String, ResilientStringEnum, CaseIterable, Identifiable {
    case turn = "Per Turn"
    case uncommitted = "Uncommitted"
    case branch = "Branch"
    case agentEdits = "Agent Edits"

    public var id: String { rawValue }
    public static var unknownFallback: DiffCompareMode { .turn }
}

public enum GitFileStatusLetter: String, ResilientStringEnum, CaseIterable {
    case modified = "M"
    case added = "A"
    case untracked = "U"
    case deleted = "D"
    case renamed = "R"

    public static var unknownFallback: GitFileStatusLetter { .modified }
}

public struct GitCommitDraft: Codable, Sendable, Equatable {
    public var message: String
    public var includeUnstaged: Bool
    public var amend: Bool

    public init(
        message: String = "",
        includeUnstaged: Bool = true,
        amend: Bool = false
    ) {
        self.message = message
        self.includeUnstaged = includeUnstaged
        self.amend = amend
    }
}

public struct GitCommitResult: Codable, Sendable, Equatable {
    public var commitSha: String
    public var commitMessage: String
    public var branchName: String
    public var pushed: Bool

    public init(
        commitSha: String,
        commitMessage: String,
        branchName: String = "main",
        pushed: Bool = false
    ) {
        self.commitSha = commitSha
        self.commitMessage = commitMessage
        self.branchName = branchName
        self.pushed = pushed
    }
}

// MARK: - Jupyter Notebook (.ipynb) & Image Region Comments (v2.27 - v2.29)

public enum JupyterCellKind: String, ResilientStringEnum {
    case markdown
    case code
    case raw

    public static var unknownFallback: JupyterCellKind { .raw }
}

public struct JupyterCellOutput: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var text: String?
    public var imageBase64PNG: String?
    public var errorName: String?
    public var errorValue: String?

    public init(
        id: String = UUID().uuidString,
        text: String? = nil,
        imageBase64PNG: String? = nil,
        errorName: String? = nil,
        errorValue: String? = nil
    ) {
        self.id = id
        self.text = text
        self.imageBase64PNG = imageBase64PNG
        self.errorName = errorName
        self.errorValue = errorValue
    }
}

public struct JupyterNotebookCell: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var cellType: JupyterCellKind
    public var executionCount: Int?
    public var source: String
    public var outputs: [JupyterCellOutput]

    public init(
        id: String = UUID().uuidString,
        cellType: JupyterCellKind,
        executionCount: Int? = nil,
        source: String,
        outputs: [JupyterCellOutput] = []
    ) {
        self.id = id
        self.cellType = cellType
        self.executionCount = executionCount
        self.source = source
        self.outputs = outputs
    }
}

public struct JupyterNotebookDocument: Codable, Sendable, Equatable {
    public var kernelName: String
    public var cells: [JupyterNotebookCell]

    public init(kernelName: String = "python3", cells: [JupyterNotebookCell] = []) {
        self.kernelName = kernelName
        self.cells = cells
    }

    /// Parses standard `.ipynb` JSON into a native Swift 6 cell model without UIKit dependencies.
    public static func parse(jsonString: String) -> JupyterNotebookDocument? {
        guard let data = jsonString.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let metadata = root["metadata"] as? [String: Any]
        let kernelspec = metadata?["kernelspec"] as? [String: Any]
        let kernelName = (kernelspec?["display_name"] as? String)
            ?? (kernelspec?["name"] as? String)
            ?? "python3"

        let rawCells = root["cells"] as? [[String: Any]] ?? []
        var parsedCells: [JupyterNotebookCell] = []

        for (idx, cell) in rawCells.enumerated() {
            let typeRaw = (cell["cell_type"] as? String ?? "code").lowercased()
            let cellType = JupyterCellKind(rawValue: typeRaw) ?? .code
            let execCount = cell["execution_count"] as? Int
            let source: String = {
                if let arr = cell["source"] as? [String] {
                    return arr.joined()
                }
                return cell["source"] as? String ?? ""
            }()

            var outputs: [JupyterCellOutput] = []
            if let rawOutputs = cell["outputs"] as? [[String: Any]] {
                for (oIdx, out) in rawOutputs.enumerated() {
                    let outType = (out["output_type"] as? String ?? "").lowercased()
                    if outType == "stream" {
                        let txt = (out["text"] as? [String])?.joined() ?? (out["text"] as? String)
                        outputs.append(JupyterCellOutput(id: "\(idx)-o-\(oIdx)", text: txt))
                    } else if outType == "error" {
                        outputs.append(
                            JupyterCellOutput(
                                id: "\(idx)-o-\(oIdx)",
                                errorName: out["ename"] as? String,
                                errorValue: out["evalue"] as? String
                            )
                        )
                    } else if let dataObj = out["data"] as? [String: Any] {
                        let txt = (dataObj["text/plain"] as? [String])?.joined() ?? (dataObj["text/plain"] as? String)
                        let png = dataObj["image/png"] as? String
                        outputs.append(JupyterCellOutput(id: "\(idx)-o-\(oIdx)", text: txt, imageBase64PNG: png))
                    }
                }
            }

            parsedCells.append(
                JupyterNotebookCell(
                    id: (cell["id"] as? String) ?? "cell-\(idx)",
                    cellType: cellType,
                    executionCount: execCount,
                    source: source,
                    outputs: outputs
                )
            )
        }
        return JupyterNotebookDocument(kernelName: kernelName, cells: parsedCells)
    }
}

public struct ImageRegionComment: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var artifactPath: String
    public var normalizedX: Double
    public var normalizedY: Double
    public var normalizedWidth: Double
    public var normalizedHeight: Double
    public var body: String
    public var author: String
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        artifactPath: String,
        normalizedX: Double,
        normalizedY: Double,
        normalizedWidth: Double,
        normalizedHeight: Double,
        body: String,
        author: String = "You",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.artifactPath = artifactPath
        self.normalizedX = min(1.0, max(0.0, normalizedX))
        self.normalizedY = min(1.0, max(0.0, normalizedY))
        self.normalizedWidth = min(1.0, max(0.01, normalizedWidth))
        self.normalizedHeight = min(1.0, max(0.01, normalizedHeight))
        self.body = body
        self.author = author
        self.createdAt = createdAt
    }
}

// MARK: - Voice Mode (Gemini Live, v2.29 - v2.31)

public struct GeminiLiveVoiceOption: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var displayName: String
    public var toneSummary: String

    public init(id: String, displayName: String, toneSummary: String) {
        self.id = id
        self.displayName = displayName
        self.toneSummary = toneSummary
    }

    /// 9 official Gemini Live voice options.
    public static let allVoices: [GeminiLiveVoiceOption] = [
        GeminiLiveVoiceOption(id: "aoede", displayName: "Aoede", toneSummary: "Warm & conversational"),
        GeminiLiveVoiceOption(id: "charon", displayName: "Charon", toneSummary: "Calm & informative"),
        GeminiLiveVoiceOption(id: "fenrir", displayName: "Fenrir", toneSummary: "Crisp & energetic"),
        GeminiLiveVoiceOption(id: "kore", displayName: "Kore", toneSummary: "Clear & focused"),
        GeminiLiveVoiceOption(id: "puck", displayName: "Puck", toneSummary: "Upbeat & responsive"),
        GeminiLiveVoiceOption(id: "leda", displayName: "Leda", toneSummary: "Balanced & composed"),
        GeminiLiveVoiceOption(id: "orus", displayName: "Orus", toneSummary: "Steady & technical"),
        GeminiLiveVoiceOption(id: "zephyr", displayName: "Zephyr", toneSummary: "Bright & direct"),
        GeminiLiveVoiceOption(id: "callirrhoe", displayName: "Callirrhoe", toneSummary: "Smooth & measured")
    ]
}

public struct VoiceTranscriptTurn: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var isUser: Bool
    public var transcript: String
    public var timestamp: Date

    public init(
        id: String = UUID().uuidString,
        isUser: Bool,
        transcript: String,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.isUser = isUser
        self.transcript = transcript
        self.timestamp = timestamp
    }
}

public struct VoiceCallTranscriptSummary: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var cascadeId: String
    public var durationSeconds: Int
    public var summaryText: String
    public var turns: [VoiceTranscriptTurn]
    public var endedAt: Date

    public init(
        id: String = UUID().uuidString,
        cascadeId: String,
        durationSeconds: Int,
        summaryText: String,
        turns: [VoiceTranscriptTurn],
        endedAt: Date = Date()
    ) {
        self.id = id
        self.cascadeId = cascadeId
        self.durationSeconds = durationSeconds
        self.summaryText = summaryText
        self.turns = turns
        self.endedAt = endedAt
    }
}

public struct VoiceModeState: Codable, Sendable, Equatable {
    public var isActive: Bool
    public var isMuted: Bool
    public var isAgentSpeaking: Bool
    public var selectedVoiceId: String
    public var playbackSpeed: Double
    public var activeTurns: [VoiceTranscriptTurn]
    public var startedAt: Date?
    public var lastCallSummary: VoiceCallTranscriptSummary?

    public init(
        isActive: Bool = false,
        isMuted: Bool = false,
        isAgentSpeaking: Bool = false,
        selectedVoiceId: String = "aoede",
        playbackSpeed: Double = 1.0,
        activeTurns: [VoiceTranscriptTurn] = [],
        startedAt: Date? = nil,
        lastCallSummary: VoiceCallTranscriptSummary? = nil
    ) {
        self.isActive = isActive
        self.isMuted = isMuted
        self.isAgentSpeaking = isAgentSpeaking
        self.selectedVoiceId = selectedVoiceId
        self.playbackSpeed = min(2.0, max(0.75, playbackSpeed))
        self.activeTurns = activeTurns
        self.startedAt = startedAt
        self.lastCallSummary = lastCallSummary
    }
}

// MARK: - Customizations Hub (Skills, Rules, MCP, Plugins Marketplace, Hooks)

public struct SkillSummary: Codable, Sendable, Equatable, Identifiable {
    public var id: String { name }
    public var name: String
    public var description: String
    public var scope: String
    public var isEnabled: Bool

    public init(name: String, description: String, scope: String = "Workspace", isEnabled: Bool = true) {
        self.name = name
        self.description = description
        self.scope = scope
        self.isEnabled = isEnabled
    }
}

public struct RuleSummary: Codable, Sendable, Equatable, Identifiable {
    public var id: String { name }
    public var name: String
    public var scope: String
    public var preview: String
    public var isActive: Bool

    public init(name: String, scope: String = "Workspace", preview: String, isActive: Bool = true) {
        self.name = name
        self.scope = scope
        self.preview = preview
        self.isActive = isActive
    }
}

public struct McpServerStatusItem: Codable, Sendable, Equatable, Identifiable {
    public enum ConnectionState: String, ResilientStringEnum {
        case connected
        case stopped
        case error

        public static var unknownFallback: ConnectionState { .stopped }
    }

    public var id: String { name }
    public var name: String
    public var transport: String
    public var state: ConnectionState
    public var toolCount: Int
    public var errorMessage: String?
    public var missingCommandHint: String?
    public var oauthConnected: Bool

    public init(
        name: String,
        transport: String = "stdio",
        state: ConnectionState = .connected,
        toolCount: Int = 0,
        errorMessage: String? = nil,
        missingCommandHint: String? = nil,
        oauthConnected: Bool = true
    ) {
        self.name = name
        self.transport = transport
        self.state = state
        self.toolCount = toolCount
        self.errorMessage = errorMessage
        self.missingCommandHint = missingCommandHint
        self.oauthConnected = oauthConnected
    }
}

public struct PluginCatalogItem: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var provider: String
    public var description: String
    public var scope: String
    public var isInstalled: Bool
    public var isEnabled: Bool
    public var isFeaturedPartner: Bool
    public var accountSignedIn: Bool
    public var mcpStartupError: String?
    public var suggestedPrompts: [String]

    public init(
        id: String,
        name: String,
        provider: String,
        description: String,
        scope: String = "Global",
        isInstalled: Bool = false,
        isEnabled: Bool = true,
        isFeaturedPartner: Bool = false,
        accountSignedIn: Bool = false,
        mcpStartupError: String? = nil,
        suggestedPrompts: [String] = []
    ) {
        self.id = id
        self.name = name
        self.provider = provider
        self.description = description
        self.scope = scope
        self.isInstalled = isInstalled
        self.isEnabled = isEnabled
        self.isFeaturedPartner = isFeaturedPartner
        self.accountSignedIn = accountSignedIn
        self.mcpStartupError = mcpStartupError
        self.suggestedPrompts = suggestedPrompts
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, provider, description, scope
        case isInstalled, isEnabled, isFeaturedPartner, accountSignedIn
        case mcpStartupError, suggestedPrompts
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        self.provider = try c.decodeIfPresent(String.self, forKey: .provider) ?? self.name
        self.description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        self.scope = try c.decodeIfPresent(String.self, forKey: .scope) ?? "Global"
        self.isInstalled = try c.decodeIfPresent(Bool.self, forKey: .isInstalled) ?? false
        self.isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        self.isFeaturedPartner = try c.decodeIfPresent(Bool.self, forKey: .isFeaturedPartner) ?? false
        self.accountSignedIn = try c.decodeIfPresent(Bool.self, forKey: .accountSignedIn) ?? false
        self.mcpStartupError = try c.decodeIfPresent(String.self, forKey: .mcpStartupError)
        self.suggestedPrompts = try c.decodeIfPresent([String].self, forKey: .suggestedPrompts) ?? []
    }
}

public struct LifecycleHookItem: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var eventName: String
    public var matcher: String
    public var command: String
    public var timeoutSeconds: Int
    public var isValid: Bool

    public init(
        id: String = UUID().uuidString,
        eventName: String,
        matcher: String = "*",
        command: String,
        timeoutSeconds: Int = 60,
        isValid: Bool = true
    ) {
        self.id = id
        self.eventName = eventName
        self.matcher = matcher
        self.command = command
        self.timeoutSeconds = timeoutSeconds
        self.isValid = isValid
    }
}

public struct CustomizationsCatalog: Codable, Sendable, Equatable {
    public var skills: [SkillSummary]
    public var rules: [RuleSummary]
    public var customAgents: [String]
    public var mcpServers: [McpServerStatusItem]
    public var plugins: [PluginCatalogItem]
    public var hooks: [LifecycleHookItem]
    public var loadedTokensLabel: String

    public init(
        skills: [SkillSummary] = [],
        rules: [RuleSummary] = [],
        customAgents: [String] = ["Default"],
        mcpServers: [McpServerStatusItem] = [],
        plugins: [PluginCatalogItem] = [],
        hooks: [LifecycleHookItem] = [],
        loadedTokensLabel: String = "6.2k tokens"
    ) {
        self.skills = skills
        self.rules = rules
        self.customAgents = customAgents
        self.mcpServers = mcpServers
        self.plugins = plugins
        self.hooks = hooks
        self.loadedTokensLabel = loadedTokensLabel
    }

    private enum CodingKeys: String, CodingKey {
        case skills, rules, customAgents, mcpServers, plugins, hooks, loadedTokensLabel
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.skills = try c.decodeIfPresent([SkillSummary].self, forKey: .skills) ?? []
        self.rules = try c.decodeIfPresent([RuleSummary].self, forKey: .rules) ?? []
        self.customAgents = try c.decodeIfPresent([String].self, forKey: .customAgents) ?? ["Default"]
        self.mcpServers = try c.decodeIfPresent([McpServerStatusItem].self, forKey: .mcpServers) ?? []
        self.plugins = try c.decodeIfPresent([PluginCatalogItem].self, forKey: .plugins) ?? []
        self.hooks = try c.decodeIfPresent([LifecycleHookItem].self, forKey: .hooks) ?? []
        self.loadedTokensLabel = try c.decodeIfPresent(String.self, forKey: .loadedTokensLabel) ?? "6.2k tokens"
    }

    public static let defaultCatalog = CustomizationsCatalog(
        skills: [
            SkillSummary(name: "go-testing", description: "Table-driven tests with -race", scope: "Global"),
            SkillSummary(name: "pr-summary", description: "Write PR descriptions from the diff", scope: "Global"),
            SkillSummary(name: "api-review", description: "Check handlers against API rules · .agents/skills", scope: "Project"),
            SkillSummary(name: "add-endpoint", description: "Scaffold handler + test + route · .agents/skills", scope: "Project"),
            SkillSummary(name: "firebase:deploy", description: "From plugin firebase", scope: "Plugin")
        ],
        rules: [
            RuleSummary(name: "AGENTS.md", scope: "Project", preview: "Injected clock, deterministic tests, zero package-level mutable state."),
            RuleSummary(name: "go-style.md", scope: "Project", preview: "Wrap errors with %w, table-driven subtests, no naked returns."),
            RuleSummary(name: "security-invariants.md", scope: "Project", preview: "Rate limits & idempotency keys required on all transfer mutations."),
            RuleSummary(name: "global-conventions.md", scope: "Global", preview: "Prefer concise diffs and cite exact file paths.")
        ],
        customAgents: ["go-reviewer"],
        mcpServers: [
            McpServerStatusItem(name: "firebase", transport: "remote-oauth", state: .connected, toolCount: 6, oauthConnected: true),
            McpServerStatusItem(name: "datadog", transport: "stdio", state: .error, toolCount: 4, errorMessage: "MCP needs an API key", oauthConnected: false)
        ],
        plugins: [
            PluginCatalogItem(
                id: "plugin-firebase",
                name: "Firebase",
                provider: "Google",
                description: "2 skills · 1 MCP server",
                scope: "Global",
                isInstalled: true,
                isEnabled: true,
                isFeaturedPartner: true,
                accountSignedIn: true,
                suggestedPrompts: ["Inspect Crashlytics regressions for latest build"]
            ),
            PluginCatalogItem(
                id: "plugin-datadog",
                name: "Datadog",
                provider: "Datadog",
                description: "MCP needs an API key",
                scope: "Workspace",
                isInstalled: true,
                isEnabled: false,
                isFeaturedPartner: true,
                accountSignedIn: false,
                mcpStartupError: "MCP needs an API key",
                suggestedPrompts: ["Check p99 latency on /transfers"]
            )
        ],
        hooks: [
            LifecycleHookItem(eventName: "PreToolUse", matcher: "run_command", command: "scripts/verify-safe-cmd.sh", timeoutSeconds: 30)
        ],
        loadedTokensLabel: "6.2k tokens"
    )
}

// MARK: - Appearance, Language, Layout, Queued Messages & Turn Navigator (v2.28 - v2.34)

public enum InterfaceLayoutMode: String, ResilientStringEnum, CaseIterable, Identifiable {
    case softwareEngineering = "Software Engineering"
    case knowledgeWork = "Knowledge Work"

    public var id: String { rawValue }
    public static var unknownFallback: InterfaceLayoutMode { .softwareEngineering }
}

public enum AppThemePreset: String, ResilientStringEnum, CaseIterable, Identifiable {
    case obsidian = "Matte Obsidian"
    case nord = "Nord Dark"
    case everforestDark = "Everforest Dark"
    case everforestLight = "Everforest Light"

    public var id: String { rawValue }
    public static var unknownFallback: AppThemePreset { .obsidian }
}

/// User-facing color appearance preference (`System` follows iOS Dark/Light setting).
public enum AppAppearanceMode: String, ResilientStringEnum, CaseIterable, Identifiable {
    case system = "System"
    case dark = "Dark"
    case light = "Light"

    public var id: String { rawValue }
    public static var unknownFallback: AppAppearanceMode { .system }

    public var displayLabel: String {
        switch self {
        case .system: return "System"
        case .dark: return "Dark"
        case .light: return "Light"
        }
    }

    public var sfSymbolName: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .dark: return "moon.fill"
        case .light: return "sun.max.fill"
        }
    }
}

/// User-facing display language preference (`UE15` Settings).
public enum AppLanguage: String, ResilientStringEnum, CaseIterable, Identifiable {
    case english = "en"
    case zhHans = "zh-Hans"

    public var id: String { rawValue }
    public static var unknownFallback: AppLanguage { .english }

    public var displayLabel: String {
        switch self {
        case .english: return "English"
        case .zhHans: return "简体中文"
        }
    }

    public var isChinese: Bool {
        self == .zhHans
    }

    public var localeIdentifier: String {
        switch self {
        case .english: return "en"
        case .zhHans: return "zh-Hans"
        }
    }

    public func t(_ english: String, _ chinese: String) -> String {
        isChinese ? chinese : english
    }

    public static func fromTag(_ raw: String?) -> AppLanguage {
        let normalized = (raw ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
        switch normalized {
        case "zh", "zhcn", "zhhans", "chinese", "简体中文":
            return .zhHans
        default:
            return .english
        }
    }
}

/// User-selectable speech-to-text dictation language preference (persisted per device).
///
/// Defaults to `.auto`, which prioritizes in-app `AppLanguage`, OS `Locale.preferredLanguages`
/// (ahead of `Locale.current`, which iOS pins to the app bundle's development region `en`),
/// and active keyboard language when dictating on an English-system device with a Chinese keyboard.
public enum VoiceDictationLanguage: String, ResilientStringEnum, CaseIterable, Identifiable {
    case auto = "auto"
    case zhCN = "zh-CN"
    case zhTW = "zh-TW"
    case zhHK = "zh-HK"
    case enUS = "en-US"

    public var id: String { rawValue }
    public static var unknownFallback: VoiceDictationLanguage { .auto }

    public var bcp47Tag: String? {
        switch self {
        case .auto: return nil
        case .zhCN: return "zh-CN"
        case .zhTW: return "zh-TW"
        case .zhHK: return "zh-HK"
        case .enUS: return "en-US"
        }
    }

    public func localizedTitle(for language: AppLanguage) -> String {
        switch self {
        case .auto: return language.t("Auto", "自动")
        case .zhCN: return "中文 (简体)"
        case .zhTW: return "中文 (繁體)"
        case .zhHK: return "粵語 (香港)"
        case .enUS: return "English"
        }
    }

    public func shortBadgeLabel(for language: AppLanguage) -> String {
        switch self {
        case .auto: return language.t("Auto", "自动")
        case .zhCN: return "中文"
        case .zhTW: return "繁體"
        case .zhHK: return "粵語"
        case .enUS: return "EN"
        }
    }

    public static func fromTag(_ raw: String?) -> VoiceDictationLanguage {
        let normalized = (raw ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
        switch normalized {
        case "zhcn", "zhhans", "zhhanscn", "zh", "chinese":
            return .zhCN
        case "zhtw", "zhhant", "zhhanttw":
            return .zhTW
        case "zhhk", "zhhanthk", "yue", "yuehk":
            return .zhHK
        case "enus", "en", "english":
            return .enUS
        default:
            return .auto
        }
    }
}

/// Pure Swift speech-recognition locale resolver mirroring `shared/core-model/VoiceLocaleResolver.kt`.
///
/// Prevents iOS from picking an English `SFSpeechRecognizer` (`Locale.current == "en_CN"`)
/// on Chinese iPhones when the app bundle does not ship a `.lproj` localization directory.
public enum VoiceLocaleResolver {
    public static func normalizeSpeechLocaleTags(_ raw: String) -> [String] {
        let cleaned = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "-")
        guard !cleaned.isEmpty else { return [] }

        let parts = cleaned.split(separator: "-").map(String.init).filter { !$0.isEmpty }
        guard let first = parts.first else { return [] }

        let lang = first.lowercased()
        let lowerParts = Set(parts.map { $0.lowercased() })

        switch lang {
        case "zh":
            if lowerParts.contains("hk") {
                return ["zh-HK", "zh-TW", "zh-CN"]
            }
            if lowerParts.contains("hant") || lowerParts.contains("tw") || lowerParts.contains("mo") {
                return ["zh-TW", "zh-HK", "zh-CN"]
            }
            if lowerParts.contains("sg") {
                return ["zh-CN", "zh-SG", "zh-Hans-CN"]
            }
            if lowerParts.contains("hans") {
                return ["zh-CN", "zh-Hans-CN", "zh-SG"]
            }
            return ["zh-CN", "zh-Hans-CN", "zh-TW", "zh-HK"]

        case "yue":
            return ["zh-HK", "yue-HK", "zh-TW", "zh-CN"]

        case "en":
            let region = (parts.count >= 2 && parts.last?.count == 2) ? parts.last?.uppercased() : nil
            if region == nil || region == "CN" {
                return ["en-US", "en-GB"]
            }
            if region == "US" {
                return ["en-US"]
            }
            return ["en-\(region!)", "en-US"]

        default:
            let region = (parts.count >= 2 && parts.last?.count == 2) ? parts.last?.uppercased() : nil
            let canonical = region.map { "\(lang)-\($0)" } ?? lang
            return [canonical]
        }
    }

    public static func buildCandidateLocaleTags(
        preference: VoiceDictationLanguage,
        appLanguage: AppLanguage,
        systemPreferredLanguages: [String],
        activeKeyboardLanguage: String? = nil,
        fallbackLocaleTag: String? = nil
    ) -> [String] {
        var result: [String] = []
        var seen = Set<String>()

        func appendNormalized(_ raw: String?) {
            guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            for tag in normalizeSpeechLocaleTags(raw) where seen.insert(tag).inserted {
                result.append(tag)
            }
        }

        // 1. Explicit user dictation language override always wins.
        if preference != .auto, let tag = preference.bcp47Tag {
            appendNormalized(tag)
        } else {
            let primarySystem = systemPreferredLanguages.first {
                !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            let primarySystemLang = primaryLanguageCode(primarySystem)
            let keyboardLang = primaryLanguageCode(activeKeyboardLanguage)

            // 2. If user switched in-app language to Chinese, prefer their Chinese variant (or zh-CN).
            if appLanguage == .zhHans {
                if primarySystemLang == "zh" || primarySystemLang == "yue" {
                    appendNormalized(primarySystem)
                }
                appendNormalized("zh-CN")
            }

            // 3. On an English-system device, if the user currently has a non-English keyboard open
            //    (e.g. Chinese Pinyin keyboard), honor the active keyboard language first.
            if primarySystemLang == "en", let keyboardLang, keyboardLang != "en" {
                appendNormalized(activeKeyboardLanguage)
            }

            // 4. OS preferred languages (MUST come before Locale.current, which iOS pins to bundle dev region).
            for sysLang in systemPreferredLanguages {
                appendNormalized(sysLang)
            }

            // 5. Active keyboard as fallback if not already added.
            appendNormalized(activeKeyboardLanguage)
        }

        // 6. Fallback locale & ultimate en-US safety net.
        appendNormalized(fallbackLocaleTag)
        if seen.insert("en-US").inserted {
            result.append("en-US")
        }
        return result
    }

    public static func resolveBestLocaleTag(
        candidates: [String],
        supportedLocaleTags: Set<String>
    ) -> String? {
        guard let firstCandidate = candidates.first else { return nil }
        guard !supportedLocaleTags.isEmpty else { return firstCandidate }

        var normalizedToOriginal: [String: String] = [:]
        var orderedEntries: [(norm: String, original: String)] = []
        for supported in supportedLocaleTags.sorted() {
            let norm = supported
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "_", with: "-")
                .lowercased()
            if !norm.isEmpty && normalizedToOriginal[norm] == nil {
                normalizedToOriginal[norm] = supported
                orderedEntries.append((norm: norm, original: supported))
            }
        }

        // Pass 1: exact normalized BCP-47 match in candidate priority order.
        for candidate in candidates {
            let norm = candidate
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "_", with: "-")
                .lowercased()
            if let exact = normalizedToOriginal[norm] {
                return exact
            }
        }

        // Pass 2: primary language code match (e.g. `ja-US` -> `ja-JP`).
        for candidate in candidates {
            guard let targetLang = primaryLanguageCode(candidate) else { continue }
            if let matched = orderedEntries.first(where: { primaryLanguageCode($0.norm) == targetLang })?.original {
                return matched
            }
        }

        return nil
    }

    public static func shortDisplayLabel(forLocaleTag localeTag: String?) -> String {
        let cleaned = (localeTag ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "-")
        guard !cleaned.isEmpty else { return "Auto" }
        let lower = cleaned.lowercased()
        guard let lang = primaryLanguageCode(lower) else { return cleaned.uppercased() }
        switch lang {
        case "zh":
            if lower.contains("-hk") { return "粵語" }
            if lower.contains("-tw") || lower.contains("-hant") || lower.contains("-mo") { return "繁體" }
            return "中文"
        case "yue":
            return "粵語"
        case "en":
            return "EN"
        case "ja":
            return "日本語"
        case "ko":
            return "한국어"
        default:
            return lang.uppercased()
        }
    }

    private static func primaryLanguageCode(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let cleaned = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "-")
        guard !cleaned.isEmpty else { return nil }
        let code = cleaned.split(separator: "-").first.map { String($0).lowercased() }
        return (code?.isEmpty == false) ? code : nil
    }
}

public struct AppAppearancePreferences: Codable, Sendable, Equatable {
    public var interfaceLayout: InterfaceLayoutMode
    public var appearanceMode: AppAppearanceMode
    public var language: AppLanguage
    public var theme: AppThemePreset
    public var fontSizePt: Int
    public var collapsedProjectIds: Set<String>
    public var notificationsEnabled: Bool
    public var suppressManualStopNotification: Bool
    public var liveUpdatesEnabled: Bool
    public var globalPermissionPreset: AgentPermissionPreset
    public var terminalSandboxEnabled: Bool

    public init(
        interfaceLayout: InterfaceLayoutMode = .softwareEngineering,
        appearanceMode: AppAppearanceMode = .system,
        language: AppLanguage = .english,
        theme: AppThemePreset = .obsidian,
        fontSizePt: Int = 14,
        collapsedProjectIds: Set<String> = [],
        notificationsEnabled: Bool = true,
        suppressManualStopNotification: Bool = true,
        liveUpdatesEnabled: Bool = true,
        globalPermissionPreset: AgentPermissionPreset = .defaultSandbox,
        terminalSandboxEnabled: Bool = true
    ) {
        self.interfaceLayout = interfaceLayout
        self.appearanceMode = appearanceMode
        self.language = language
        self.theme = theme
        self.fontSizePt = [12, 14, 16].contains(fontSizePt) ? fontSizePt : 14
        self.collapsedProjectIds = collapsedProjectIds
        self.notificationsEnabled = notificationsEnabled
        self.suppressManualStopNotification = suppressManualStopNotification
        self.liveUpdatesEnabled = liveUpdatesEnabled
        self.globalPermissionPreset = globalPermissionPreset
        self.terminalSandboxEnabled = terminalSandboxEnabled
    }

    private enum CodingKeys: String, CodingKey {
        case interfaceLayout
        case appearanceMode
        case language
        case theme
        case fontSizePt
        case collapsedProjectIds
        case notificationsEnabled
        case suppressManualStopNotification
        case liveUpdatesEnabled
        case globalPermissionPreset
        case terminalSandboxEnabled
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedLayout = try container.decodeIfPresent(InterfaceLayoutMode.self, forKey: .interfaceLayout) ?? .softwareEngineering
        let decodedTheme = try container.decodeIfPresent(AppThemePreset.self, forKey: .theme) ?? .obsidian
        let decodedAppearanceMode: AppAppearanceMode
        if let explicitMode = try container.decodeIfPresent(AppAppearanceMode.self, forKey: .appearanceMode) {
            decodedAppearanceMode = explicitMode
        } else {
            // Migrate legacy `appearance_prefs.json` snapshots without `appearanceMode`.
            decodedAppearanceMode = (decodedTheme == .everforestLight) ? .light : .system
        }
        let decodedLanguage = try container.decodeIfPresent(AppLanguage.self, forKey: .language) ?? .english
        let rawFontSize = try container.decodeIfPresent(Int.self, forKey: .fontSizePt) ?? 14
        let decodedCollapsed = try container.decodeIfPresent(Set<String>.self, forKey: .collapsedProjectIds) ?? []
        let decodedNotifications = try container.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? true
        let decodedSuppressStop = try container.decodeIfPresent(Bool.self, forKey: .suppressManualStopNotification) ?? true
        let decodedLiveUpdates = try container.decodeIfPresent(Bool.self, forKey: .liveUpdatesEnabled) ?? true
        let decodedPermission = try container.decodeIfPresent(AgentPermissionPreset.self, forKey: .globalPermissionPreset) ?? .defaultSandbox
        let decodedSandbox = try container.decodeIfPresent(Bool.self, forKey: .terminalSandboxEnabled) ?? true

        self.init(
            interfaceLayout: decodedLayout,
            appearanceMode: decodedAppearanceMode,
            language: decodedLanguage,
            theme: decodedTheme,
            fontSizePt: rawFontSize,
            collapsedProjectIds: decodedCollapsed,
            notificationsEnabled: decodedNotifications,
            suppressManualStopNotification: decodedSuppressStop,
            liveUpdatesEnabled: decodedLiveUpdates,
            globalPermissionPreset: decodedPermission,
            terminalSandboxEnabled: decodedSandbox
        )
    }
}

public struct QueuedMessageItem: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var cascadeId: String
    public var text: String
    public var attachments: [ComposerAttachmentChip]
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        cascadeId: String,
        text: String,
        attachments: [ComposerAttachmentChip] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.cascadeId = cascadeId
        self.text = text
        self.attachments = attachments
        self.createdAt = createdAt
    }
}

public struct ConversationTurnSummary: Codable, Sendable, Equatable, Identifiable {
    public var id: String { "\(stepIndex)" }
    public var turnNumber: Int
    public var stepIndex: Int
    public var promptPreview: String
    public var timestamp: Date

    public init(turnNumber: Int, stepIndex: Int, promptPreview: String, timestamp: Date = Date()) {
        self.turnNumber = turnNumber
        self.stepIndex = stepIndex
        self.promptPreview = promptPreview
        self.timestamp = timestamp
    }
}

/// Evaluates whether a conversation status transition should emit a proactive push/local notification.
public enum NotificationPolicy: Sendable {
    public static func shouldNotify(
        previousStatus: CortexStepStatus,
        newStatus: CortexStepStatus,
        wasManuallyCancelled: Bool,
        preferences: AppAppearancePreferences
    ) -> Bool {
        guard preferences.notificationsEnabled else { return false }
        if wasManuallyCancelled && preferences.suppressManualStopNotification {
            return false
        }
        if previousStatus == newStatus {
            return false
        }
        return newStatus == .waiting || newStatus == .done || newStatus == .error
    }
}
