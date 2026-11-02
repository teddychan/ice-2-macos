# Changelog

## 2.16.1 - 2026-09-28

### Fixed

- **A collapsed Hidden or Always-Hidden section no longer leaves a gap in the menu bar on macOS
  27.** On the macOS 27 backend a collapsed divider set its status item length to 0, but first
  re-activated a content-view constraint that keeps a status item from reaching zero width. The
  divider stayed as a blank space while collapsed and shrank to about 1pt when expanded with the
  None style, so the spacing changed on every toggle. A collapsed native divider now takes no space
  at all, through the same constraint-off path the None style already used. macOS 26 and earlier
  keep the oversized divider unchanged. Closes #120.
- **The macOS 27 Layout editor is translated.** 2.16.0 shipped its 35 `app.native.*` strings in
  English in all six other locales, so the Layout pane read English inside otherwise localized
  Settings (#120). Each is now translated with the terms that locale's Settings UI already uses.

### Changed

- **The four Settings sliders are standard macOS sliders.** Hover delay, rehide interval, menu bar
  item spacing and the temporary-show interval now use the system `Slider`, with a tick mark per
  step and the current value beside the track, in place of CompactSlider's filled bar with the
  value inside it. The system control takes the Liquid Glass treatment on macOS 26 and 27 by
  itself. CompactSlider is gone from the project, so Settings ▸ About no longer credits it.

### Internal

- **Ice 2 builds with Xcode 27.** The macOS 27 SDK rejects CompactSlider 1.2.1, its last 1.x
  release, with an ambiguous `opacity` call, so the project did not compile on Xcode 27 at all.
  Replacing the package (above) fixed the build. CI stayed green throughout because it runs
  Xcode 26.
- **The locale checks now read every `String(format:)` specifier.** `LocalizationCoverageTests`
  compares each translation's specifiers with English, but its pattern had no room for length
  modifiers, so the two `%ld` counts in the Layout profile result message were never compared.
  It now reads the whole printf grammar (flags, width, precision, length and every conversion,
  plus `%%`), and a new test pins each form.
- **`scripts/run-debug.sh` keeps the debug build's permission grants across rebuilds.** It signs
  with a stable local identity instead of ad hoc, and launches with `open -n` so macOS checks
  Ice 2 Debug's own grants rather than the terminal's.

## 2.16.0 - 2026-09-18

### Added

- **Menu bar hiding works again on macOS 27.** macOS 27 represents the whole menu bar as a single
  window rather than one window per item, which is what every item-discovery path in Ice 2 was
  built on — so the list came back empty, nothing hid, and Layout never finished loading. A new
  backend, used only on macOS 27 and later, discovers menu bar apps and supported system items
  through Accessibility and hides them with runtime-loaded `MenuBarClientCore` assessment-mode
  assertions instead of an oversized divider. The Ice icon, the Hidden and Always-Hidden sections,
  section hotkeys and automatic rehiding behave as before. Accessibility permission is required;
  without it the app says so and leaves everything visible. Closes #53.
- **A Layout editor built for the new backend.** Three labelled drop targets — Visible, Hidden and
  Always-Hidden — take a dragged app card, or a section can be chosen from the card's menu;
  assignments persist immediately. One card represents one app bundle, because on macOS 27 all of
  an app's menu bar icons share visibility. Saved layout profiles still apply: migration maps
  stable identities, prefers the more visible section on conflict, reports what could not be
  matched, and refuses a wholly unmappable profile rather than overwriting current assignments.
  Native profiles save section membership, not ordering. Assignments are stored separately under
  the new `NativeMenuBarSections` defaults key, so old per-window layouts are left intact.

### Fixed

- **The Ice Bar no longer spins on "Loading menu bar items…" forever when there is nothing to
  load.** A completed but empty item cache now shows an empty state with a Check Again button
  instead of an indefinite progress indicator. This was the visible symptom of the macOS 27 break,
  but the empty state applies on every supported version. Closes #116.

### Changed

- **Three features are unavailable on macOS 27:** the separate Ice Bar, per-icon search, and
  temporarily showing a single icon. None of them has a representation in the new backend — hidden
  items reveal directly in the system menu bar instead of in a separate bar. Their controls and
  hotkeys are disabled on macOS 27 only; saved preferences and key bindings are kept untouched, so
  they return unchanged on macOS 26. Assessment mode can also conceal Focus and some other system
  extras as a side effect, section visibility applies across all displays at once, and Clock,
  Control Center and unmapped system items cannot be assigned. Physical icon order is still changed
  by Command-dragging in the menu bar.

### Internal

- macOS 26 and earlier are untouched: `NativeMenuBarManager.usesNativeBackend` gates every new code
  path on `operatingSystemVersion.majorVersion >= 27`, and the legacy window-based backend, the
  `MenuBarItemService` XPC connection and the existing Layout editor run exactly as before.
- Every failure path fails open. A failed or timed-out activation, a missing private framework and
  revoked Accessibility permission all release the assertions and restore every section, so a
  regression in the private API leaves items visible rather than stranded. An assertion is replaced
  only after its successor activates, and generation checks discard stale callbacks; quit and sleep
  release assertions, wake and Space changes refresh discovery.
- The private API is reached through a small Objective-C bridge with runtime class and selector
  checks; nothing is linked against `MenuBarClientCore` at build time. Implementation notes and the
  manual checklist are in `docs/testing/macos27-integration.md`; the isolated feasibility probe is
  retained in `docs/testing/macos27-prototype.md` and `scripts/macos27-prototype.m`.

## 2.15.2 - 2026-08-20

### Fixed

- **Uninstall now refuses to run when it finds more than one copy of Ice 2 on the Mac.** Moving
  the copy you are running to the Trash was always safe, but settings, the login item, support
  files and the Homebrew record are keyed by the app's identity, not its location — so two copies
  on disk share all of them, and there is no way to tell which copy's data belongs to which.
  Uninstalling a spare copy could have removed the settings belonging to the copy actually in use.
  It now stops before removing anything and lists where the copies are, so the ones you do not
  want can be trashed and the uninstall retried. Anyone with a single copy, which is nearly
  everyone, sees no change.

### Internal

- **Ice 2 now builds against version 4.1.1** of the shared Dragon app framework, up from 4.1.0.
  The uninstall fix above is what changed. DragonKit 4.1.1 also fixed a raw developer error that
  could surface in Settings ▸ Updates, but only in local debug builds of the apps that depend on
  it — no shipped copy of Ice 2 could ever hit it, so it is not claimed in the What's New pane,
  per this repo's rule against announcing fixes for something no user could see. **Settings ▸
  About** reports `DragonKit v4.1.1` under Built with.

## 2.15.1 - 2026-08-18

### Internal

- **Nothing about the app behaves differently.** Ice 2 now builds against version 4.1.0 of the
  shared Dragon app framework, up from 4.0.0. Since 2.15.0 this repository gained exactly two
  changes to the app, and this is one of them; there is no user-facing fix or feature in this
  release, and the notes in the What's New pane say so rather than inventing one.

  The bump is for pin currency rather than to adopt anything. The shared conformance rules
  require each app's declared framework version to be at least the newest one published, so
  publishing 4.1.0 put this app in breach of that rule the moment it landed — every pull request
  here failed §R10 until the pin moved. No code here had to change to take the bump.

  The one place you can see any of it is **Settings ▸ About**, which reports the framework it was
  built with and now reads `DragonKit v4.1.0`.

- **Both bundles' `Info.plist` moved into `App/`.** DragonKit's conformance §R16 places every
  app's bundle inputs under `App/` at the repo root, so the app's plist is `App/Info.plist` and
  the bundled menu bar helper's is `App/MenuBarItemService/Info.plist`. Only `INFOPLIST_FILE` in
  the Xcode project moved with them; neither file's contents changed, and neither carries a
  version key — Ice 2's version is `MARKETING_VERSION` in `Ice.xcodeproj`, and the release
  workflow stamps `CFBundleVersion` with the commit count.

## 2.15.0 - 2026-08-13

### Added

- **Ice 2 speaks seven languages.** English, Español, Français, 日本語, 한국어, 简体中文 and
  繁體中文, chosen from a new **Language** control in Settings ▸ General. The whole app switches
  the moment you pick one — settings, the menu bar dropdown, alerts and the permissions window —
  with no relaunch. Set it to **Automatic** to follow macOS.

  This is the last of the five Dragon apps to ship localization; the other four already had these
  same seven. Ice 2 previously had none at all: no `.lproj`, no String Catalog, and 213 English
  strings hardcoded across 31 files.

### Changed

- **The right-click menu's Settings item now reads "Settings…", with the gear icon every other
  Dragon app shows.** It said "Ice 2 Settings…" and carried no icon, because it was built by hand
  instead of coming from the shared `DragonAppMenu` — the exact drift dragon-kit's conformance
  spec exists to prevent, and one its §R1 check happened to miss because the construction spanned
  two lines. "Edit Menu Bar Appearance…" above it is Ice 2's own and is unchanged.

- **The backup folder button reads "Choose…" rather than "Change…".** It now uses DragonKit's
  string, so this row matches the same row in every other Dragon app.

### Internal

- Every user-visible string resolves through DragonKit's `L(_:)` rather than SwiftUI's
  `LocalizedStringKey`. A `LocalizedStringKey` is looked up against the localizations the process
  read at launch, so the picker could only ever have taken effect on the *next* run; `L(_:)`
  re-resolves per call and `.dragonLocalized()` on the settings and permissions windows rebuilds
  them when the choice changes. Keys are semantic (`app.general.showOnClick`), never English text.

- Shared wording — OK, Cancel, the sidebar pane titles, and the whole Backup, Uninstall and
  Updates chrome — is read from DragonKit's own table instead of being copied into Ice 2's. An app
  that redefines a `DragonKit.` key cannot win the lookup anyway; duplicating them is how the
  shared menu's casing drifted across apps before.

- `LocalizationCoverageTests` pins the invariants that otherwise break silently: all seven tables
  define exactly the same keys, their `%@`/`%d` specifiers match English positionally, none claims
  a kit-owned key, and switching language re-resolves both app- and kit-owned strings in-process.
  It reads the *built* bundle, so it also proves the `.lproj` folders were copied in.

- `.dragon-conformance.json`'s `strings` glob now points at the shipped locale files. It matched
  nothing before, so conformance §R8 (no app-defined kit keys) and §R13 (the picker offers exactly
  what the app ships) were both passing by having nothing to check.

- **The Sparkle appcast mirror on www.dragonapp.com is retired.** Ice 2's update feed is now
  published to this repository only. This was step 3 of a migration planned across three releases:
  2.14.3 started publishing to both, 2.14.4 pointed `SUFeedURL` at the app-owned copy, and the
  mirror was held until a minor release so that anything still reading the site had time to move.
  The site copy is left in place, frozen at 2.14.7, rather than deleted — a stale feed offers an
  old version, which is recoverable; a 404 is not.

- The release gate now watches all seven `Localizable.strings` files alongside
  `WhatsNewConfig.swift`. The notes moved behind `L()` keys, so the Swift file can now sit still
  through a complete rewrite of the text; watching it alone would have waved through a release
  whose notes never actually changed in any language.

## 2.14.7 - 2026-08-11

### Fixed

- **The bundle's copyright notice now matches About.** `INFOPLIST_KEY_NSHumanReadableCopyright`
  read `Copyright © 2025 Jordan Baird · © 2026 Teddy Chan` while Settings ▸ About rendered
  `© 2026 Teddy Chan`, so the app made two different claims about itself depending on where you
  looked. Both now name one holder. Finder's Get Info panel is where a user sees this key.

  The old value was deliberate and documented in `AboutConfig.swift`: Ice 2 is a git fork carrying
  Jordan Baird's source under GPL-3.0, whose §4 requires his notice to travel with the work, and
  the argument was that this plist key is the binary's notice. The first half stands; the second
  was wrong. The key is an **optional** Apple one that no licence names — three of the five Dragon
  apps shipped without it entirely — so it displays a line in Get Info rather than discharging an
  obligation. §4 is carried by `LICENSE`, which fills in the GPL's own notice template with his
  name and year, and by `Resources/Acknowledgements.rtf`, which states that Ice 2 inherits GPL-3.0
  from the original Ice. Neither is touched here.

  This corrects 2.14.6's release notes, which told users "the app's own copyright notice still
  names both authors". True when written; this release is what changed it, and the new notes say
  so rather than leaving the claim to rot.

- **Nothing about licensing or lineage changed.** Ice 2 is still GPL-3.0 inherited from Ice.
  Jordan Baird is still credited twice in About — the `Original project` link and the `Based on`
  row, both driven by `OriginalWork` — and the full licence texts are still bundled and published
  at dragonapp.com/ice-2/licenses/.

  Part of unifying the field across all five Dragon apps, which held it in four different states:
  a tagline in ClipMenu 2, two holders here, and nothing at all in Spectacle 2, Yahoo! KeyKey 2
  and Dragon Sample App.

## 2.14.6 - 2026-08-11

### Fixed

- **Settings ▸ About links the original project again — or rather, for the first time.** Credits
  read `Based on · Ice by Jordan Baird`, and nothing anywhere in the pane linked to Ice: the pane
  told you Ice 2 has an upstream and gave you no way to reach it. There is now an **Original
  project** row in the links list, beside Website and Support, opening
  `github.com/jordanbaird/Ice`.

  This was possible because the upstream project's name and its URL were two unrelated optional
  values in the shared framework, so all four combinations of "credited" and "linked" shipped
  across the five Dragon apps — Ice 2 and ClipMenu credited a project neither of them linked. The
  framework's 4.0.0 release folds the URL into the same value that carries the name, so one entry
  now drives both the link row and the credit line and they cannot disagree again. It was found by
  putting all five apps' About panes side by side, which is how every case of this drift has been
  found.

### Changed

- **Settings ▸ About names one copyright holder.** The line under the version read
  `© 2025 Jordan Baird · © 2026 Teddy Chan`; it now reads `© 2026 Teddy Chan`, which is the form
  the other Dragon apps already used — only Ice 2 and ClipMenu carried a second holder, and the
  shared framework now enforces the single-holder form (conformance rule R14).

  **Nothing about Ice 2's licensing or its lineage changed.** Ice 2 is still GPL-3.0, inherited
  from Ice; Jordan Baird is still named as a copyright holder in `LICENSE`, in the bundled
  acknowledgements, and in the app bundle's own copyright notice (`NSHumanReadableCopyright`,
  which keeps both holders deliberately — Ice 2 is a fork that carries his source, and GPL-3.0
  requires his notice to travel with the binary). In the About pane he is now credited twice
  rather than once, by the new Original project link and the existing Based on line, and the full
  licence texts remain both bundled with the app and published at
  `dragonapp.com/ice-2/licenses/`. What changed is one display line, which now describes who
  maintains and distributes this app.

