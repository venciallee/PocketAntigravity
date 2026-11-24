import Foundation
import AntigravityData
#if canImport(AntigravityShared)
@preconcurrency import AntigravityShared
#endif

/// Main-app bridge connecting `AntigravitySessionStore` to the Kotlin Multiplatform
/// `AntigravityShared.xcframework` (`Ktor Darwin` + `SKIE` + `AntigravityCoreCoordinator`).
///
/// Only compiled into the `Antigravity` iOS application target (never into WidgetKit or Share Extensions).
public final class KmpCoreEngineAdapter: AntigravityKmpEnginePort, @unchecked Sendable {

    #if canImport(AntigravityShared)
    private let coordinator: AntigravityShared.AntigravityCoreCoordinator

    public init(coordinator: AntigravityShared.AntigravityCoreCoordinator) {
        self.coordinator = coordinator
    }

    public static func makeDefault() -> (any AntigravityKmpEnginePort)? {
        let coordinator = AntigravitySharedFacade.shared.createCoordinatorWithSyncPorts(
            secretStore: KmpKeychainSecretStore(),
            networkMonitor: KmpNetworkPathMonitorAdapter(),
            powerStateProvider: KmpPowerStateAdapter(),
            preferencesStore: KmpUserDefaultsPreferencesAdapter()
        )
        return KmpCoreEngineAdapter(coordinator: coordinator)
    }

    public var engineName: String {
        "KMP-Ktor-Darwin-SKIE (\(AntigravitySharedFacade.shared.CORE_VERSION))"
    }

    public func connectDirectLan(
        endpointURLString: String,
        csrfToken: String,
        certSHA256: String?,
        hostName: String,
        isRestoringSavedSession: Bool
    ) async throws -> AntigravityData.BackendHandshakeResult {
        do {
            let result = try await coordinator.connectDirectLan(
                endpointUrlString: endpointURLString,
                csrfToken: csrfToken,
                certSha256: certSHA256,
                hostName: hostName,
                isRestoringSavedSession: isRestoringSavedSession,
                startSummaryStream: true
            )
            return KmpModelConverters.toSwiftHandshake(result)
        } catch {
            throw KmpModelConverters.mapKmpError(error)
        }
    }

    public func connectCloudRelay(
        relayURLString: String,
        sessionCookie: String,
        authUser: String?,
        resolvedInstanceUuid: String?,
        relayApiKey: String?,
        hostName: String,
        isRestoringSavedSession: Bool,
        strictTargetMatch: Bool
    ) async throws -> AntigravityData.BackendHandshakeResult {
        do {
            let result = try await coordinator.connectCloudRelay(
                relayUrlString: relayURLString,
                sessionCookie: sessionCookie,
                authUser: authUser,
                resolvedInstanceUuid: resolvedInstanceUuid,
                relayApiKey: relayApiKey,
                hostName: hostName,
                isRestoringSavedSession: isRestoringSavedSession,
                strictTargetMatch: strictTargetMatch,
                startSummaryStream: true
            )
            return KmpModelConverters.toSwiftHandshake(result)
        } catch {
            throw KmpModelConverters.mapKmpError(error)
        }
    }

    public func probeHostReachability(
        allowCrossHostFallback: Bool
    ) async throws -> AntigravityData.HostReachabilityProbeResult {
        do {
            let result = try await coordinator.probeHostReachability(
                allowCrossHostFallback: allowCrossHostFallback
            )
            return KmpModelConverters.toSwiftProbeResult(result)
        } catch {
            throw KmpModelConverters.mapKmpError(error)
        }
    }

    public func refreshWorkspacesAndSummaries(
        hostScope: AntigravityData.AgentsHostFilterScope,
        skipRelayListRefresh: Bool
    ) async throws -> AntigravityData.KmpFederatedSyncResult {
        do {
            let kmpScope = KmpModelConverters.toKmpHostScope(hostScope)
            let result = try await coordinator.refreshWorkspacesAndSummaries(
                hostScope: kmpScope,
                skipRelayListRefresh: skipRelayListRefresh
            )
            return KmpModelConverters.toSwiftFederatedSync(result)
        } catch {
            throw KmpModelConverters.mapKmpError(error)
        }
    }

    public func syncSteps(
        cascadeId: String,
        knownStepCount: Int,
        isCloud: Bool,
        instanceUuidOverride: String?
    ) async throws -> [AntigravityData.CascadeStep] {
        do {
            let steps = try await coordinator.syncSteps(
                cascadeId: cascadeId,
                knownStepCount: Int32(knownStepCount),
                isCloud: isCloud,
                instanceUuidOverride: instanceUuidOverride
            )
            return steps.map(KmpModelConverters.toSwiftStep)
        } catch {
            throw KmpModelConverters.mapKmpError(error)
        }
    }

