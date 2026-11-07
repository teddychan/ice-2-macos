<div align="center">
    <img src="Ice/Resources/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" width="160" height="160" alt="Ice 2 app icon">
    <h1>Ice 2</h1>
    <p><strong>Menu bar management for macOS</strong></p>
</div>

Ice 2 hides the menu bar items you don't need. Each item is either shown or hidden, and
the hidden ones wait in the Ice Bar, a small panel under the Ice icon. Click an item there to
open its menu.

[![Download](https://img.shields.io/badge/download-latest-brightgreen?style=flat-square)](https://github.com/teddychan/ice-2-macos/releases/latest)
![Platform](https://img.shields.io/badge/platform-macOS-blue?style=flat-square)
![Requirements](https://img.shields.io/badge/requirements-macOS%2027%2B-fa4e49?style=flat-square)
[![Website](https://img.shields.io/badge/Website-dragonapp.com-015FBA?style=flat-square)](https://www.dragonapp.com/ice-2/)
[![License](https://img.shields.io/badge/license-GPL--3.0-blue?style=flat-square)](LICENSE)

## Contents

- [Requirements](#requirements)
- [Install](#install)
- [Features](#features)
- [How it works](#how-it-works)
- [Troubleshooting](#troubleshooting)
- [Building from source](#building-from-source)
- [Tests](#tests)
- [Contributing](#contributing)
- [Credits](#credits)
- [License](#license)

## Requirements

- macOS 27 or later. Ice 2 2.17 remains the release for macOS 26, on the
  [releases page](https://github.com/teddychan/ice-2-macos/releases).
- An Apple Silicon Mac.
- Accessibility permission. Ice 2 uses it to find menu bar items and to open an item's menu
  from the Ice Bar. Until it is granted, nothing is hidden.

## Install

### Homebrew

```sh
brew install --cask teddychan/tap/ice-2
```

### Manual

Download the `Ice-2-vX.Y.Z.zip` file from the
[latest release](https://github.com/teddychan/ice-2-macos/releases/latest) and move the
unzipped app into your `Applications` folder.

### Uninstall

Quit Ice 2 before uninstalling.

If you installed with Homebrew:

```sh
brew uninstall --cask teddychan/tap/ice-2
```

If you installed manually, delete `Ice 2.app` from your `Applications` folder.

To also remove Ice 2 settings and cached data:

```sh
rm -rf ~/Library/Application\ Support/com.dragonapp.ice \
       ~/Library/Caches/com.dragonapp.ice \
       ~/Library/HTTPStorages/com.dragonapp.ice \
       ~/Library/Preferences/com.dragonapp.ice.plist \
       ~/Library/Saved\ Application\ State/com.dragonapp.ice.savedState
```

## Features

> [!NOTE]
> Ice 2 is an independent, open-source fork of [Ice](https://github.com/jordanbaird/Ice) — the menu bar manager originally created by [Jordan Baird](https://github.com/jordanbaird) — now actively maintained by [Teddy Chan](https://github.com/teddychan) and carried forward to support modern macOS. Download the latest release [here](https://github.com/teddychan/ice-2-macos/releases/latest) and see the roadmap below for upcoming features.

- Show or Hide each menu bar item. On macOS 27 this applies to a whole app: all of an app's
  icons are shown or hidden together.
- The Ice Bar: click the Ice icon to see the hidden items, and click one to open its menu.
- One order for the Ice Bar and Settings; drag in either to change it.
- Launch at login, Settings in eight languages, and a switch to hide the Ice icon from the
  menu bar.
- Updates through [Sparkle](https://sparkle-project.org).
- Back up and restore every setting to a folder you choose.

## How it works

- **Click** the Ice icon to open the Ice Bar. Click it again, click elsewhere or press Escape
  to close it.
- **Click an item in the Ice Bar** to open its menu. Ice 2 shows the item in the menu bar for as
  long as its menu is open, so the menu opens at the item's own place in the menu bar.
- **Right-click** the Ice icon for About, Check for Updates, Settings and Quit.
- Choose Show or Hide for each item in **Settings ▸ General**. New apps start as Show.
- Ice 2 can't change the order of the menu bar itself. **Command-drag** hidden apps next to the
  Ice icon so their menus open close by.
- The clock and Control Center can't be hidden on macOS 27, so they aren't listed.
- Quitting Ice 2 shows every item again.

## Troubleshooting

If nothing hides, check that Ice 2 still has Accessibility permission in
**System Settings ▸ Privacy & Security ▸ Accessibility**. Settings ▸ General says when hiding
is off and why.

### Why does Ice 2 3.0 require macOS 27?

macOS 27 draws every menu bar item into one system window, which broke the way earlier
versions found and moved items. Ice 2 3.0 is built for the new menu bar. Ice 2 2.17 keeps
working on macOS 26 and is on the
[releases page](https://github.com/teddychan/ice-2-macos/releases).

### Why does Ice 2 need network access?

Only to check for and download updates, using [Sparkle](https://sparkle-project.org).
Ice 2 has no telemetry, analytics, or crash reporting, and it sends nothing about
you, your Mac, or your menu bar anywhere. Automatic update checks are off by default,
so Ice 2 only goes online when you choose **Check for Updates…** or turn on automatic
checks in **Settings ▸ Updates**.

If you'd rather Ice 2 never goes online, block its network access on your Mac with
an outbound firewall or your organization's device management. Everything except
updating keeps working.

### Can I back up, restore, or sync my settings?

Yes. Open **Settings ▸ Backup & Restore** and choose a backup folder. **Back Up Now** saves
every setting: launch at login, the language, whether the Ice icon shows in the menu bar, which
items are shown or hidden, and their order. Restore any backup with one click; Ice 2 relaunches
to apply it.

To **sync across Macs** or move to a new Mac, point the backup folder at a synced location such
as Dropbox, iCloud Drive, or Google Drive, then restore the backup on the other Mac.

## Building from source

Ice 2 is a plain Xcode project — no package manager step is required.

1. Clone the repo and open `Ice.xcodeproj` in Xcode 26 or later (the project targets
   the macOS 26 SDK and builds for arm64).
2. Select the **Ice** scheme and run. The product is named `Ice 2.app`.

From the command line:

```sh
xcodebuild -scheme Ice -configuration Debug -destination 'generic/platform=macOS' build
xcodebuild -scheme Ice -destination 'platform=macOS' test
```

The **Ice** scheme's test action runs the `IceTests` unit-test target.

The Debug configuration builds the app as `com.dragonapp.ice.debug`, displayed as
**Ice 2 Debug**, never the release id — so neither a local build nor the test host
(which runs *inside* the app) can read or write the settings of an installed Ice 2.
The product itself is the isolated app; nothing re-ids it afterwards, so only one
bundle ever claims that id.

To try a local build alongside an installed copy of Ice 2, use the debug runner. It
builds the **Ice** scheme, installs the product as `/Applications/Ice 2 Debug.app`
(replacing the previous copy) and launches it from there. It already has its own
name, permissions, and settings, so it runs alongside the release app:

```sh
bash scripts/run-debug.sh
```

Swift sources are linted with [SwiftLint](https://github.com/realm/SwiftLint)
(`.swiftlint.yml`); CI runs `swiftlint lint --strict` on every pull request that
touches Swift files.

## Tests

The unit tests live in `IceTests/` and are written with Swift Testing. They cover the parts
of Ice 2 that need no permissions: which entries count as items, how discovered items and saved
settings combine into the list, the shared order, the hiding configuration, the Ice Bar's
placement, the upgrade from 2.x, settings persistence, localization coverage, the uninstaller's
configuration and the bundled notices. Hiding, the Ice Bar and opening an item's menu need a
live macOS 27 menu bar and granted Accessibility, so they are checked by hand (see the manual
list in [the 3.0.0 spec](docs/superpowers/specs/2026-11-07-ice-2-v3-design.md#testing)). CI runs
the suite on every pull request; the Debug configuration signs ad-hoc, so no Apple Development
certificate is needed to run it locally either.

[![Tests](https://github.com/teddychan/ice-2-macos/actions/workflows/tests.yml/badge.svg)](https://github.com/teddychan/ice-2-macos/actions/workflows/tests.yml)

```bash
xcodebuild test -project Ice.xcodeproj -scheme Ice \
  -destination 'platform=macOS,arch=arm64'
```

| Metric | Value |
|---|---|
| Test cases | 66 passing |
| Measured on | 3.0.0, Xcode 27.2 on macOS 27.2 |

## Contributing

Issues and pull requests are welcome.

- Read the [Code of Conduct](CODE_OF_CONDUCT.md) before taking part.
- Check [FREQUENT_ISSUES.md](FREQUENT_ISSUES.md) first — several common reports are
  already answered there.
- Keep the build lint-clean; CI runs SwiftLint in strict mode.
- Release mechanics (tagging, signing, notarization, the Sparkle appcast, and the
  Homebrew cask) are documented in [docs/RELEASING.md](docs/RELEASING.md).

## Credits

Ice 2 is a fork of [Ice](https://github.com/jordanbaird/Ice), created by [Jordan Baird](https://github.com/jordanbaird). All credit for the original app goes to him and its contributors. Ice 2 is currently maintained by [Teddy Chan](https://github.com/teddychan).

## License

Ice 2 is available under the [GPL-3.0 license](LICENSE), the same license as the original Ice.
