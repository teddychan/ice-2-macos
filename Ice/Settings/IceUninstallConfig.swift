//
//  IceUninstallConfig.swift
//  Ice
//

import DragonKit
import Foundation

/// App-owned Uninstall configuration for Ice 2, rendered by DragonKit's
/// ``UninstallSettingsPane`` and performed by ``DragonUninstaller``.
///
/// Only Ice 2's own content lives here — the confirmation layout and the teardown are owned
/// by DragonKit. Ice 2's settings live in its `UserDefaults` domain (`Defaults.store` is
/// `.standard`), which the shared teardown wipes from `bundleID` along with the matching
/// preference plist and saved application state, so there are no extra suites. Ice 2 keeps no
/// separate user data either — its settings *are* its data, always removed — so there is no
/// optional "also delete data" toggle, unlike ClipMenu.
///
/// `extraCleanupPaths` covers the per-bundle-id folders the shared teardown can't know about:
/// the `Caches` and `HTTPStorages` folders macOS creates for the app's own network traffic
/// (Sparkle's appcast fetches), plus `Application Support`. Ice 2 writes nothing to
/// `Application Support` today, but it is listed so the in-app uninstall, the manual `rm -rf`
/// in `README.md`, and the Homebrew cask's `zap trash:` all remove the same five paths —
/// keeping those three from drifting is the point, and removing an absent folder is a no-op.
enum IceUninstallConfig {
    /// The bundle id Homebrew installed: the fallback for the running bundle's id below, and the
    /// gate the cask token is issued against — deliberately not both at once, see
    /// ``homebrewCask(forBundleID:)``.
    ///
    /// Aliases ``Constants/releaseBundleIdentifier`` rather than repeating the literal: three
    /// places now ask "is this the installed release, or the isolated debug build?", and a
    /// second copy of that id is exactly the kind of literal that drifts.
    private static let releaseBundleID = Constants.releaseBundleIdentifier

    /// The Homebrew cask token for `actual`, or `nil` when that isn't the bundle brew installed.
    ///
    /// Ice 2 ships as the cask `ice-2` — the token declared by `Casks/ice-2.rb` in
    /// teddychan/homebrew-tap, not inferred from the repo name. Homebrew never watches the
    /// filesystem, so an app that deletes itself leaves brew's receipt still claiming the cask is
    /// installed and `Caskroom/ice-2/<version>/Ice 2.app` a dangling symlink; `brew install --cask
    /// ice-2` then refuses outright — "already installed" — for an app that isn't there, pointing
    /// at nothing that would fix it. Naming the token lets the kit's post-exit shell run
    /// `brew uninstall --cask --force ice-2` and clear that record.
    ///
    /// The comparison is the kit's (``UninstallConfig/caskToken(_:ifBundleIs:actual:)``, DragonKit
    /// 3.2.0) rather than a local `==`, because it has to fail closed and Ice 2's own version
    /// didn't. `brew uninstall --cask` is not bundle-scoped: it deletes whatever the receipt points
    /// at — the *release* app in /Applications — and the cask carries `uninstall quit:`, so it
    /// quits that app first. A debug build (com.dragonapp.ice.debug), which brew never installed,
    /// must issue nothing; so must a build that can't state its id at all. Ice 2 used to compare
    /// `Bundle.main.bundleIdentifier ?? releaseBundleID`, so a missing id fell back to the release
    /// id and handed the delete to the one build least entitled to it. Hence the raw identifier
    /// here, never `config`'s fallen-back `bundleID`.
    static func homebrewCask(forBundleID actual: String?) -> String? {
        UninstallConfig.caskToken("ice-2", ifBundleIs: releaseBundleID, actual: actual)
    }

    @MainActor
    static var config: UninstallConfig {
        // The running bundle's id, so a debug build (com.dragonapp.ice.debug) cleans its OWN
        // domain/state/caches and never the installed release's.
        let bundleID = Bundle.main.bundleIdentifier ?? releaseBundleID
        let library = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library")
        return UninstallConfig(
            appName: Constants.displayName,
            bundleID: bundleID,
            // No `suiteNames:`. Every setting lives in the standard settings suite (see
            // `SettingsModel`), which DragonKit clears on its own.
            // Resolved here, not keyed: `UninstallConfig` is built fresh each time the pane
            // renders and the kit shows these strings as-is (its own doc comment says to
            // localize them in the app), so `L(_:)` reads the language selected right now.
            checklistItems: [
                L("app.uninstall.item.app"),
                L("app.uninstall.item.settings"),
                L("app.uninstall.item.state"),
                L("app.uninstall.item.caches"),
            ],
            extraCleanupPaths: [
                library.appending(path: "Application Support/\(bundleID)"),
                library.appending(path: "Caches/\(bundleID)"),
                library.appending(path: "HTTPStorages/\(bundleID)"),
            ],
            // The *raw* identifier, never `bundleID` above: that one falls back to the release id
            // so a build which can't state its own still cleans a sensible domain, which is
            // harmless there and authorises a delete of the installed release here.
            homebrewCask: homebrewCask(forBundleID: Bundle.main.bundleIdentifier)
        )
    }
}
