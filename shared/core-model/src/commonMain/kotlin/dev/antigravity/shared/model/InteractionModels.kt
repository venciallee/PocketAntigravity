package dev.antigravity.shared.model

import kotlinx.serialization.Serializable

/**
 * Maps to `exa.cortex_pb.RequestedInteraction` (field 56 on `gemini_coder.Step`).
 * Authoritative specification of what interaction member the LanguageServer expects
 * in `HandleCascadeUserInteraction`.
 */
@Serializable
public data class RequestedInteraction(
    public val kind: MemberKind,
    public val permission: PermissionInteractionSpec? = null,
    public val filePermission: FilePermissionInteractionSpec? = null,
    public val runCommand: RunCommandInteractionSpec? = null,
    public val askQuestion: AskQuestionInteractionSpec? = null,
    public val executeUrl: ExecuteUrlInteractionSpec? = null,
    public val downloadUrl: DownloadUrlInteractionSpec? = null,
    public val browserUpload: BrowserUploadInteractionSpec? = null,
    public val workflowScript: WorkflowScriptInteractionSpec? = null,
    public val mcpServerName: String? = null,
    public val mcpToolName: String? = null,
    public val pluginName: String? = null,
    public val rawMemberKey: String? = null,
    public val rawSummary: String? = null,
    public val rawWireFieldNumber: Int? = null,
) {
    public val isUnrecognizedWireMember: Boolean
        get() = rawWireFieldNumber != null && rawMemberKey.isNullOrEmpty()

    @Serializable
    public enum class MemberKind(public val wireKey: String) {
        DEPLOY("deploy"),
        RUN_COMMAND("runCommand"),
        OPEN_BROWSER_URL("openBrowserUrl"),
        RUN_EXTENSION_CODE("runExtensionCode"),
        EXECUTE_BROWSER_JAVASCRIPT("executeBrowserJavascript"),
        CAPTURE_BROWSER_SCREENSHOT("captureBrowserScreenshot"),
        CLICK_BROWSER_PIXEL("clickBrowserPixel"),
        BROWSER_ACTION("browserAction"),
        OPEN_BROWSER_SETUP("openBrowserSetup"),
        CONFIRM_BROWSER_SETUP("confirmBrowserSetup"),
        SEND_COMMAND_INPUT("sendCommandInput"),
        READ_URL_CONTENT("readUrlContent"),
        MCP("mcp"),
        FILE_PERMISSION("filePermission"),
        ELICITATION("elicitation"),
        PERMISSION("permission"),
        ASK_QUESTION("askQuestion"),
        APPROVAL_INTERACTION("approvalInteraction"),
        EXECUTE_URL("executeUrl"),
        DOWNLOAD_URL("downloadUrl"),
        BROWSER_UPLOAD("browserUpload"),
        WORKFLOW_SCRIPT("workflowScript");

        public companion object {
            public fun fromWireKey(raw: String): MemberKind? =
                entries.firstOrNull { it.wireKey.equals(raw, ignoreCase = true) }
        }
    }
}

@Serializable
public enum class PersistSuggestionType(public val rawValue: Int) {
    UNSPECIFIED(0),
    SUGGESTED(1),
    BLOCKED(2);

    public companion object {
        public fun fromRaw(raw: Int): PersistSuggestionType =
            entries.firstOrNull { it.rawValue == raw } ?: SUGGESTED
    }
}

@Serializable
public data class PermissionInteractionSpec(
    public val action: String,
    public val target: String,
    public val suggestedPersistPattern: String? = null,
    public val persistSuggestionType: PersistSuggestionType = PersistSuggestionType.SUGGESTED,
    public val reason: String? = null,
    public val pluginName: String? = null,
    public val toolIconName: String? = null,
)

@Serializable
public data class ExecuteUrlInteractionSpec(
    public val url: String,
    public val domain: String,
    public val isRedirect: Boolean = false,
)

@Serializable
public data class DownloadUrlInteractionSpec(
    public val url: String,
    public val origin: String,
    public val fileName: String,
    public val mimeType: String = "application/octet-stream",
    public val destinationFolder: String = "~/Downloads",
)

@Serializable
public data class BrowserUploadInteractionSpec(
    public val origin: String,
    public val fileNames: List<String>,
)

@Serializable
public data class WorkflowScriptInteractionSpec(
    public val title: String,
    public val pythonScript: String,
    public val phaseNames: List<String> = emptyList(),
)

@Serializable
public data class FilePermissionInteractionSpec(
    public val absolutePathUri: String,
    public val isDirectory: Boolean = false,
    public val blockReason: String? = null,
)

@Serializable
public data class RunCommandInteractionSpec(
    public val proposedCommandLine: String,
    public val cwd: String,
    public val isDaemon: Boolean = false,
)

@Serializable
public data class AskQuestionInteractionSpec(
    public val question: String,
    public val options: List<String>,
    public val isMultiSelect: Boolean = false,
)

@Serializable
public data class StructuredQuestionStepItem(
    public val id: String,
    public val stepNumber: Int,
    public val shortTabTitle: String,
    public val questionTitle: String,
    public val options: List<String>,
    public val selectedOptions: Set<String> = emptySet(),
    public val customWriteIn: String = "",
    public val isCompleted: Boolean = false,
    public val isMultiSelect: Boolean = true,
)

/**
 * User decision mode when answering a permission gate or structured question.
 */
public sealed interface InteractionDecision {
    public data object AllowOnce : InteractionDecision
    public data object AllowWithBiometric : InteractionDecision
    public data object AlwaysAllowInTurn : InteractionDecision
    public data object AllowInConversation : InteractionDecision
    public data object AlwaysAllow : InteractionDecision
    public data class AllowWithModifiedCommand(public val commandLine: String) : InteractionDecision
    public data class AnswerQuestion(
        public val selectedOptions: List<String>,
        public val customWriteIn: String? = null,
    ) : InteractionDecision
    public data object Reject : InteractionDecision
}

/**
 * Strictly typed representation of `exa.cortex_pb.CascadeUserInteraction`.
 */
@Serializable
public data class CascadeUserInteractionPayload(
    public val cascadeId: String,
    public val stepIndex: Int,
    public val kind: RequestedInteraction.MemberKind,
    public val workspaceUri: String? = null,
    public val runCommand: RunCommandAnswer? = null,
    public val permission: PermissionAnswer? = null,
    public val filePermission: FilePermissionAnswer? = null,
    public val askQuestion: AskQuestionAnswer? = null,
    public val genericConfirm: Boolean? = null,
    public val approvalScope: String? = null,
    public val rawMemberKey: String? = null,
) {
    @Serializable
    public data class RunCommandAnswer(
        public val confirm: Boolean,
        public val proposedCommandLine: String,
        public val submittedCommandLine: String,
        public val biometricVerified: Boolean = false,
    )

    @Serializable
    public data class PermissionAnswer(
        public val allow: Boolean,
        public val grantPatterns: List<String> = emptyList(),
        public val scope: String = "PERMISSION_SCOPE_ONCE",
    )

    @Serializable
    public data class FilePermissionAnswer(
        public val allow: Boolean,
        public val scope: String = "PERMISSION_SCOPE_ONCE",
        public val absolutePathUri: String? = null,
    )

    @Serializable
    public data class AskQuestionAnswer(
        public val selectedOptions: List<String>,
        public val customResponse: String? = null,
    )
}
