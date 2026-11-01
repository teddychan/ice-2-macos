//
//  NativeMenuBarPolicy.swift
//  Ice
//

import Foundation

/// Native identities deliberately never masquerade as CGWindowIDs.
struct NativeMenuBarItem: Identifiable, Equatable, Sendable {
    let id: String
    let name: String

    var fallbackSymbol: String {
        switch id {
        case "system:0": "battery.100percent"
        case "system:1": "antenna.radiowaves.left.and.right"
        case "system:3": "display"
        case "system:4": "keyboard"
        case "system:5": "speaker.wave.2"
        case "system:6": "wifi"
        case "system:7": "rectangle.on.rectangle"
        case NativeMenuBarPolicy.systemUIServerID: "network.badge.shield.half.filled"
        default: "menubar.rectangle"
        }
    }

    var canAssign: Bool {
        if id.hasPrefix("bundle:") {
            let bundle = String(id.dropFirst(7))
            return !bundle.isEmpty && !NativeMenuBarPolicy.ownBundles.contains(bundle)
                && bundle != "com.apple.MenuBarAgent"
        }
        guard id.hasPrefix("system:"), let number = Int(id.dropFirst(7)) else { return false }
        return (0...8).contains(number) && number != 2 && number != 8
    }
}

enum NativeMenuBarPolicy {
    static let ownBundles: Set<String> = ["com.dragonapp.ice", "com.dragonapp.ice.debug"]
    /// SystemUIServer still hosts legacy extras such as VPN. Assessment mode filters
    /// by process, so its extras can only be shown or hidden together, as one item.
    static let systemUIServerBundle = "com.apple.systemuiserver"
    static let systemUIServerID = "bundle:\(systemUIServerBundle)"
    static let systemNames = ["Battery", "Bluetooth", "Clock", "Displays", "Keyboard", "Sound", "Wi-Fi", "Screen Mirroring", "Control Center"]
    static let inputMenuBundle = "com.apple.TextInputMenuAgent"

    /// Informational entries, including when assessment mode removes their AX nodes.
    /// They have no supported assessment ID and must never become assignable.
    static let unmanagedSystemControls: [(item: NativeMenuBarItem, nameKey: String)] = [
        (.init(id: "unmanaged:com.apple.menuextra.now-playing", name: "Now Playing"), "app.native.system.nowPlaying"),
        (.init(id: "unmanaged:com.apple.menuextra.focusmode", name: "Focus"), "app.native.system.focus"),
        (.init(id: "unmanaged:com.apple.menuextra.airdrop", name: "AirDrop"), "app.native.system.airDrop"),
        (.init(id: "unmanaged:com.apple.menuextra.user", name: "Fast User Switching"), "app.native.system.userSwitching"),
    ]

    private static func id(forSystemIdentifier identifier: String) -> String? {
        let normalized = identifier.lowercased()
        let prefix = "com.apple.menuextra."
        let suffix = normalized.hasPrefix(prefix) ? String(normalized.dropFirst(prefix.count)) : normalized
        if suffix == "textinput" {
            return "bundle:\(inputMenuBundle)"
        }
        let number = [
            "battery": 0, "bluetooth": 1, "clock": 2, "display": 3, "displays": 3,
            "keyboard": 4, "sound": 5, "volume": 5, "wifi": 6,
            "screen-mirroring": 7, "screenmirroring": 7, "controlcenter": 8,
        ][suffix]
        return number.map { "system:\($0)" }
    }

    static func item(bundle: String?, identifier: String?, name: String) -> NativeMenuBarItem? {
        if let bundle {
            guard !ownBundles.contains(bundle) else { return nil }
            if bundle == "com.apple.MenuBarAgent" {
                return NativeMenuBarItem(id: "unmanaged:\(bundle)", name: name)
            }
            return NativeMenuBarItem(id: "bundle:\(bundle)", name: name)
        }
        guard let identifier else { return nil }
        if let id = id(forSystemIdentifier: identifier) {
            let number = id.hasPrefix("system:") ? Int(id.dropFirst(7)) : nil
            return NativeMenuBarItem(id: id, name: number.map { systemNames[$0] } ?? "Input Menu")
        }
        let unmanagedID = "unmanaged:\(identifier)"
        if let control = unmanagedSystemControls.first(where: { $0.item.id.caseInsensitiveCompare(unmanagedID) == .orderedSame }) {
            return control.item
        }
        return NativeMenuBarItem(id: unmanagedID, name: name)
    }

