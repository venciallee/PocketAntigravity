package dev.antigravity.shared.model

import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlin.test.Test
import kotlin.test.assertEquals

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
}
