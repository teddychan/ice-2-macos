//
//  LocalizedTextSupport.swift
//  IceTests
//

import DragonKit
import Foundation
import Testing
@testable import Ice_2

/// Runs `body` with the app pinned to English, then restores the previous selection.
///
/// Every display string in Ice 2 now resolves through DragonKit's `L(_:)`, which reads
/// ``LocalizationManager``. Its default is `.system`, i.e. `Bundle.main.preferredLocalizations`
/// — and the test host is a real `.app` shipping all eight locales, so the tests that pin exact
/// wording would return Spanish on a Spanish Mac and fail there while passing on every English
/// machine and on CI. That is a test whose result depends on who runs it, which is worse than no
/// test: it reports green everywhere it is normally run.
///
/// Pinning is deliberate rather than asserting language-independently (say, that each case
/// merely resolves to something non-empty). The assertions exist to pin the *English copy* a
/// user reads; the seven translations are checked structurally instead, by
/// `LocalizationCoverageTests`.
@MainActor
func withEnglish<T>(_ body: () throws -> T) rethrows -> T {
    let previous = LocalizationManager.shared.language
    LocalizationManager.shared.setLanguage(.en)
    defer { LocalizationManager.shared.setLanguage(previous) }
    return try body()
}

/// Structural checks over the eight shipped `Localizable.strings` tables.
///
/// These are the invariants that break silently. A key added to `en.lproj` and nowhere else
/// still compiles, still passes every other test, and renders the raw key — `app.general.width`
/// — to any user not running in English. A `%@` dropped from one translation of a string used
/// with `String(format:)` is worse: `String(format:)` reads arguments positionally off the
/// stack, so a mismatched specifier list is a crash or garbage in that language only.
///
/// Read from the built bundle rather than the source tree, so this also proves the resources
/// were actually copied in — the `.lproj` folders reach the app through the Xcode file-system
/// synchronized group, with nothing in `project.pbxproj` naming them individually.
@MainActor
struct LocalizationCoverageTests {
    /// Every language Ice 2 ships, which §R13 requires to equal what `LanguagePicker` offers.
    private static let shipped = DragonLanguage.selectable

