package dev.antigravity.android.ui.chat

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.provider.OpenableColumns
import android.util.Base64
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.AttachFile
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.Image
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import dev.antigravity.android.core.ui.theme.LocalAntigravityColors
import dev.antigravity.shared.model.ComposerAttachmentChip
import java.io.ByteArrayOutputStream
import java.util.UUID
import kotlin.math.max
import kotlin.math.roundToInt
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

private const val MAX_IMAGE_DIMENSION_PX = 2048
private const val MAX_PASSTHROUGH_IMAGE_BYTES = 2 * 1024 * 1024
private const val MAX_ENCODED_IMAGE_BYTES = 2_500_000
private const val MAX_GENERIC_FILE_BYTES = 8 * 1024 * 1024

private val MODEL_EFFORT_SUFFIXES = listOf(
    " (XHigh)",
    " (X-High)",
    " (Extra High)",
    " (Extra)",
    " (Max)",
    " (High)",
    " (Medium)",
    " (Med)",
    " (Low)",
    " (Minimal)",
    " (Thinking)",
)

/**
 * Normalizes a model display name for the single-line composer pill (`Gemini 4 Neon ⌄`),
 * stripping any inline effort or `(Thinking)` suffixes (effort is shown inside the Model sheet).
 */
internal fun formatComposerModelPillName(rawName: String?): String {
    var name = rawName?.trim().orEmpty().ifEmpty { "Gemini 4 Neon" }
    for (suffix in MODEL_EFFORT_SUFFIXES) {
        if (name.endsWith(suffix, ignoreCase = true)) {
            name = name.dropLast(suffix.length).trim()
        }
    }
    return name.ifEmpty { "Gemini 4 Neon" }
}

/**
 * Reads an image or document from an Android `content://` URI on [Dispatchers.IO],
 * downscales/compresses large images safely (max 2048px, JPEG fallback) to avoid OOM or
 * oversized RPC payloads, and returns a ready-to-send [ComposerAttachmentChip].
 */
internal suspend fun loadMediaAttachmentFromUri(
    context: Context,
    uri: Uri,
    existingLabels: Set<String>,
    preferImageKind: Boolean = false,
): ComposerAttachmentChip? = withContext(Dispatchers.IO) {
    val resolver = context.contentResolver
    val resolvedMime = resolver.getType(uri)?.lowercase()
    val rawFileName = queryDisplayName(context, uri)
    val ext = rawFileName?.substringAfterLast('.', "")?.lowercase().orEmpty()

    val isImage = preferImageKind ||
        resolvedMime?.startsWith("image/") == true ||
        ext in setOf("png", "jpg", "jpeg", "webp", "heic", "heif", "gif")

    val rawBytes = resolver.openInputStream(uri)?.use { stream ->
        readBoundedBytes(stream, maxBytes = if (isImage) 24 * 1024 * 1024 else MAX_GENERIC_FILE_BYTES)
    } ?: return@withContext null
    if (rawBytes.isEmpty()) return@withContext null

    if (isImage) {
        val prepared = prepareImageBytes(rawBytes, resolvedMime) ?: return@withContext null
        val stem = rawFileName?.substringBeforeLast('.')?.takeIf { it.isNotBlank() } ?: "photo"
        val baseLabel = if (rawFileName != null && ext in setOf("png", "jpg", "jpeg") && prepared.ext == ext) {
            rawFileName
        } else {
            "$stem.${prepared.ext}"
        }
        val label = makeUniqueLabel(baseLabel, prepared.ext, existingLabels)
        val chipId = "photo-${UUID.randomUUID()}"
        ComposerAttachmentChip(
            id = chipId,
            kind = ComposerAttachmentChip.Kind.IMAGE_SCREENSHOT,
            label = label,
            targetUri = "attachment://photo/$chipId/$label",
            mimeType = prepared.mimeType,
            inlinePayload = Base64.encodeToString(prepared.bytes, Base64.NO_WRAP),
        )
    } else {
        if (rawBytes.size > MAX_GENERIC_FILE_BYTES) return@withContext null
        val kind = when {
            resolvedMime == "application/pdf" || ext == "pdf" -> ComposerAttachmentChip.Kind.PDF_DOCUMENT
            resolvedMime?.startsWith("audio/") == true || ext in setOf("m4a", "mp3", "wav", "aac", "flac") ->
                ComposerAttachmentChip.Kind.AUDIO_CLIP
            resolvedMime?.startsWith("video/") == true || ext in setOf("mp4", "mov", "mkv", "webm") ->
                ComposerAttachmentChip.Kind.VIDEO_CLIP
            else -> ComposerAttachmentChip.Kind.FILE_MENTION
        }
        val fallbackExt = ext.ifEmpty { "bin" }
        val label = makeUniqueLabel(rawFileName ?: "attachment.$fallbackExt", fallbackExt, existingLabels)
        val chipId = "file-${UUID.randomUUID()}"
        ComposerAttachmentChip(
            id = chipId,
            kind = kind,
            label = label,
            targetUri = "attachment://file/$chipId/$label",
            mimeType = resolvedMime ?: "application/octet-stream",
            inlinePayload = Base64.encodeToString(rawBytes, Base64.NO_WRAP),
        )
    }
}

