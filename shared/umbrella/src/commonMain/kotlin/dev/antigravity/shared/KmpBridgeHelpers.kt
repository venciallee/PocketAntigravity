package dev.antigravity.shared

import dev.antigravity.shared.model.AgentPermissionPreset
import dev.antigravity.shared.model.AgentsHostFilterScope
import dev.antigravity.shared.model.AskQuestionInteractionSpec
import dev.antigravity.shared.model.BrowserUploadInteractionSpec
import dev.antigravity.shared.model.CascadeExecutionMode
import dev.antigravity.shared.model.CascadeStep
import dev.antigravity.shared.model.ComposerAttachmentChip
import dev.antigravity.shared.model.CortexStepStatus
import dev.antigravity.shared.model.CortexStepType
import dev.antigravity.shared.model.DownloadUrlInteractionSpec
import dev.antigravity.shared.model.ExecuteUrlInteractionSpec
import dev.antigravity.shared.model.FilePermissionInteractionSpec
import dev.antigravity.shared.model.InteractionDecision
import dev.antigravity.shared.model.PermissionInteractionSpec
import dev.antigravity.shared.model.PersistSuggestionType
import dev.antigravity.shared.model.ProjectRuntimeTarget
import dev.antigravity.shared.model.RemoteConnectionChannel
import dev.antigravity.shared.model.RequestedInteraction
import dev.antigravity.shared.model.RunCommandInteractionSpec
import dev.antigravity.shared.model.RunCommandPayload
import dev.antigravity.shared.model.TaskChecklistStatus
import dev.antigravity.shared.model.ThinkingEffortLevel
import dev.antigravity.shared.model.WorkflowScriptInteractionSpec
import dev.antigravity.shared.platform.NetworkReachabilityStatus
import dev.antigravity.shared.platform.SavedBackendCredentials
import dev.antigravity.shared.platform.SecretStore
import dev.antigravity.shared.protocol.AntigravityRpcError
import dev.antigravity.shared.protocol.RelayInstanceInfo
import dev.antigravity.shared.protocol.RelayInstanceStatus

/**
 * Synchronous secret-store bridge interface so Swift / iOS Keychain (`Security.framework`)
 * can implement KMP secret persistence cleanly without ObjC `suspend` completion-handler boilerplate.
 */
public interface SyncSecretStore {
    public fun storeSecretSync(value: String, key: String)
    public fun readSecretSync(key: String): String?
    public fun removeSecretSync(key: String)
    public fun saveCredentialsSync(credentials: SavedBackendCredentials)
    public fun loadCredentialsSync(): SavedBackendCredentials?
    public fun clearCredentialsSync()
}

public class SyncSecretStoreAdapter(
    private val delegate: SyncSecretStore,
) : SecretStore {
    override suspend fun storeSecret(value: String, key: String) = delegate.storeSecretSync(value, key)
    override suspend fun readSecret(key: String): String? = delegate.readSecretSync(key)
    override suspend fun removeSecret(key: String) = delegate.removeSecretSync(key)
    override suspend fun saveCredentials(credentials: SavedBackendCredentials) = delegate.saveCredentialsSync(credentials)
    override suspend fun loadCredentials(): SavedBackendCredentials? = delegate.loadCredentialsSync()
    override suspend fun clearCredentials() = delegate.clearCredentialsSync()
}

/**
 * Strongly-typed factory & interop helpers exported via SKIE into `AntigravityShared.xcframework`
 * so Swift bridges can construct Kotlin sealed interfaces, enums, and DTOs cleanly with zero
 * Objective-C name-mangling fragility.
 */
public object KmpBridgeHelpers {

    // MARK: - Host Filter Scope
    public fun scopeAllHosts(): AgentsHostFilterScope = AgentsHostFilterScope.AllHosts
    public fun scopeAntigravityCloud(): AgentsHostFilterScope = AgentsHostFilterScope.AntigravityCloud
    public fun scopeLocalHost(id: String, name: String): AgentsHostFilterScope =
        AgentsHostFilterScope.LocalHost(id = id, name = name)

