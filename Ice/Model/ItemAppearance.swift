//
//  ItemAppearance.swift
//  Ice
//

import AppKit
import DragonKit

/// How an item is drawn: the app's own icon and name, or a symbol and localized name for a
/// system item. macOS 27 offers no reliable per-icon image of the menu bar, so Ice shows the
/// app icon instead.
@MainActor
enum ItemAppearance {
    private static var icons = [String: NSImage]()

    static func icon(for item: MenuBarItem) -> NSImage {
        if let cached = icons[item.id] {
            return cached
        }
        let image: NSImage
        if let bundle = item.bundleIdentifier, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) {
            image = NSWorkspace.shared.icon(forFile: url.path)
        } else {
            image = NSImage(systemSymbolName: item.systemSymbol, accessibilityDescription: nil) ?? NSImage()
            image.isTemplate = true
        }
        icons[item.id] = image
        return image
    }

    /// Apple background agents whose process names mean nothing to a person.
    private static let agentNameKeys = [
        "com.apple.TextInputMenuAgent": "app.system.inputMenu",
        "com.apple.SSMenuAgent": "app.system.screenSharing",
    ]

    static func name(for item: MenuBarItem) -> String {
        if let key = item.systemNameKey ?? item.bundleIdentifier.flatMap({ agentNameKeys[$0] }) {
            return L(key)
        }
        if !item.name.isEmpty {
            return item.name
        }
        // An app seen before Ice recorded its name (for example after an upgrade from 2.x).
        if let bundle = item.bundleIdentifier, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) {
            return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        }
        return item.bundleIdentifier ?? item.id
    }
}
