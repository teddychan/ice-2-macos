#!/usr/bin/env bash
#
# run-debug.sh — build Ice, install the Debug product as /Applications/Ice 2 Debug.app,
# and (re)launch it from there.
#
# Why: a debug build must not share the installed app's bundle id
# (com.dragonapp.ice), which collides on TCC permissions, the menu-bar manager,
# and the UserDefaults domain. The Debug configuration handles that itself: it
# sets PRODUCT_BUNDLE_IDENTIFIER to com.dragonapp.ice.debug and the display name
# to "Ice 2 Debug", so the built product is already the isolated app and
# `xcodebuild test` gets the same isolation without going through this script.
#
# This script therefore builds, stamps, installs and launches — it deliberately does
# NOT re-id a copy of the product inside DerivedData. An earlier version did, which
# left two bundles claiming com.dragonapp.ice.debug in every DerivedData folder;
# LaunchServices then resolved that id ambiguously and could launch a stale build
# instead of the one just built. The stamped product is installed to
# /Applications/Ice 2 Debug.app (the old copy is deleted first, no backup) and
# launched by that exact path, so the running build is always the one just made.
#
# PRODUCT_NAME is "Ice 2 Debug" in the Debug configuration, so the bundle on disk,
# its executable, CFBundleName and CFBundleDisplayName all read "Ice 2 Debug" —
# there is nowhere left for the name "Ice 2" to appear on a debug build.
# PRODUCT_MODULE_NAME is pinned to Ice_2 so the Swift module keeps the name
# IceTests imports; TEST_HOST points at the Debug product by its own name.
#
# What the script stamps afterwards (all of them need the built bundle to exist):
#   CFBundleVersion             the git commit count, never a hardcoded number
#   DragonCommitDate            the commit's own timestamp
#   DragonBuildChannel          "Debug", which DragonKit renders as "vX.Y.Z Debug (<build>)"
#   SUEnableAutomaticChecks     false, so a debug build never schedules a production check
# and what it deletes:
#   SUFeedURL                   so the production appcast is unreachable from this bundle
#
# CFBundleShortVersionString is asserted to be numeric X.Y.Z and is never modified. It used to
# be suffixed " (Debug)" here; MAC-APP-RELEASE-LIFECYCLE.md forbids that outright, because that
# field is the sole source of truth for the version the public `vX.Y.Z` tag is checked against,
# and a debug build is the *same* numeric candidate as the next release — "Debug" is a channel
# label, never part of a version number. DragonKit 3.3.0's DragonAbout.buildChannel(_:) reads
# DragonBuildChannel and renders the label beside the version instead.
#
# Usage: bash scripts/run-debug.sh
#
# This is the Ice-specific instance of a shared convention: every Dragon macOS
# app builds its debug product as "<App> Debug" (<release-bundle-id>.debug).
# Other repos can copy this and change the vars below. See the "dragon-mac-ops"
# skill for the general recipe + rationale.
#
set -euo pipefail

SCHEME="Ice"
CONFIG="Debug"
DEBUG_ID="com.dragonapp.ice.debug"
DEBUG_NAME="Ice 2 Debug"

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

echo "==> Building $SCHEME ($CONFIG)…"
xcodebuild -scheme "$SCHEME" -configuration "$CONFIG" \
  -destination 'generic/platform=macOS' \
  build -quiet

products_dir="$(xcodebuild -scheme "$SCHEME" -configuration "$CONFIG" \
  -destination 'generic/platform=macOS' -showBuildSettings 2>/dev/null \
  | awk -F' = ' '/ BUILT_PRODUCTS_DIR = /{print $2; exit}')"

app="$products_dir/$DEBUG_NAME.app"

if [[ ! -d "$app" ]]; then
  echo "error: built app not found at: $app" >&2
  exit 1
fi

plist="$app/Contents/Info.plist"
pb=/usr/libexec/PlistBuddy

built_id="$("$pb" -c "Print :CFBundleIdentifier" "$plist")"
if [[ "$built_id" != "$DEBUG_ID" ]]; then
  echo "error: built app has bundle id '$built_id', expected '$DEBUG_ID'." >&2
  echo "       The Debug configuration must never build with the release id." >&2
  exit 1
fi

# Build number is the git commit count, never the hardcoded CURRENT_PROJECT_VERSION
# in the project — that value goes stale the moment anyone commits without bumping
# it, and a debug build reporting a stale number is worse than useless when you are
# trying to tell two builds apart. Same rule the release scripts follow.
build_number="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
"$pb" -c "Set :CFBundleVersion $build_number" "$plist"

# The commit's own timestamp, which DragonKit renders after the build number. The
# release workflow passes it as the DRAGON_COMMIT_DATE build setting; a plain local
# build defines no such setting, so stamp it here or a debug About pane shows the
# build number with no date beside it.
commit_date="$(git log -1 --format=%cI 2>/dev/null || true)"
if [[ -n "$commit_date" ]]; then
  "$pb" -c "Set :DragonCommitDate $commit_date" "$plist" 2>/dev/null \
    || "$pb" -c "Add :DragonCommitDate string $commit_date" "$plist"
fi

