package dev.antigravity.shared.protocol

import java.io.ByteArrayOutputStream
import java.util.zip.Inflater

internal actual fun decompressRawDeflate(data: ByteArray): ByteArray? {
    val inflater = Inflater(/* nowrap = */ true)
    return try {
        inflater.setInput(data)
        val out = ByteArrayOutputStream(data.size * 2)
        val buf = ByteArray(4096)
        while (!inflater.finished()) {
            val count = inflater.inflate(buf)
            if (count > 0) {
                out.write(buf, 0, count)
            } else if (inflater.needsInput() || inflater.needsDictionary()) {
                break
            }
        }
        out.toByteArray()
    } catch (_: Throwable) {
        null
    } finally {
        inflater.end()
    }
}
