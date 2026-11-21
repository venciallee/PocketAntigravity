package dev.antigravity.shared.protocol

/**
 * Implements the Connect-RPC 5-byte streaming envelope format used by
 * `exa.language_server_pb.LanguageServerService` server-streaming methods
 * (`JetboxSubscribeToSummaries`, `StreamCascadeReactiveUpdates`, `StreamAgentStateUpdates`, `ProjectUpdatesStream`).
 *
 * Wire layout:
 * - Byte 0: `flags` (`0x00` = uncompressed message, `0x01` = compressed, `0x02` = EndStream trailer)
 * - Bytes 1..4: `uint32` big-endian payload length
 * - Bytes 5..(5+length): JSON or binary Protobuf payload
 */
public object ConnectEnvelopeFlags {
    public const val NONE: Int = 0x00
    public const val COMPRESSED: Int = 0x01
    public const val END_STREAM: Int = 0x02
}

public data class ConnectEnvelopeFrame(
    public val flags: Int = ConnectEnvelopeFlags.NONE,
    public val payload: ByteArray,
) {
    public val isCompressed: Boolean
        get() = (flags and ConnectEnvelopeFlags.COMPRESSED) != 0

    public val isEndStream: Boolean
        get() = (flags and ConnectEnvelopeFlags.END_STREAM) != 0

    public fun encode(): ByteArray {
        val len = payload.size
        val out = ByteArray(5 + len)
        out[0] = (flags and 0xFF).toByte()
        out[1] = ((len ushr 24) and 0xFF).toByte()
        out[2] = ((len ushr 16) and 0xFF).toByte()
        out[3] = ((len ushr 8) and 0xFF).toByte()
        out[4] = (len and 0xFF).toByte()
        payload.copyInto(out, destinationOffset = 5)
        return out
    }

    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is ConnectEnvelopeFrame) return false
        return flags == other.flags && payload.contentEquals(other.payload)
    }

    override fun hashCode(): Int = 31 * flags + payload.contentHashCode()
}

public object ConnectEnvelope {
    public fun encode(payload: ByteArray, flags: Int = ConnectEnvelopeFlags.NONE): ByteArray =
        ConnectEnvelopeFrame(flags = flags, payload = payload).encode()
}

/**
 * Incremental stream parser that buffers incoming bytes from HTTP/2 streaming or Cloud Relay chunks
 * and yields complete [ConnectEnvelopeFrame] frames.
 */
public class ConnectStreamParser {
    private var buffer = ByteArray(0)

    public val hasBufferedBytes: Boolean
        get() = buffer.isNotEmpty()

    public fun feedByte(byte: Byte): ConnectEnvelopeFrame? =
        feed(byteArrayOf(byte)).firstOrNull()

    public fun feed(chunk: ByteArray): List<ConnectEnvelopeFrame> {
        if (chunk.isNotEmpty()) {
            val combined = ByteArray(buffer.size + chunk.size)
            buffer.copyInto(combined, destinationOffset = 0)
            chunk.copyInto(combined, destinationOffset = buffer.size)
            buffer = combined
        }

        val frames = mutableListOf<ConnectEnvelopeFrame>()
        var offset = 0

        while (buffer.size - offset >= 5) {
            val flagByte = buffer[offset].toInt() and 0xFF
            val b1 = (buffer[offset + 1].toInt() and 0xFF) shl 24
            val b2 = (buffer[offset + 2].toInt() and 0xFF) shl 16
            val b3 = (buffer[offset + 3].toInt() and 0xFF) shl 8
            val b4 = buffer[offset + 4].toInt() and 0xFF
            val payloadLength = b1 or b2 or b3 or b4

            if (payloadLength < 0 || buffer.size - offset < 5 + payloadLength) {
                break
            }

            val payloadStart = offset + 5
            val payloadEnd = payloadStart + payloadLength
            val payload = buffer.copyOfRange(payloadStart, payloadEnd)
            offset = payloadEnd

            frames.add(ConnectEnvelopeFrame(flags = flagByte, payload = payload))
        }

        if (offset > 0) {
            buffer = if (offset >= buffer.size) ByteArray(0) else buffer.copyOfRange(offset, buffer.size)
        }

        return frames
    }
}