private data class PreparedImageBytes(
    val bytes: ByteArray,
    val mimeType: String,
    val ext: String,
)

private fun prepareImageBytes(rawBytes: ByteArray, preferredMime: String?): PreparedImageBytes? {
    val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
    BitmapFactory.decodeByteArray(rawBytes, 0, rawBytes.size, bounds)
    val srcW = bounds.outWidth
    val srcH = bounds.outHeight
    if (srcW <= 0 || srcH <= 0) {
        val mime = preferredMime ?: "image/jpeg"
        val ext = if (mime.contains("png")) "png" else "jpg"
        return PreparedImageBytes(rawBytes, mime, ext)
    }

    val largest = max(srcW, srcH)
    val isStandardWeb = preferredMime == "image/png" || preferredMime == "image/jpeg" || preferredMime == "image/jpg"
    if (isStandardWeb && largest <= MAX_IMAGE_DIMENSION_PX && rawBytes.size <= MAX_PASSTHROUGH_IMAGE_BYTES) {
        val mime = if (preferredMime == "image/png") "image/png" else "image/jpeg"
        val ext = if (mime == "image/png") "png" else "jpg"
        return PreparedImageBytes(rawBytes, mime, ext)
    }

    var sampleSize = 1
    while ((srcW / sampleSize) > MAX_IMAGE_DIMENSION_PX * 2 || (srcH / sampleSize) > MAX_IMAGE_DIMENSION_PX * 2) {
        sampleSize *= 2
    }
    val decodeOpts = BitmapFactory.Options().apply { inSampleSize = sampleSize }
    val decoded = BitmapFactory.decodeByteArray(rawBytes, 0, rawBytes.size, decodeOpts) ?: return null

    val scaled = if (max(decoded.width, decoded.height) > MAX_IMAGE_DIMENSION_PX) {
        val scale = MAX_IMAGE_DIMENSION_PX.toFloat() / max(decoded.width, decoded.height).toFloat()
        val dstW = max(1, (decoded.width * scale).roundToInt())
        val dstH = max(1, (decoded.height * scale).roundToInt())
        Bitmap.createScaledBitmap(decoded, dstW, dstH, true).also {
            if (it !== decoded) decoded.recycle()
        }
    } else {
        decoded
    }

    try {
        var bestBytes: ByteArray? = null
        for (quality in listOf(84, 72, 58)) {
            val out = ByteArrayOutputStream()
            if (scaled.compress(Bitmap.CompressFormat.JPEG, quality, out)) {
                val candidate = out.toByteArray()
                bestBytes = candidate
                if (candidate.size <= MAX_ENCODED_IMAGE_BYTES) break
            }
        }
        val finalBytes = bestBytes ?: return null
        return PreparedImageBytes(finalBytes, "image/jpeg", "jpg")
    } finally {
        scaled.recycle()
    }
}

private fun queryDisplayName(context: Context, uri: Uri): String? {
    return runCatching {
        context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) {
                val idx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (idx >= 0) cursor.getString(idx) else null
            } else {
                null
            }
        }
    }.getOrNull()?.takeIf { it.isNotBlank() }
}

private fun readBoundedBytes(stream: java.io.InputStream, maxBytes: Int): ByteArray? {
    val buffer = ByteArrayOutputStream()
    val chunk = ByteArray(16 * 1024)
    var total = 0
    while (true) {
        val read = stream.read(chunk)
        if (read <= 0) break
        total += read
        if (total > maxBytes) return null
        buffer.write(chunk, 0, read)
    }
    return buffer.toByteArray()
}

private fun makeUniqueLabel(preferred: String, ext: String, existing: Set<String>): String {
    if (preferred !in existing) return preferred
    val stem = preferred.substringBeforeLast('.').ifBlank { "photo" }
    var idx = 1
    while (true) {
        val candidate = "$stem-$idx.$ext"
        if (candidate !in existing) return candidate
        idx += 1
    }
}

/**
 * Shared horizontal attachments strip for both Home and Chat composers on Android:
 * renders crisp 56dp rounded image thumbnails with a remove `×` badge for picked photos
 * alongside standard text pills for `@file` mentions and device documents.
 */