    // MARK: - Network Reachability Status
    public fun networkSatisfied(
        interfaceFingerprint: String,
        isExpensive: Boolean,
        isConstrained: Boolean,
    ): NetworkReachabilityStatus = NetworkReachabilityStatus.Satisfied(
        interfaceFingerprint = interfaceFingerprint,
        isExpensive = isExpensive,
        isConstrained = isConstrained,
    )

    public fun networkUnsatisfied(): NetworkReachabilityStatus = NetworkReachabilityStatus.Unsatisfied

    // MARK: - Credentials & Relay DTO Factories
    public fun makeSavedCredentials(
        endpointUrlString: String,
        isCloudRelay: Boolean,
        hostname: String,
        csrfToken: String?,
        sessionCookie: String?,
        authUser: String?,
        resolvedInstanceUuid: String?,
        relayApiKey: String?,
        certFingerprintSha256: String?,
        pairedAtEpochMs: Long,
    ): SavedBackendCredentials = SavedBackendCredentials(
        endpointUrlString = endpointUrlString,
        channel = channelFromIsCloudRelay(isCloudRelay),
        hostname = hostname,
        csrfToken = csrfToken,
        sessionCookie = sessionCookie,
        authUser = authUser,
        resolvedInstanceUuid = resolvedInstanceUuid,
        relayApiKey = relayApiKey,
        certFingerprintSha256 = certFingerprintSha256,
        pairedAtEpochMs = pairedAtEpochMs,
    )

    public fun makeRelayInstanceInfo(
        uuid: String,
        name: String,
        version: String,
        supportsChunking: Boolean,
        statusRawCode: Int,
        updatedAtEpochMs: Long?,
    ): RelayInstanceInfo = RelayInstanceInfo(
        uuid = uuid,
        name = name,
        version = version,
        supportsChunking = supportsChunking,
        status = RelayInstanceStatus.fromRawCode(statusRawCode),
        updatedAtEpochMs = updatedAtEpochMs,
    )

    public fun makeAttachmentChip(
        id: String,
        kindName: String,
        label: String,
        targetUri: String?,
        mimeType: String?,
        inlinePayload: String?,
    ): ComposerAttachmentChip = ComposerAttachmentChip(
        id = id,
        kind = attachmentKindFromName(kindName),
        label = label,
        targetUri = targetUri,
        mimeType = mimeType,
        inlinePayload = inlinePayload,
    )

