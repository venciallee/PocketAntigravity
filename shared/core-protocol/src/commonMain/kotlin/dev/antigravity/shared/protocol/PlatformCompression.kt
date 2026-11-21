package dev.antigravity.shared.protocol

/**
 * Platform-native RFC 1951 raw-deflate decompressor used for transparent GZIP/ZLIB unwrapping
 * inside Cloud Relay `ProxyCommand` / `StreamProxyCommand` payloads.
 */
internal expect fun decompressRawDeflate(data: ByteArray): ByteArray?