### Internal

- **The shared Dragon app framework moves to 4.0.0**, up from 3.4.0. This is the framework's first
  breaking release: the About pane's rows are now closed by the framework's own function signature
  rather than by a written rule, so the two defects above became compile errors instead of things
  a reviewer had to notice. The notices page is a required argument, the upstream project's URL
  lives inside the value that names it, and the dual-holder copyright helper is gone. **Settings ▸
  About** reports `DragonKit v4.0.0` under Built with.

## 2.14.5 - 2026-08-11

### Internal

- **Nothing about the app behaves differently.** Ice 2 now builds against version 3.4.0 of the
  shared Dragon app framework, up from 3.3.0. That release adds one thing — a way for an app to
  narrow the framework's language picker to the languages it has actually translated itself into
  — which Ice 2 has no use for: it ships no translations at all, so it shows no language picker.
  Both of the new arguments have defaults, so no code here had to change to take the bump.

  The bump is for pin currency rather than to adopt anything. The shared conformance rules
  require each app's declared framework version to be at least the newest one published, because
  every app once sat a release behind and so none of them had the shared menu at all; a stale pin
  silently misses shared fixes. Publishing 3.4.0 put this app in breach of that rule the moment
  it landed, which would have failed the next pull request here on a rule it did not break.

  The one place you can see any of it is **Settings ▸ About**, which reports the framework it was
  built with and now reads `DragonKit v3.4.0`.