    public fun makeCascadeStepForInteraction(
        cascadeId: String,
        stepIndex: Int,
        stepTypeRaw: Int,
        stepStatusRaw: Int,
        runCommandId: String?,
        runCommandLine: String?,
        runCommandProposed: String?,
        runCommandCwd: String?,
        interactionKindWireKey: String?,
        interactionRawMemberKey: String?,
        permAction: String?,
        permTarget: String?,
        permSuggestedPattern: String?,
        permPersistTypeRaw: Int,
        permReason: String?,
        permPluginName: String?,
        filePermUri: String?,
        filePermIsDirectory: Boolean,
        filePermBlockReason: String?,
        askQuestionText: String?,
        askQuestionOptions: List<String>,
        askQuestionMultiSelect: Boolean,
        executeUrl: String?,
        executeUrlDomain: String?,
        executeUrlIsRedirect: Boolean,
        downloadUrl: String?,
        downloadOrigin: String?,
        downloadFileName: String?,
        downloadMimeType: String?,
        downloadDestFolder: String?,
        browserUploadOrigin: String?,
        browserUploadFiles: List<String>,
        workflowTitle: String?,
        workflowScript: String?,
        workflowPhases: List<String>,
        mcpServerName: String?,
        mcpToolName: String?,
    ): CascadeStep {
        val rcPayload = if (!runCommandLine.isNullOrEmpty() || !runCommandProposed.isNullOrEmpty()) {
            RunCommandPayload(
                commandId = runCommandId ?: "cmd-$stepIndex",
                commandLine = runCommandLine ?: runCommandProposed.orEmpty(),
                proposedCommandLine = runCommandProposed ?: runCommandLine,
                cwd = runCommandCwd ?: "/workspace",
            )
        } else null

        val requested = interactionKindWireKey?.let { wireKey ->
            val kind = memberKindFromWireKey(wireKey)
            RequestedInteraction(
                kind = kind,
                permission = if (permAction != null && permTarget != null) {
                    PermissionInteractionSpec(
                        action = permAction,
                        target = permTarget,
                        suggestedPersistPattern = permSuggestedPattern,
                        persistSuggestionType = PersistSuggestionType.fromRaw(permPersistTypeRaw),
                        reason = permReason,
                        pluginName = permPluginName,
                    )
                } else null,
                filePermission = filePermUri?.let {
                    FilePermissionInteractionSpec(
                        absolutePathUri = it,
                        isDirectory = filePermIsDirectory,
                        blockReason = filePermBlockReason,
                    )
                },
                runCommand = if (kind == RequestedInteraction.MemberKind.RUN_COMMAND) {
                    RunCommandInteractionSpec(
                        proposedCommandLine = runCommandProposed ?: runCommandLine.orEmpty(),
                        cwd = runCommandCwd ?: "/workspace",
                    )
                } else null,
                askQuestion = askQuestionText?.let {
                    AskQuestionInteractionSpec(
                        question = it,
                        options = askQuestionOptions,
                        isMultiSelect = askQuestionMultiSelect,
                    )
                },
                executeUrl = executeUrl?.let {
                    ExecuteUrlInteractionSpec(
                        url = it,
                        domain = executeUrlDomain.orEmpty(),
                        isRedirect = executeUrlIsRedirect,
                    )
                },
                downloadUrl = downloadUrl?.let {
                    DownloadUrlInteractionSpec(
                        url = it,
                        origin = downloadOrigin.orEmpty(),
                        fileName = downloadFileName.orEmpty(),
                        mimeType = downloadMimeType ?: "application/octet-stream",
                        destinationFolder = downloadDestFolder ?: "~/Downloads",
                    )
                },
                browserUpload = browserUploadOrigin?.let {
                    BrowserUploadInteractionSpec(origin = it, fileNames = browserUploadFiles)
                },
                workflowScript = workflowTitle?.let {
                    WorkflowScriptInteractionSpec(
                        title = it,
                        pythonScript = workflowScript.orEmpty(),
                        phaseNames = workflowPhases,
                    )
                },
                mcpServerName = mcpServerName,
                mcpToolName = mcpToolName,
                pluginName = permPluginName,
                rawMemberKey = interactionRawMemberKey ?: wireKey,
            )
        }

        return CascadeStep(
            cascadeId = cascadeId,
            stepIndex = stepIndex,
            type = CortexStepType.fromRaw(stepTypeRaw),
            status = CortexStepStatus.fromRaw(stepStatusRaw),
            runCommand = rcPayload,
            requestedInteraction = requested,
        )
    }

    // MARK: - Interaction Decisions
    public fun decisionAllowOnce(): InteractionDecision = InteractionDecision.AllowOnce
    public fun decisionAllowWithBiometric(): InteractionDecision = InteractionDecision.AllowWithBiometric
    public fun decisionAlwaysAllowInTurn(): InteractionDecision = InteractionDecision.AlwaysAllowInTurn
    public fun decisionAllowInConversation(): InteractionDecision = InteractionDecision.AllowInConversation
    public fun decisionAlwaysAllow(): InteractionDecision = InteractionDecision.AlwaysAllow
    public fun decisionAllowWithModifiedCommand(commandLine: String): InteractionDecision =
        InteractionDecision.AllowWithModifiedCommand(commandLine = commandLine)
    public fun decisionAnswerQuestion(
        selectedOptions: List<String>,
        customWriteIn: String?,
    ): InteractionDecision = InteractionDecision.AnswerQuestion(
        selectedOptions = selectedOptions,
        customWriteIn = customWriteIn,
    )
    public fun decisionReject(): InteractionDecision = InteractionDecision.Reject

