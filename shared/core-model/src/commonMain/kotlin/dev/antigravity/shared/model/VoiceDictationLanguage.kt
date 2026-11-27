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
 * Candidate speech transcription output evaluated during automatic bilingual language detection.
 *
 * Mirrors `AntigravityData.VoiceTranscriptCandidate` on iOS so both platforms share identical
 * auto-fallback thresholds and confidence/script coherence scoring.
 */
public data class VoiceTranscriptCandidate(
    public val localeTag: String,
    public val text: String,
    public val averageConfidence: Double = 0.0,
    public val hasPopulatedConfidence: Boolean = false,
)

/**
 * Pure cross-platform speech recognition locale resolver & auto-detection evaluator shared across
 * Android & iOS.
 *
 * Prevents the classic iOS/Android bug where an app without full OS locale bundles receives
 * `Locale.current = "en_CN"` on a Chinese phone and mistakenly transcribes Chinese speech
 * with an English recognizer, and supports automatic bilingual Chinese <-> English detection
 * without requiring manual language switching.
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
     * Infers a coarse BCP-47 speech locale from freeform text (draft, recent conversation turns,
     * or recognized transcript) using Unicode script counts.
     */
    public fun inferLocaleTagFromText(text: String?): String? {
        val trimmed = text?.trim().orEmpty()
        if (trimmed.isEmpty()) return null

        var cjkIdeographs = 0
        var japaneseKana = 0
        var koreanHangul = 0
        var latinLetters = 0

        for (ch in trimmed) {
            val code = ch.code
            when {
                code in 0x3040..0x30FF -> japaneseKana += 1
                code in 0xAC00..0xD7AF || code in 0x1100..0x11FF -> koreanHangul += 1
                code in 0x4E00..0x9FFF || code in 0x3400..0x4DBF || code in 0xF900..0xFAFF -> cjkIdeographs += 1
                code in 'A'.code..'Z'.code || code in 'a'.code..'z'.code -> latinLetters += 1
            }
        }

        return when {
            japaneseKana >= 2 -> "ja-JP"
            koreanHangul >= 2 -> "ko-KR"
            cjkIdeographs >= 2 || (cjkIdeographs >= 1 && latinLetters <= 8) -> "zh-CN"
            latinLetters >= 12 && cjkIdeographs == 0 && japaneseKana == 0 && koreanHangul == 0 -> "en-US"
            else -> null
        }
    }

    /**
     * Builds the ordered list of candidate BCP-47 speech recognizer locale tags.
     *
     * For bilingual Chinese/English devices (e.g., English-OS iPhone with Chinese secondary OS
     * language or Chinese keyboard enabled), prefers the user's Chinese recognizer ahead of
     * `en-US` because Chinese recognizers accurately handle both Mandarin and Chinese-English
     * code-switching, whereas `en-US` turns Chinese speech into English gibberish — while keeping
     * `en-US` immediately behind for automatic runtime fallback when pure English is spoken.
     */
    public fun buildCandidateLocaleTags(
        preference: VoiceDictationLanguage,
        appLanguage: AppLanguage,
        systemPreferredLanguages: List<String>,
        activeKeyboardLanguage: String? = null,
        installedKeyboardLanguages: List<String> = emptyList(),
        contextTextHint: String? = null,
        lastDetectedLocaleTag: String? = null,
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
            val contextLocale = inferLocaleTagFromText(contextTextHint)
            val contextLang = primaryLanguageCode(contextLocale)
            val lastDetectedLang = primaryLanguageCode(lastDetectedLocaleTag)

            val preferredChineseSource = buildList {
                if (!activeKeyboardLanguage.isNullOrBlank()) add(activeKeyboardLanguage)
                addAll(systemPreferredLanguages)
                addAll(installedKeyboardLanguages)
            }.firstOrNull { tag ->
                val lang = primaryLanguageCode(tag)
                lang == "zh" || lang == "yue"
            }

            val hasChineseSignal = appLanguage == AppLanguage.ZH_HANS ||
                keyboardLang == "zh" ||
                keyboardLang == "yue" ||
                preferredChineseSource != null ||
                contextLang == "zh" ||
                lastDetectedLang == "zh" ||
                lastDetectedLang == "yue"

            // 2. Active conversation/draft text containing Chinese immediately prioritizes the
            //    user's preferred Chinese variant.
            if (contextLang == "zh") {
                addNormalized(preferredChineseSource ?: "zh-CN")
            }

            // 3. Pure-English conversation context combined with recent English voice detection
            //    keeps English primary (with Chinese right behind for auto-fallback).
            if (contextLang == "en" && lastDetectedLang == "en") {
                addNormalized(lastDetectedLocaleTag)
                addNormalized("en-US")
            }

            // 4. If user switched in-app language to Chinese, prefer their Chinese variant (or zh-CN).
            if (appLanguage == AppLanguage.ZH_HANS) {
                addNormalized(preferredChineseSource ?: "zh-CN")
            }

            // 5. On an English-system device, if the user currently has a non-English keyboard open
            //    (e.g. Chinese Pinyin keyboard), honor the active keyboard language first.
            if (primarySystemLang == "en" && keyboardLang != null && keyboardLang != "en") {
                addNormalized(activeKeyboardLanguage)
            }

            // 6. Bilingual English-OS user with Chinese OS secondary language or installed Chinese
            //    keyboard: start with Chinese unless their very last auto-detected turn was English.
            if (primarySystemLang == "en" && hasChineseSignal && lastDetectedLang != "en") {
                addNormalized(preferredChineseSource ?: "zh-CN")
            }

            // 7. Remembered auto-detected locale from the previous turn (when not overridden above).
            addNormalized(lastDetectedLocaleTag)

            // 8. OS preferred languages (MUST come before Locale.current which iOS pins to app bundle).
            for (sysLang in systemPreferredLanguages) {
                addNormalized(sysLang)
            }

            // 9. Active & installed keyboards as additional bilingual signals.
            addNormalized(activeKeyboardLanguage)
            for (kbLang in installedKeyboardLanguages) {
                addNormalized(kbLang)
            }

            // 10. Context locale hint (e.g. ja-JP / ko-KR / en-US).
            addNormalized(contextLocale)
        }

        // 11. Fallback locale & ultimate en-US safety net.
        addNormalized(fallbackLocaleTag)
        result.add("en-US")
        return result.toList()
    }

    /**
     * Produces a compact deduplicated list of distinct primary-language BCP-47 tags for
     * Android 14+ native language detection/switching (`EXTRA_LANGUAGE_DETECTION_ALLOWED_LANGUAGES`)
     * and iOS automatic PCM-replay alternate locale selection.
     */
    public fun buildAutoDetectionAllowedLocales(
        candidates: List<String>,
        includeBilingualFallback: Boolean = false,
        maxCount: Int = 4,
    ): List<String> {
        if (maxCount <= 0) return emptyList()
        val selected = ArrayList<String>(maxCount)
        val seenPrimary = HashSet<String>()

        for (candidate in candidates) {
            if (selected.size >= maxCount) break
            val normalized = normalizeSpeechLocaleTags(candidate).firstOrNull() ?: continue
            val primary = primaryLanguageCode(normalized) ?: continue
            val bucket = if (primary == "yue") "zh" else primary
            if (seenPrimary.add(bucket)) {
                selected.add(normalized)
            }
        }

        if (includeBilingualFallback && selected.size == 1 && maxCount >= 2) {
            val primary = primaryLanguageCode(selected[0])
            if (primary == "en") {
                selected.add("zh-CN")
            } else if (primary == "zh" || primary == "yue") {
                selected.add("en-US")
            }
        }

        return selected
    }

    /**
     * Decides whether an automatic bilingual session should probe [alternateLocaleTag]
     * using buffered PCM audio (either mid-utterance when silent/low-confidence, or on finalize).
     */
    public fun shouldProbeAlternateLocale(
        primary: VoiceTranscriptCandidate,
        alternateLocaleTag: String?,
        activeSpeechDurationMs: Int,
        isFinal: Boolean,
    ): Boolean {
        val altTag = alternateLocaleTag?.trim().orEmpty()
        if (altTag.isEmpty()) return false
        val primaryLang = primaryLanguageCode(primary.localeTag) ?: return false
        val altLang = primaryLanguageCode(altTag) ?: return false
        if (primaryLang == altLang) return false
        if (activeSpeechDurationMs < 400) return false

        val trimmedText = primary.text.trim()
        if (trimmedText.isEmpty()) {
            return isFinal || activeSpeechDurationMs >= 1600
        }

        if (primary.hasPopulatedConfidence) {
            if (!isFinal) {
                return activeSpeechDurationMs >= 1400 && primary.averageConfidence < 0.52
            }
            if (primary.averageConfidence < 0.76) {
                return true
            }
        }

        if (!isFinal) return false

        val inferredLang = primaryLanguageCode(inferLocaleTagFromText(trimmedText))
        // Chinese recognizer produced pure English text -> verify with en-US for proper casing/accuracy.
        if (primaryLang == "zh" && altLang == "en" && inferredLang == "en") {
            return true
        }
        // English recognizer returned unpopulated confidence on a short or chopped phrase ->
        // verify against Chinese in case Chinese speech was phonetically mis-transcribed as English.
        if (primaryLang == "en" && altLang == "zh" && !primary.hasPopulatedConfidence) {
            return looksLikeSuspiciousEnglishPhoneticGibberish(trimmedText)
        }
        return false
    }

    /**
     * Compares primary and alternate recognition candidates for the same audio buffer and
     * selects the higher-quality transcript with hysteresis to avoid noisy flip-flops.
     */
    public fun chooseBetterAutoDetectTranscript(
        primary: VoiceTranscriptCandidate,
        alternate: VoiceTranscriptCandidate,
    ): VoiceTranscriptCandidate {
        val primaryText = primary.text.trim()
        val alternateText = alternate.text.trim()
        if (primaryText.isEmpty() && alternateText.isNotEmpty()) return alternate
        if (alternateText.isEmpty()) return primary

        val primaryScore = scoreAutoDetectCandidate(primary)
        val alternateScore = scoreAutoDetectCandidate(alternate)

        if (alternateScore >= primaryScore + 0.05) {
            return alternate
        }

        val primaryLang = primaryLanguageCode(primary.localeTag)
        val altLang = primaryLanguageCode(alternate.localeTag)
        val primaryInferred = primaryLanguageCode(inferLocaleTagFromText(primaryText))
        val altInferred = primaryLanguageCode(inferLocaleTagFromText(alternateText))
        if (primaryLang == "zh" &&
            altLang == "en" &&
            primaryInferred == "en" &&
            altInferred == "en" &&
            alternateScore >= primaryScore - 0.02
        ) {
            return alternate
        }

        return primary
    }

    internal fun looksLikeSuspiciousEnglishPhoneticGibberish(text: String): Boolean {
        val words = text.trim()
            .split(Regex("\\s+"))
            .map { token -> token.filter { it.isLetter() } }
            .filter { it.isNotEmpty() }
        if (words.isEmpty()) return true
        if (words.size <= 5) return true
        val avgWordLength = words.sumOf { it.length }.toDouble() / words.size.toDouble()
        return avgWordLength <= 3.6
    }

    private fun scoreAutoDetectCandidate(candidate: VoiceTranscriptCandidate): Double {
        val trimmed = candidate.text.trim()
        if (trimmed.isEmpty()) return 0.0

        var score = if (candidate.hasPopulatedConfidence) {
            candidate.averageConfidence.coerceIn(0.0, 1.0)
        } else {
            0.60
        }

        val candLang = primaryLanguageCode(candidate.localeTag)
        val inferred = primaryLanguageCode(inferLocaleTagFromText(trimmed))

        if (candLang == "zh") {
            if (inferred == "zh") score += 0.06
            if (inferred == "en") score -= 0.08
        } else if (candLang == "en") {
            if (inferred == "en") score += 0.04
            val words = trimmed.split(Regex("\\s+"))
                .map { token -> token.filter { it.isLetter() } }
                .filter { it.isNotEmpty() }
            if (words.size >= 3) {
                val avgLen = words.sumOf { it.length }.toDouble() / words.size.toDouble()
                if (avgLen < 3.4) {
                    score -= 0.08
                }
            }
        }

        return score
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
