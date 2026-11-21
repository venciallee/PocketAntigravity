package dev.antigravity.shared

import dev.antigravity.shared.markdown.AntigravityMarkdownParser
import dev.antigravity.shared.markdown.MarkdownBlock
import dev.antigravity.shared.model.CascadeStep
import dev.antigravity.shared.protocol.ConnectEnvelope
import dev.antigravity.shared.protocol.ProtobufStepCodec
import dev.antigravity.shared.protocol.SapisidHashGenerator

/**
 * Umbrella entry point exported in `AntigravityShared.xcframework` (iOS) and JVM/Android artifacts.
 */
public object AntigravitySharedFacade {
    public const val CORE_VERSION: String = "2.33.0-kmp-phase1"
    public const val PROTOBUF_STEP_THRESHOLD: Int = 600

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