    public func preloadSteps(
        cascadeId: String,
        knownStepCount: Int,
        isCloud: Bool,
        instanceUuidOverride: String?,
        requireRemoteRefresh: Bool
    ) async throws -> [AntigravityData.CascadeStep] {
        do {
            let steps = try await coordinator.preloadSteps(
                cascadeId: cascadeId,
                knownStepCount: Int32(knownStepCount),
                isCloud: isCloud,
                instanceUuidOverride: instanceUuidOverride,
                requireRemoteRefresh: requireRemoteRefresh
            )
            return steps.map(KmpModelConverters.toSwiftStep)
        } catch {
            throw KmpModelConverters.mapKmpError(error)
        }
    }

    public func startConversation(
        workspaceUri: String,
        initialPrompt: String,
        modelId: String,
        cloudProjectId: String?,
        isCloud: Bool,
        instanceUuidOverride: String?
    ) async throws -> String {
        do {
            return try await coordinator.startConversation(
                workspaceUri: workspaceUri,
                initialPrompt: initialPrompt,
                modelId: modelId,
                cloudProjectId: cloudProjectId,
                isCloud: isCloud,
                instanceUuidOverride: instanceUuidOverride
            )
        } catch {
            throw KmpModelConverters.mapKmpError(error)
        }
    }

    public func sendMessage(
        cascadeId: String,
        message: String,
        workspaceUri: String,
        attachments: [AntigravityData.ComposerAttachmentChip],
        modelId: String,
        effort: AntigravityData.ThinkingEffortLevel,
        mode: AntigravityData.CascadeExecutionMode,
        agentPersona: String,
        isCloud: Bool,
        cloudProjectId: String?,
        permissionPreset: AntigravityData.AgentPermissionPreset?,
        instanceUuidOverride: String?,
        isOptimisticDraft: Bool
    ) async throws -> AntigravityData.KmpSendMessageResult {
        do {
            let kmpAttachments = attachments.map(KmpModelConverters.toKmpAttachment)
            let kmpEffort = KmpBridgeHelpers.shared.thinkingEffortFromCli(cliValue: effort.cliValue)
            let kmpMode = KmpBridgeHelpers.shared.executionModeFromIsPlanning(isPlanning: mode == .planning)
            let kmpPreset = KmpBridgeHelpers.shared.permissionPresetFromRaw(rawValue: permissionPreset?.rawValue)

            let outcome = try await coordinator.sendMessage(
                cascadeId: cascadeId,
                message: message,
                workspaceUri: workspaceUri,
                attachments: kmpAttachments,
                modelId: modelId,
                effort: kmpEffort,
                mode: kmpMode,
                agentPersona: agentPersona,
                isCloud: isCloud,
                cloudProjectId: cloudProjectId,
                permissionPreset: kmpPreset,
                instanceUuidOverride: instanceUuidOverride,
                isOptimisticDraft: isOptimisticDraft
            )
            return AntigravityData.KmpSendMessageResult(
                resolvedCascadeId: outcome.resolvedCascadeId,
                dispatchedLive: outcome.dispatchedLive,
                queuedInOutbox: outcome.queuedInOutbox,
                errorMessage: outcome.errorMessage
            )
        } catch {
            throw KmpModelConverters.mapKmpError(error)
        }
    }

    public func resolveWaitingInteraction(
        step: AntigravityData.CascadeStep,
        decision: AntigravityData.InteractionDecision,
        workspaceUri: String?,
        instanceUuidOverride: String?
    ) async throws -> AntigravityData.CascadeUserInteractionPayload {
        do {
            let kmpStep = KmpModelConverters.toKmpStepForInteraction(step)
            let kmpDecision = KmpModelConverters.toKmpDecision(decision)
            let payload = try await coordinator.resolveWaitingInteraction(
                cascadeId: step.cascadeId,
                stepIndex: Int32(step.stepIndex),
                decision: kmpDecision,
                workspaceUri: workspaceUri,
                instanceUuidOverride: instanceUuidOverride,
                stepOverride: kmpStep
            )
            return KmpModelConverters.toSwiftInteractionPayload(payload)
        } catch {
            throw KmpModelConverters.mapKmpError(error)
        }
    }

    public func cancelActiveTurn(
        cascadeId: String,
        instanceUuidOverride: String?
    ) async throws {
        do {
            try await coordinator.cancelActiveTurn(
                cascadeId: cascadeId,
                instanceUuidOverride: instanceUuidOverride
            )
        } catch {
            throw KmpModelConverters.mapKmpError(error)
        }
    }

    public func replayPendingOutbox(
        modelId: String,
        effort: AntigravityData.ThinkingEffortLevel,
        mode: AntigravityData.CascadeExecutionMode
    ) async -> Int {
        let kmpEffort = KmpBridgeHelpers.shared.thinkingEffortFromCli(cliValue: effort.cliValue)
        let kmpMode = KmpBridgeHelpers.shared.executionModeFromIsPlanning(isPlanning: mode == .planning)
        let result = try? await coordinator.replayPendingOutbox(
            modelId: modelId,
            effort: kmpEffort,
            mode: kmpMode
        )
        return Int(result?.replayedCount ?? 0)
    }

