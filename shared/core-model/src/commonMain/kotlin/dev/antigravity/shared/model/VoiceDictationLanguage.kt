package dev.antigravity.shared.model

import kotlinx.serialization.Serializable

/**
 * User-selectable speech-to-text dictation language preference (persisted per device).
 *
 * Defaults to [AUTO], which resolves from in-app [AppLanguage], OS preferred languages
 * (ahead of `Locale.current` so apps without `.lproj` bundles never mis-default to English),
 * and active IME keyboard language.
 */
@Serializable(with = VoiceDictationLanguageSerializer::class)
public enum class VoiceDictationLanguage(
    public val tag: String,
    public val bcp47Tag: String?,
) {
    AUTO(tag = "auto", bcp47Tag = null),
    ZH_CN(tag = "zh-CN", bcp47Tag = "zh-CN"),
    ZH_TW(tag = "zh-TW", bcp47Tag = "zh-TW"),
    ZH_HK(tag = "zh-HK", bcp47Tag = "zh-HK"),
    EN_US(tag = "en-US", bcp47Tag = "en-US"),
    ;

    public fun localizedTitle(language: AppLanguage): String = when (this) {
        AUTO -> language.t("Auto", "自动")
        ZH_CN -> "中文 (简体)"
        ZH_TW -> "中文 (繁體)"
        ZH_HK -> "粵語 (香港)"
        EN_US -> "English"
    }

    public fun shortBadgeLabel(language: AppLanguage): String = when (this) {
        AUTO -> language.t("Auto", "自动")
        ZH_CN -> "中文"
        ZH_TW -> "繁體"
        ZH_HK -> "粵語"
        EN_US -> "EN"
    }

    public companion object {
        public fun fromTag(raw: String?): VoiceDictationLanguage {
            val norm = normalizeResilientEnumToken(raw.orEmpty())
            return when (norm) {
                "zhcn", "zhhans", "zhhanscn", "zh", "chinese", "中文简体" -> ZH_CN
                "zhtw", "zhhant", "zhhanttw", "中文繁體" -> ZH_TW
                "zhhk", "zhhanthk", "yue", "yuehk", "粵語香港" -> ZH_HK
                "enus", "en", "english" -> EN_US
                else -> AUTO
            }
        }
    }
}

public object VoiceDictationLanguageSerializer : ResilientEnumSerializer<VoiceDictationLanguage>(
    serialName = "dev.antigravity.shared.model.VoiceDictationLanguage",
    entriesProvider = { VoiceDictationLanguage.entries },
    fallbackProvider = { VoiceDictationLanguage.AUTO },
    extraMatcher = { raw ->
        val norm = normalizeResilientEnumToken(raw)
        when (norm) {
            "auto" -> VoiceDictationLanguage.AUTO
            "zhcn", "zhhans", "zhhanscn", "zh" -> VoiceDictationLanguage.ZH_CN
            "zhtw", "zhhant", "zhhanttw" -> VoiceDictationLanguage.ZH_TW
            "zhhk", "zhhanthk", "yue", "yuehk" -> VoiceDictationLanguage.ZH_HK
            "enus", "en", "english" -> VoiceDictationLanguage.EN_US
            else -> null
        }
    },
)

/**
 * Pure cross-platform speech recognition locale resolver shared across Android & iOS.
 *
 * Prevents the classic iOS/Android bug where an app without full OS locale bundles receives
 * `Locale.current = "en_CN"` on a Chinese phone and mistakenly transcribes Chinese speech
 * with an English recognizer.
 */
public object VoiceLocaleResolver {
    /**
     * Normalizes raw OS/keyboard locale tags (including script subtags like `zh-Hans-CN`,
     * `zh-Hans-US`, `zh_Hant_HK`, `en_CN`) into ordered BCP-47 speech recognizer tags.
     */
    public fun normalizeSpeechLocaleTags(raw: String): List<String> {
        val cleaned = raw.trim().replace('_', '-')
        if (cleaned.isEmpty()) return emptyList()

        val parts = cleaned.split('-').filter { it.isNotEmpty() }
        if (parts.isEmpty()) return emptyList()

        val lang = parts[0].lowercase()
        val lowerParts = parts.map { it.lowercase() }

        return when (lang) {
            "zh" -> {
                val hasHans = lowerParts.contains("hans")
                val hasHant = lowerParts.contains("hant")
                val hasHk = lowerParts.contains("hk")
                val hasTw = lowerParts.contains("tw") || lowerParts.contains("mo")
                val hasSg = lowerParts.contains("sg")
                when {
                    hasHk -> listOf("zh-HK", "zh-TW", "zh-CN")
                    hasHant || hasTw -> listOf("zh-TW", "zh-HK", "zh-CN")
                    hasSg -> listOf("zh-CN", "zh-SG", "zh-Hans-CN")
                    hasHans -> listOf("zh-CN", "zh-Hans-CN", "zh-SG")
                    else -> listOf("zh-CN", "zh-Hans-CN", "zh-TW", "zh-HK")
                }
            }

            "yue" -> listOf("zh-HK", "yue-HK", "zh-TW", "zh-CN")

            "en" -> {
                val region = parts.lastOrNull()?.takeIf { parts.size >= 2 && it.length == 2 }?.uppercase()
                when {
                    region == null || region == "CN" -> listOf("en-US", "en-GB")
                    region == "US" -> listOf("en-US")
                    else -> listOf("en-$region", "en-US")
                }
            }

            else -> {
                val region = parts.lastOrNull()?.takeIf { parts.size >= 2 && it.length == 2 }?.uppercase()
                val canonical = if (region != null) "$lang-$region" else lang
                listOf(canonical)
            }
        }
    }

