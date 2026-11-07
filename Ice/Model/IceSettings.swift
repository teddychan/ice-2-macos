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

// MARK: Items

extension IceSettings {
    /// Adds newly discovered items to the end of the order (they start as Show) and records
    /// each app's current name.
    mutating func merge(discovered: [MenuBarItem]) {
        var known = Set(order)
        for item in discovered {
            if known.insert(item.id).inserted {
                order.append(item.id)
            }
            if item.bundleIdentifier != nil, !item.name.isEmpty, names[item.id] != item.name {
                names[item.id] = item.name
            }
        }
    }

    /// The items Settings lists, in order: everything on screen now, plus hidden items whose
    /// app isn't running so they can still be shown again. A shown app that quit drops out of
    /// the list but keeps its place in the order for when it returns.
    func listedItems(discovered: [MenuBarItem]) -> [MenuBarItem] {
        let present = Dictionary(discovered.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return order.compactMap { id in
            if let item = present[id] {
                return item
            }
            guard hidden.contains(id) else {
                return nil
            }
            return MenuBarItem(id: id, name: names[id] ?? "")
        }
    }

    func isHidden(_ id: String) -> Bool {
        hidden.contains(id)
    }

    mutating func setHidden(_ isHidden: Bool, for id: String) {
        if isHidden {
            hidden.insert(id)
        } else {
            hidden.remove(id)
        }
    }
}