    public func switchToRelayInstance(_ instance: AntigravityData.RelayInstanceInfo) async {
        let kmpInst = KmpModelConverters.toKmpRelayInstance(instance)
        try? await coordinator.switchToRelayInstance(instance: kmpInst)
    }

    public func summaryUpdatesStream() -> AsyncStream<[AntigravityData.CascadeSummary]> {
        return AsyncStream { continuation in
            let task = Task { [self] in
                for await syncState in self.coordinator.syncState {
                    if Task.isCancelled { break }
                    let mapped = syncState.summaries.map(KmpModelConverters.toSwiftSummary)
                    if !mapped.isEmpty {
                        continuation.yield(mapped)
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    public func onBackground() {
        coordinator.onBackground()
    }

    public func onForeground() async {
        try? await coordinator.onForeground()
    }

    public func disconnectAndClearCredentials() async {
        try? await coordinator.disconnectAndClearCredentials()
    }

    public func fetchUserDisplayName() async -> String? {
        do {
            return try await coordinator.refreshUserProfile()
        } catch {
            return nil
        }
    }

    public var lastHandshakeDiagnostic: String {
        coordinator.lastHandshakeDiagnostic()
    }
    #else
    public static func makeDefault() -> (any AntigravityKmpEnginePort)? { nil }
    public var engineName: String { "Unavailable" }
    public var lastHandshakeDiagnostic: String { "" }
    public func connectDirectLan(endpointURLString: String, csrfToken: String, certSHA256: String?, hostName: String, isRestoringSavedSession: Bool) async throws -> AntigravityData.BackendHandshakeResult { throw AntigravityRPCError.invalidEndpoint }
    public func connectCloudRelay(relayURLString: String, sessionCookie: String, authUser: String?, resolvedInstanceUuid: String?, relayApiKey: String?, hostName: String, isRestoringSavedSession: Bool, strictTargetMatch: Bool) async throws -> AntigravityData.BackendHandshakeResult { throw AntigravityRPCError.invalidEndpoint }
    public func probeHostReachability(allowCrossHostFallback: Bool) async throws -> AntigravityData.HostReachabilityProbeResult { throw AntigravityRPCError.invalidEndpoint }
    public func refreshWorkspacesAndSummaries(hostScope: AntigravityData.AgentsHostFilterScope, skipRelayListRefresh: Bool) async throws -> AntigravityData.KmpFederatedSyncResult { throw AntigravityRPCError.invalidEndpoint }
    public func syncSteps(cascadeId: String, knownStepCount: Int, isCloud: Bool, instanceUuidOverride: String?) async throws -> [AntigravityData.CascadeStep] { [] }
    public func preloadSteps(cascadeId: String, knownStepCount: Int, isCloud: Bool, instanceUuidOverride: String?, requireRemoteRefresh: Bool) async throws -> [AntigravityData.CascadeStep] { [] }
    public func startConversation(workspaceUri: String, initialPrompt: String, modelId: String, cloudProjectId: String?, isCloud: Bool, instanceUuidOverride: String?) async throws -> String { "" }
    public func sendMessage(cascadeId: String, message: String, workspaceUri: String, attachments: [AntigravityData.ComposerAttachmentChip], modelId: String, effort: AntigravityData.ThinkingEffortLevel, mode: AntigravityData.CascadeExecutionMode, agentPersona: String, isCloud: Bool, cloudProjectId: String?, permissionPreset: AntigravityData.AgentPermissionPreset?, instanceUuidOverride: String?, isOptimisticDraft: Bool) async throws -> AntigravityData.KmpSendMessageResult { KmpSendMessageResult(resolvedCascadeId: cascadeId, dispatchedLive: false, queuedInOutbox: false) }
    public func resolveWaitingInteraction(step: AntigravityData.CascadeStep, decision: AntigravityData.InteractionDecision, workspaceUri: String?, instanceUuidOverride: String?) async throws -> AntigravityData.CascadeUserInteractionPayload { throw AntigravityRPCError.interactionRejected }
    public func cancelActiveTurn(cascadeId: String, instanceUuidOverride: String?) async throws {}
    public func replayPendingOutbox(modelId: String, effort: AntigravityData.ThinkingEffortLevel, mode: AntigravityData.CascadeExecutionMode) async -> Int { 0 }
    public func switchToRelayInstance(_ instance: AntigravityData.RelayInstanceInfo) async {}
    public func summaryUpdatesStream() -> AsyncStream<[AntigravityData.CascadeSummary]> { AsyncStream { $0.finish() } }
    public func onBackground() {}
    public func onForeground() async {}
    public func disconnectAndClearCredentials() async {}
    public func fetchUserDisplayName() async -> String? { nil }
    #endif
}