    // MARK: - Enum Lookups & Projections
    public fun channelFromIsCloudRelay(isCloudRelay: Boolean): RemoteConnectionChannel =
        if (isCloudRelay) RemoteConnectionChannel.CLOUD_RELAY else RemoteConnectionChannel.DIRECT_HOST

    public fun isCloudRelayChannel(channel: RemoteConnectionChannel): Boolean =
        channel == RemoteConnectionChannel.CLOUD_RELAY

    public fun isCloudProjectRuntime(runtime: ProjectRuntimeTarget): Boolean =
        runtime == ProjectRuntimeTarget.CLOUD

    public fun taskChecklistStatusRaw(status: TaskChecklistStatus): String = when (status) {
        TaskChecklistStatus.DONE -> "done"
        TaskChecklistStatus.IN_PROGRESS -> "inProgress"
        TaskChecklistStatus.WAITING -> "waiting"
        TaskChecklistStatus.PENDING -> "pending"
    }

    public fun relayStatusFromRaw(rawCode: Int): RelayInstanceStatus =
        RelayInstanceStatus.fromRawCode(rawCode)

    public fun stepStatusFromRaw(rawValue: Int): CortexStepStatus =
        CortexStepStatus.fromRaw(rawValue)

    public fun stepTypeFromRaw(rawValue: Int): CortexStepType =
        CortexStepType.fromRaw(rawValue)

    public fun memberKindFromWireKey(wireKey: String): RequestedInteraction.MemberKind =
        RequestedInteraction.MemberKind.fromWireKey(wireKey)
            ?: RequestedInteraction.MemberKind.APPROVAL_INTERACTION

    public fun persistSuggestionFromRaw(rawValue: Int): PersistSuggestionType =
        PersistSuggestionType.fromRaw(rawValue)

    public fun thinkingEffortFromCli(cliValue: String): ThinkingEffortLevel =
        ThinkingEffortLevel.entries.firstOrNull {
            it.cliValue.equals(cliValue, ignoreCase = true) || it.protoWireValue.equals(cliValue, ignoreCase = true)
        } ?: ThinkingEffortLevel.HIGH

    public fun executionModeFromIsPlanning(isPlanning: Boolean): CascadeExecutionMode =
        if (isPlanning) CascadeExecutionMode.PLANNING else CascadeExecutionMode.FAST

    public fun isPlanningMode(mode: CascadeExecutionMode): Boolean =
        mode == CascadeExecutionMode.PLANNING

    public fun permissionPresetFromRaw(rawValue: String?): AgentPermissionPreset? =
        rawValue?.let { AgentPermissionPreset.fromRaw(it) }

    public fun attachmentKindFromName(rawName: String): ComposerAttachmentChip.Kind =
        ComposerAttachmentChip.Kind.entries.firstOrNull { it.name.equals(rawName, ignoreCase = true) }
            ?: ComposerAttachmentChip.Kind.FILE_MENTION

    public fun errorKindTag(throwable: Throwable): String = when (throwable) {
        is AntigravityRpcError.Unauthorized -> "unauthorized"
        is AntigravityRpcError.InvalidEndpoint -> "invalidEndpoint"
        is AntigravityRpcError.HttpError -> "http:${throwable.statusCode}"
        is AntigravityRpcError.DecodingError -> "decoding"
        is AntigravityRpcError.InteractionRejected -> "interactionRejected"
        else -> "other"
    }
}
