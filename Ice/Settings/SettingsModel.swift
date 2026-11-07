//
//  SettingsModel.swift
//  Ice
//

import DragonKit
import Foundation

/// The observable owner of ``IceSettings``: every change is saved to the settings suite and its
/// side effect applied.
@MainActor
@Observable
final class SettingsModel {
    /// A dedicated suite, distinct from the app's own defaults domain, so a backup holds the
    /// settings and nothing else.
    nonisolated static var suiteName: String { Constants.bundleIdentifier + ".settings" }

    @ObservationIgnored private let store: DragonSettingsStore<IceSettings>

    private(set) var settings: IceSettings {
        didSet {
            guard settings != oldValue else {
                return
            }
            store.save(settings)
            if settings.hidden != oldValue.hidden {
                onHiddenChange()
            }
        }
    }

    /// The items on screen at the last discovery. Not saved.
    private(set) var discovered: [MenuBarItem] = []

    /// Called when the hidden set changes, so the menu bar follows.
    @ObservationIgnored var onHiddenChange: () -> Void = {}

    init(suiteName: String = SettingsModel.suiteName) {
        let store = DragonSettingsStore(suiteName: suiteName, defaultValue: IceSettings())
        self.store = store
        self.settings = store.load()
    }

    /// Applies the stored login item preference to the system, so a restored backup or a
    /// login item removed in System Settings comes back in line.
    func reconcileLoginItem() {
        if LoginItem.isEnabled != settings.launchAtLogin {
            LoginItem.setEnabled(settings.launchAtLogin)
        }
    }

    /// Records the items discovered on screen; new ones join the order as shown.
    func update(discovered items: [MenuBarItem]) {
        discovered = items
        settings.merge(discovered: items)
    }

    /// The items Settings lists, in order.
    var listedItems: [MenuBarItem] {
        settings.listedItems(discovered: discovered)
    }

    func isHidden(_ item: MenuBarItem) -> Bool {
        settings.isHidden(item.id)
    }

    func setHidden(_ isHidden: Bool, for item: MenuBarItem) {
        settings.setHidden(isHidden, for: item.id)
    }

    var launchAtLogin: Bool {
        get { settings.launchAtLogin }
        set {
            settings.launchAtLogin = newValue
            LoginItem.setEnabled(newValue)
        }
    }
}
