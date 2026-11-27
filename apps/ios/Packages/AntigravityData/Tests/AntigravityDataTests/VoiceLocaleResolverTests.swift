import XCTest
@testable import AntigravityData

final class VoiceLocaleResolverTests: XCTestCase {
    private let iosSupportedLocales: Set<String> = [
        "en_US",
        "en_GB",
        "en_CN",
        "zh_CN",
        "zh_TW",
        "zh_HK",
        "ja_JP",
        "ko_KR",
    ]

    func testChinesePhoneWithEnglishBundleLocaleCurrentResolvesToZhCN() {
        let candidates = VoiceLocaleResolver.buildCandidateLocaleTags(
            preference: .auto,
            appLanguage: .english,
            systemPreferredLanguages: ["zh-Hans-CN", "en-US"],
            activeKeyboardLanguage: nil,
            fallbackLocaleTag: "en_CN"
        )
        XCTAssertEqual(candidates.first, "zh-CN")
        XCTAssertEqual(
            VoiceLocaleResolver.resolveBestLocaleTag(candidates: candidates, supportedLocaleTags: iosSupportedLocales),
            "zh_CN"
        )
    }

    func testChinesePhoneWithUsRegionResolvesToZhCN() {
        let candidates = VoiceLocaleResolver.buildCandidateLocaleTags(
            preference: .auto,
            appLanguage: .english,
            systemPreferredLanguages: ["zh-Hans-US", "en-US"],
            fallbackLocaleTag: "en_US"
        )
        XCTAssertEqual(candidates.first, "zh-CN")
        XCTAssertEqual(
            VoiceLocaleResolver.resolveBestLocaleTag(candidates: candidates, supportedLocaleTags: iosSupportedLocales),
            "zh_CN"
        )
    }

    func testTraditionalChineseVariantsResolveToTaiwanAndHongKong() {
        let twCandidates = VoiceLocaleResolver.buildCandidateLocaleTags(
            preference: .auto,
            appLanguage: .english,
            systemPreferredLanguages: ["zh-Hant-TW", "en-US"],
            fallbackLocaleTag: "en_TW"
        )
        XCTAssertEqual(
            VoiceLocaleResolver.resolveBestLocaleTag(candidates: twCandidates, supportedLocaleTags: iosSupportedLocales),
            "zh_TW"
        )

        let hkCandidates = VoiceLocaleResolver.buildCandidateLocaleTags(
            preference: .auto,
            appLanguage: .english,
            systemPreferredLanguages: ["zh-Hant-HK", "en-US"],
            fallbackLocaleTag: "en_HK"
        )
        XCTAssertEqual(
            VoiceLocaleResolver.resolveBestLocaleTag(candidates: hkCandidates, supportedLocaleTags: iosSupportedLocales),
            "zh_HK"
        )
    }

    func testEnglishPhoneWithChineseInAppLanguageResolvesToZhCN() {
        let candidates = VoiceLocaleResolver.buildCandidateLocaleTags(
            preference: .auto,
            appLanguage: .zhHans,
            systemPreferredLanguages: ["en-US"],
            fallbackLocaleTag: "en_US"
        )
        XCTAssertEqual(candidates.first, "zh-CN")
        XCTAssertEqual(
            VoiceLocaleResolver.resolveBestLocaleTag(candidates: candidates, supportedLocaleTags: iosSupportedLocales),
            "zh_CN"
        )
    }

    func testEnglishPhoneWithChineseKeyboardActiveResolvesToZhCN() {
        let candidates = VoiceLocaleResolver.buildCandidateLocaleTags(
            preference: .auto,
            appLanguage: .english,
            systemPreferredLanguages: ["en-US", "zh-Hans-CN"],
            activeKeyboardLanguage: "zh-Hans",
            fallbackLocaleTag: "en_US"
        )
        XCTAssertEqual(candidates.first, "zh-CN")
        XCTAssertEqual(
            VoiceLocaleResolver.resolveBestLocaleTag(candidates: candidates, supportedLocaleTags: iosSupportedLocales),
            "zh_CN"
        )
    }

