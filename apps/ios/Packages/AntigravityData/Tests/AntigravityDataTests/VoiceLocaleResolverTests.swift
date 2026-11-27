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
}
