package dev.antigravity.shared.protocol

import dev.antigravity.shared.model.RemoteConnectionChannel
import kotlin.math.max
import kotlin.math.min
import kotlin.random.Random

/**
 * Lifecycle state of the backend connectivity state machine.
 */
public sealed interface ConnectionLifecyclePhase {
    public data object Disconnected : ConnectionLifecyclePhase
    public data object Suspended : ConnectionLifecyclePhase
    public data object NoNetwork : ConnectionLifecyclePhase
    public data object Connecting : ConnectionLifecyclePhase
    public data object OnlineIdle : ConnectionLifecyclePhase
    public data object OnlineStreaming : ConnectionLifecyclePhase
    public data class OfflineBackoff(
        public val attempt: Int,
        public val nextRetrySeconds: Double,
    ) : ConnectionLifecyclePhase

    public val isOfflineBackoff: Boolean
        get() = this is OfflineBackoff
}

/**
 * Centralized, power-aware scheduling policy for mobile heartbeat, step streaming,
 * offline detection debounce, and exponential reconnect backoff.
 */
public object ConnectionPowerPolicy {
    public val offlineBackoffScheduleSeconds: List<Double> = listOf(3.0, 6.0, 12.0, 24.0, 45.0, 60.0)
    public const val MAX_OFFLINE_BACKOFF_SECONDS: Double = 60.0
    public const val MAX_LOW_POWER_OFFLINE_BACKOFF_SECONDS: Double = 120.0
    public const val MIN_STREAM_REOPEN_SPACING_SECONDS: Double = 3.0

    public fun onlineHeartbeatIntervalSeconds(
        channel: RemoteConnectionChannel,
        isLowPowerMode: Boolean,
        isExpensiveNetwork: Boolean,
        isStreamHealthy: Boolean,
    ): Double {
        val base = when (channel) {
            RemoteConnectionChannel.CLOUD_RELAY ->
                if (isStreamHealthy) {
                    if (isExpensiveNetwork) 45.0 else 30.0
                } else {
                    if (isExpensiveNetwork) 20.0 else 15.0
                }
            RemoteConnectionChannel.DIRECT_HOST ->
                if (isStreamHealthy) 15.0 else 8.0
        }
        return if (isLowPowerMode) base * 2.0 else base
    }

    public fun onlineFullSyncIntervalSeconds(
        channel: RemoteConnectionChannel,
        isLowPowerMode: Boolean,
    ): Double {
        val base = if (channel == RemoteConnectionChannel.CLOUD_RELAY) 60.0 else 30.0
        return if (isLowPowerMode) base * 2.0 else base
    }

    public fun activeStreamingStepPollIntervalSeconds(
        channel: RemoteConnectionChannel,
        isLowPowerMode: Boolean,
    ): Double = when (channel) {
        RemoteConnectionChannel.CLOUD_RELAY -> if (isLowPowerMode) 1.5 else 1.0
        RemoteConnectionChannel.DIRECT_HOST -> if (isLowPowerMode) 1.0 else 0.5
    }

    public fun idleChatFallbackStepPollIntervalSeconds(
        isStreamHealthy: Boolean,
        isLowPowerMode: Boolean,
    ): Double? {
        if (isStreamHealthy) return null
        return if (isLowPowerMode) 30.0 else 15.0
    }

    public fun offlineBackoffBaseDelaySeconds(
        attempt: Int,
        isLowPowerMode: Boolean,
    ): Double {
        val clamped = attempt.coerceIn(0, offlineBackoffScheduleSeconds.lastIndex)
        val base = offlineBackoffScheduleSeconds[clamped]
        return if (isLowPowerMode) {
            min(base * 2.0, MAX_LOW_POWER_OFFLINE_BACKOFF_SECONDS)
        } else {
            min(base, MAX_OFFLINE_BACKOFF_SECONDS)
        }
    }

    public fun offlineBackoffDelaySeconds(
        attempt: Int,
        isLowPowerMode: Boolean,
        applyJitter: Boolean = true,
        jitterFactor: Double? = null,
    ): Double {
        val base = offlineBackoffBaseDelaySeconds(attempt, isLowPowerMode)
        if (!applyJitter) return base
        val factor = jitterFactor ?: Random.nextDouble(0.85, 1.15)
        val cap = if (isLowPowerMode) MAX_LOW_POWER_OFFLINE_BACKOFF_SECONDS else MAX_OFFLINE_BACKOFF_SECONDS
        return max(1.0, min(base * factor, cap))
    }

    public fun offlineFailureThreshold(
        channel: RemoteConnectionChannel,
        error: Throwable,
    ): Int {
        if (error is AntigravityRpcError) {
            return when (error) {
                is AntigravityRpcError.Unauthorized,
                is AntigravityRpcError.InvalidEndpoint -> 1
                is AntigravityRpcError.HttpError -> {
                    if (error.statusCode == 503 && error.body.contains("no reachable", ignoreCase = true)) {
                        1
                    } else if (channel == RemoteConnectionChannel.CLOUD_RELAY) {
                        2
                    } else {
                        1
                    }
                }
                is AntigravityRpcError.DecodingError,
                is AntigravityRpcError.InteractionRejected -> Int.MAX_VALUE
            }
        }
        return if (channel == RemoteConnectionChannel.CLOUD_RELAY) 2 else 1
    }
}
