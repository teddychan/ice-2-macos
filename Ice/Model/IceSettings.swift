//
//  IceSettings.swift
//  Ice
//

import Foundation

/// Every setting Ice 2 has, stored as one value in a `DragonSettingsStore` suite so that
/// Backup & Restore captures all of it.
struct IceSettings: Codable, Equatable, Sendable {
    /// Whether Ice opens at login. Applied to the system login item on launch and on change.
    var launchAtLogin = false

    /// The ids of hidden items (see ``MenuBarItem/id``). Every other item is shown.
    var hidden: Set<String> = []

    /// One order of item ids, shared by the Ice Bar and the Settings list.
    var order: [String] = []

    /// The last name seen for each item, so an app that isn't running stays readable.
    var names: [String: String] = [:]
}