@Composable
fun ComposerAttachmentsStrip(
    chips: List<ComposerAttachmentChip>,
    onRemoveChip: (String) -> Unit,
    isImporting: Boolean = false,
    modifier: Modifier = Modifier,
) {
    if (chips.isEmpty() && !isImporting) return
    val colors = LocalAntigravityColors.current

    Row(
        modifier = modifier
            .fillMaxWidth()
            .horizontalScroll(rememberScrollState()),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        chips.forEach { chip ->
            if (chip.kind == ComposerAttachmentChip.Kind.IMAGE_SCREENSHOT && !chip.inlinePayload.isNullOrBlank()) {
                val bitmap = remember(chip.id, chip.inlinePayload) {
                    runCatching {
                        val bytes = Base64.decode(chip.inlinePayload, Base64.DEFAULT)
                        BitmapFactory.decodeByteArray(bytes, 0, bytes.size)?.asImageBitmap()
                    }.getOrNull()
                }
                Box(
                    modifier = Modifier
                        .padding(top = 4.dp, end = 4.dp)
                        .testTag("composer-image-chip-${chip.id}"),
                ) {
                    Surface(
                        modifier = Modifier.size(56.dp),
                        shape = RoundedCornerShape(12.dp),
                        color = colors.surfaceElevated,
                        border = BorderStroke(1.dp, colors.cardBorder),
                    ) {
                        if (bitmap != null) {
                            Image(
                                bitmap = bitmap,
                                contentDescription = chip.label,
                                contentScale = ContentScale.Crop,
                                modifier = Modifier.fillMaxSize(),
                            )
                        } else {
                            Box(contentAlignment = Alignment.Center) {
                                Icon(
                                    imageVector = Icons.Rounded.Image,
                                    contentDescription = chip.label,
                                    tint = colors.accentPeriwinkle,
                                    modifier = Modifier.size(22.dp),
                                )
                            }
                        }
                    }

                    Surface(
                        onClick = { onRemoveChip(chip.id) },
                        modifier = Modifier
                            .align(Alignment.TopEnd)
                            .offset(x = 5.dp, y = (-5).dp)
                            .size(20.dp),
                        shape = CircleShape,
                        color = Color.Black.copy(alpha = 0.76f),
                        border = BorderStroke(0.75.dp, Color.White.copy(alpha = 0.25f)),
                    ) {
                        Box(contentAlignment = Alignment.Center) {
                            Icon(
                                imageVector = Icons.Rounded.Close,
                                contentDescription = "Remove ${chip.label}",
                                tint = Color.White,
                                modifier = Modifier.size(12.dp),
                            )
                        }
                    }
                }
            } else {
                val chipTag = if (chip.label.contains("ratelimit", ignoreCase = true)) {
                    "composer-chip-ratelimit"
                } else {
                    "composer-chip-${chip.id}"
                }
                Surface(
                    shape = RoundedCornerShape(100.dp),
                    color = colors.surfaceElevated,
                    border = BorderStroke(1.dp, colors.cardBorder),
                    modifier = Modifier.testTag(chipTag),
                ) {
                    Row(
                        modifier = Modifier.padding(horizontal = 10.dp, vertical = 5.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(6.dp),
                    ) {
                        if (!chip.inlinePayload.isNullOrBlank()) {
                            Icon(
                                imageVector = Icons.Rounded.AttachFile,
                                contentDescription = null,
                                tint = colors.accentPeriwinkle,
                                modifier = Modifier.size(13.dp),
                            )
                        }
                        Text(
                            text = chip.label,
                            style = MaterialTheme.typography.labelSmall.copy(
                                fontFamily = FontFamily.Monospace,
                                fontSize = 11.5.sp,
                            ),
                            color = colors.inkLabel,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                        Icon(
                            imageVector = Icons.Rounded.Close,
                            contentDescription = "Remove ${chip.label}",
                            tint = colors.inkMuted,
                            modifier = Modifier
                                .size(13.dp)
                                .clip(CircleShape)
                                .clickable { onRemoveChip(chip.id) },
                        )
                    }
                }
            }
        }

        if (isImporting) {
            Surface(
                shape = RoundedCornerShape(100.dp),
                color = colors.surfaceElevated,
            ) {
                Row(
                    modifier = Modifier.padding(horizontal = 10.dp, vertical = 6.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(12.dp),
                        strokeWidth = 1.8.dp,
                        color = colors.accentPeriwinkle,
                    )
                    Text(
                        text = "Adding photo…",
                        style = MaterialTheme.typography.labelSmall,
                        color = colors.inkSecondary,
                    )
                }
            }
        }
    }
}
