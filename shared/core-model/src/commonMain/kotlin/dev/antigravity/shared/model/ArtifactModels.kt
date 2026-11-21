package dev.antigravity.shared.model

import kotlinx.serialization.Serializable

@Serializable
public enum class ArtifactKind {
    IMPLEMENTATION_PLAN,
    WALKTHROUGH,
    TASK_LIST,
    GENERATIVE_UI_HTML,
    URL_BOOKMARK,
    PDF_DOCUMENT,
    JUPYTER_NOTEBOOK,
    IMAGE_ASSET,
    VIDEO_ASSET,
}

@Serializable
public data class ArtifactSnapshot(
    public val artifactPath: String,
    public val title: String,
    public val summary: String,
    public val kind: ArtifactKind,
    public val content: String,
    public val requestFeedback: Boolean = false,
    public val userFacing: Boolean = true,
    public val version: Int = 1,
    public val updatedAtEpochMs: Long = 0L,
) {
    public val id: String get() = artifactPath
}

@Serializable
public enum class EmbedResourceSource {
    TRAJECTORY_STEP,
    ARTIFACT_SNAPSHOT,
    REMOTE_HOST,
    DIRECT_NETWORK,
    INLINE_DATA_URI,
}

@Serializable
public data class ResolvedEmbedResource(
    public val uri: String,
    public val normalizedPath: String = normalizePath(uri),
    public val mimeType: String,
    public val textContent: String? = null,
    public val binaryData: ByteArray? = null,
    public val source: EmbedResourceSource,
) {
    public val isHtml: Boolean
        get() = mimeType.lowercase().contains("html") ||
            normalizedPath.lowercase().endsWith(".html") ||
            normalizedPath.lowercase().endsWith(".htm")

    public val isSvg: Boolean
        get() = mimeType.lowercase().contains("svg") ||
            normalizedPath.lowercase().endsWith(".svg")

    public val isImage: Boolean
        get() = mimeType.lowercase().startsWith("image/")

    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is ResolvedEmbedResource) return false
        return uri == other.uri &&
            normalizedPath == other.normalizedPath &&
            mimeType == other.mimeType &&
            textContent == other.textContent &&
            (binaryData?.contentEquals(other.binaryData) ?: (other.binaryData == null)) &&
            source == other.source
    }

    override fun hashCode(): Int {
        var result = uri.hashCode()
        result = 31 * result + normalizedPath.hashCode()
        result = 31 * result + mimeType.hashCode()
        result = 31 * result + (textContent?.hashCode() ?: 0)
        result = 31 * result + (binaryData?.contentHashCode() ?: 0)
        result = 31 * result + source.hashCode()
        return result
    }

    public companion object {
        public fun normalizePath(raw: String): String {
            var s = raw.trim()
            if (s.lowercase().startsWith("file://")) {
                s = s.drop("file://".length)
            }
            s = percentDecodeUtf8(s)
            val hashIdx = s.indexOf('#')
            if (hashIdx >= 0) s = s.substring(0, hashIdx)
            val queryIdx = s.indexOf('?')
            if (queryIdx >= 0) s = s.substring(0, queryIdx)
            return s
        }

        public fun inferredMimeType(rawPathOrUri: String): String {
            val lower = normalizePath(rawPathOrUri).lowercase()
            return when {
                lower.endsWith(".html") || lower.endsWith(".htm") -> "text/html"
                lower.endsWith(".svg") -> "image/svg+xml"
                lower.endsWith(".png") -> "image/png"
                lower.endsWith(".jpg") || lower.endsWith(".jpeg") -> "image/jpeg"
                lower.endsWith(".webp") -> "image/webp"
                lower.endsWith(".gif") -> "image/gif"
                lower.endsWith(".md") || lower.endsWith(".markdown") -> "text/markdown"
                lower.endsWith(".json") -> "application/json"
                lower.endsWith(".css") -> "text/css"
                lower.endsWith(".js") -> "application/javascript"
                else -> "text/plain"
            }
        }

        public fun isEmbeddableTextArtifactPath(rawPathOrUri: String): Boolean {
            val lower = normalizePath(rawPathOrUri).lowercase()
            return lower.endsWith(".html") ||
                lower.endsWith(".htm") ||
                lower.endsWith(".svg") ||
                lower.endsWith(".md") ||
                lower.endsWith(".markdown") ||
                lower.endsWith(".mmd") ||
                lower.endsWith(".mermaid") ||
                lower.endsWith(".json")
        }

        public fun decodeDataUri(rawUri: String): ResolvedEmbedResource? {
            val trimmed = rawUri.trim()
            if (!trimmed.lowercase().startsWith("data:")) return null
            val commaIdx = trimmed.indexOf(',')
            if (commaIdx < 0) return null
            val header = trimmed.substring(5, commaIdx)
            val payload = trimmed.substring(commaIdx + 1)
            val parts = header.split(';')
            val mime = parts.firstOrNull()?.takeIf { it.isNotEmpty() } ?: "text/plain"
            val isBase64 = parts.any { it.equals("base64", ignoreCase = true) }

            return if (isBase64) {
                val bytes = decodeBase64FlexibleBytes(payload) ?: return null
                val text = if (mime.lowercase().startsWith("text/") || mime.lowercase().contains("svg")) {
                    bytes.decodeToString()
                } else {
                    null
                }
                ResolvedEmbedResource(
                    uri = trimmed,
                    normalizedPath = trimmed,
                    mimeType = mime,
                    textContent = text,
                    binaryData = bytes,
                    source = EmbedResourceSource.INLINE_DATA_URI,
                )
            } else {
                val decodedText = percentDecodeUtf8(payload)
                ResolvedEmbedResource(
                    uri = trimmed,
                    normalizedPath = trimmed,
                    mimeType = mime,
                    textContent = decodedText,
                    binaryData = decodedText.encodeToByteArray(),
                    source = EmbedResourceSource.INLINE_DATA_URI,
                )
            }
        }
    }
}