    static func shouldHide(_ section: MenuBarSection.Name, hiddenShown: Bool, alwaysHiddenShown: Bool, alwaysHiddenEnabled: Bool) -> Bool {
        switch section {
        case .visible: false
        case .hidden: !hiddenShown
        case .alwaysHidden: alwaysHiddenEnabled && !alwaysHiddenShown
        }
    }

    struct Configuration: Equatable {
        let bundles: [String]
        let systemItems: [Int]
    }

    static func configuration(
        assignments: [String: MenuBarSection.Name],
        runningBundles: Set<String>,
        hiddenShown: Bool,
        alwaysHiddenShown: Bool,
        alwaysHiddenEnabled: Bool
    ) -> Configuration? {
        let hiddenIDs = Set(assignments.compactMap { id, section in
            NativeMenuBarItem(id: id, name: id).canAssign && shouldHide(
                section, hiddenShown: hiddenShown, alwaysHiddenShown: alwaysHiddenShown, alwaysHiddenEnabled: alwaysHiddenEnabled
            ) ? id : nil
        })
        let hiddenBundles = Set(hiddenIDs.filter { $0.hasPrefix("bundle:") }.map { String($0.dropFirst(7)) })
            .subtracting(ownBundles)
        let systems = (0...8).filter { !hiddenIDs.contains("system:\($0)") }
        // Avoid activating assessment mode (and its collateral effects) when
        // none of the running apps or supported system items needs to be hidden.
        guard !hiddenBundles.isDisjoint(with: runningBundles) || systems.count < 9 else { return nil }
        return Configuration(bundles: runningBundles.union(ownBundles).subtracting(hiddenBundles).sorted(), systemItems: systems)
    }

    @MainActor
    static func nativeID(for tag: MenuBarItemTag) -> String? {
        guard !tag.isControlItem, !tag.isSpacerItem, case .string(let bundle) = tag.namespace,
              !ownBundles.contains(bundle) else { return nil }
        if bundle == "com.dragonapp.ice.native.system" {
            guard let number = Int(tag.title), (0...8).contains(number) else { return nil }
            return "system:\(number)"
        }
        if bundle == "com.apple.controlcenter" || bundle == "com.apple.MenuBarAgent" {
            return id(forSystemIdentifier: tag.title)
        }
        return item(bundle: bundle, identifier: nil, name: bundle).flatMap { $0.canAssign ? $0.id : nil }
    }

    @MainActor
    static func tag(for id: String) -> MenuBarItemTag? {
        if id.hasPrefix("bundle:") {
            return MenuBarItemTag(namespace: .string(String(id.dropFirst(7))), title: "Ice.Native.Bundle")
        }
        if id.hasPrefix("system:") {
            return MenuBarItemTag(namespace: .string("com.dragonapp.ice.native.system"), title: String(id.dropFirst(7)))
        }
        return nil
    }

    struct Migration {
        var assignments = [String: MenuBarSection.Name]()
        var conflicts = Set<String>()
        var unmatched = 0
    }

    @MainActor
    static func migrate(_ profile: MenuBarLayoutProfile) -> Migration {
        var result = Migration()
        // Iteration order deliberately prefers the more visible section.
        for section in MenuBarSection.Name.allCases {
            for tag in profile.itemTags(for: section) where !tag.isControlItem && !tag.isSpacerItem {
                guard let id = nativeID(for: tag), NativeMenuBarItem(id: id, name: id).canAssign else {
                    result.unmatched += 1
                    continue
                }
                if let existing = result.assignments[id], existing != section {
                    result.conflicts.insert(id)
                } else {
                    result.assignments[id] = section
                }
            }
        }
        return result
    }
}
