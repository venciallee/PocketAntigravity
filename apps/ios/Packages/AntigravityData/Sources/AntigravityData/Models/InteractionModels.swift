import Foundation

/// Maps to `exa.cortex_pb.RequestedInteraction` (field 56 on `gemini_coder.Step`).
/// Authoritative specification of what interaction member the LanguageServer expects
/// in `HandleCascadeUserInteraction`.
public struct RequestedInteraction: Codable, Sendable, Equatable {
    public enum MemberKind: String, Codable, Sendable {
        case deploy
        case runCommand
        case openBrowserUrl
        case runExtensionCode
        case executeBrowserJavascript
        case captureBrowserScreenshot
        case clickBrowserPixel
        case browserAction
        case openBrowserSetup
        case confirmBrowserSetup
        case sendCommandInput
        case readUrlContent
        case mcp
        case filePermission
        case elicitation
        case permission
        case askQuestion
        case approvalInteraction
        case executeUrl
        case downloadUrl
        case browserUpload
        case workflowScript
    }

    public var kind: MemberKind
    public var permission: PermissionInteractionSpec?
    public var filePermission: FilePermissionInteractionSpec?
    public var runCommand: RunCommandInteractionSpec?
    public var askQuestion: AskQuestionInteractionSpec?
    public var executeUrl: ExecuteUrlInteractionSpec?
    public var downloadUrl: DownloadUrlInteractionSpec?
    public var browserUpload: BrowserUploadInteractionSpec?
    public var workflowScript: WorkflowScriptInteractionSpec?
    public var mcpServerName: String?
    public var mcpToolName: String?
    public var pluginName: String?
    public var rawMemberKey: String?
    public var rawSummary: String?
    /// `true` when decoded from an unknown binary Protobuf oneof field number (no JSON member key known)
    /// so the client avoids sending a mismatched `approvalInteraction` payload that newer PCs silently drop.
    public var isUnrecognizedWireMember: Bool
    /// Raw Protobuf field number inside `RequestedInteraction` when `isUnrecognizedWireMember == true`.
    public var rawWireFieldNumber: Int?

    public init(
        kind: MemberKind,
        permission: PermissionInteractionSpec? = nil,
        filePermission: FilePermissionInteractionSpec? = nil,
        runCommand: RunCommandInteractionSpec? = nil,
        askQuestion: AskQuestionInteractionSpec? = nil,
        executeUrl: ExecuteUrlInteractionSpec? = nil,
        downloadUrl: DownloadUrlInteractionSpec? = nil,
        browserUpload: BrowserUploadInteractionSpec? = nil,
        workflowScript: WorkflowScriptInteractionSpec? = nil,
        mcpServerName: String? = nil,
        mcpToolName: String? = nil,
        pluginName: String? = nil,
        rawMemberKey: String? = nil,
        rawSummary: String? = nil,
        isUnrecognizedWireMember: Bool = false,
        rawWireFieldNumber: Int? = nil
    ) {
        self.kind = kind
        self.permission = permission
        self.filePermission = filePermission
        self.runCommand = runCommand
        self.askQuestion = askQuestion
        self.executeUrl = executeUrl
        self.downloadUrl = downloadUrl
        self.browserUpload = browserUpload
        self.workflowScript = workflowScript
        self.mcpServerName = mcpServerName
        self.mcpToolName = mcpToolName
        self.pluginName = pluginName
        self.rawMemberKey = rawMemberKey
        self.rawSummary = rawSummary
        self.isUnrecognizedWireMember = isUnrecognizedWireMember
        self.rawWireFieldNumber = rawWireFieldNumber
    }

    private enum CodingKeys: String, CodingKey {
        case kind, permission, filePermission, runCommand, askQuestion, executeUrl, downloadUrl
        case browserUpload, workflowScript, mcpServerName, mcpToolName, pluginName
        case rawMemberKey, rawSummary, isUnrecognizedWireMember, rawWireFieldNumber
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.kind = (try? c.decode(MemberKind.self, forKey: .kind)) ?? .approvalInteraction
        self.permission = try c.decodeIfPresent(PermissionInteractionSpec.self, forKey: .permission)
        self.filePermission = try c.decodeIfPresent(FilePermissionInteractionSpec.self, forKey: .filePermission)
        self.runCommand = try c.decodeIfPresent(RunCommandInteractionSpec.self, forKey: .runCommand)
        self.askQuestion = try c.decodeIfPresent(AskQuestionInteractionSpec.self, forKey: .askQuestion)
        self.executeUrl = try c.decodeIfPresent(ExecuteUrlInteractionSpec.self, forKey: .executeUrl)
        self.downloadUrl = try c.decodeIfPresent(DownloadUrlInteractionSpec.self, forKey: .downloadUrl)
        self.browserUpload = try c.decodeIfPresent(BrowserUploadInteractionSpec.self, forKey: .browserUpload)
        self.workflowScript = try c.decodeIfPresent(WorkflowScriptInteractionSpec.self, forKey: .workflowScript)
        self.mcpServerName = try c.decodeIfPresent(String.self, forKey: .mcpServerName)
        self.mcpToolName = try c.decodeIfPresent(String.self, forKey: .mcpToolName)
        self.pluginName = try c.decodeIfPresent(String.self, forKey: .pluginName)
        self.rawMemberKey = try c.decodeIfPresent(String.self, forKey: .rawMemberKey)
        self.rawSummary = try c.decodeIfPresent(String.self, forKey: .rawSummary)
        self.isUnrecognizedWireMember = try c.decodeIfPresent(Bool.self, forKey: .isUnrecognizedWireMember) ?? false
        self.rawWireFieldNumber = try c.decodeIfPresent(Int.self, forKey: .rawWireFieldNumber)
    }
}