    func testChinesePhoneWithTemporaryEnglishKeyboardStillResolvesToZhCN() {
        let candidates = VoiceLocaleResolver.buildCandidateLocaleTags(
            preference: .auto,
            appLanguage: .english,
            systemPreferredLanguages: ["zh-Hans-CN", "en-US"],
            activeKeyboardLanguage: "en-US",
            fallbackLocaleTag: "en_CN"
        )
        XCTAssertEqual(candidates.first, "zh-CN")
        XCTAssertEqual(
            VoiceLocaleResolver.resolveBestLocaleTag(candidates: candidates, supportedLocaleTags: iosSupportedLocales),
            "zh_CN"
        )
    }

    func testExplicitPreferenceOverridesSystemAndAppLanguage() {
        let enCandidates = VoiceLocaleResolver.buildCandidateLocaleTags(
            preference: .enUS,
            appLanguage: .zhHans,
            systemPreferredLanguages: ["zh-Hans-CN"],
            activeKeyboardLanguage: "zh-Hans",
            fallbackLocaleTag: "zh_CN"
        )
        XCTAssertEqual(enCandidates.first, "en-US")
        XCTAssertEqual(
            VoiceLocaleResolver.resolveBestLocaleTag(candidates: enCandidates, supportedLocaleTags: iosSupportedLocales),
            "en_US"
        )

        let zhCandidates = VoiceLocaleResolver.buildCandidateLocaleTags(
            preference: .zhCN,
            appLanguage: .english,
            systemPreferredLanguages: ["en-US"],
            activeKeyboardLanguage: "en-US",
            fallbackLocaleTag: "en_US"
        )
        XCTAssertEqual(zhCandidates.first, "zh-CN")
        XCTAssertEqual(
            VoiceLocaleResolver.resolveBestLocaleTag(candidates: zhCandidates, supportedLocaleTags: iosSupportedLocales),
            "zh_CN"
        )
    }

    func testPrimaryLanguageFallbackAndResilientDecoding() throws {
        let jaCandidates = VoiceLocaleResolver.buildCandidateLocaleTags(
            preference: .auto,
            appLanguage: .english,
            systemPreferredLanguages: ["ja-US"]
        )
        XCTAssertEqual(
            VoiceLocaleResolver.resolveBestLocaleTag(candidates: jaCandidates, supportedLocaleTags: iosSupportedLocales),
            "ja_JP"
        )

        let decodedUnknown = try JSONDecoder().decode(VoiceDictationLanguage.self, from: Data("\"future-locale-v9\"".utf8))
        XCTAssertEqual(decodedUnknown, .auto)

        XCTAssertEqual(VoiceLocaleResolver.shortDisplayLabel(forLocaleTag: "zh_CN"), "中文")
        XCTAssertEqual(VoiceLocaleResolver.shortDisplayLabel(forLocaleTag: "zh-TW"), "繁體")
        XCTAssertEqual(VoiceLocaleResolver.shortDisplayLabel(forLocaleTag: "zh-HK"), "粵語")
        XCTAssertEqual(VoiceLocaleResolver.shortDisplayLabel(forLocaleTag: "en-US"), "EN")
    }

    func testEnglishOsBilingualUserWithInstalledChineseKeyboardPrefersChineseFirst() {
        // Unfocused TextField (activeKeyboardLanguage == nil), English OS + English App UI,
        // but Chinese keyboard is installed -> bilingual user should default to zh-CN (handles
        // Chinese & CN+EN code-switching) with en-US right behind for auto-fallback.
        let candidates = VoiceLocaleResolver.buildCandidateLocaleTags(
            preference: .auto,
            appLanguage: .english,
            systemPreferredLanguages: ["en-US"],
            activeKeyboardLanguage: nil,
            installedKeyboardLanguages: ["en-US", "zh-Hans"],
            fallbackLocaleTag: "en_US"
        )
        XCTAssertEqual(candidates.first, "zh-CN")
        XCTAssertEqual(
            VoiceLocaleResolver.buildAutoDetectionAllowedLocales(candidates: candidates),
            ["zh-CN", "en-US"]
        )
    }

