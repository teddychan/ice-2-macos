//
//  UninstallConfigTests.swift
//  IceTests
//

import DragonKit
import Foundation
import Testing
@testable import Ice_2

/// Pins the configuration Ice 2 hands to DragonKit's uninstaller. This is the seam where a
/// mistake silently changes what a destructive, unrecoverable operation deletes, so the
/// contract is asserted here rather than trusted to review: the domain that gets wiped, every
/// path removed alongside it, the checklist the user is shown, and — just as importantly —
/// that all of it stays scoped to the *running* bundle id.
@MainActor
struct UninstallConfigTests {
    private var config: UninstallConfig { IceUninstallConfig.config }

    @Test func wipesTheRunningBundlesDomain() {
        // The running bundle's id, never a hardcoded release id: a debug build
        // (com.dragonapp.ice.debug) must clean its own domain and saved state, and must
        // never touch the installed release's.
        #expect(config.bundleID == Bundle.main.bundleIdentifier)
        #expect(!config.bundleID.isEmpty)
    }

    @Test func namesTheRunningBuildNotTheReleaseName() {
        // Same rule as the bundle id above, for the name the confirmation sheet shows:
        // the running bundle's display name, never a hardcoded "Ice 2". A debug build
        // must say "Ice 2 Debug" so the sheet for a destructive, unrecoverable action
        // can't be mistaken for the installed release's. Asserted against the bundle
        // rather than a literal so it holds for both builds.
        #expect(config.appName == Constants.displayName)
        #expect(config.appName == "Ice 2 Debug") // the test host is the Debug build
    }

    @Test func namesExactlyWhatIsRemoved() {
        // Pinned in English so the assertion means the same thing on every machine; the
        // checklist is localized now, and `L(_:)` follows the OS language by default.
        withEnglish {
            #expect(config.checklistItems == [
                "The app and its login item",
                "Settings, layout profiles, and hotkeys",
                "Saved application state",
                // The caches/support folders `extraCleanupPaths` adds are deleted, so the
                // confirmation has to say so — the sheet must not under-report the damage.
                "Caches and support files",
            ])
        }
    }

    @Test func everyChecklistKeyActuallyResolves() {
        // `L(_:)` falls back to the key itself when nothing matches, so a typo'd key does not
        // crash or blank the row — it renders "app.uninstall.item.app" to the user, inside the
        // confirmation for an unrecoverable delete. The test above cannot catch that on its
        // own: it would still pass if the English table were the thing that was wrong.
        for item in config.checklistItems {
            #expect(!item.hasPrefix("app."), "unresolved localization key in the checklist: \(item)")
            #expect(!item.isEmpty)
        }
    }

    @Test func removesThePerBundleLibraryFolders() {
        // The three folders the shared teardown can't infer, matching the manual `rm -rf` in
        // README.md and the Homebrew cask's `zap trash:`. Pinned exactly — and in order — so
        // widening or narrowing an unrecoverable delete has to be a deliberate edit here.
        let library = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library")
        #expect(config.extraCleanupPaths == [
            library.appending(path: "Application Support/\(config.bundleID)"),
            library.appending(path: "Caches/\(config.bundleID)"),
            library.appending(path: "HTTPStorages/\(config.bundleID)"),
        ])
    }

    @Test func scopesEveryCleanupPathToTheRunningBundle() {
        // The guardrail behind `wipesTheRunningBundlesDomain`: a debug build
        // (com.dragonapp.ice.debug) must never delete the installed release's caches, so every
        // path has to be built from the *running* bundle id and stay inside ~/Library.
        let library = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library")
        for url in config.extraCleanupPaths {
            // Each folder is named for the running bundle id...
            #expect(url.lastPathComponent == Bundle.main.bundleIdentifier)
            // ...and sits under this user's ~/Library, never anywhere else on disk.
            #expect(url.path.hasPrefix(library.path + "/"))
        }
    }

    @Test func neverDeletesTheUsersBackups() {
        // Uninstalling removes everything Ice 2 owns *except* backups — they exist precisely to
        // outlive a reinstall or a move to a new Mac, so deleting them would defeat the feature.
        // They're safe structurally rather than by luck: the default folder is under ~/Documents
        // and a configured one can be anywhere (Dropbox, iCloud Drive), while every cleanup path
        // is pinned inside ~/Library. This asserts the two can't overlap.
        let defaultFolder = DragonBackup.defaultFolder(appName: Constants.displayName)
        for url in config.extraCleanupPaths {
            #expect(defaultFolder.path != url.path)
            #expect(!defaultFolder.path.hasPrefix(url.path + "/"))
        }

        // And the reason it holds for a *configured* folder too, wherever the user pointed it:
        // the default already lives outside the ~/Library subtree that bounds every cleanup path.
        let library = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library")
        #expect(!defaultFolder.path.hasPrefix(library.path + "/"))
    }

    @Test func clearsHomebrewsReceiptOnlyForTheReleaseBuild() {
        // Ice 2 ships as the cask `ice-2` (`Casks/ice-2.rb` in teddychan/homebrew-tap), so the
        // teardown clears brew's receipt too — left behind, it claims the cask is still installed
        // and `brew install --cask ice-2` refuses for an app that isn't there.
        //
        // Gated on the running bundle id for the same reason every path above is: `brew uninstall
        // --cask` deletes the app *brew* recorded, so a debug build (com.dragonapp.ice.debug),
        // which brew never installed, would delete the installed release instead of itself.
        //
        // The identity is passed in rather than read from the test host, because the host is
        // always the Debug build: the previous version of this test asked
        // `Bundle.main.bundleIdentifier` and could therefore only ever exercise the `nil` branch,
        // asserting as a fact about Ice 2 something that was only a fact about CI.
        func token(for bundleID: String?) -> String? {
            IceUninstallConfig.homebrewCask(forBundleID: bundleID)
        }

        #expect(token(for: "com.dragonapp.ice") == "ice-2")
        #expect(token(for: "com.dragonapp.ice.debug") == nil, "the debug re-id is why this gate exists")
        #expect(token(for: "com.dragonapp.clipmenu-2") == nil)
        #expect(token(for: nil) == nil, "a build that can't state its id must authorise nothing")

        // And that `config` actually asks: without this, hardcoding the token back into the
        // initializer would leave every case above still passing. Holds in either build — it
        // pins the wiring, not a configuration-specific answer.
        #expect(config.homebrewCask == token(for: Bundle.main.bundleIdentifier))
    }

    @Test func deletesNothingBeyondTheBundlesOwnFolders() {
        // Ice 2's settings live in `UserDefaults.standard` (`Defaults.store`), i.e. the
        // bundle-id domain the uninstaller already wipes — so no extra suites.
        #expect(config.suiteNames.isEmpty)
        // Ice 2 keeps no separate user data — its settings *are* its data, always removed —
        // so there is no optional "also delete data" choice to opt into.
        #expect(config.optionalDataToggle == nil)
    }
}