public enum PersistSuggestionType: Int, Codable, Sendable {
    case unspecified = 0
    case suggested = 1
    case blocked = 2
}

/// Outside-of-project or tool permission gate (`PermissionInteractionSpec` field 21).
public struct PermissionInteractionSpec: Codable, Sendable, Equatable {
    public var action: String
    public var target: String
    public var suggestedPersistPattern: String?
    public var persistSuggestionType: PersistSuggestionType
    public var reason: String?
    public var pluginName: String?
    public var toolIconName: String?

    public init(
        action: String,
        target: String,
        suggestedPersistPattern: String? = nil,
        persistSuggestionType: PersistSuggestionType = .suggested,
        reason: String? = nil,
        pluginName: String? = nil,
        toolIconName: String? = nil
    ) {
        self.action = action
        self.target = target
        self.suggestedPersistPattern = suggestedPersistPattern
        self.persistSuggestionType = persistSuggestionType
        self.reason = reason
        self.pluginName = pluginName
        self.toolIconName = toolIconName
    }
}

/// Built-in browser navigation / actuation approval (`execute_url`, v2.30.0+).
public struct ExecuteUrlInteractionSpec: Codable, Sendable, Equatable {
    public var url: String
    public var domain: String
    public var isRedirect: Bool

    public init(url: String, domain: String, isRedirect: Bool = false) {
        self.url = url
        self.domain = domain
        self.isRedirect = isRedirect
    }
}

/// Built-in browser file download approval (`download_url`, v2.31.0+).
public struct DownloadUrlInteractionSpec: Codable, Sendable, Equatable {
    public var url: String
    public var origin: String
    public var fileName: String
    public var mimeType: String
    public var destinationFolder: String

    public init(
        url: String,
        origin: String,
        fileName: String,
        mimeType: String = "application/octet-stream",
        destinationFolder: String = "~/Downloads"
    ) {
        self.url = url
        self.origin = origin
        self.fileName = fileName
        self.mimeType = mimeType
        self.destinationFolder = destinationFolder
    }
}

/// One-time browser file upload confirmation (required even in Turbo preset).
public struct BrowserUploadInteractionSpec: Codable, Sendable, Equatable {
    public var origin: String
    public var fileNames: [String]

    public init(origin: String, fileNames: [String]) {
        self.origin = origin
        self.fileNames = fileNames
    }
}

/// Dynamic Workflows (`/run-workflow`, v2.32.0+) Python script approval prompt.
public struct WorkflowScriptInteractionSpec: Codable, Sendable, Equatable {
    public var title: String
    public var pythonScript: String
    public var phaseNames: [String]

    public init(title: String, pythonScript: String, phaseNames: [String] = []) {
        self.title = title
        self.pythonScript = pythonScript
        self.phaseNames = phaseNames
    }
}

/// File access gate (`FilePermissionInteractionSpec` field 19).
public struct FilePermissionInteractionSpec: Codable, Sendable, Equatable {
    public var absolutePathUri: String
    public var isDirectory: Bool
    public var blockReason: String?

    public init(absolutePathUri: String, isDirectory: Bool = false, blockReason: String? = nil) {
        self.absolutePathUri = absolutePathUri
        self.isDirectory = isDirectory
        self.blockReason = blockReason
    }
}

/// Command approval gate (`RunCommandInteractionSpec` field 3).
public struct RunCommandInteractionSpec: Codable, Sendable, Equatable {
    public var proposedCommandLine: String
    public var cwd: String
    public var isDaemon: Bool

    public init(proposedCommandLine: String, cwd: String, isDaemon: Bool = false) {
        self.proposedCommandLine = proposedCommandLine
        self.cwd = cwd
        self.isDaemon = isDaemon
    }
}

/// Interactive multiple-choice question (`AskQuestionInteractionSpec` field 22).
public struct AskQuestionInteractionSpec: Codable, Sendable, Equatable {
    public var question: String
    public var options: [String]
    public var isMultiSelect: Bool

    public init(question: String, options: [String], isMultiSelect: Bool = false) {
        self.question = question
        self.options = options
        self.isMultiSelect = isMultiSelect
    }
}

