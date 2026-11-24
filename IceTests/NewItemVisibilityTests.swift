//
//  NewItemVisibilityTests.swift
//  Ice
//

import DragonKit
import Foundation
import Testing
@testable import Ice_2

@MainActor
struct NewItemVisibilityTests {
    @Test func storedDefaultHidesOnlyNewItems() {
        let (defaults, suite) = ScratchDefaults.make(label: "NewItems")
        defer { ScratchDefaults.destroy(suite) }
        defaults.set(Data(#"{"hideNewItems":true,"hidden":["system:1"],"order":["system:1","system:6"]}"#.utf8), forKey: "settings.v1")
        let store = DragonSettingsStore(suiteName: suite, defaultValue: IceSettings())
        var settings = store.load()
        let wifi = MenuBarItem(id: "system:6", name: "Wi-Fi")!
        let app = MenuBarItem(id: "bundle:com.example.new", name: "New")!

        settings.merge(discovered: [wifi, app])

        #expect(settings.hidden == ["system:1", app.id])
        settings.setHidden(false, for: app.id)
        store.save(settings)
        var restored = store.load()
        restored.merge(discovered: [])
        restored.merge(discovered: [app, wifi, MenuBarItem(id: "system:0", name: "Battery")!])
        #expect(restored.hidden == ["system:1", "system:0"])
    }

    @Test func oldSettingsKeepTheirChoicesAndShowNewItems() {
        let (defaults, suite) = ScratchDefaults.make(label: "OldSettings")
        defer { ScratchDefaults.destroy(suite) }
        defaults.set(Data(#"{"launchAtLogin":true,"showInMenuBar":false,"hidden":["system:6"],"order":["system:6"],"names":{},"language":"zh-Hans"}"#.utf8), forKey: "settings.v1")
        var settings = DragonSettingsStore(suiteName: suite, defaultValue: IceSettings()).load()
        settings.merge(discovered: [MenuBarItem(id: "system:1", name: "Bluetooth")!])
        #expect(settings.launchAtLogin)
        #expect(!settings.showInMenuBar)
        #expect(settings.language == "zh-Hans")
        #expect(settings.hidden == ["system:6"])
        #expect(settings.order == ["system:6", "system:1"])
    }

    @Test func newItemDefaultIsSavedAndOnlyDiscoveryChangesVisibility() {
        let (_, suite) = ScratchDefaults.make(label: "NewItemDefault")
        defer { ScratchDefaults.destroy(suite) }
        let defaults = UserDefaults(suiteName: suite)!
        let model = SettingsModel(suiteName: suite, legacyDefaults: defaults)
        let wifi = MenuBarItem(id: "system:6", name: "Wi-Fi")!
        let bluetooth = MenuBarItem(id: "system:1", name: "Bluetooth")!
        model.update(discovered: [wifi])
        var changes = 0
        model.onHiddenChange = { changes += 1 }

        model.hideNewItems = true
        #expect(changes == 0)
        model.update(discovered: [wifi, bluetooth])
        #expect(!model.isHidden(wifi))
        #expect(model.isHidden(bluetooth))
        #expect(changes == 1)

        let restored = SettingsModel(suiteName: suite, legacyDefaults: defaults)
        #expect(restored.hideNewItems)
        restored.hideNewItems = false
        let battery = MenuBarItem(id: "system:0", name: "Battery")!
        restored.update(discovered: [wifi, bluetooth, battery])
        #expect(restored.isHidden(bluetooth))
        #expect(!restored.isHidden(battery))
        #expect(!SettingsModel(suiteName: suite, legacyDefaults: defaults).hideNewItems)
    }
}