    /**
     * Builds the ordered list of candidate BCP-47 speech recognizer locale tags.
     */
    public fun buildCandidateLocaleTags(
        preference: VoiceDictationLanguage,
        appLanguage: AppLanguage,
        systemPreferredLanguages: List<String>,
        activeKeyboardLanguage: String? = null,
        fallbackLocaleTag: String? = null,
    ): List<String> {
        val result = LinkedHashSet<String>()
        fun addNormalized(raw: String?) {
            if (raw.isNullOrBlank()) return
            for (tag in normalizeSpeechLocaleTags(raw)) {
                result.add(tag)
            }
        }

        // 1. Explicit user dictation language override always wins.
        if (preference != VoiceDictationLanguage.AUTO && preference.bcp47Tag != null) {
            addNormalized(preference.bcp47Tag)
        } else {
            val primarySystem = systemPreferredLanguages.firstOrNull { it.isNotBlank() }
            val primarySystemLang = primaryLanguageCode(primarySystem)
            val keyboardLang = primaryLanguageCode(activeKeyboardLanguage)

            // 2. If user switched in-app language to Chinese, prefer their Chinese variant (or zh-CN).
            if (appLanguage == AppLanguage.ZH_HANS) {
                if (primarySystemLang == "zh" || primarySystemLang == "yue") {
                    addNormalized(primarySystem)
                }
                addNormalized("zh-CN")
            }

            // 3. On an English-system device, if the user currently has a non-English keyboard open
            //    (e.g. Chinese Pinyin keyboard), honor the active keyboard language first.
            if (primarySystemLang == "en" && keyboardLang != null && keyboardLang != "en") {
                addNormalized(activeKeyboardLanguage)
            }

            // 4. OS preferred languages (MUST come before Locale.current which iOS pins to app bundle language).
            for (sysLang in systemPreferredLanguages) {
                addNormalized(sysLang)
            }

            // 5. Active keyboard as fallback if not already added.
            addNormalized(activeKeyboardLanguage)
        }

        // 6. Fallback locale & ultimate en-US safety net.
        addNormalized(fallbackLocaleTag)
        result.add("en-US")
        return result.toList()
    }

    /**
     * Picks the best matching locale identifier from [supportedLocaleTags] for [candidates].
     * Preserves the exact identifier string present in [supportedLocaleTags] when found.
     */
    public fun resolveBestLocaleTag(
        candidates: List<String>,
        supportedLocaleTags: Set<String>,
    ): String? {
        if (candidates.isEmpty()) return null
        if (supportedLocaleTags.isEmpty()) return candidates.first()

        val normalizedToOriginal = LinkedHashMap<String, String>()
        for (supported in supportedLocaleTags) {
            val norm = supported.trim().replace('_', '-').lowercase()
            if (norm.isNotEmpty() && !normalizedToOriginal.containsKey(norm)) {
                normalizedToOriginal[norm] = supported
            }
        }

        // Match each candidate in priority order:
        // 1. Exact normalized BCP-47 match immediately wins.
        // 2. Once all explicit regional variants for a language have been checked without an exact match,
        //    match any supported locale sharing that primary language (e.g. `ja-US` -> `ja-JP`)
        //    before falling through to lower-priority languages such as the `en-US` safety net.
        for (index in candidates.indices) {
            val candidate = candidates[index]
            val norm = candidate.trim().replace('_', '-').lowercase()
            val exact = normalizedToOriginal[norm]
            if (exact != null) return exact

            val targetLang = primaryLanguageCode(candidate) ?: continue
            val hasLaterSameLanguage = (index + 1 until candidates.size).any { laterIdx ->
                primaryLanguageCode(candidates[laterIdx]) == targetLang
            }
            if (!hasLaterSameLanguage) {
                val matched = normalizedToOriginal.entries.firstOrNull { (normKey, _) ->
                    primaryLanguageCode(normKey) == targetLang
                }?.value
                if (matched != null) return matched
            }
        }

        return null
    }

    public fun shortDisplayLabelForLocale(localeTag: String?): String {
        val cleaned = localeTag?.trim()?.replace('_', '-').orEmpty()
        if (cleaned.isEmpty()) return "Auto"
        val lower = cleaned.lowercase()
        val lang = primaryLanguageCode(lower) ?: return cleaned.uppercase()
        return when (lang) {
            "zh" -> when {
                lower.contains("-hk") -> "粵語"
                lower.contains("-tw") || lower.contains("-hant") || lower.contains("-mo") -> "繁體"
                else -> "中文"
            }
            "yue" -> "粵語"
            "en" -> "EN"
            "ja" -> "日本語"
            "ko" -> "한국어"
            else -> lang.uppercase()
        }
    }

    private fun primaryLanguageCode(raw: String?): String? {
        val cleaned = raw?.trim()?.replace('_', '-') ?: return null
        if (cleaned.isEmpty()) return null
        return cleaned.substringBefore('-').lowercase().takeIf { it.isNotEmpty() }
    }
}
