package dev.antigravity.shared.model

import kotlinx.serialization.KSerializer
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder

/**
 * Forward-compatible [KSerializer] for enum types decoded from Antigravity Desktop / Cloud Relay JSON
 * or persisted local projections.
 *
 * Any unrecognized upstream wire value safely falls back to [fallbackProvider] instead of throwing
 * `SerializationException`, matching Swift `ResilientStringEnum` semantics across KMP targets.
 */
public open class ResilientEnumSerializer<T : Enum<T>>(
    serialName: String,
    private val entriesProvider: () -> List<T>,
    private val fallbackProvider: () -> T,
    private val wireName: (T) -> String = { it.name },
    private val extraMatcher: ((String) -> T?)? = null,
) : KSerializer<T> {

    public constructor(
        serialName: String,
        values: List<T>,
        fallback: T,
        wireName: (T) -> String = { it.name },
        extraMatcher: ((String) -> T?)? = null,
    ) : this(
        serialName = serialName,
        entriesProvider = { values },
        fallbackProvider = { fallback },
        wireName = wireName,
        extraMatcher = extraMatcher,
    )

    override val descriptor: SerialDescriptor =
        PrimitiveSerialDescriptor(serialName, PrimitiveKind.STRING)

    override fun serialize(encoder: Encoder, value: T) {
        encoder.encodeString(wireName(value))
    }

    override fun deserialize(decoder: Decoder): T {
        val raw = runCatching { decoder.decodeString() }.getOrNull()
        return decodeResilientEnumOrDefault(
            raw = raw,
            values = entriesProvider(),
            fallback = fallbackProvider(),
            wireName = wireName,
            extraMatcher = extraMatcher,
        )
    }
}

/**
 * Decodes [raw] into an entry of [values] by checking:
 * 1. Case-insensitive exact match against [wireName] or [Enum.name]
 * 2. Alphanumeric-normalized match (bridging `camelCase`, `UPPER_SNAKE_CASE`, and `kebab-case`)
 * 3. Optional [extraMatcher]
 * Falls back safely to [fallback] when unrecognized.
 */
public fun <T : Enum<T>> decodeResilientEnumOrDefault(
    raw: String?,
    values: List<T>,
    fallback: T,
    wireName: (T) -> String = { it.name },
    extraMatcher: ((String) -> T?)? = null,
): T {
    val trimmed = raw?.trim() ?: return fallback
    if (trimmed.isEmpty()) return fallback

    values.firstOrNull {
        wireName(it).equals(trimmed, ignoreCase = true) || it.name.equals(trimmed, ignoreCase = true)
    }?.let { return it }

    val normalized = normalizeResilientEnumToken(trimmed)
    if (normalized.isNotEmpty()) {
        values.firstOrNull {
            normalizeResilientEnumToken(wireName(it)) == normalized ||
                normalizeResilientEnumToken(it.name) == normalized
        }?.let { return it }
    }

    extraMatcher?.invoke(trimmed)?.let { return it }
    return fallback
}

internal fun normalizeResilientEnumToken(raw: String): String =
    buildString(raw.length) {
        for (ch in raw) {
            if (ch.isLetterOrDigit()) {
                append(ch.lowercaseChar())
            }
        }
    }
