//
//  AppDelegate.swift
//  Ice
//

import AppKit
import DragonKit
import SwiftUI

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    private let model = SettingsModel()
    private lazy var menuBar = MenuBarController(model: model)
    private let updates = UpdatesManager()
    private let selection = SettingsSelection()
    private var statusItem: NSStatusItem?
    private lazy var iceBar = IceBarPanel(model: model) { [menuBar] item in
        menuBar.reveal(item)
    }

    private lazy var settingsController = DragonSettingsWindowController(
        title: String(format: L("app.settings.windowTitle"), Constants.displayName),
        rootView: SettingsRoot(
            panes: { [model, menuBar, updates, selection] in
                SettingsPanes.panes(model: model, menuBar: menuBar, updater: updates.updater, selection: selection)
            },
            selection: selection
        )
    )

    /// Whether the app is the host of a unit test run, which needs no menu bar presence.
    private var isTestHost: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !isTestHost else {
            return
        }
        model.reconcileLoginItem()
        updates.showUpdatesPane = { [weak self] in self?.showSettings(pane: "updates") }
        updates.performSetup()
        installStatusItem()
        menuBar.start()
        if !AXIsProcessTrusted() {
            showSettings(pane: "permissions")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Quitting must never leave items hidden with no Ice to show them again.
        menuBar.restore()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        showSettings(pane: nil)
        return true
    }

    // MARK: Ice icon

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // Per-bundle-id autosave name, so the release and debug builds keep separate slots.
        item.autosaveName = "IceIcon-\(Constants.bundleIdentifier)"
        if let button = item.button {
            let image = NSImage(named: "DotFill")
            image?.isTemplate = true
            image?.accessibilityDescription = Constants.displayName
            button.image = image
            button.target = self
            button.action = #selector(iconClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item
    }

    @objc private func iconClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            iceBar.hide()
            showAppMenu()
        } else {
            // macOS 27 reports the status item's window frame as zero, so the click location
            // is the best measure of where the icon is.
            iceBar.toggle(anchorX: NSEvent.mouseLocation.x)
        }
    }

    /// The standard Dragon app menu, shown from a right-click on the Ice icon.
    private func showAppMenu() {
        guard let statusItem else {
            return
        }
        statusItem.menu = DragonAppMenu.menu(DragonAppMenu.Config(
            appName: Constants.displayName,
            onAbout: { [weak self] in self?.showSettings(pane: "about") },
            onSettings: { [weak self] in self?.showSettings(pane: nil) },
            // A debug build has no route to the production appcast at all.
            onCheckForUpdates: UpdatesManager.updatingIsDisabled
                ? nil
                : { [weak self] in self?.updates.checkForUpdates() }
        ))
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    // MARK: Settings

    /// Opens Settings, on `pane` when given, otherwise on the last pane shown.
    private func showSettings(pane: String?) {
        if let pane {
            selection.paneID = pane
        }
        NSApp.activate()
        settingsController.show()
    }
}