- **The appcast mirror now retires on a date that can actually arrive.** 2.14.4 moved Ice 2's
  update feed to this repository and kept the copy on the marketing site as a mirror, so that
  installed copies still reading the site were not stranded. The condition for dropping that
  mirror was "when no supported version still reads the site" — which reads like a rule but names
  no observable event: the site is GitHub Pages and exposes no per-path traffic, so there is no
  way to see the last reader stop. The next minor release retires it instead, which is a real,
  deliberate event, and Sparkle checks daily by default, so anyone who has launched Ice 2 even
  once since 2.14.4 has already moved to the feed in this repository. This is a comment in the
  release workflow; nothing about how this release is built or published changed.

## 2.14.4 - 2026-08-11

### Internal

- **`SUFeedURL` now points at this repository** —
  `raw.githubusercontent.com/teddychan/ice-2/main/docs/ice-2/appcast.xml` — instead of
  `www.dragonapp.com/ice-2/appcast.xml`. Step 2 of 2, completing what 2.14.3 began.

  2.14.3 was step 1: it made this repository the appcast's home while keeping the marketing
  site as a mirror, which is what first created `docs/ice-2/appcast.xml` here. Only after that
  had actually run could the app be pointed at it — flipping both at once would have sent every
  installed copy to a feed that did not exist. Verified before this change: both copies exist
  and are byte-identical (sha256 `a3498f5…`), and the new URL serves 200.

  The mirror deliberately stays. Every copy at 2.14.3 or earlier still reads the site, and only
  a release after which no supported version does may drop it.

