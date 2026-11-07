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

    @Test func settingsRoundTripThroughTheStore() {
        let (_, suite) = ScratchDefaults.make(label: "IceSettings")
        defer { ScratchDefaults.destroy(suite) }
        let store = DragonSettingsStore(suiteName: suite, defaultValue: IceSettings())
        var settings = IceSettings()
        settings.hidden = ["bundle:com.getdropbox.dropbox", "system:1"]
        settings.order = ["bundle:com.getdropbox.dropbox", "system:1", "system:6"]
        settings.names = ["bundle:com.getdropbox.dropbox": "Dropbox"]

        store.save(settings)

        #expect(store.load() == settings)
    }
}