    func testEnglishOsUserWithSecondaryChineseSystemLanguagePrefersChineseFirst() {
        let candidates = VoiceLocaleResolver.buildCandidateLocaleTags(
            preference: .auto,
            appLanguage: .english,
            systemPreferredLanguages: ["en-US", "zh-Hans-CN"],
            activeKeyboardLanguage: nil,
            fallbackLocaleTag: "en_US"
        )
        XCTAssertEqual(candidates.first, "zh-CN")
        XCTAssertEqual(
            VoiceLocaleResolver.buildAutoDetectionAllowedLocales(candidates: candidates),
            ["zh-CN", "en-US"]
        )
    }

    func testPureEnglishUserRemainsEnglishFirstWithOptionalBilingualFallback() {
        let candidates = VoiceLocaleResolver.buildCandidateLocaleTags(
            preference: .auto,
            appLanguage: .english,
            systemPreferredLanguages: ["en-US"],
            activeKeyboardLanguage: nil,
            installedKeyboardLanguages: ["en-US"],
            contextTextHint: "Fix the authentication timeout in the relay client",
            fallbackLocaleTag: "en_US"
        )
        XCTAssertEqual(candidates.first, "en-US")
        XCTAssertEqual(
            VoiceLocaleResolver.buildAutoDetectionAllowedLocales(candidates: candidates, includeBilingualFallback: false),
            ["en-US"]
        )
        XCTAssertEqual(
            VoiceLocaleResolver.buildAutoDetectionAllowedLocales(candidates: candidates, includeBilingualFallback: true),
            ["en-US", "zh-CN"]
        )
    }

    func testConversationContextHintAndLastDetectedLocaleGuideAutoSelection() {
        // Pure English OS device inside a Chinese conversation immediately picks zh-CN
        let zhContextCandidates = VoiceLocaleResolver.buildCandidateLocaleTags(
            preference: .auto,
            appLanguage: .english,
            systemPreferredLanguages: ["en-US"],
            installedKeyboardLanguages: ["en-US"],
            contextTextHint: "帮我排查一下登录超时的问题",
            lastDetectedLocaleTag: "en-US",
            fallbackLocaleTag: "en_US"
        )
        XCTAssertEqual(zhContextCandidates.first, "zh-CN")

        // Bilingual device that just spoke pure English in an English conversation stays on en-US
        // while keeping zh-CN as immediate alternate
        let enFollowUpCandidates = VoiceLocaleResolver.buildCandidateLocaleTags(
            preference: .auto,
            appLanguage: .english,
            systemPreferredLanguages: ["en-US", "zh-Hans-CN"],
            installedKeyboardLanguages: ["en-US", "zh-Hans"],
            contextTextHint: "Please refactor the retry queue and add unit tests",
            lastDetectedLocaleTag: "en-US",
            fallbackLocaleTag: "en_US"
        )
        XCTAssertEqual(enFollowUpCandidates.first, "en-US")
        XCTAssertEqual(
            VoiceLocaleResolver.buildAutoDetectionAllowedLocales(candidates: enFollowUpCandidates),
            ["en-US", "zh-CN"]
        )
    }

