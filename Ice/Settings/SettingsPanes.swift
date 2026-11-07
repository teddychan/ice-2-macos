//
//  SettingsPanes.swift
//  Ice
//

import DragonKit
import DragonKitUpdates
import SwiftUI

/// Host-owned pane selection, so the app menu can open Settings on a given pane.
@MainActor
@Observable
final class SettingsSelection {
    var paneID: String? = GeneralPane.paneID
}

/// The Settings sidebar, in DragonKit's canonical order (CONFORMANCE §R9). This file is the
/// `paneOrder` file in `.dragon-conformance.json`.
@MainActor
enum SettingsPanes {
    static func panes(
        model: SettingsModel,
        menuBar: MenuBarController,
        updater: DragonUpdater,
        selection: SettingsSelection
    ) -> [AnySettingsPane] {
        [
            AnySettingsPane(GeneralPane(model: model, menuBar: menuBar)),
            AnySettingsPane(PermissionsSettingsPane(permissions: [.accessibility()])),
            AnySettingsPane(BackupSettingsPane(config: BackupConfig(
                appName: Constants.displayName,
                suiteName: SettingsModel.suiteName,
                appVersion: DragonAbout.versionString(),
                contents: IceSettings.backupContentKeys.map { L($0.key) },
                relaunch: relaunch
            ))),
            AnySettingsPane(WhatsNewSettingsPane(content: WhatsNewConfig.content)),
            AnySettingsPane(UpdatesSettingsPane(updater: updater)),
            AnySettingsPane(AboutSettingsPane(content: AboutConfig.content)),
            AnySettingsPane(UninstallSettingsPane(
                config: IceUninstallConfig.config,
                onCancel: { selection.paneID = GeneralPane.paneID }
            )),
        ]
    }

    /// Relaunches after a restore so every setting is read fresh.
    private static func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}

/// The Settings window's root: rebuilds the panes when the language changes, so host-supplied
/// text (About, What's New) switches live.
struct SettingsRoot: View {
    @ObservedObject private var localization = LocalizationManager.shared
    let panes: () -> [AnySettingsPane]
    @Bindable var selection: SettingsSelection

    var body: some View {
        SettingsShell(appName: Constants.displayName, panes: panes(), selection: $selection.paneID)
            .dragonLocalized()
    }
}