## 2.14.3 - 2026-08-11

### Internal

- **Ice 2's Sparkle appcast is now published to this repository as well as the marketing site.**
  Step 1 of 2 in giving the app its own update feed, per dragon-kit's
  `docs/MAC-APP-RELEASE-LIFECYCLE.md`: "Sparkle appcasts are update infrastructure, not marketing
  content. Each app should host its production appcast in its own repository so an outage,
  permission problem, or rejected change in the marketing-site repository cannot interfere with
  update delivery."

  Nothing changes for anyone who has Ice 2 installed. `SUFeedURL` still points at
  `www.dragonapp.com/ice-2/appcast.xml`, which is still being written; this release is what first
  creates `docs/ice-2/appcast.xml` here. Step 2 moves `SUFeedURL` to the app-owned URL, and only a
  release after which no supported version reads the site may drop the mirror. Flipping the two at
  once would have pointed every installed copy at a feed that did not exist yet.

  Ice 2 is the first xcodebuild-built app to use this configuration; the `generate_appcast` lookup
  is unchanged and only the publish destinations move.

- The release also moved to `dragon-release-ci@v6` with `whats_new_path`, which had landed on
  `main` without a release of its own. v6's tag gate accepts only an exact `vX.Y.Z` and requires
  the What's New source to have changed since the preceding tag.

## 2.14.2 - 2026-08-10

### Fixed

- **What's New inside the app was four releases out of date.** Ice 2's own **What's New** pane
  still described 2.11.0 while 2.14.1 was the version running, so if you read the app rather than
  this file, 2.12.0 through 2.14.0 were never announced to you at all — including that item groups
  had been removed, which deleted any groups you had saved the moment you updated. The pane now
  covers the menu bar icon placement added in 2.14.0, that removal from 2.12.0, and the 2.12.x
  fixes, each entry naming the release it came from. 2.13.0 and 2.14.1 were framework bumps with
  nothing user-facing in them and are deliberately absent rather than padded out. Updating this
  pane is now a required part of every public release rather than something to remember, so it
  cannot fall this far behind again.

### Internal

- **Nothing about the installed app behaves differently.** Everything below concerns running a
  development build of Ice 2 on the same Mac as the copy you have installed. The two are meant to
  be separate apps — separate identifier, separate name, separate permissions — and this release
  is the audit of what was still shared between them. If you only ever run the installed Ice 2,
  none of it applies to you.

- **A development build's version stays a number.** `scripts/run-debug.sh` appended `(Debug)` to
  `CFBundleShortVersionString`, which is the one field a public `vX.Y.Z` tag is checked against,
  so every hands-on build left that field non-numeric. The script now asserts `X.Y.Z` and fails
  loudly otherwise, stamping a separate build-channel key instead, which the shared framework
  renders as `v2.14.2 Debug` beside the build number. About, logs and screenshots still say Debug
  outright, while the number stays the numeric candidate the next release will carry: "Debug" is a
  channel label, never part of a version.

- **The two builds no longer ask macOS for the same helper service.** Ice 2 asks a small bundled
  helper which app each menu bar item belongs to. That service's name was written out in full, in
  a file that compiles into both the app and the helper, so an installed release and a development
  build asked launchd for one name and their embedded helpers claimed one identifier — exactly the
  collision that stops the two from being run at the same time. The name is now derived from
  whichever bundle is running. The app's half of that agreement and the helper's half live in
  different files, and a mismatch is silent at build time yet leaves every menu bar item without a
  source app at runtime, so a test reads the embedded helper out of the built app and checks the
  pair together.

- **A development build cannot reach the production update feed.** It started Sparkle at launch
  regardless, so a development build ran scheduled background checks against the real appcast,
  while the manual **Check for Updates…** item put up an alert calling the check unsupported —
  which described a hang rather than the policy. Updating is now off in such a build end to end:
  no scheduled checks, the menu omits **Check for Updates…** rather than showing an item that does
  nothing, and `scripts/run-debug.sh` deletes the feed address from the built bundle as well.
  Merely reading the automatic-check preference was enough to start the updater, so "off" has to
  mean never creating it, not just never checking.

- **A development build no longer deletes the installed app's settings backups, or quits it.**
  Three places treated the other Ice 2 as an unrelated third-party app. The default backup folder
  `~/Documents/Ice Backups` was spelled out in source, so both builds wrote into it — and because
  pruning keeps the ten newest *files* rather than the ten newest per build, with automatic
  backups on by default, ten quits of a development build were enough to delete every backup the
  installed copy had written. Applying a menu bar spacing offset quits and relaunches every app
  that has a menu bar item, excluding only the running process, so changing spacing in a
  development build terminated the installed release. And with both running, each offered the
  other as the app to trigger a section on, which is never what anyone means. One predicate now
  answers "is this one of ours" for all three, and the default backup folder is named per build.

- Ice 2 now builds against version 3.3.0 of the shared Dragon app framework, up from 3.2.0. That
  release is what renders the build-channel label beside the version, and what lets the app ask
  whether it is a development build at all, so the isolation above depends on it.

## 2.14.1 - 2026-08-10

### Internal

- Nothing about the app behaves differently. All four Dragon apps were audited together to confirm they depend on the shared Dragon app framework the same way — version 3.2.0, or any later 3.x — and are being released in step. Ice 2 needed no change to make that true: its Xcode project already expressed exactly that rule, in the only form Xcode has for writing it, and the dependency lock committed alongside the project already resolves to 3.2.0. This release is a version bump and nothing else, so that Ice 2's number lines up with its siblings.

