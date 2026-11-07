//
//  LegacyMigration.swift
//  Ice
//

import Foundation

/// Carries a 2.x user's macOS 27 setup into 3.x on first launch.
///
/// 2.16 and later stored the macOS 27 sections as JSON under `NativeMenuBarSections` in the
/// app's standard defaults: `[item id: "visible" | "hidden" | "alwaysHidden"]`, with the same
/// item ids 3.x uses. Visible becomes Show; hidden and always-hidden both become Hide.
///
/// 2.x stored "Show Ice 2 icon" as a Bool under `ShowIceIcon`, in the same
/// defaults; it becomes "Show in menu bar". Every other 2.x setting is left behind, and 2.x's
/// defaults are never modified.
enum LegacyMigration {
    /// The 2.x defaults key holding the macOS 27 sections.
    static let nativeSectionsKey = "NativeMenuBarSections"

    /// The 2.x defaults key holding "Show Ice 2 icon".
    static let showIceIconKey = "ShowIceIcon"

    /// 2.x's "Show Ice 2 icon", or nil when 2.x never saved one.
    static func showIceIcon(in defaults: UserDefaults) -> Bool? {
        defaults.object(forKey: showIceIconKey) as? Bool
    }

    /// 3.x settings for a 2.x `NativeMenuBarSections` value and "Show Ice 2 icon", or nil when
    /// there is nothing to carry over.
    static func settings(fromNativeSections data: Data?, showIceIcon: Bool? = nil) -> IceSettings? {
        var settings = sectionSettings(from: data)
        if showIceIcon == false {
            settings = settings ?? IceSettings()
            settings?.showInMenuBar = false
        }
        return settings
    }

    private static func sectionSettings(from data: Data?) -> IceSettings? {
        guard
            let data,
            let sections = try? JSONDecoder().decode([String: String].self, from: data)
        else {
            return nil
        }
        var hidden = [String]()
        var shown = [String]()
        for (id, section) in sections where MenuBarItem(id: id, name: "") != nil {
            switch section {
            case "visible": shown.append(id)
            case "hidden", "alwaysHidden": hidden.append(id)
            default: continue
            }
        }
        guard !hidden.isEmpty || !shown.isEmpty else {
            return nil
        }
        var settings = IceSettings()
        settings.hidden = Set(hidden)
        // 2.x saved no order: hidden items first, each group sorted by id to stay stable.
        settings.order = hidden.sorted() + shown.sorted()
        return settings
    }
}
