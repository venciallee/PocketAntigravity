package dev.antigravity.shared.model

import kotlinx.serialization.Serializable

/**
 * Signed-in user profile snapshot extracted from Antigravity Language Server `GetUserStatus`.
 */
@Serializable
public data class LiveUserProfile(
    public val displayName: String? = null,
    public val email: String? = null,
    public val planDisplayName: String? = null,
)

/**
 * Cross-platform home hero greeting & user display-name sanitizer shared by Android and iOS.
 *
 * Ensures live mode displays the real signed-in user's name from `GetUserStatus` (or a clean
 * nameless greeting when unavailable) and never leaks static design-mockup placeholder names.
 */
public object UserGreetingFormatter {
    private const val MAX_GREETING_NAME_LENGTH = 24

    private val PLACEHOLDER_NAMES = setOf(
        "unknown",
        "anonymous",
        "user",
        "guest",
        "default",
        "antigravity",
        "none",
        "null",
        "n/a",
        "me",
        "self",
    )

    private val UUID_LIKE_REGEX = Regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$")
    private val HEX_ID_REGEX = Regex("^[0-9a-fA-F-]{16,}$")

    /**
     * Normalizes a raw display name (with optional email fallback) into a concise, friendly
     * greeting name suitable for `"Welcome back, <name>."`, or `null` if no usable name exists.
     */
    public fun formatGreetingName(
        rawName: String?,
        fallbackEmail: String? = null,
    ): String? {
        normalizeCandidate(rawName)?.let { return it }
        return extractFromEmail(fallbackEmail)
    }

    /**
     * Builds the centered Home (`UE01`) hero greeting copy.
     */
    public fun homeHeroGreeting(
        displayName: String?,
        language: AppLanguage = AppLanguage.ENGLISH,
    ): String {
        val clean = formatGreetingName(displayName)
        if (language.isChinese) {
            return if (clean != null) {
                "欢迎回来，\n$clean。\n今天从哪里开始？"
            } else {
                "欢迎回来。\n今天从哪里\n开始？"
            }
        }
        return if (clean != null) {
            "Welcome back,\n$clean. Where\nshould we pick up?"
        } else {
            "Welcome back.\nWhere should\nwe pick up?"
        }
    }

    /**
     * Builds the dimmed Add Context popover backdrop greeting copy.
     */
    public fun addContextBackdropGreeting(
        displayName: String?,
        language: AppLanguage = AppLanguage.ENGLISH,
    ): String {
        val clean = formatGreetingName(displayName)
        if (language.isChinese) {
            return if (clean != null) {
                "欢迎回来，$clean。\n今天从哪里开始？"
            } else {
                "欢迎回来。\n今天从哪里开始？"
            }
        }
        return if (clean != null) {
            "Welcome back, $clean.\nWhere should we pick\nup?"
        } else {
            "Welcome back.\nWhere should we pick\nup?"
        }
    }

    /**
     * Builds the compact dimmed Permissions Preset popover backdrop greeting copy.
     */
    public fun compactBackdropGreeting(
        displayName: String?,
        language: AppLanguage = AppLanguage.ENGLISH,
    ): String {
        val clean = formatGreetingName(displayName)
        if (language.isChinese) {
            return if (clean != null) {
                "欢迎回来，$clean。"
            } else {
                "欢迎回来。"
            }
        }
        return if (clean != null) {
            "Welcome back, $clean."
        } else {
            "Welcome back."
        }
    }

    private fun normalizeCandidate(raw: String?): String? {
        val trimmed = raw?.trim().orEmpty()
        if (trimmed.isEmpty()) return null
        if (trimmed.contains('@')) {
            return extractFromEmail(trimmed)
        }
        val collapsed = trimmed.split(Regex("\\s+")).filter { it.isNotEmpty() }.joinToString(" ")
        if (collapsed.isEmpty()) return null
        if (isDisallowedToken(collapsed)) return null

        val tokens = collapsed.split(' ')
        val chosen = if (tokens.size > 1) {
            val first = tokens.first()
            val isShortInitial = first.length <= 1 || (first.length == 2 && first.endsWith('.'))
            if (isShortInitial) collapsed else first
        } else {
            collapsed
        }

        if (chosen.isEmpty() || chosen.length > MAX_GREETING_NAME_LENGTH) return null
        if (isDisallowedToken(chosen)) return null
        if (!chosen.any { it.isLetter() }) return null
        return chosen
    }

    private fun extractFromEmail(rawEmail: String?): String? {
        val trimmed = rawEmail?.trim().orEmpty()
        val atIdx = trimmed.indexOf('@')
        if (atIdx <= 0) return null
        val localPart = trimmed.substring(0, atIdx).substringBefore('+').trim()
        if (localPart.isEmpty()) return null

        val segments = localPart.split('.', '_', '-').filter { it.isNotEmpty() }
        val chosen = segments.firstOrNull { seg ->
            seg.length <= MAX_GREETING_NAME_LENGTH &&
                seg.any { it.isLetter() } &&
                !isDisallowedToken(seg)
        } ?: return null

        val isAllLowerAscii = chosen.all { it in 'a'..'z' || it in '0'..'9' }
        return if (isAllLowerAscii && chosen[0] in 'a'..'z') {
            chosen.replaceFirstChar { it.uppercaseChar() }
        } else {
            chosen
        }
    }

    private fun isDisallowedToken(value: String): Boolean {
        val lower = value.lowercase()
        if (lower in PLACEHOLDER_NAMES) return true
        if (UUID_LIKE_REGEX.matches(value) || HEX_ID_REGEX.matches(value)) return true
        return false
    }
}