## 2.14.0 - 2026-08-10

### Added

- **A newly installed app's menu bar icon now appears where you can see it.** macOS hands every brand-new menu bar item the leftmost slot, which in Ice 2's layout sits inside the always-hidden section. So the first time you installed an app with a menu bar icon, that icon was invisible from the moment it was created, and the app looked like it had never added one at all. Ice 2 now recognises an item it has never seen before and moves it into the visible section.

  Items you have already arranged are left alone. Updating to this version does not move anything: Ice 2 takes a note of everything currently in your menu bar first, so only icons that turn up afterwards count as new. If you then drag one of those into Hidden or Always-Hidden, it stays where you put it.

  This needs screen recording permission, which is what lets Ice 2 tell one menu bar item from another. Without it, nothing is moved.

## 2.13.0 - 2026-08-07

### Internal

- Ice 2 now builds against version 2.4.0 of the shared Dragon app framework. That release adds one thing — an option letting a system-managed input method keep Quit out of its settings menu bar — which Ice 2 is not and does not use. Nothing about the app behaves differently; this keeps Ice 2 current with the shared framework rather than drifting behind it.

## 2.12.1 - 2026-08-07

### Fixed

- **A future update can no longer wipe your settings.** Ice 2 saves your preferences as a single encoded record. Because of a flaw in the shared Dragon framework, the next version that *added* a setting would have failed to read the record you already had, quietly fallen back to defaults, and then written those defaults over your real preferences the moment anything changed — every setting reset, with no warning and no way back. Nothing has been lost: the flaw needed a future version to trigger it, and this update closes it first.

- **Restoring a damaged backup now refuses the file instead of erasing everything.** Handing Settings ▸ Backup a corrupted backup cleared your entire settings store rather than declining to read it, so one bad file could take your working preferences with it.

- **A failed uninstall says so.** If uninstalling Ice 2 hit a problem partway through, it quit reporting success anyway — after it had already torn your settings down.

- **VoiceOver can tell the menu bar shape buttons apart.** In Settings ▸ Appearance, the buttons that choose how each end of the menu bar shape is drawn — squared off or rounded — were pictures with no name attached. VoiceOver described the picture rather than what the button does, so picking a shape without looking at the screen meant guessing. They now read as "Square cap" and "Round cap". The tooltips you see on hover are unchanged.

- **Hardened the connection to Ice 2's bundled helper.** Ice 2 asks a small helper process which app each menu bar item belongs to. When that connection was interrupted, the code that cleared it skipped the lock that guards every other use of it, so a cleanup and an in-flight request could overlap. Nobody reported this and the timing needed to hit it is narrow, but the result would have been undefined — a dropped request at best, a crash at worst. Every access now goes through the same lock.

### Internal

- Ice 2 now builds with no compiler warnings, and the shared and helper sources are covered by the linter alongside the main app. Groundwork for moving to Swift's stricter data-race checking; no change to how the app behaves.

## 2.12.0 - 2026-08-06

### Fixed

- **The Layout pane keeps up with your menu bar again.** Applying a layout profile rearranged the real menu bar immediately, but the Visible / Hidden / Always-Hidden bars in Settings could go on showing the old arrangement for up to half a minute, until something unrelated happened to nudge them. They now catch up about a second after the last item moves. The same staleness could also affect the profile *being applied*: if you dragged an item and pressed **Apply** within a second of it, Ice 2 worked from the layout as it was before your drag, and moved the wrong items.

- **Dragging an item between sections no longer freezes the section you took it from.** Ice 2 pauses a section's bar while you drag out of it, so it doesn't rearrange under your cursor — but it only unpaused the section you dropped into. Drag from Hidden to Visible and the Hidden bar stopped updating for good, so an item that had moved kept showing in both places. Closing and reopening Settings was the only way out.

- **Menu bar item icons refresh while you are looking at them.** Ice 2 only redraws its picture of your menu bar items while the pane that displays them is open, which is the Layout pane. Since 2.8.0 it had been checking for the Appearance pane instead — the one pane that shows no item icons — so the icons in the layout bars were whatever had been captured on some earlier visit. If capturing one item failed at that moment, it kept showing a lettered placeholder instead of its icon for as long as you stayed on the Layout pane.

- **Restoring a backup, or using either "Relaunch Ice 2" button, brings Ice 2 back.** Ice 2 asked macOS to reopen it *before* quitting, while it was still running — so macOS simply brought the running copy to the front, reported success, and the quit that followed left nothing running at all. Ice 2 disappeared and did not come back. This affected restoring a settings backup and both Relaunch buttons.

### Removed

- **Item groups are gone.** The **Groups** section in Settings ▸ Layout — saving a set of hidden items under a name and revealing them with **Show** — has been removed, along with the option to point a trigger at a group. It saw very little use for the amount of the app it occupied, and layout profiles already cover arranging your menu bar. Any groups you saved are deleted from your settings when you update. **Triggers still work**: a trigger now always shows the hidden section when its app comes to the front, so the **Target** menu is gone and existing hidden-section triggers are untouched. If you had a trigger pointing at a group, only that trigger is dropped — the rest are kept.

## 2.11.0 - 2026-08-04

### Fixed

- **Scheduled update checks stop interrupting you again.** When Ice 2 checks for updates on its own schedule, it shows the update window quietly, without pulling you out of what you were doing. Version 2.10.0 moved updates onto the shared Dragon app framework that Ice 2 uses for its menu, permissions, and settings — and in that move Ice 2 stopped asking for the quiet behaviour, so a check running in the background could take over the screen unprompted. It asks for it again.

- **Ice 2 tells you when a background check finds an update.** The notification titled "A new update is available" is back. Because the update window deliberately does not steal focus, it can sit behind whatever you are working in — the notification is how you know it is there. This also went missing in 2.10.0. It applies only if you have **Automatically check for updates** turned on in Settings ▸ Updates, which is where macOS will ask permission to show notifications; declining changes nothing about how updates work, you just do not get the nudge.

