package dev.antigravity.shared.protocol

/**
 * Implements the Connect-RPC 5-byte streaming envelope format used by
 * `exa.language_server_pb.LanguageServerService` server-streaming methods
 * (`JetboxSubscribeToSummaries`, `StreamCascadeReactiveUpdates`, `StreamAgentStateUpdates`, `ProjectUpdatesStream`).
 *
 * Wire layout:
 * - Byte 0: `flags` (`0x00` = uncompressed message, `0x01` = compressed, `0x02` = Connect EndStream trailer, `0x80` = gRPC-Web trailer)
 * - Bytes 1..4: `uint32` big-endian payload length
 * - Bytes 5..(5+length): JSON or binary Protobuf payload
 */
public object ConnectEnvelopeFlags {
    public const val NONE: Int = 0x00
    public const val COMPRESSED: Int = 0x01
    public const val END_STREAM: Int = 0x02
    public const val GRPC_WEB_TRAILER: Int = 0x80
}

public data class ConnectEnvelopeFrame(
    public val flags: Int = ConnectEnvelopeFlags.NONE,
    public val payload: ByteArray,
) {
    public val isCompressed: Boolean
        get() = (flags and ConnectEnvelopeFlags.COMPRESSED) != 0

    public val isEndStream: Boolean
        get() = (flags and ConnectEnvelopeFlags.END_STREAM) != 0 ||
            (flags and ConnectEnvelopeFlags.GRPC_WEB_TRAILER) != 0

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
    private var readOffset = 0
    private var writeOffset = 0

    public val hasBufferedBytes: Boolean
        get() = writeOffset > readOffset

    public val bufferedByteCount: Int
        get() = maxOf(0, writeOffset - readOffset)

    public fun feedByte(byte: Byte): ConnectEnvelopeFrame? =
        feed(byteArrayOf(byte)).firstOrNull()

    public fun feed(chunk: ByteArray): List<ConnectEnvelopeFrame> {
        if (chunk.isNotEmpty()) {
            val available = writeOffset - readOffset
            val needed = available + chunk.size
            if (buffer.size - writeOffset < chunk.size) {
                if (buffer.size >= needed) {
                    if (available > 0 && readOffset > 0) {
                        buffer.copyInto(buffer, destinationOffset = 0, startIndex = readOffset, endIndex = writeOffset)
                    }
                    readOffset = 0
                    writeOffset = available
                } else {
                    var newCap = if (buffer.isEmpty()) 4096 else buffer.size
                    while (newCap < needed) newCap = newCap shl 1
                    val next = ByteArray(newCap)
                    if (available > 0) {
                        buffer.copyInto(next, destinationOffset = 0, startIndex = readOffset, endIndex = writeOffset)
                    }
                    buffer = next
                    readOffset = 0
                    writeOffset = available
                }
            }
            chunk.copyInto(buffer, destinationOffset = writeOffset)
            writeOffset += chunk.size
        }

        val frames = mutableListOf<ConnectEnvelopeFrame>()

        while (writeOffset - readOffset >= 5) {
            val flagByte = buffer[readOffset].toInt() and 0xFF
            val b1 = (buffer[readOffset + 1].toInt() and 0xFF) shl 24
            val b2 = (buffer[readOffset + 2].toInt() and 0xFF) shl 16
            val b3 = (buffer[readOffset + 3].toInt() and 0xFF) shl 8
            val b4 = buffer[readOffset + 4].toInt() and 0xFF
            val payloadLength = b1 or b2 or b3 or b4

            if (payloadLength < 0 || writeOffset - readOffset < 5 + payloadLength) {
                break
            }

            val payloadStart = readOffset + 5
            val payloadEnd = payloadStart + payloadLength
            val payload = buffer.copyOfRange(payloadStart, payloadEnd)
            readOffset = payloadEnd

            frames.add(ConnectEnvelopeFrame(flags = flagByte, payload = payload))
        }

        if (readOffset == writeOffset) {
            readOffset = 0
            writeOffset = 0
            if (buffer.size > 262_144) {
                buffer = ByteArray(0)
            }
        } else if (readOffset > 65_536 && readOffset * 2 >= writeOffset) {
            val remaining = writeOffset - readOffset
            buffer.copyInto(buffer, destinationOffset = 0, startIndex = readOffset, endIndex = writeOffset)
            readOffset = 0
            writeOffset = remaining
        }

        return frames
    }
}