# The version field is read, never written. It carries the numeric candidate this debug build
# is testing towards — the very number a later `vX.Y.Z` tag is asserted against — so anything
# appended to it (this script used to append " (Debug)") makes the release gate compare a tag
# against a non-numeric string. Fail loudly instead: a candidate that isn't X.Y.Z means the
# project's MARKETING_VERSION is wrong, and every downstream stamp would inherit that.
short_version="$("$pb" -c "Print :CFBundleShortVersionString" "$plist")"
if [[ ! "$short_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "error: non-numeric candidate version: '$short_version'." >&2
  echo "       CFBundleShortVersionString must stay X.Y.Z — 'Debug' is a build channel," >&2
  echo "       stamped below as DragonBuildChannel, never part of a version number." >&2
  exit 1
fi

# The channel label the version field must not carry. DragonKit 3.3.0's
# DragonAbout.versionString() reads this key and renders "v2.14.1 Debug (1346) · …", so About,
# logs and screenshots still say Debug outright while the number stays the release candidate.
"$pb" -c "Set :DragonBuildChannel Debug" "$plist" 2>/dev/null \
  || "$pb" -c "Add :DragonBuildChannel string Debug" "$plist"

# Production updating off, two ways. The plist default only sets what Sparkle does when the
# user has expressed no preference — and user defaults win, so someone who once enabled
# scheduled checks in this debug build's own domain would still get them. Deleting SUFeedURL
# is what actually makes the production appcast unreachable: DragonUpdater's lazy SPUUpdater
# fails to start without a feed, so DragonKit's Updates pane (kit-owned UI this app cannot
# make channel-aware) renders inert instead of checking the real feed. The runtime guards in
# UpdatesManager remain the primary defence; this is belt and braces, per the
# `macos-debug-build` skill.
if "$pb" -c "Print :SUEnableAutomaticChecks" "$plist" >/dev/null 2>&1; then
  "$pb" -c "Set :SUEnableAutomaticChecks false" "$plist"
fi
"$pb" -c "Delete :SUFeedURL" "$plist" 2>/dev/null || true

# Editing Info.plist invalidates the code signature, so re-sign, deep: the bundle carries
# Sparkle.framework and the MenuBarItemService XPC, and a broken signature on either makes
# the app fail to launch rather than fail visibly.
#
# TCC binds a grant to the designated requirement. Ad-hoc, that is the cdhash, so every
# rebuild is a new app and Accessibility / Screen Recording must be granted again. Signed
# with a stable self-signed certificate it is "this identifier + this certificate", which
# survives rebuilds. "ClipMenu Dev" is the one clipmenu-2's scripts already sign with; the
# bundle id still keeps each app's grant separate. Without it, fall back to ad-hoc.
SIGN_IDENTITY="ClipMenu Dev"
if security find-identity -p codesigning 2>/dev/null | grep -q "\"$SIGN_IDENTITY\""; then
  identity="$SIGN_IDENTITY"
else
  identity="-"
fi
echo "==> Re-signing after stamping Debug channel, v$short_version ($build_number), as: $identity"
codesign --force --deep --sign "$identity" "$app"

# Every running copy, wherever it was started from (/Applications, another DerivedData folder),
# found by the Debug bundle id, so the installed release "Ice 2.app" (com.dragonapp.ice) is
# never touched. The guard keeps the rm -rf below from ever naming a non-Debug bundle.
[[ "$DEBUG_NAME" == *" Debug" && "$DEBUG_ID" == *.debug ]] \
  || { echo "error: refusing to stop or replace a non-Debug identity" >&2; exit 1; }
debug_pids() {
  lsappinfo find "bundleid=$DEBUG_ID" | while IFS= read -r asn; do
    lsappinfo info -only pid "$asn" | sed -n 's/.*pid = \([0-9][0-9]*\).*/\1/p'
  done
}
echo "==> Quitting any running ${DEBUG_NAME}…"
pids="$(debug_pids)"
if [[ -n "$pids" ]]; then
  kill $pids 2>/dev/null || true
  for _ in {1..10}; do
    [[ -z "$(debug_pids)" ]] && break
    sleep 0.5
  done
  pids="$(debug_pids)"
  [[ -z "$pids" ]] || kill -9 $pids 2>/dev/null || true
fi

# Installed like any other app: the previous copy is deleted outright (no backup), then the
# freshly stamped bundle is copied in. ditto keeps the signature intact.
installed="/Applications/$DEBUG_NAME.app"
echo "==> Installing $installed"
rm -rf "$installed"
ditto "$app" "$installed"

# `open -n` on this exact path, never `open -b <id>`: the DerivedData product and stray
# "Ice 2 Debug.app" copies in other DerivedData folders claim the same id, and LaunchServices
# would pick one it likes. Not an exec from this shell either: a process started from a
# terminal has the terminal as its responsible process, so TCC checks the terminal's grants
# and the app reports Accessibility as missing however often it is granted. `open` also
# parents the app to launchd, so it outlives this shell.
echo "==> Launching $installed"
open -n "$installed"

cat <<EOF

Launched "$DEBUG_NAME" v$short_version Debug (build $build_number), id $DEBUG_ID, from:
  $installed

- v$short_version is the numeric candidate for the next public release; "Debug" is the
  build channel, not part of the version.
- Grant Accessibility / Screen Recording to "$DEBUG_NAME" in its Permissions
  window if you want full functionality (separate from your installed Ice 2).
$(if [[ "$identity" == "-" ]]; then
  echo "- Signed ad-hoc (no \"$SIGN_IDENTITY\" identity found), so every rebuild must be re-granted."
else
  echo "- Signed with \"$SIGN_IDENTITY\", so grants survive rebuilds."
fi)
- Updating is disabled in this build: no scheduled checks, no Check for Updates…
  item in the menu, and no production feed in the bundle.
EOF