### If you are updating from 2.9.x

- **Uninstalling Ice 2 has moved into Settings.** It used to be an **Uninstall** item in the Ice 2 menu that opened a separate window. Since 2.10.0 it is the last pane in the Settings sidebar, under **Uninstall**, with the confirmation right there in the pane. What gets removed is unchanged: the app and its login item, your settings, layout profiles, and hotkeys, and Ice 2's saved application state. The flow was **rewritten** in 2.10.0 on top of the shared framework rather than Ice 2's own copy of that code — the steps are the same and they are covered by automated tests, but it is a rewrite of a destructive, one-way path, so if removing Ice 2 misbehaves for you, please report it.

## 2.10.0 - 2026-08-04

### Changed

- **Uninstall now lives in Settings.** Removing Ice 2 used to be an **Uninstall** item in the Ice 2 menu that opened a separate window. It is now the last pane in the Settings sidebar, under **Uninstall**, and the confirmation appears right there in the pane instead of in its own window. What gets removed is unchanged: the app and its login item, your settings, layout profiles, and hotkeys, and Ice 2's saved application state.

### Removed

- **The Uninstall item is gone from the Ice 2 menu.** An unrecoverable action does not belong one click away from **Quit** in the everyday menu. Settings ▸ Uninstall is now the way to remove Ice 2 from inside the app.

### Fixed

- **Uninstalling no longer leaves an emptied settings file behind.** macOS rewrites an app's preferences file as the app quits, which could recreate the file Ice 2 had just deleted. Ice 2 now deletes those leftovers again once it has quit, so nothing lingers.

### Behind the scenes

- **The uninstall flow was rewritten** on top of the shared Dragon app framework that Ice 2 already uses for its menu, updates, and permissions, replacing Ice 2's own copy of that code. The steps it performs are the same ones as before, and they are covered by automated tests — but this is a rewrite of a destructive, one-way path, so if removing Ice 2 misbehaves for you, please report it.

## 2.9.11 - 2026-08-01

### Improved

- **Ice 2 looks at your screen far less often.** To draw a menu bar shape, remove the menu bar background, or round the screen corners, Ice 2 needs to know what your wallpaper looks like behind the menu bar. macOS no longer tells apps when the wallpaper changes, so Ice 2 has to look for itself every five seconds. It was doing that around the clock — including while the display was asleep or the screen was locked, where nothing it draws is visible, and for appearance settings that only tint, outline, or shadow the menu bar and never use the wallpaper at all. Ice 2 now looks only when the result will actually be drawn.

- **Why you may have seen a big number in the privacy report.** macOS counts each of those looks under **System Settings → Privacy & Security → Screen & System Audio Recording**, and occasionally shows the running total in a notification — which is how it could reach tens of thousands in a month. That number should grow much more slowly from now on. To be clear about what was being counted: Ice 2 has never recorded audio, and it only ever captures the menu bar strip and the wallpaper directly behind it. macOS combines screen and audio into a single permission, so its wording mentions both.

## 2.9.10 - 2026-07-25

### Fixed

- **The menu bar color can no longer be calculated from an empty screen capture.** When a capture of the menu bar area came back completely transparent — which can happen while displays are being reconfigured or right after waking from sleep — Ice 2 produced an invalid ("not a number") average color and passed it along as if it were real, which could tint the Ice 2 Bar or the item search panel with a garbage color. Ice 2 now treats an empty capture as "no color available" and keeps the previous color instead.

### Improved

- **Faster lookup of the wallpaper behind the menu bar.** This lookup inspected each window's owning application before checking its title, which meant building a process object for every window on screen. Checking the title first makes the scan roughly 40× faster (about 1 ms down to 25 µs on a typical desktop). It runs whenever Ice 2 refreshes the menu bar appearance overlay, the Ice 2 Bar, or the item search panel.

### Behind the scenes

- **More automated checks.** The test suite grew from 162 to 261 checks, now also covering menu bar image processing, appearance-settings upgrades, menu bar window identification, and the shared concurrency helpers. Both fixes above were found while writing those tests.

## 2.9.9 - 2026-07-11

### Behind the scenes

- **A reliability release — nothing changes in how Ice 2 looks or works.** Under the hood, we added a large automated test suite (162 checks) that continuously verifies Ice 2's core logic: your **settings**, **backup & restore**, **keyboard shortcuts**, and **saved menu bar layouts**. Think of it as a safety net — it catches mistakes before an update ships, so future releases are much less likely to accidentally break something that already works.

## 2.9.8 - 2026-07-10

### Fixed

- **Updating a layout profile can no longer erase it.** If capturing the current menu bar layout failed — for example right after Ice 2 launched, or if Screen Recording permission had been revoked — clicking **Update** on a saved profile could overwrite it with an empty layout. Ice 2 now ignores an empty capture and leaves your saved profile untouched.

### Improved

- **Lower idle CPU and energy use.** The Ice 2 Bar no longer captures the screen every few seconds while it's hidden — it only refreshes its background color while actually visible — and menu bar item names are now computed once instead of on every access. This continues the idle-power work from 2.8.4–2.8.6.

## 2.9.7 - 2026-07-09

### Fixed

- **"Update" on a layout profile now saves your latest arrangement.** After dragging menu bar items between sections, clicking **Update** on a saved profile could record the previous layout instead of the current one, so the profile looked unchanged (deleting and re-saving worked around it). Ice 2 now refreshes the menu bar layout before capturing, so both **Update** and **Save Current Layout** always store what's actually in your menu bar.

## 2.9.6 - 2026-07-08

### Changed

- **Simpler show options.** The two separate hover settings in General ("Show on hover over empty menu bar" and "Show on hover over Ice 2 icon") are now a single **Show on hover** that reacts to both, with one shared delay. Your existing hover preference is preserved.
- **Icon chooser moved to Appearance.** The menu bar icon chooser — icon, custom image, and dynamic appearance — now lives in the **Appearance** pane alongside the other menu bar look-and-feel options. General keeps the simple **Show Ice 2 icon** switch.

