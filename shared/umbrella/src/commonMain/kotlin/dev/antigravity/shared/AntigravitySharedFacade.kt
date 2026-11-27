package dev.antigravity.shared

import dev.antigravity.shared.domain.AntigravityCoreCoordinator
import dev.antigravity.shared.domain.InMemoryProjectionStorage
import dev.antigravity.shared.domain.ProjectionStoragePort
import dev.antigravity.shared.markdown.AntigravityMarkdownParser
import dev.antigravity.shared.markdown.MarkdownBlock
import dev.antigravity.shared.model.CascadeStep
import dev.antigravity.shared.platform.InMemoryPreferencesStore
import dev.antigravity.shared.platform.InMemorySecretStore
import dev.antigravity.shared.platform.KeyValuePreferencesStore
import dev.antigravity.shared.platform.NetworkReachabilityMonitoring
import dev.antigravity.shared.platform.NoopNetworkReachabilityMonitor
import dev.antigravity.shared.platform.PowerStateProviding
import dev.antigravity.shared.platform.SecretStore
import dev.antigravity.shared.platform.StaticPowerStateProvider
import dev.antigravity.shared.protocol.ConnectEnvelope
import dev.antigravity.shared.protocol.ProtobufStepCodec
import dev.antigravity.shared.protocol.SapisidHashGenerator

/**
 * Umbrella entry point exported via SKIE into `AntigravityShared.xcframework` (iOS)
 * and JVM/Android artifacts.
 */
public object AntigravitySharedFacade {
    public const val CORE_VERSION: String = "2.33.0-kmp-phase2"
    public const val TRAJECTORY_SYNC_STRATEGY: String = "binary-first-adaptive-json"

    public fun createCoordinator(
        secretStore: SecretStore = InMemorySecretStore(),
        networkMonitor: NetworkReachabilityMonitoring = NoopNetworkReachabilityMonitor(),
        powerStateProvider: PowerStateProviding = StaticPowerStateProvider(),
        preferencesStore: KeyValuePreferencesStore = InMemoryPreferencesStore(),
        projectionStorage: ProjectionStoragePort = InMemoryProjectionStorage(),
    ): AntigravityCoreCoordinator = AntigravityCoreCoordinator(
        secretStore = secretStore,
        networkMonitor = networkMonitor,
        powerStateProvider = powerStateProvider,
        preferencesStore = preferencesStore,
        projectionStorage = projectionStorage,
    )

    public fun createCoordinatorWithSyncPorts(
        secretStore: SyncSecretStore,
        networkMonitor: NetworkReachabilityMonitoring,
        powerStateProvider: PowerStateProviding,
        preferencesStore: KeyValuePreferencesStore,
    ): AntigravityCoreCoordinator = AntigravityCoreCoordinator(
        secretStore = SyncSecretStoreAdapter(secretStore),
        networkMonitor = networkMonitor,
        powerStateProvider = powerStateProvider,
        preferencesStore = preferencesStore,
        projectionStorage = InMemoryProjectionStorage(),
        autoPreloadConversations = false,
        enableForegroundHeartbeatLoop = false,
    )

    public fun createEsddVerificationCoordinator(): AntigravityCoreCoordinator =
        AntigravityCoreCoordinator.createEsddVerificationCoordinator()

    public fun parseMarkdown(markdown: String): List<MarkdownBlock> =
        AntigravityMarkdownParser.parse(markdown)

    public fun decodeBinarySteps(data: ByteArray, cascadeId: String, startingIndex: Int = 0): List<CascadeStep> =
        ProtobufStepCodec.decodeStepsResponse(data, cascadeId, startingIndex)

    public fun encodeConnectFrame(payload: ByteArray): ByteArray =
        ConnectEnvelope.encode(payload)

    public fun computeSapisidAuthHeader(
        cookieHeader: String,
        origin: String = SapisidHashGenerator.DEFAULT_ORIGIN,
        timestampSeconds: Long,
    ): String? = SapisidHashGenerator.computeAuthorizationHeader(cookieHeader, origin, timestampSeconds)
}
