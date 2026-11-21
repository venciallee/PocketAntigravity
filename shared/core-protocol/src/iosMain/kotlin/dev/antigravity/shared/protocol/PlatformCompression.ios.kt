@file:OptIn(kotlinx.cinterop.ExperimentalForeignApi::class, kotlinx.cinterop.BetaInteropApi::class)

package dev.antigravity.shared.protocol

import kotlinx.cinterop.addressOf
import kotlinx.cinterop.usePinned
import platform.Foundation.NSData
import platform.Foundation.NSDataCompressionAlgorithmZlib
import platform.Foundation.create
import platform.Foundation.decompressedDataUsingAlgorithm
import platform.posix.memcpy

internal actual fun decompressRawDeflate(data: ByteArray): ByteArray? {
    if (data.isEmpty()) return ByteArray(0)
    val nsData = data.usePinned { pinned ->
        NSData.create(bytes = pinned.addressOf(0), length = data.size.toULong())
    }
    val decompressed = nsData.decompressedDataUsingAlgorithm(NSDataCompressionAlgorithmZlib, error = null)
        ?: return null
    val outSize = decompressed.length.toInt()
    if (outSize == 0) return ByteArray(0)
    val result = ByteArray(outSize)
    result.usePinned { pinned ->
        memcpy(pinned.addressOf(0), decompressed.bytes, decompressed.length)
    }
    return result
}