    func testAutoDetectProbeTriggersAndWinnerSelection() {
        // 1. High-confidence English never triggers unnecessary probe
        let fluentEnglish = VoiceTranscriptCandidate(
            localeTag: "en-US",
            text: "Please refactor the voice recognizer to detect languages automatically.",
            averageConfidence: 0.92,
            hasPopulatedConfidence: true
        )
        XCTAssertFalse(
            VoiceLocaleResolver.shouldProbeAlternateLocale(
                primary: fluentEnglish,
                alternateLocaleTag: "zh-CN",
                activeSpeechDurationMs: 2200,
                isFinal: true
            )
        )

        // 2. Active speech with empty transcript triggers live switch at >= 1600ms
        let emptyPrimary = VoiceTranscriptCandidate(localeTag: "en-US", text: "")
        XCTAssertFalse(
            VoiceLocaleResolver.shouldProbeAlternateLocale(
                primary: emptyPrimary,
                alternateLocaleTag: "zh-CN",
                activeSpeechDurationMs: 900,
                isFinal: false
            )
        )
        XCTAssertTrue(
            VoiceLocaleResolver.shouldProbeAlternateLocale(
                primary: emptyPrimary,
                alternateLocaleTag: "zh-CN",
                activeSpeechDurationMs: 1700,
                isFinal: false
            )
        )

        // 3. Low-confidence English phonetic gibberish when speaking Chinese triggers probe & zh-CN wins
        let garbledEn = VoiceTranscriptCandidate(
            localeTag: "en-US",
            text: "knee how bang washy shot",
            averageConfidence: 0.41,
            hasPopulatedConfidence: true
        )
        let crispZh = VoiceTranscriptCandidate(
            localeTag: "zh-CN",
            text: "你好帮我修一下",
            averageConfidence: 0.91,
            hasPopulatedConfidence: true
        )
        XCTAssertTrue(
            VoiceLocaleResolver.shouldProbeAlternateLocale(
                primary: garbledEn,
                alternateLocaleTag: "zh-CN",
                activeSpeechDurationMs: 1500,
                isFinal: true
            )
        )
        let zhWinner = VoiceLocaleResolver.chooseBetterAutoDetectTranscript(
            primary: garbledEn,
            alternate: crispZh
        )
        XCTAssertEqual(zhWinner, crispZh)

        // 4. zh-CN recognizer outputting pure English sentence triggers en-US probe & en-US wins
        let zhRecognizedEn = VoiceTranscriptCandidate(
            localeTag: "zh-CN",
            text: "please refactor the authentication middleware",
            averageConfidence: 0.79,
            hasPopulatedConfidence: true
        )
        let enRefined = VoiceTranscriptCandidate(
            localeTag: "en-US",
            text: "Please refactor the authentication middleware.",
            averageConfidence: 0.93,
            hasPopulatedConfidence: true
        )
        XCTAssertTrue(
            VoiceLocaleResolver.shouldProbeAlternateLocale(
                primary: zhRecognizedEn,
                alternateLocaleTag: "en-US",
                activeSpeechDurationMs: 2100,
                isFinal: true
            )
        )
        let enWinner = VoiceLocaleResolver.chooseBetterAutoDetectTranscript(
            primary: zhRecognizedEn,
            alternate: enRefined
        )
        XCTAssertEqual(enWinner, enRefined)

        // 5. Mixed Chinese-English high-confidence under zh-CN stays zh-CN without probing
        let mixedCnEn = VoiceTranscriptCandidate(
            localeTag: "zh-CN",
            text: "帮我重构一下 VoiceInputManager 的冷启动逻辑",
            averageConfidence: 0.89,
            hasPopulatedConfidence: true
        )
        XCTAssertFalse(
            VoiceLocaleResolver.shouldProbeAlternateLocale(
                primary: mixedCnEn,
                alternateLocaleTag: "en-US",
                activeSpeechDurationMs: 2400,
                isFinal: true
            )
        )

        // 6. Text script inference handles CJK, English, Japanese, Korean, and neutral short strings
        XCTAssertEqual(VoiceLocaleResolver.inferLocaleTag(fromText: "帮我修一下 bug"), "zh-CN")
        XCTAssertEqual(VoiceLocaleResolver.inferLocaleTag(fromText: "Fix the timeout in relay client"), "en-US")
        XCTAssertEqual(VoiceLocaleResolver.inferLocaleTag(fromText: "こんにちは世界"), "ja-JP")
        XCTAssertEqual(VoiceLocaleResolver.inferLocaleTag(fromText: "안녕하세요 테스트"), "ko-KR")
        XCTAssertNil(VoiceLocaleResolver.inferLocaleTag(fromText: "ok"))
    }
}
