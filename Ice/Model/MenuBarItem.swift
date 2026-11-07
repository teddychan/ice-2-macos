//
//  MenuBarItem.swift
//  Ice
//

import Foundation

/// One entry in the menu bar that Ice can hide.
///
/// macOS 27's assessment mode filters by process, so an item is a whole app (all of its icons
/// share one setting) or one of the system items assessment mode can hide on its own. The clock,
/// Control Center, MenuBarAgent and Ice itself are never items.
struct MenuBarItem: Identifiable, Equatable, Hashable, Sendable {
    /// `bundle:<bundle id>` for an app, `system:<n>` for a system item.
    let id: String
    /// The app's name as last seen. System items show ``systemNameKey`` instead.
    let name: String

    /// The assessment-mode numbers of the system items, in their order. 2 (Clock) and
    /// 8 (Control Center) can't be hidden independently, so they are never items.
    static let systemKeys = [
        0: "battery", 1: "bluetooth", 3: "displays", 4: "keyboard",
        5: "sound", 6: "wifi", 7: "screenMirroring",
    ]

    /// MenuBarAgent identifier suffixes (`com.apple.menuextra.<suffix>`) for each number.
    static let systemIdentifierSuffixes = [
        "battery": 0, "bluetooth": 1, "display": 3, "displays": 3, "keyboard": 4,
        "sound": 5, "volume": 5, "wifi": 6, "screen-mirroring": 7, "screenmirroring": 7,
    ]

    /// An item from a MenuBarAgent snapshot row: an owning app's bundle id, or a system
    /// extra's accessibility identifier.
    init?(bundle: String?, identifier: String?, name: String) {
        if let bundle {
            guard Self.canHide(bundle: bundle) else {
                return nil
            }
            self.init(uncheckedID: "bundle:\(bundle)", name: name)
            return
        }
        guard
            let identifier,
            identifier.hasPrefix("com.apple.menuextra."),
            let number = Self.systemIdentifierSuffixes[
                String(identifier.dropFirst("com.apple.menuextra.".count)).lowercased()
            ]
        else {
            return nil
        }
        self.init(uncheckedID: "system:\(number)", name: name)
    }

    /// The item a stored id names, or nil when the id names nothing Ice can hide.
    init?(id: String, name: String) {
        if id.hasPrefix("bundle:") {
            self.init(bundle: String(id.dropFirst(7)), identifier: nil, name: name)
        } else if id.hasPrefix("system:"), let number = Int(id.dropFirst(7)), Self.systemKeys[number] != nil {
            self.init(uncheckedID: id, name: name)
        } else {
            return nil
        }
    }

    private init(uncheckedID id: String, name: String) {
        self.id = id
        self.name = name
    }

    private static func canHide(bundle: String) -> Bool {
        !bundle.isEmpty && !Constants.isIceBundleID(bundle) && bundle != "com.apple.MenuBarAgent"
    }

    var bundleIdentifier: String? {
        id.hasPrefix("bundle:") ? String(id.dropFirst(7)) : nil
    }

    var systemNumber: Int? {
        id.hasPrefix("system:") ? Int(id.dropFirst(7)) : nil
    }

    /// The localization key of a system item's name (`app.system.<key>`).
    var systemNameKey: String? {
        systemNumber.flatMap { Self.systemKeys[$0] }.map { "app.system.\($0)" }
    }

    /// The SF Symbol drawn for a system item, which has no app icon.
    var systemSymbol: String {
        switch systemNumber {
        case 0: "battery.100percent"
        case 1: "wave.3.right"
        case 3: "display"
        case 4: "keyboard"
        case 5: "speaker.wave.2.fill"
        case 6: "wifi"
        case 7: "rectangle.on.rectangle"
        default: "menubar.rectangle"
        }
    }

    /// The MenuBarAgent identifiers that belong to this system item, for finding it again.
    var systemIdentifiers: [String] {
        guard let number = systemNumber else {
            return []
        }
        return Self.systemIdentifierSuffixes.filter { $0.value == number }.keys.sorted()
            .map { "com.apple.menuextra.\($0)" }
    }
}
