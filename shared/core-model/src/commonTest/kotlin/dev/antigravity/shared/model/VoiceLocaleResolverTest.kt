package dev.antigravity.shared.model

import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class VoiceLocaleResolverTest {
    private val iosSupportedLocales = setOf(
        "en_US",
        "en_GB",
        "en_CN",
        "zh_CN",
        "zh_TW",
        "zh_HK",
        "ja_JP",
        "ko_KR",
    )

    @Test
    fun chinesePhoneWithEnglishBundleLocaleCurrentResolvesToZhCN() {
        val candidates = VoiceLocaleResolver.buildCandidateLocaleTags(
            preference = VoiceDictationLanguage.AUTO,
            appLanguage = AppLanguage.ENGLISH,
            systemPreferredLanguages = listOf("zh-Hans-CN", "en-US"),
            activeKeyboardLanguage = null,
            fallbackLocaleTag = "en_CN",
        )
        assertEquals("zh-CN", candidates.first())
        assertEquals("zh_CN", VoiceLocaleResolver.resolveBestLocaleTag(candidates, iosSupportedLocales))
    }

    @Test
    fun chinesePhoneWithUsRegionResolvesToZhCN() {
        val candidates = VoiceLocaleResolver.buildCandidateLocaleTags(
            preference = VoiceDictationLanguage.AUTO,
            appLanguage = AppLanguage.ENGLISH,
            systemPreferredLanguages = listOf("zh-Hans-US", "en-US"),
            fallbackLocaleTag = "en_US",
        )
        assertEquals("zh-CN", candidates.first())
        assertEquals("zh_CN", VoiceLocaleResolver.resolveBestLocaleTag(candidates, iosSupportedLocales))
    }

    @Test
    fun traditionalChineseVariantsResolveToTaiwanAndHongKong() {
        val twCandidates = VoiceLocaleResolver.buildCandidateLocaleTags(
            preference = VoiceDictationLanguage.AUTO,
            appLanguage = AppLanguage.ENGLISH,
            systemPreferredLanguages = listOf("zh-Hant-TW", "en-US"),
            fallbackLocaleTag = "en_TW",
        )
        assertEquals("zh_TW", VoiceLocaleResolver.resolveBestLocaleTag(twCandidates, iosSupportedLocales))

        val hkCandidates = VoiceLocaleResolver.buildCandidateLocaleTags(
            preference = VoiceDictationLanguage.AUTO,
            appLanguage = AppLanguage.ENGLISH,
            systemPreferredLanguages = listOf("zh-Hant-HK", "en-US"),
            fallbackLocaleTag = "en_HK",
        )
        assertEquals("zh_HK", VoiceLocaleResolver.resolveBestLocaleTag(hkCandidates, iosSupportedLocales))
    }

    @Test
    fun englishPhoneWithChineseInAppLanguageResolvesToZhCN() {
        val candidates = VoiceLocaleResolver.buildCandidateLocaleTags(
            preference = VoiceDictationLanguage.AUTO,
            appLanguage = AppLanguage.ZH_HANS,
            systemPreferredLanguages = listOf("en-US"),
            fallbackLocaleTag = "en_US",
        )
        assertEquals("zh-CN", candidates.first())
        assertEquals("zh_CN", VoiceLocaleResolver.resolveBestLocaleTag(candidates, iosSupportedLocales))
    }

    @Test
    fun englishPhoneWithChineseKeyboardActiveResolvesToZhCN() {
        val candidates = VoiceLocaleResolver.buildCandidateLocaleTags(
            preference = VoiceDictationLanguage.AUTO,
            appLanguage = AppLanguage.ENGLISH,
            systemPreferredLanguages = listOf("en-US", "zh-Hans-CN"),
            activeKeyboardLanguage = "zh-Hans",
            fallbackLocaleTag = "en_US",
        )
        assertEquals("zh-CN", candidates.first())
        assertEquals("zh_CN", VoiceLocaleResolver.resolveBestLocaleTag(candidates, iosSupportedLocales))
    }

    @Test
    fun chinesePhoneWithTemporaryEnglishKeyboardStillResolvesToZhCN() {
        val candidates = VoiceLocaleResolver.buildCandidateLocaleTags(
            preference = VoiceDictationLanguage.AUTO,
            appLanguage = AppLanguage.ENGLISH,
            systemPreferredLanguages = listOf("zh-Hans-CN", "en-US"),
            activeKeyboardLanguage = "en-US",
            fallbackLocaleTag = "en_CN",
        )
        assertEquals("zh-CN", candidates.first())
        assertEquals("zh_CN", VoiceLocaleResolver.resolveBestLocaleTag(candidates, iosSupportedLocales))
    }

    @Test
    fun explicitPreferenceOverridesSystemAndAppLanguage() {
        val enCandidates = VoiceLocaleResolver.buildCandidateLocaleTags(
            preference = VoiceDictationLanguage.EN_US,
            appLanguage = AppLanguage.ZH_HANS,
            systemPreferredLanguages = listOf("zh-Hans-CN"),
            activeKeyboardLanguage = "zh-Hans",
            fallbackLocaleTag = "zh_CN",
        )
        assertEquals("en-US", enCandidates.first())
        assertEquals("en_US", VoiceLocaleResolver.resolveBestLocaleTag(enCandidates, iosSupportedLocales))

        val zhCandidates = VoiceLocaleResolver.buildCandidateLocaleTags(
            preference = VoiceDictationLanguage.ZH_CN,
            appLanguage = AppLanguage.ENGLISH,
            systemPreferredLanguages = listOf("en-US"),
            activeKeyboardLanguage = "en-US",
            fallbackLocaleTag = "en_US",
        )
        assertEquals("zh-CN", zhCandidates.first())
        assertEquals("zh_CN", VoiceLocaleResolver.resolveBestLocaleTag(zhCandidates, iosSupportedLocales))
    }

    @Test
    fun primaryLanguageFallbackAndResilientEnumSerialization() {
        val jaCandidates = VoiceLocaleResolver.buildCandidateLocaleTags(
            preference = VoiceDictationLanguage.AUTO,
            appLanguage = AppLanguage.ENGLISH,
            systemPreferredLanguages = listOf("ja-US"),
        )
        assertEquals("ja_JP", VoiceLocaleResolver.resolveBestLocaleTag(jaCandidates, iosSupportedLocales))

        val json = Json { ignoreUnknownKeys = true }
        val encoded = json.encodeToString(VoiceDictationLanguage.ZH_CN)
        assertEquals(VoiceDictationLanguage.ZH_CN, json.decodeFromString<VoiceDictationLanguage>(encoded))
        assertEquals(VoiceDictationLanguage.AUTO, json.decodeFromString<VoiceDictationLanguage>("\"future-locale-v9\""))

        assertEquals("中文", VoiceLocaleResolver.shortDisplayLabelForLocale("zh_CN"))
        assertEquals("繁體", VoiceLocaleResolver.shortDisplayLabelForLocale("zh-TW"))
        assertEquals("粵語", VoiceLocaleResolver.shortDisplayLabelForLocale("zh-HK"))
        assertEquals("EN", VoiceLocaleResolver.shortDisplayLabelForLocale("en-US"))
    }

    @Test
    fun englishOsBilingualUserWithInstalledChineseKeyboardPrefersChineseFirst() {
        val candidates = VoiceLocaleResolver.buildCandidateLocaleTags(
            preference = VoiceDictationLanguage.AUTO,
            appLanguage = AppLanguage.ENGLISH,
            systemPreferredLanguages = listOf("en-US"),
            activeKeyboardLanguage = null,
            installedKeyboardLanguages = listOf("en-US", "zh-Hans"),
            fallbackLocaleTag = "en_US",
        )
        assertEquals("zh-CN", candidates.first())
        assertEquals(
            listOf("zh-CN", "en-US"),
            VoiceLocaleResolver.buildAutoDetectionAllowedLocales(candidates),
        )
    }

    @Test
    fun englishOsUserWithSecondaryChineseSystemLanguagePrefersChineseFirst() {
        val candidates = VoiceLocaleResolver.buildCandidateLocaleTags(
            preference = VoiceDictationLanguage.AUTO,
            appLanguage = AppLanguage.ENGLISH,
            systemPreferredLanguages = listOf("en-US", "zh-Hans-CN"),
            activeKeyboardLanguage = null,
            fallbackLocaleTag = "en_US",
        )
        assertEquals("zh-CN", candidates.first())
        assertEquals(
            listOf("zh-CN", "en-US"),
            VoiceLocaleResolver.buildAutoDetectionAllowedLocales(candidates),
        )
    }

    @Test
    fun pureEnglishUserRemainsEnglishFirstWithOptionalBilingualFallback() {
        val candidates = VoiceLocaleResolver.buildCandidateLocaleTags(
            preference = VoiceDictationLanguage.AUTO,
            appLanguage = AppLanguage.ENGLISH,
            systemPreferredLanguages = listOf("en-US"),
            activeKeyboardLanguage = null,
            installedKeyboardLanguages = listOf("en-US"),
            contextTextHint = "Fix the authentication timeout in the relay client",
            fallbackLocaleTag = "en_US",
        )
        assertEquals("en-US", candidates.first())
        assertEquals(
            listOf("en-US"),
            VoiceLocaleResolver.buildAutoDetectionAllowedLocales(candidates, includeBilingualFallback = false),
        )
        assertEquals(
            listOf("en-US", "zh-CN"),
            VoiceLocaleResolver.buildAutoDetectionAllowedLocales(candidates, includeBilingualFallback = true),
        )
    }

    @Test
    fun conversationContextHintAndLastDetectedLocaleGuideAutoSelection() {
        val zhContextCandidates = VoiceLocaleResolver.buildCandidateLocaleTags(
            preference = VoiceDictationLanguage.AUTO,
            appLanguage = AppLanguage.ENGLISH,
            systemPreferredLanguages = listOf("en-US"),
            installedKeyboardLanguages = listOf("en-US"),
            contextTextHint = "帮我排查一下登录超时的问题",
            lastDetectedLocaleTag = "en-US",
            fallbackLocaleTag = "en_US",
        )
        assertEquals("zh-CN", zhContextCandidates.first())

        val enFollowUpCandidates = VoiceLocaleResolver.buildCandidateLocaleTags(
            preference = VoiceDictationLanguage.AUTO,
            appLanguage = AppLanguage.ENGLISH,
            systemPreferredLanguages = listOf("en-US", "zh-Hans-CN"),
            installedKeyboardLanguages = listOf("en-US", "zh-Hans"),
            contextTextHint = "Please refactor the retry queue and add unit tests",
            lastDetectedLocaleTag = "en-US",
            fallbackLocaleTag = "en_US",
        )
        assertEquals("en-US", enFollowUpCandidates.first())
        assertEquals(
            listOf("en-US", "zh-CN"),
            VoiceLocaleResolver.buildAutoDetectionAllowedLocales(enFollowUpCandidates),
        )
    }

    @Test
    fun autoDetectProbeTriggersAndWinnerSelection() {
        val fluentEnglish = VoiceTranscriptCandidate(
            localeTag = "en-US",
            text = "Please refactor the voice recognizer to detect languages automatically.",
            averageConfidence = 0.92,
            hasPopulatedConfidence = true,
        )
        assertFalse(
            VoiceLocaleResolver.shouldProbeAlternateLocale(
                primary = fluentEnglish,
                alternateLocaleTag = "zh-CN",
                activeSpeechDurationMs = 2200,
                isFinal = true,
            ),
        )

        val emptyPrimary = VoiceTranscriptCandidate(localeTag = "en-US", text = "")
        assertFalse(
            VoiceLocaleResolver.shouldProbeAlternateLocale(
                primary = emptyPrimary,
                alternateLocaleTag = "zh-CN",
                activeSpeechDurationMs = 900,
                isFinal = false,
            ),
        )
        assertTrue(
            VoiceLocaleResolver.shouldProbeAlternateLocale(
                primary = emptyPrimary,
                alternateLocaleTag = "zh-CN",
                activeSpeechDurationMs = 1700,
                isFinal = false,
            ),
        )

        val garbledEn = VoiceTranscriptCandidate(
            localeTag = "en-US",
            text = "knee how bang washy shot",
            averageConfidence = 0.41,
            hasPopulatedConfidence = true,
        )
        val crispZh = VoiceTranscriptCandidate(
            localeTag = "zh-CN",
            text = "你好帮我修一下",
            averageConfidence = 0.91,
            hasPopulatedConfidence = true,
        )
        assertTrue(
            VoiceLocaleResolver.shouldProbeAlternateLocale(
                primary = garbledEn,
                alternateLocaleTag = "zh-CN",
                activeSpeechDurationMs = 1500,
                isFinal = true,
            ),
        )
        assertEquals(
            crispZh,
            VoiceLocaleResolver.chooseBetterAutoDetectTranscript(garbledEn, crispZh),
        )

        val zhRecognizedEn = VoiceTranscriptCandidate(
            localeTag = "zh-CN",
            text = "please refactor the authentication middleware",
            averageConfidence = 0.79,
            hasPopulatedConfidence = true,
        )
        val enRefined = VoiceTranscriptCandidate(
            localeTag = "en-US",
            text = "Please refactor the authentication middleware.",
            averageConfidence = 0.93,
            hasPopulatedConfidence = true,
        )
        assertTrue(
            VoiceLocaleResolver.shouldProbeAlternateLocale(
                primary = zhRecognizedEn,
                alternateLocaleTag = "en-US",
                activeSpeechDurationMs = 2100,
                isFinal = true,
            ),
        )
        assertEquals(
            enRefined,
            VoiceLocaleResolver.chooseBetterAutoDetectTranscript(zhRecognizedEn, enRefined),
        )

        val mixedCnEn = VoiceTranscriptCandidate(
            localeTag = "zh-CN",
            text = "帮我重构一下 VoiceInputManager 的冷启动逻辑",
            averageConfidence = 0.89,
            hasPopulatedConfidence = true,
        )
        assertFalse(
            VoiceLocaleResolver.shouldProbeAlternateLocale(
                primary = mixedCnEn,
                alternateLocaleTag = "en-US",
                activeSpeechDurationMs = 2400,
                isFinal = true,
            ),
        )

        assertEquals("zh-CN", VoiceLocaleResolver.inferLocaleTagFromText("帮我修一下 bug"))
        assertEquals("en-US", VoiceLocaleResolver.inferLocaleTagFromText("Fix the timeout in relay client"))
        assertEquals("ja-JP", VoiceLocaleResolver.inferLocaleTagFromText("こんにちは世界"))
        assertEquals("ko-KR", VoiceLocaleResolver.inferLocaleTagFromText("안녕하세요 테스트"))
        assertNull(VoiceLocaleResolver.inferLocaleTagFromText("ok"))
    }
}
