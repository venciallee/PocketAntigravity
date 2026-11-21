package dev.antigravity.shared.protocol

/**
 * Typed protocol & transport error hierarchy shared across Direct LAN and Google Cloud Relay channels.
 */
public sealed class AntigravityRpcError(message: String) : Exception(message) {
    public data object Unauthorized : AntigravityRpcError("Unauthorized (401/403)")
    public data class InvalidEndpoint(public val rawEndpoint: String) :
        AntigravityRpcError("Invalid endpoint: $rawEndpoint")
    public data class HttpError(public val statusCode: Int, public val body: String) :
        AntigravityRpcError("HTTP $statusCode: $body")
    public data class DecodingError(public val detail: String) :
        AntigravityRpcError("Decoding error: $detail")
    public data class InteractionRejected(public val detail: String) :
        AntigravityRpcError("Interaction rejected: $detail")
}
