//
//  LegacyMigrationTests.swift
//  IceTests
//

import Foundation
import Testing
@testable import Ice_2

/// Upgrading from 2.x on macOS 27 keeps the user's setup: 2.x's `NativeMenuBarSections` maps
/// visible to Show and hidden or always-hidden to Hide. Nothing else from 2.x carries over.
struct LegacyMigrationTests {
    private func data(_ sections: [String: String]) -> Data {
        try! JSONEncoder().encode(sections)
    }

    @Test func visibleIsShownAndBothHiddenSectionsAreHidden() throws {
        let settings = try #require(LegacyMigration.settings(fromNativeSections: data([
            "bundle:com.getdropbox.dropbox": "hidden",
            "bundle:eu.exelban.Stats": "alwaysHidden",
            "system:6": "visible",
        ])))
        #expect(settings.hidden == ["bundle:com.getdropbox.dropbox", "bundle:eu.exelban.Stats"])
        #expect(!settings.isHidden("system:6"))
    }

    @Test func hiddenItemsComeFirstInTheOrder() throws {
        let settings = try #require(LegacyMigration.settings(fromNativeSections: data([
            "system:6": "visible",
            "bundle:com.getdropbox.dropbox": "hidden",
            "bundle:com.apple.TextInputMenuAgent": "visible",
            "bundle:eu.exelban.Stats": "alwaysHidden",
        ])))
        // 2.x saved no order, so each group is sorted by id to keep the result stable.
        #expect(settings.order == [
            "bundle:com.getdropbox.dropbox", "bundle:eu.exelban.Stats",
            "bundle:com.apple.TextInputMenuAgent", "system:6",
        ])
    }

    @Test func entriesThatAreNotItemsAreDropped() throws {
        let settings = try #require(LegacyMigration.settings(fromNativeSections: data([
            "bundle:com.getdropbox.dropbox": "hidden",
            "system:2": "hidden",
            "unmanaged:com.apple.menuextra.focusmode": "hidden",
            "bundle:com.dragonapp.ice": "hidden",
            "bundle:eu.exelban.Stats": "somewhere",
        ])))
        #expect(settings.hidden == ["bundle:com.getdropbox.dropbox"])
        #expect(settings.order == ["bundle:com.getdropbox.dropbox"])
    }

    @Test func nothingToMigrateGivesNoSettings() {
        #expect(LegacyMigration.settings(fromNativeSections: nil) == nil)
        #expect(LegacyMigration.settings(fromNativeSections: Data("not json".utf8)) == nil)
        #expect(LegacyMigration.settings(fromNativeSections: data([:])) == nil)
        #expect(LegacyMigration.settings(fromNativeSections: data(["system:2": "hidden"])) == nil)
    }
}

/// The model runs the migration once: on a first 3.x launch with no 3.x settings.
@MainActor
struct FirstLaunchMigrationTests {
    @Test func aFirstLaunchStartsFromThe2xSetupAndSavesIt() throws {
        let (legacy, legacySuite) = ScratchDefaults.make(label: "Legacy")
        let (_, suite) = ScratchDefaults.make(label: "Settings")
        defer { ScratchDefaults.destroy(legacySuite); ScratchDefaults.destroy(suite) }
        legacy.set(try JSONEncoder().encode(["bundle:com.getdropbox.dropbox": "hidden"]), forKey: "NativeMenuBarSections")

        let model = SettingsModel(suiteName: suite, legacyDefaults: legacy)

        #expect(model.settings.hidden == ["bundle:com.getdropbox.dropbox"])
        #expect(SettingsModel(suiteName: suite, legacyDefaults: UserDefaults(suiteName: suite)!).settings.hidden
            == ["bundle:com.getdropbox.dropbox"], "the migrated settings were saved")
        #expect(legacy.data(forKey: "NativeMenuBarSections") != nil, "2.x defaults are left alone")
    }

    @Test func existing3xSettingsAreNeverOverwritten() throws {
        let (legacy, legacySuite) = ScratchDefaults.make(label: "Legacy")
        let (defaults, suite) = ScratchDefaults.make(label: "Settings")
        defer { ScratchDefaults.destroy(legacySuite); ScratchDefaults.destroy(suite) }
        legacy.set(try JSONEncoder().encode(["bundle:com.getdropbox.dropbox": "hidden"]), forKey: "NativeMenuBarSections")
        defaults.set(Data(#"{"hidden":["system:6"]}"#.utf8), forKey: "settings.v1")

        let model = SettingsModel(suiteName: suite, legacyDefaults: legacy)

        #expect(model.settings.hidden == ["system:6"])
    }
}