@Serializable
public data class PlanProposedFileChange(
    public val id: String,
    public val changeKind: String,
    public val filePath: String,
    public val summaryText: String,
    public val highlightedSpan: String? = null,
    public val isSelectedForCallout: Boolean = false,
)

@Serializable
public data class PlanInlineComment(
    public val id: String,
    public val authorInitials: String = "WL",
    public val authorName: String = "You",
    public val statusLabel: String = "Pending",
    public val targetFilePath: String,
    public val quotedSpan: String,
    public val body: String,
)

@Serializable
public data class IntSpan(
    public val start: Int,
    public val endExclusive: Int,
)

@Serializable
public data class DiffLine(
    public val id: Int,
    public val kind: Kind,
    public val oldLineNumber: Int? = null,
    public val newLineNumber: Int? = null,
    public val text: String,
    public val wordHighlightRange: String? = null,
    public val emphasizedRanges: List<IntSpan> = emptyList(),
) {
    @Serializable
    public enum class Kind {
        CONTEXT,
        ADDITION,
        DELETION,
        HUNK_HEADER,
    }

    public val displayLineNumber: Int?
        get() = newLineNumber ?: oldLineNumber
}

@Serializable
public data class FilePatchDiff(
    public val turnNumber: Int = 3,
    public val filePath: String,
    public val additions: Int,
    public val deletions: Int,
    public val hunkHeader: String = "@@ -18,9 +18,27 @@ Allow",
    public val isReviewed: Boolean = false,
    public val statusLetter: GitFileStatusLetter = GitFileStatusLetter.MODIFIED,
    public val isStaged: Boolean = false,
    public val compareScope: DiffCompareMode = DiffCompareMode.TURN,
    public val lines: List<DiffLine>,
) {
    public val id: String get() = "$turnNumber:$filePath"
}

@Serializable
public data class DiffLineComment(
    public val id: String,
    public val filePath: String,
    public val lineNumber: Int,
    public val body: String,
    public val sentToAgent: Boolean = false,
    public val author: String = "You",
    public val createdAtEpochMs: Long = 0L,
)

internal fun percentDecodeUtf8(input: String): String {
    if (!input.contains('%')) return input
    val out = ArrayList<Byte>(input.length)
    var i = 0
    while (i < input.length) {
        val ch = input[i]
        if (ch == '%' && i + 2 < input.length) {
            val hi = input[i + 1].digitToIntOrNull(16)
            val lo = input[i + 2].digitToIntOrNull(16)
            if (hi != null && lo != null) {
                out.add(((hi shl 4) or lo).toByte())
                i += 3
                continue
            }
        }
        for (b in ch.toString().encodeToByteArray()) {
            out.add(b)
        }
        i += 1
    }
    return out.toByteArray().decodeToString()
}

internal fun decodeBase64FlexibleBytes(raw: String): ByteArray? {
    val cleaned = buildString(raw.length) {
        for (ch in raw) {
            when (ch) {
                '-' -> append('+')
                '_' -> append('/')
                '\r', '\n', ' ', '\t' -> Unit
                else -> append(ch)
            }
        }
    }
    if (cleaned.isEmpty()) return ByteArray(0)
    if (cleaned.length % 4 == 1) return null
    val padded = when (cleaned.length % 4) {
        0 -> cleaned
        2 -> "$cleaned=="
        3 -> "$cleaned="
        else -> return null
    }
    val out = ByteArray((padded.length / 4) * 3)
    var outIdx = 0
    var i = 0
    while (i < padded.length) {
        val c0 = base64CharValue(padded[i]) ?: return null
        val c1 = base64CharValue(padded[i + 1]) ?: return null
        val p2 = padded[i + 2]
        val p3 = padded[i + 3]
        val c2 = if (p2 == '=') -1 else (base64CharValue(p2) ?: return null)
        val c3 = if (p3 == '=') -1 else (base64CharValue(p3) ?: return null)

        out[outIdx++] = ((c0 shl 2) or (c1 shr 4)).toByte()
        if (c2 >= 0) {
            out[outIdx++] = (((c1 and 0x0F) shl 4) or (c2 shr 2)).toByte()
            if (c3 >= 0) {
                out[outIdx++] = (((c2 and 0x03) shl 6) or c3).toByte()
            }
        }
        i += 4
    }
    return out.copyOf(outIdx)
}

private fun base64CharValue(ch: Char): Int? = when (ch) {
    in 'A'..'Z' -> ch - 'A'
    in 'a'..'z' -> ch - 'a' + 26
    in '0'..'9' -> ch - '0' + 52
    '+' -> 62
    '/' -> 63
    else -> null
}
