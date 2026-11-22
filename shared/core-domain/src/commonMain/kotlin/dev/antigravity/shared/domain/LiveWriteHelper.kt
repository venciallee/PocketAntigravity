package dev.antigravity.shared.domain

import dev.antigravity.shared.protocol.AntigravityKmpRpcClient
import dev.antigravity.shared.protocol.AntigravityRpcError
import dev.antigravity.shared.protocol.HostCapability
import dev.antigravity.shared.protocol.ProtocolCompatibilityEngine
import kotlinx.coroutines.CancellationException

/**
 * Standardized live-backend capability write wrapper shared across KMP domain stores.
 *
 * - When `client == null` (offline/ESDD verification mode), returns `null` without rolling back
 *   optimistic state so deterministic local journeys succeed cleanly.
 * - When `client != null` (live host), invokes [block]. On any non-cancellation failure, executes
 *   [rollback] and surfaces an honest user-facing message via [onUnsupported] — using
 *   `profile.userFacingUnsupportedMessage(capability)` when the host does not implement the RPC.
 *   Never silently swallows live write errors.
 */
internal suspend fun <T> performLiveCapabilityWrite(
    client: AntigravityKmpRpcClient?,
    capability: HostCapability,
    onUnsupported: (String) -> Unit,
    rollback: () -> Unit,
    block: suspend (AntigravityKmpRpcClient) -> T,
): T? {
    if (client == null) return null
    return try {
        block(client)
    } catch (c: CancellationException) {
        throw c
    } catch (e: AntigravityRpcError) {
        rollback()
        val message = if (ProtocolCompatibilityEngine.isMethodUnimplementedError(e)) {
            client.capabilityProfile().userFacingUnsupportedMessage(capability)
        } else {
            e.message ?: "${capability.displayTitle} failed"
        }
        onUnsupported(message)
        null
    } catch (e: Throwable) {
        rollback()
        val message = if (ProtocolCompatibilityEngine.isMethodUnimplementedError(e)) {
            client.capabilityProfile().userFacingUnsupportedMessage(capability)
        } else {
            e.message ?: "${capability.displayTitle} failed"
        }
        onUnsupported(message)
        null
    }
}
