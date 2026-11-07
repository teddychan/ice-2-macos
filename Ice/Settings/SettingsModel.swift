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
        }
    }

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

    var launchAtLogin: Bool {
        get { settings.launchAtLogin }
        set {
            settings.launchAtLogin = newValue
            LoginItem.setEnabled(newValue)
        }
    }
}
