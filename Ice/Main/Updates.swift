//
//  Updates.swift
//  Ice
//

import DragonKit
import DragonKitUpdates
import OSLog
import SwiftUI
import UserNotifications

/// Manager for app updates.
///
/// Sparkle itself lives in DragonKit's ``DragonUpdater`` (module `DragonKitUpdates`), which
/// every Dragon app shares — same feed handling, same settings, and the same reworded
/// "Ice 2 is up to date" alert. Ice 2 keeps only the app-specific parts here: bringing the
/// app forward so Sparkle's dialogs appear in front, the debug-build guard, and its own
/// notification for an update a background check found.
@MainActor
final class UpdatesManager {
    /// Brings the Updates pane forward before a manual check, so Sparkle's result appears
    /// over it.
    var showUpdatesPane: () -> Void = {}

    /// The underlying updater. The Updates settings pane observes this directly.
    ///
    /// Both settings are behaviour Ice 2 had when it wired Sparkle itself and lost when it
    /// moved onto the kit, because ``DragonUpdater`` passed no user-driver delegate at all.
    let updater = DragonUpdater(config: DragonUpdaterConfig(
        // A scheduled check shows Sparkle's window without stealing focus, rather than a modal
        // arriving unprompted while you are working.
        usesGentleScheduledReminders: true,
        onUpdateFoundInBackground: { UpdatesManager.notifyUpdateAvailable() }
    ))

    /// Whether this build must leave the production updater alone entirely.
    ///
    /// Primarily the build channel `scripts/run-debug.sh` stamps into `Info.plist`, read through
    /// DragonKit 3.3.0's ``DragonAbout/isDebugBuild(bundle:)``: `MAC-APP-RELEASE-LIFECYCLE.md`
    /// scopes the rule to the *bundle* someone is running hands-on beside their installed Ice 2,
    /// and the channel is the only thing that describes that bundle.
    ///
    /// `#if DEBUG` is kept alongside it rather than replaced by it. A build launched straight
    /// from Xcode is never stamped, so the channel alone would let ⌘R reach the production
    /// appcast — which the `#if DEBUG` guard this replaced did block. Two conditions, because
    /// they answer different questions: how the binary was compiled, and what the bundle says
    /// it is.
    ///
    /// "Disabled" means never initializing Sparkle either, not just never checking:
    /// ``DragonUpdater`` creates its `SPUUpdater` lazily on first property access, so merely
    /// reading ``DragonUpdater/automaticallyChecksForUpdates`` would start it and its
    /// scheduled-check timer.
    static var updatingIsDisabled: Bool {
        #if DEBUG
        return true
        #else
        return DragonAbout.isDebugBuild()
        #endif
    }

    /// Performs the initial setup of the manager.
    func performSetup() {
        guard !Self.updatingIsDisabled else {
            // Not even `updater.start()`: a debug build must never read the production appcast.
            Logger.default.notice("Debug build - skipping updater setup")
            return
        }
        // Starting the updater at launch is what lets Sparkle schedule its background update
        // checks, exactly as `SPUStandardUpdaterController(startingUpdater: true)` did.
        updater.start()
        // Only users who turned scheduled checks on can ever see the notification below
        // (`SUEnableAutomaticChecks` is false by default), and only they were prompted before:
        // the old `SPUUpdaterDelegate` hook that requested this fired when Sparkle scheduled a
        // check, which it only does when they are enabled. Don't prompt everyone else.
        if updater.automaticallyChecksForUpdates {
            requestNotificationAuthorization()
        }
    }

    /// Checks for app updates.
    ///
    /// Unreachable from the menu in a debug build — ``ControlItem`` passes
    /// `onCheckForUpdates: nil`, so DragonKit omits the item rather than showing an inert one.
    /// The guard stays because the menu is not the only caller a future change could add, and
    /// this used to be an `#if DEBUG` alert saying the check "is not supported in debug mode",
    /// which described a hang rather than the policy.
    func checkForUpdates() {
        guard !Self.updatingIsDisabled else {
            Logger.default.notice("Debug build - ignoring check for updates")
            return
        }
        // Bring the app forward in case an alert needs to be displayed.
        showUpdatesPane()
        updater.checkForUpdates()
    }

    /// Asks for permission to post ``notifyUpdateAvailable()``.
    private func requestNotificationAuthorization() {
        Task {
            do {
                try await UNUserNotificationCenter.current()
                    .requestAuthorization(options: [.badge, .alert, .sound])
            } catch {
                Logger.default.error("Failed to request notification authorization: \(error)")
            }
        }
    }

    /// Posts Ice 2's "A new update is available" notification.
    ///
    /// Only ever called for a check the user did not start — ``DragonUpdaterConfig`` filters out
    /// user-initiated ones, since someone who just clicked **Check for Updates…** is already
    /// looking at the result. Because gentle reminders are on, Sparkle shows its update window
    /// *without* activating Ice 2, so on a busy desktop that window can sit unnoticed behind
    /// other apps; this is the nudge.
    ///
    /// Deliberately just the one notification, not the `UserNotificationManager` subsystem this
    /// replaces. Sparkle is always the one showing the update here, so there is no state for a
    /// `UNUserNotificationCenterDelegate` to drive that Sparkle's own window doesn't already
    /// cover, and the two callbacks the old code hung off — clearing a delivered notification
    /// once the update got attention, and naming the version in the body — need parts of
    /// Sparkle's delegate that ``DragonUpdaterConfig`` does not expose.
    private static func notifyUpdateAvailable() {
        let content = UNMutableNotificationContent()
        content.title = L("app.updates.notification.title")
        content.body = String(format: L("app.updates.notification.body"), Constants.displayName)
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "UpdateCheck", content: content, trigger: nil)
        )
    }
}