## 2.9.5 - 2026-07-08

### Changed

- **Simpler, cleaner Settings.** The General pane is reorganized into clear sections (Show Hidden Items, Rehide, Ice 2 Bar) so the most-used options are front and center. Advanced extras — automatic Ice 2 Bar and menu bar item spacing — now sit behind expandable "Automatic Ice 2 Bar" and "Advanced" rows, out of the way until you need them.
- **Grouped sidebar.** The Settings sidebar now groups What's New, Updates, and About together, separated from the functional panes above.
- **Removed a duplicate.** The Advanced pane no longer repeats the Permissions list — Permissions still has its own dedicated pane.

## 2.9.4 - 2026-07-08

### Changed

- **Settings pane order.** Moved Updates below What's New so Ice's Settings sidebar follows the shared Dragon app order (General → the app's own panes → Permissions → Backup & Restore → What's New → Updates → About).

## 2.9.3 - 2026-07-07

### Changed

- **New app icon.** The Ice 2 icon now shows two ice cubes — a nod to "Ice 2" — while keeping the familiar blue tile and glass look.

## 2.9.2 - 2026-07-06

### Fixed

- **"Check for Updates" now finds new releases.** The build number is now derived from the git commit count each release, so Sparkle correctly detects newer versions (previous releases all shared the same build number, which made update checks report "up to date"). No functional changes otherwise — same as 2.9.1.

## 2.9.1 - 2026-07-06

### Changed

- **Clearer "up to date" update message.** The dialog shown when you check for updates and you're already on the latest version has been reworded for clarity.
- **Richer version in About.** The About pane now shows the version as `v<version> (<build>) · <UTC build time>`, so it's easier to tell exactly which build you're running.

## 2.9.0 - 2026-07-06

### Fixed

- **Fixed a crash on first launch.** Ice 2 could crash immediately on launch when Accessibility hadn't been granted yet (for example, right after a fresh install), because a permission check could retrigger itself in a tight loop. It now launches reliably and keeps checking for the permission in the background without recursing.

### Changed

- **Layout is now its own Settings tab.** The menu bar **Layout** editor moved out of the Appearance tab's Style/Layout switch into its own item in the Settings sidebar, right after Appearance — so you can jump straight to arranging your menu bar items.
- **Refined the Settings UI.** About, What's New, and Permissions now use Ice 2's shared design components for a consistent look, and the Settings sidebar text is sized correctly.

### Added

- **What's New tab.** A new Settings tab shows what changed in the current version.

## 2.8.6 - 2026-07-05

### Fixed

- **Even lower idle CPU.** The pop-out Menu Bar Appearance editor was being built at launch and kept alive off screen, where its form kept re-laying itself out every display cycle. It's now built only when you actually open it (and released when closed), removing the remaining background CPU cost measured after 2.8.5. The editor itself is unchanged — it just loads on demand.

## 2.8.5 - 2026-07-05

### Fixed

