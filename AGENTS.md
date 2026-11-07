# AGENTS.md

Ice 2 is a macOS menu bar manager, a GPL-3.0 fork of Jordan Baird's Ice, built from `Ice.xcodeproj` on the shared DragonKit package. Version 3 is a rewrite for macOS 27 and later; the design is `docs/superpowers/specs/2026-11-07-ice-2-v3-design.md`.

## Project rules

### Localization

- Resolve every user-visible string through DragonKit's `L(_:)` (it returns `String`), with `.dragonLocalized()` at each window root. Never use SwiftUI `LocalizedStringKey` for app text: it resolves against the languages read at launch, so a language change would only apply after a relaunch.
- Use semantic keys (`app.general.showOnClick`), never English text as the key, so a copy edit doesn't become a rename across eight files.
- Read shared wording (OK/Cancel, Settings pane titles, Backup/Uninstall/Updates chrome) from the kit with `L("DragonKit.…")`. Never redefine a `DragonKit.*` key in `Ice/Resources/*.lproj`; conformance §R8 forbids it and the kit's table wins the lookup anyway.
- Add every key to all eight `Ice/Resources/<lang>.lproj/Localizable.strings` files with matching format specifiers; `LocalizationCoverageTests` enforces this against the built bundle. The `.lproj` folders reach the app through the file-system synchronized group, so nothing in `project.pbxproj` names them — but a new locale must still be added to `knownRegions` and to `whats_new_path` in `.github/workflows/release.yml`.
- Wrap tests that assert English copy in `withEnglish { }` (in `IceTests/LocalizedTextSupport.swift`), or they fail on a non-English Mac.

### Tests and conformance

- The app's Swift module is `Ice_2` (the product is "Ice 2"), so tests use `@testable import Ice_2`, not `import Ice`.
- `IceTests` is not a synchronized group: after adding a file under `IceTests/`, re-run `ruby scripts/add-icetests-target.rb` (idempotent; needs the `xcodeproj` gem, and the system Ruby needs `LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8`).
- After changing a glob in `.dragon-conformance.json`, or adding a file a conformance rule covers, prove the rule is live: inject a fault (for example delete one locale's `.lproj`, or add a `DragonKit.*` key to `en.lproj`), confirm the conformance check fails, then revert. A glob that matches no files makes its rules pass with nothing to check.

### Dependencies and concurrency

- Sparkle is not a direct package reference; it arrives transitively through DragonKit and appears only in `Package.resolved`, so it cannot be pinned from this project. When bumping DragonKit, edit the `minimumVersion` in the package reference whose `repositoryURL` is `https://github.com/teddychan/dragon-kit` (not a bare version-string search), then diff `Package.resolved`; Sparkle moving with it is expected.
- The project builds in Swift 5 language mode with default (minimal) strict concurrency. Before committing `SWIFT_STRICT_CONCURRENCY` or `SWIFT_VERSION = 6.0`, check the build with a command-line override: `xcodebuild build -project Ice.xcodeproj -scheme Ice -destination 'platform=macOS,arch=arm64' SWIFT_STRICT_CONCURRENCY=targeted`.

### macOS 27 menu bar

- Hiding is one `MBAssessmentModeAssertion` (runtime-loaded `MenuBarClientCore`, see `Ice/MenuBar/MenuBarAgentBridge.m`) whose configuration allows everything except the hidden items. MenuBarAgent shows the union of every client's allowed set, so a second client can only reveal items, never hide them: a Debug build run beside the release Ice 2 cannot hide anything, and makes the release's hidden items appear. Quit the release before testing hiding by hand.
- A status item's window frame reads as zero on macOS 27, so anything positioned relative to the Ice icon uses the click location (`IceBarPlacement`).
- `AXPress` on an item in MenuBarAgent's tree opens that app's real menu, but the call blocks until the menu closes and then returns `kAXErrorCannotComplete`; set a short messaging timeout on the element first.
- Every failure path fails open: release the assertion so every item shows. Quit and sleep release it too.

### Releases and platform

- Adopting a new DragonKit version gets a minor version bump, even when nothing user-visible changes. Record it under `### Internal` in `CHANGELOG.md`, never as `### Fixed`, and don't invent user-visible benefits.
- Don't add an iCloud ubiquity container, CloudKit or `NSUbiquitousKeyValueStore`. Ice 2 ships Developer ID only and cannot be sandboxed (it drives the menu bar through Accessibility), so those containers are unavailable to real users. Cross-Mac settings sync works by pointing the Backup & Restore folder at a synced folder such as iCloud Drive.
- The support link in `Ice/Settings/AboutConfig.swift` names the pre-rename repo `teddychan/ice-2` on purpose. DragonKit CONFORMANCE §R15 requires the support repo to equal the page slug, so leave it until DragonKit accepts the `-macos` suffix. `SUFeedURL` in `App/Info.plist` uses the current repo name.
