//
//  ItemListTests.swift
//  IceTests
//

import Testing
@testable import Ice_2

/// How discovered items and saved settings combine into the list Settings shows.
struct ItemListTests {
    private let dropbox = MenuBarItem(id: "bundle:com.getdropbox.dropbox", name: "Dropbox")!
    private let stats = MenuBarItem(id: "bundle:eu.exelban.Stats", name: "Stats")!
    private let wifi = MenuBarItem(id: "system:6", name: "Wi-Fi")!

    @Test func newItemsAreAppendedAndShown() {
        var settings = IceSettings()
        settings.order = [stats.id]

        settings.merge(discovered: [dropbox, stats])

        #expect(settings.order == [stats.id, dropbox.id])
        #expect(!settings.isHidden(dropbox.id))
    }

    @Test func mergeRemembersEachAppsName() {
        var settings = IceSettings()
        settings.merge(discovered: [dropbox, wifi])
        #expect(settings.names[dropbox.id] == "Dropbox")
    }

    @Test func listFollowsTheSavedOrder() {
        var settings = IceSettings()
        settings.order = [wifi.id, dropbox.id, stats.id]

        let ids = settings.listedItems(discovered: [stats, dropbox, wifi]).map(\.id)

        #expect(ids == [wifi.id, dropbox.id, stats.id])
    }

    @Test func aHiddenAppThatQuitStaysListedUnderItsLastName() {
        var settings = IceSettings()
        settings.merge(discovered: [dropbox, stats])
        settings.setHidden(true, for: dropbox.id)

        let listed = settings.listedItems(discovered: [stats])

        #expect(listed.map(\.id) == [dropbox.id, stats.id])
        #expect(listed.first?.name == "Dropbox")
    }

    @Test func aShownAppThatQuitLeavesTheListButKeepsItsPlace() {
        var settings = IceSettings()
        settings.merge(discovered: [dropbox, stats])

        #expect(settings.listedItems(discovered: [stats]).map(\.id) == [stats.id])

        settings.merge(discovered: [dropbox, stats])
        #expect(settings.order == [dropbox.id, stats.id])
    }

    @Test func idsThatNameNothingHideableAreNotListed() {
        var settings = IceSettings()
        settings.order = ["system:2", "bundle:com.dragonapp.ice", dropbox.id]
        settings.hidden = ["system:2", "bundle:com.dragonapp.ice"]

        #expect(settings.listedItems(discovered: [dropbox]).map(\.id) == [dropbox.id])
    }

    @Test func showingAnItemAgainClearsItFromHidden() {
        var settings = IceSettings()
        settings.setHidden(true, for: wifi.id)
        #expect(settings.isHidden(wifi.id))
        settings.setHidden(false, for: wifi.id)
        #expect(!settings.isHidden(wifi.id))
        #expect(settings.hidden.isEmpty)
    }

    @MainActor
    @Test func removingAnAbsentAppForgetsItsSavedStateAndAllowsAFreshReturn() {
        let (defaults, suite) = ScratchDefaults.make(label: "RemoveItem")
        defer { ScratchDefaults.destroy(suite) }
        let model = SettingsModel(suiteName: suite, legacyDefaults: defaults)
        model.update(discovered: [dropbox, stats, wifi])
        model.setHidden(true, for: dropbox)
        model.setHidden(true, for: stats)
        model.update(discovered: [stats, wifi])
        #expect(model.listedItems.map(\.id) == [dropbox.id, stats.id, wifi.id])
        var hiddenChanges = 0
        model.onHiddenChange = { hiddenChanges += 1 }

        model.remove(dropbox)
        model.remove(dropbox)

        #expect(model.listedItems.map(\.id) == [stats.id, wifi.id])
        #expect(model.settings.hidden == [stats.id])
        #expect(model.settings.order == [stats.id, wifi.id])
        #expect(model.settings.names == [stats.id: stats.name])
        #expect(hiddenChanges == 1, "removing a hidden app updates hiding once")
        let reloaded = SettingsModel(suiteName: suite, legacyDefaults: defaults)
        #expect(reloaded.settings == model.settings, "the removed record stays gone after relaunch")

        reloaded.update(discovered: [dropbox, stats, wifi])

        #expect(!reloaded.isHidden(dropbox), "a rediscovered app starts as Show")
        #expect(reloaded.settings.order == [stats.id, wifi.id, dropbox.id])
        #expect(reloaded.settings.names[dropbox.id] == dropbox.name)
    }

    @Test func theIceBarLeavesOutHiddenAppsThatAreNotRunning() {
        var settings = IceSettings()
        settings.merge(discovered: [dropbox, stats, wifi])
        settings.setHidden(true, for: dropbox.id)
        settings.setHidden(true, for: stats.id)
        settings.setHidden(true, for: wifi.id)

        // Hidden items are absent from MenuBarAgent's tree, so "running" is the only sign an
        // app still has an item to open. System items are always there.
        let ids = settings.iceBarItems(discovered: [], runningBundles: ["eu.exelban.Stats"]).map(\.id)

        #expect(ids == [stats.id, wifi.id])
    }
}