- **Much lower idle CPU/energy use.** Ice 2 was keeping its Settings and Permissions windows laid out in the background even when they were closed and off screen, which made the app continuously re-render and burn several percent CPU at idle (visible in Activity Monitor's Energy tab). These windows now render their contents only while actually visible, so a closed Settings window costs nothing. This is the main fix for the reported battery/power drain, and it builds on the 2.8.4 changes.

## 2.8.4 - 2026-07-05

### Fixed

- **Lower power use.** Ice 2 no longer wakes on every mouse movement when it doesn't need to. The mouse-tracking used for "show on hover" is now only active while a hover option is actually turned on, so with hover off the app stays idle as you move the pointer — noticeably reducing CPU and energy use in Activity Monitor.
- **Lower CPU when switching apps (with a custom menu bar appearance).** The overlay that redraws the menu bar used to keep polling the macOS Accessibility API every 50 ms for up to 10 seconds after each app switch whenever the menu size hadn't changed. It now polls quickly only briefly while the menu settles, then backs off, cutting a CPU/energy spike that happened every time you changed apps.

## 2.8.2 - 2026-06-30

### Changed

- **Refined the About and Uninstall screens.** About now leads with a **Website** link (dragonapp.com/ice-2) and a **Support on GitHub** link that goes straight to the issues page, plus creator and license rows. **Uninstall** is now a clear confirmation sheet that lists exactly what gets removed, with the destructive **Uninstall** button on the left and **Cancel** as the default.

## 2.6.0 - 2026-06-29

### Added

- **Back up & restore your settings.** A new **Backup & Restore** settings pane saves a snapshot of all your Ice 2 settings — layout profiles, item groups, spacers, triggers, hotkeys, and appearance — to a folder you choose. Ice 2 keeps the newest 10 backups, backs up automatically when you quit, and restores any backup in one click. Point the backup folder at Dropbox, iCloud Drive, or Google Drive to sync your settings across Macs or set up a new Mac.

## 2.5.3 - 2026-06-28

### Added

- New option to show hidden menu bar items by hovering over the Ice 2 icon. Turn it on under Settings → General → "Show on hover over Ice 2 icon" (off by default). Each hover option now has its own delay slider shown right beneath it.

### Changed

- The existing "Show on hover" option is now labelled "Show on hover over empty menu bar" to make clear it reacts to empty areas of the menu bar, and its delay slider moved from Advanced settings to sit directly beneath the option in General settings. The "Automatically rehide" options now sit in the same section as the show options.

## 2.5.2 - 2026-06-27

### Changed

- Maintenance release: the CI lint workflow now runs on the latest supported Node.js runtime (GitHub Actions `actions/checkout@v7`, Node 24) and lints with the current SwiftLint (0.65.0) via its official image, replacing an unmaintained 2021-era action. A couple of now-redundant SwiftLint directives were removed. No user-facing changes.

## 2.5.1 - 2026-06-27

### Changed

- The always-hidden menu bar section is now enabled by default. You can still turn it off under Settings → Advanced → Menu Bar Sections.

## 2.5.0 - 2026-06-27

This update makes Ice 2 an Apple Silicon–only app.

### Changed

- **Ice 2 now runs only on Apple Silicon Macs** (the M1, M2, M3, M4 chips and newer). Support for older Intel-based Macs has been removed. If your Mac was made in late 2020 or later, it almost certainly has an Apple Silicon chip and you're all set. (You can check under  → About This Mac — look for a "Chip" line that says "Apple M…".)
- The app is now built just for Apple Silicon, so the download is a bit smaller and runs natively on your Mac with no Intel compatibility layer.

### Note

- If you're on an older Intel Mac, please stay on version 2.4.1, which remains available and continues to work.

## 2.3.0 - 2026-06-26

This release focuses on stability fixes for Tahoe/macOS 26 and early macOS 27 behavior reported upstream in `jordanbaird/Ice`.

### Added

- Added menu bar layout profiles, item groups, spacer items, trigger-based item showing, and extra hotkey actions for section divider icons, auto rehide, and temporarily showing individual menu bar items.
- Added an Advanced setting to disable Ice 2 right-click context menus in the menu bar. References upstream issue #892 and upstream PR #893.
- Added an option to remove the background behind the menu bar while keeping menu bar content visible.

### Fixed

- Added resilient Menu Bar Layout rendering when screen capture or item image capture fails, including per-item fallback labels instead of blank bars. References upstream issues #951, #921, #918, #916, #913, #891, #846, #833, #818, #816, #773, #762.
- Fixed MenuBarItemService XPC startup for ad-hoc/local builds without an Apple Team Identifier, preventing Menu Bar Layout from spinning forever on empty item data. References upstream issues #744 and #891, and upstream PRs #950 and #953.
- Fixed duplicate or same-app menu bar items overwriting each other in caches by keying item images, search IDs, and temporary visibility contexts by window identity. References upstream issues #857 and #854.
- Hardened synthetic menu bar click/move event handling to avoid checked-continuation double-resume crashes and stuck cursor hiding. References upstream issues #947, #821, #810, #796, #786, #759, #757, #751.
- Increased move-operation timing tolerance and reduced tight polling for apps whose menu bar items respond slowly on Tahoe. References upstream issues #918 and #861.
- Improved Ice Bar behavior so it does not auto-hide while the pointer is moving from the menu bar into the Ice Bar, and added a short grace period for transient offscreen frame reports. References upstream issues #925, #914, #871, #813, #890, #888, #814 and upstream PR #911.
- Fixed multi-display and fullscreen screen selection by preferring the display under the pointer when appropriate, including cases where macOS no longer reports an active menu bar display. References upstream issues #955, #929, #899, #858, #829, #825, #824, #790 and upstream PRs #868 and #922.
- Fixed Ice Bar sizing and color sampling when the reused Ice Bar panel moves between displays with different scale factors. References upstream issue #955.
- Anchored menu bar appearance overlays to the actual WindowServer menu bar bounds instead of inferred screen geometry, improving vertical monitor placement. References upstream issue #780.
- Fixed Menu Bar Layout getting stuck indefinitely on "Loading menu bar items..." by tracking completed cache attempts and offering a retry state when no manageable items are found. References upstream issues #954, #846, #818.
- Improved permissions onboarding by adding direct Accessibility settings URLs, active-window permission refresh, and manual recheck behavior. References upstream issues #882, #770, #934.
- Avoided stealing focus back from System Settings after permissions that may require relaunch, and clarified relaunch guidance for screen recording on macOS 26. References upstream issues #770 and #934.
- Prevented repeated Sparkle update permission prompts by declining automatic update-check permission prompting. References upstream issues #937, #912, #837.
- Added a Menu Bar Layout recovery action to restore the Ice 2 control icon when it has been removed. References upstream issues #919 and #860.
- Fixed color picker usability by allowing the appearance editor and system color panel to activate normally. References upstream issue #763.
- Improved tint alpha handling for menu bar appearance shapes so split/full shapes are visible while no-shape tint remains subtle. References upstream issue #943.
- Kept Ice as an accessory/menu bar app at launch to avoid unwanted Dock activation. References upstream issues #808, #768, #906.
- Added README uninstall instructions for Homebrew, manual removal, and optional settings cleanup. References upstream issue #949.
- Improved Tahoe source PID matching and Control Center title fallback for menu bar item identity. References upstream issues #832, #878, #887, #806.
- Fixed hide-application-menus behavior so it can still run when Ice Bar is enabled. References upstream issue #879.
- Fixed Option-click behavior so the always-hidden section can still be shown when regular Show on Click is disabled, and control-item Option-click falls back to normal expansion when the always-hidden section is disabled. References upstream issues #634 and #595.
- Fixed Show on Scroll so discrete mouse-wheel events can toggle hidden menu bar items instead of only high-delta trackpad swipes. References upstream issue #717.
- Excluded Ice's own spacer items from layout profiles, item groups, and trigger-based showing, so applying a profile or trigger no longer moves or clicks the app's spacer status items.
- Fixed menu bar appearance overlay placement by converting the WindowServer menu bar bounds from CoreGraphics to AppKit coordinates, correcting the overlay's vertical position on non-primary displays.
- Added a tag-based fallback when rehiding temporarily shown items, so an item is still returned to its original location if its owning app recreates its status window while shown.
- Ensured default layout profile and item group names stay unique even after earlier profiles/groups are deleted.

### Known Limitations

- macOS 27 introduces deeper system menu bar hiding behavior. This release improves cache, layout, and empty-state handling for the related reports, but full visible/hidden/always-hidden parity on macOS 27 still requires runtime validation on affected hardware. References upstream issue #954.
