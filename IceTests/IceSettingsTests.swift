//
//  IceSettingsTests.swift
//  IceTests
//

import DragonKit
import Foundation
import Testing
@testable import Ice_2

/// ``IceSettings`` is every setting Ice has, stored as one value. A backup restored from an
/// older build holds fewer keys, so a value missing some keys must still load, keeping what it
/// has and taking defaults for the rest.
struct IceSettingsTests {
    @Test func freshSettingsShowEverythingAndDoNotLaunchAtLogin() {
        let settings = IceSettings()
        #expect(!settings.launchAtLogin)
        #expect(settings.showInMenuBar)
        #expect(settings.hidden.isEmpty)
        #expect(settings.order.isEmpty)
    }

    @Test func aStoredValueMissingKeysKeepsWhatItHas() throws {
        let (defaults, suite) = ScratchDefaults.make(label: "IceSettings")
        defer { ScratchDefaults.destroy(suite) }
        defaults.set(Data(#"{"launchAtLogin":true}"#.utf8), forKey: "settings.v1")

        let loaded = DragonSettingsStore(suiteName: suite, defaultValue: IceSettings()).load()

        #expect(loaded.launchAtLogin)
        #expect(loaded.hidden.isEmpty)
        #expect(loaded.order.isEmpty)
    }

    @Test func aStoredValueWithoutShowInMenuBarShowsTheIcon() throws {
        let (defaults, suite) = ScratchDefaults.make(label: "IceSettings")
        defer { ScratchDefaults.destroy(suite) }
        // What a 3.0.0 build before this setting saved: no `showInMenuBar` key at all.
        defaults.set(Data(#"{"launchAtLogin":false,"hidden":["system:6"],"order":["system:6"]}"#.utf8), forKey: "settings.v1")

        let loaded = DragonSettingsStore(suiteName: suite, defaultValue: IceSettings()).load()

        #expect(loaded.showInMenuBar)
        #expect(loaded.hidden == ["system:6"], "the stored keys survive the missing one")
    }

    @Test func settingsRoundTripThroughTheStore() {
        let (_, suite) = ScratchDefaults.make(label: "IceSettings")
        defer { ScratchDefaults.destroy(suite) }
        let store = DragonSettingsStore(suiteName: suite, defaultValue: IceSettings())
        var settings = IceSettings()
        settings.hidden = ["bundle:com.getdropbox.dropbox", "system:1"]
        settings.order = ["bundle:com.getdropbox.dropbox", "system:1", "system:6"]
        settings.names = ["bundle:com.getdropbox.dropbox": "Dropbox"]
        settings.showInMenuBar = false

        store.save(settings)

        #expect(store.load() == settings)
    }
}

/// "Show in menu bar" is saved like every other setting, and the Ice icon follows each change.
@MainActor
struct ShowInMenuBarTests {
    @Test func turningTheIconOffIsSavedAndReported() {
        let (_, suite) = ScratchDefaults.make(label: "Settings")
        defer { ScratchDefaults.destroy(suite) }
        let model = SettingsModel(suiteName: suite, legacyDefaults: UserDefaults(suiteName: suite)!)
        var reported = [Bool]()
        model.onShowInMenuBarChange = { reported.append(model.showInMenuBar) }

        model.showInMenuBar = false
        model.showInMenuBar = false

        #expect(reported == [false], "only a real change is reported")
        #expect(!SettingsModel(suiteName: suite, legacyDefaults: UserDefaults(suiteName: suite)!).showInMenuBar)
    }
}
