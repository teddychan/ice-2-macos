//
//  LanguageSettingTests.swift
//  IceTests
//

import DragonKit
import Testing
@testable import Ice_2

/// DragonKit keeps the language choice in the app's standard defaults, outside the settings
/// suite a backup holds. So Ice keeps its own copy in ``IceSettings`` and settles the two at
/// launch: a stored choice wins (a restored backup brings its language back), and with none
/// stored, the current choice (for example one made in 2.x) is adopted rather than reset.
struct LanguageSettingTests {
    @Test func aStoredLanguageIsAppliedWhenItDiffers() {
        var settings = IceSettings()
        settings.language = "fr"
        #expect(settings.settleLanguage(current: .ja) == .fr)
        #expect(settings.language == "fr")
    }

    @Test func aStoredLanguageThatIsAlreadyActiveNeedsNothing() {
        var settings = IceSettings()
        settings.language = "ja"
        #expect(settings.settleLanguage(current: .ja) == nil)
    }

    @Test func withNothingStoredTheCurrentChoiceIsAdopted() {
        var settings = IceSettings()
        #expect(settings.settleLanguage(current: .zhHant) == nil)
        #expect(settings.language == "zh-Hant")
    }

    @Test func followingTheMacStoresNothing() {
        var settings = IceSettings()
        #expect(settings.settleLanguage(current: .system) == nil)
        #expect(settings.language == nil)
    }

    @Test func anUnknownStoredLanguageIsReplacedByTheCurrentChoice() {
        var settings = IceSettings()
        settings.language = "xx"
        #expect(settings.settleLanguage(current: .ko) == nil)
        #expect(settings.language == "ko")
    }
}