// MARK: - Multi-Step Structured Question Wizard (UE10)

/// Single step in the multi-question interactive stepper card (`✓ 1 Storage`, `2 Actions`, `3 Retention` in `UE10`).
public struct StructuredQuestionStepItem: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var stepNumber: Int
    public var shortTabTitle: String
    public var questionTitle: String
    public var options: [String]
    public var selectedOptions: Set<String>
    public var customWriteIn: String
    public var isCompleted: Bool
    public var isMultiSelect: Bool

    public init(
        id: String,
        stepNumber: Int,
        shortTabTitle: String,
        questionTitle: String,
        options: [String],
        selectedOptions: Set<String> = [],
        customWriteIn: String = "",
        isCompleted: Bool = false,
        isMultiSelect: Bool = true
    ) {
        self.id = id
        self.stepNumber = stepNumber
        self.shortTabTitle = shortTabTitle
        self.questionTitle = questionTitle
        self.options = options
        self.selectedOptions = selectedOptions
        self.customWriteIn = customWriteIn
        self.isCompleted = isCompleted
        self.isMultiSelect = isMultiSelect
    }
}

public typealias StructuredQuestionStep = StructuredQuestionStepItem

/// User decision mode when answering a permission gate or structured question.
public enum InteractionDecision: Sendable, Equatable {
    case allowOnce
    case allowWithFaceID
    case alwaysAllowInTurn
    case allowInConversation
    case alwaysAllow
    case allowWithModifiedCommand(String)
    case answerQuestion(selectedOptions: [String], customWriteIn: String?)
    case reject
}

// MARK: - Typed Sendable HandleCascadeUserInteraction Payload

/// Strictly typed, `Sendable` representation of `exa.cortex_pb.CascadeUserInteraction`
/// safe to pass across Swift 6 actor isolation boundaries.
public struct CascadeUserInteractionPayload: Codable, Sendable, Equatable {
    public struct RunCommandAnswer: Codable, Sendable, Equatable {
        public var confirm: Bool
        public var proposedCommandLine: String
        public var submittedCommandLine: String
        public var faceIdVerified: Bool

        public init(
            confirm: Bool,
            proposedCommandLine: String,
            submittedCommandLine: String,
            faceIdVerified: Bool = false
        ) {
            self.confirm = confirm
            self.proposedCommandLine = proposedCommandLine
            self.submittedCommandLine = submittedCommandLine
            self.faceIdVerified = faceIdVerified
        }
    }

    public struct PermissionAnswer: Codable, Sendable, Equatable {
        public var allow: Bool
        public var grantPatterns: [String]
        public var scope: String

        public init(allow: Bool, grantPatterns: [String] = [], scope: String = "PERMISSION_SCOPE_ONCE") {
            self.allow = allow
            self.grantPatterns = grantPatterns
            self.scope = scope
        }
    }

    public struct FilePermissionAnswer: Codable, Sendable, Equatable {
        public var allow: Bool
        public var scope: String
        public var absolutePathUri: String?

        public init(allow: Bool, scope: String = "PERMISSION_SCOPE_ONCE", absolutePathUri: String? = nil) {
            self.allow = allow
            self.scope = scope
            self.absolutePathUri = absolutePathUri
        }
    }

    public struct AskQuestionAnswer: Codable, Sendable, Equatable {
        public var selectedOptions: [String]
        public var customResponse: String?

        public init(selectedOptions: [String], customResponse: String? = nil) {
            self.selectedOptions = selectedOptions
            self.customResponse = customResponse
        }
    }

    public var cascadeId: String
    public var stepIndex: Int
    public var kind: RequestedInteraction.MemberKind
    public var workspaceUri: String?
    public var runCommand: RunCommandAnswer?
    public var permission: PermissionAnswer?
    public var filePermission: FilePermissionAnswer?
    public var askQuestion: AskQuestionAnswer?
    public var genericConfirm: Bool?
    public var approvalScope: String?
    public var rawMemberKey: String?

    public init(
        cascadeId: String,
        stepIndex: Int,
        kind: RequestedInteraction.MemberKind,
        workspaceUri: String? = nil,
        runCommand: RunCommandAnswer? = nil,
        permission: PermissionAnswer? = nil,
        filePermission: FilePermissionAnswer? = nil,
        askQuestion: AskQuestionAnswer? = nil,
        genericConfirm: Bool? = nil,
        approvalScope: String? = nil,
        rawMemberKey: String? = nil
    ) {
        self.cascadeId = cascadeId
        self.stepIndex = stepIndex
        self.kind = kind
        self.workspaceUri = workspaceUri
        self.runCommand = runCommand
        self.permission = permission
        self.filePermission = filePermission
        self.askQuestion = askQuestion
        self.genericConfirm = genericConfirm
        self.approvalScope = approvalScope
        self.rawMemberKey = rawMemberKey
    }
}