    private func table(_ language: DragonLanguage) throws -> [String: String] {
        let code = try #require(language.localeCode)
        let path = try #require(
            Bundle.main.path(forResource: code, ofType: "lproj"),
            "no \(code).lproj in the built app — the resource never got copied"
        )
        let bundle = try #require(Bundle(path: path))
        let url = try #require(bundle.url(forResource: "Localizable", withExtension: "strings"))
        let raw = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: raw, format: nil)
        return try #require(plist as? [String: String])
    }

    @Test func shipsEveryLanguageTheKitOffers() throws {
        // The app-side half of §R13: the picker is constructed bare, so it offers
        // `DragonLanguage.selectable`, and every one of those has to be on disk.
        #expect(Self.shipped.count == 8)
        for language in Self.shipped {
            #expect(throws: Never.self) { try table(language) }
        }
    }

    @Test func everyTranslationDefinesExactlyTheEnglishKeys() throws {
        let english = Set(try table(.en).keys)
        #expect(!english.isEmpty)
        for language in Self.shipped where language != .en {
            let keys = Set(try table(language).keys)
            // Asserted as two empty diffs rather than `keys == english`: a set-equality
            // failure prints both 213-key sets, ~10 KB of noise around the one key that
            // actually differs.
            #expect(english.subtracting(keys).sorted() == [],
                    "\(language.rawValue) is missing keys that en defines")
            #expect(keys.subtracting(english).sorted() == [],
                    "\(language.rawValue) defines keys en does not")
        }
    }

    /// The `String(format:)` specifiers in `value`, in order, each spelled exactly as written.
    ///
    /// Matches the whole grammar, `%` [`n$`] [flags] [width] [`.`precision] [length] conversion,
    /// because any part the pattern has no room for makes that specifier invisible, and an
    /// invisible specifier compares `[]` to `[]` and passes. That is how `%ld` went unchecked
    /// until the length modifier was added. `%%` is matched so the `%d` in `100%%d` is not read
    /// as a specifier, and so a translation that turns `%%` into a bare `%` fails. The space flag
    /// is left out on purpose: with it, the `% o` in "50% off" would read as an octal conversion.
    static func formatSpecifiers(in value: String) -> [String] {
        let pattern = #/%%|%(?:\d+\$)?[-+#0']*(?:\d+|\*)?(?:\.(?:\d+|\*)?)?(?:hh|ll|[hlqLzjt])?[@dDiuUoOxXfFeEgGaAcCsSp]/#
        return value.matches(of: pattern).map { String($0.0) }
    }

    @Test func formatSpecifierPatternReadsEveryPartOfTheGrammar() {
        #expect(Self.formatSpecifiers(in: "%@ has %d") == ["%@", "%d"])
        #expect(Self.formatSpecifiers(in: "%1$@ has %2$ld") == ["%1$@", "%2$ld"])
        // Length modifiers. `%u` and `%lu` are the unsigned twins of `%d` and `%ld`: 32-bit
        // `UInt32` and 64-bit `UInt`. They differ from each other as much as `%d` and `%ld` do.
        #expect(Self.formatSpecifiers(in: "%lld %hhd %hd %qd %zd %jd %td")
                == ["%lld", "%hhd", "%hd", "%qd", "%zd", "%jd", "%td"])
        #expect(Self.formatSpecifiers(in: "%u %lu %i %x %X %o %c %C %S %p %e %g %a")
                == ["%u", "%lu", "%i", "%x", "%X", "%o", "%c", "%C", "%S", "%p", "%e", "%g", "%a"])
        // Flags, width and precision, including `*`, which consumes an argument of its own.
        #expect(Self.formatSpecifiers(in: "%.1f %02d %-8@ %+d %#x %*d %.*f %1$5.2f")
                == ["%.1f", "%02d", "%-8@", "%+d", "%#x", "%*d", "%.*f", "%1$5.2f"])
        #expect(Self.formatSpecifiers(in: "100%% of %d") == ["%%", "%d"])
        #expect(Self.formatSpecifiers(in: "100%%d") == ["%%"])
        #expect(Self.formatSpecifiers(in: "50% off, up to 100%").isEmpty)
    }

    @Test func formatSpecifiersMatchEnglishInEveryTranslation() throws {
        // Order matters as well as multiset: `%1$d visible, %2$d hidden` reorders safely only
        // because the positional forms are preserved, and a bare `%d`/`%@` swap changes how
        // `String(format:)` interprets the argument.
        let english = try table(.en)
        for language in Self.shipped where language != .en {
            let translated = try table(language)
            for (key, source) in english {
                let want = Self.formatSpecifiers(in: source)
                let got = Self.formatSpecifiers(in: translated[key] ?? "")
                #expect(want == got, "\(language.rawValue) \(key): expected \(want), got \(got)")
            }
        }
    }

    @Test func switchingLanguageTakesEffectWithoutARelaunch() {
        // The point of routing every string through `L(_:)` instead of `LocalizedStringKey`.
        // A `LocalizedStringKey` resolves against `Bundle.main.preferredLocalizations`, which
        // the process reads once at launch — so the picker could only ever have taken effect
        // on the next run. `L(_:)` re-resolves against `LocalizationManager` on each call, and
        // `.dragonLocalized()` on the two window roots rebuilds the tree when it changes.
        //
        // Synchronous and main-actor-isolated on purpose: `withEnglish` elsewhere mutates the
        // same shared singleton, and with no suspension point inside, neither block can be
        // interleaved with the other.
        let previous = LocalizationManager.shared.language
        defer { LocalizationManager.shared.setLanguage(previous) }

        var seen: [DragonLanguage: String] = [:]
        for language in Self.shipped {
            LocalizationManager.shared.setLanguage(language)
            // One app-owned string and one DragonKit-owned string: the settings window renders
            // both, so both have to follow the selection or the pane comes out half-translated.
            seen[language] = L("app.general.launchAtLogin") + "|" + L("DragonKit.pane.about")
        }

        #expect(seen[.en] == "Launch at login|About")
        #expect(seen[.ja] == "ログイン時に起動|情報")
        // Every language resolves to something distinct — a table that failed to load would
        // fall back to the key and collapse all eight onto the same value.
        #expect(Set(seen.values).count == Self.shipped.count)
        for (language, value) in seen {
            #expect(!value.contains("app."), "\(language.rawValue) left a key unresolved")
            #expect(!value.contains("DragonKit."), "\(language.rawValue) left a kit key unresolved")
        }
    }

    @Test func errorAlertsFollowTheChosenLanguage() {
        // `NSAlert(error:)` and `LocalizedErrorWrapper` read the nonisolated `LocalizedError`
        // properties, which `L(_:)` cannot be called from directly. Until #132 they were English
        // literals, so a failed profile apply, spacing relaunch or item move showed an English
        // alert in every language. `localizedErrorText(_:)` routes them through `L(_:)`.
        let previous = LocalizationManager.shared.language
        defer { LocalizationManager.shared.setLanguage(previous) }
        let error = MenuBarLayoutProfilesSettings.ApplyError.missingAppState

        LocalizationManager.shared.setLanguage(.en)
        #expect(error.errorDescription == "Ice 2 is not ready to apply layout profiles.")
        LocalizationManager.shared.setLanguage(.ru)
        #expect(error.errorDescription == "Ice 2 пока не может применять профили расположения.")
        #expect(
            String(format: localizedErrorText("app.error.moveItem.itemNotMovable"), "Wi-Fi")
                == "«Wi-Fi» нельзя переместить"
        )
    }

    @Test func noTranslationClaimsAKitOwnedKey() throws {
        // The app-side half of §R8. `L(_:)` resolves DragonKit's module bundle first, so a
        // `DragonKit.` key here could never win — it would be dead weight that reads as
        // authoritative, which is exactly how the shared menu casing drifted before.
        for language in Self.shipped {
            let offenders = try table(language).keys.filter { $0.hasPrefix("DragonKit.") }
            #expect(offenders.sorted().isEmpty, "\(language.rawValue) defines kit-owned keys")
        }
    }
}
