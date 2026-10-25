# macOS 27 native sections

The macOS 27 backend uses Accessibility to discover app bundles and native system
items, and runtime-loaded `MenuBarClientCore` assertions to hide them. It never
invents window IDs. macOS 26 and earlier continue to use the legacy backend.

## Behavior

* Layout has three labeled drop targets: Visible, Hidden, and Always-Hidden.
  Drag an app card into a section, or use its ellipsis menu for Move to actions.
  All status items belonging to one bundle share visibility. New apps default
  to Visible. Drops persist immediately and do not change physical ordering.
* Cards use installed app icons, explicitly labeled “App icon”; supported system
  items use symbolic fallbacks labeled “Preview unavailable”. The native bridge
  has no verified per-icon image source. Earlier AX snapshots reported overlapping
  rectangles for unrelated apps, so screen crops would risk showing the wrong
  icon. Real menu bar previews are deferred until reliable bounds are verified.
* Hidden and saved absent apps remain editable. Unsupported system items appear
  separately under “Managed by macOS”. Visibility buttons explicitly distinguish
  showing items from changing their saved assignments.
* Show Hidden reveals the Hidden section; Show All includes Always-Hidden.
  Ice's section toggles, section hotkeys, and rehide behavior use the native
  backend. Items reveal directly in the system menu bar, across displays.
* Hidden AX nodes disappear, so discovered rows remain cached and saved identities
  stay available while apps are hidden or not running. Discovery runs off the main
  thread with AX timeouts and a bounded traversal.
* Section assignments persist under `NativeMenuBarSections`, separately from old
  per-window layouts. The existing backup mechanism includes the new key.
* Applying an old profile maps stable bundle namespaces and recognized system
  names. Conflicting entries keep the more visible section. Unmatched entries and
  conflicts are counted in the UI; applying a wholly unmappable profile fails
  without changing assignments. Applying does not rewrite the source profile.
* Native profile capture saves section membership, including saved absent apps.
  It does not save ordering. Native profile tags do not restore per-item ordering
  on older macOS. Keep legacy profiles if moving between OS versions.
* Assertion replacements activate before the old assertion is released. Generation
  checks ignore stale callbacks. Failure or timeout restores all sections. Quit
  and sleep invalidate both active and pending assertions; wake and Space changes
  refresh discovery and restore the requested section state.

## Limitations shown in the app

* Focus and other system extras can disappear as a side effect of assessment mode.
* Clock, Control Center, SystemUIServer extras and unmapped native items cannot
  be independently assigned through this backend.
* Separate Ice Bar, per-icon search and temporary per-icon reveal are unavailable.
  Their controls/hotkeys are disabled, without deleting saved bindings or older
  OS preferences. App triggers that rely on individual legacy items are not
  supported by this backend.
* Command-drag in the system menu bar remains the way to change physical order.
* The private API may change; runtime capability checks do not guarantee future
  macOS support.

## Verification

Automated tests cover section policy, protected items, new apps, native tag
round-trips, legacy profile conflicts/unmatched identities, unmappable profile
rejection, assertion handover, stale failures, failure cleanup, late callbacks
after restoration and avoiding redundant reactivation.

2026-09-17 validation: **341 tests passed**, changed app Swift files passed strict
lint, and the Objective-C bridge passed `-Wall -Wextra -Werror` syntax checking.
Live verification passed steps 2–6 below with automatic rehide temporarily off
for the section-isolation check. The preview's original automatic-rehide setting
was restored afterward. Applying a copy of the user's `Default View` profile
reported one bundle conflict and five unmappable entries, retained the source
profile, and persisted the mapped sections across relaunch. Quitting while Dropbox
and Google Drive were hidden restored both in MenuBarAgent's Accessibility tree.

Manual checklist on macOS 27.0 (26A428):

1. Start the separate Debug build with the release and prototype stopped.
2. Drag two test apps to Hidden and Always-Hidden; Hide Hidden and Always-Hidden Items hides both.
3. Show Hidden reveals only the Hidden app; Show All restores both.
4. Save a profile, change assignments, then apply the profile and verify membership.
5. Quit while hidden: both apps return. Relaunch: assignments persist.
6. Check Layout while hidden: rows stay present and editable.
7. Verify multiple displays, Spaces, sleep/wake, permission revocation, hotkeys,
   and new app launches before release. These require additional runtime coverage
   beyond the automated policy and lifecycle tests.

The preview uses `com.dragonapp.ice.debug` with separate preferences. It does not
replace `/Applications/Ice 2.app` or automatically import release profiles. For the
local verification session, a copy of the release profile was explicitly put into
the preview's preferences; the release preferences were not modified.

The isolated [prototype report](macos27-prototype.md) records the earlier feasibility
experiment. Its integration checklist predates this backend.

## Visual section editor validation (2026-09-18)

* Clean Debug build succeeded; **343 tests passed**. The two new tests verify
  saving each native section and capturing a single bundle tag, and rejecting
  protected items / unknown drop identities without changing saved membership.
* All four changed native Swift files passed strict lint; `git diff --check`
  passed. Existing native profile tags, migration, and the earlier-macOS layout
  branch were retained.
* Live inspection caught macOS Menu consuming the drag gesture and flattening
  card labels. Cards now have an AppKit drag source, a separately accessible
  ellipsis menu, an exported private pasteboard type, and a move drop proposal.
* Accessibility is working. The separate Downloads preview is signed with the
  existing Apple Development identity and a stable designated requirement;
  permission remained valid across subsequent preview updates and restarts.
* Verified a real Always-Hidden → Hidden drag with Dropbox and immediate saved
  feedback. Menu assignment to Always-Hidden persisted across a process restart.
  A temporary profile saved successfully and restored Dropbox from Visible to
  Hidden with zero migration conflicts or unmatched entries.
* Other automated pointer drops were intermittent (source events arrived, but
  some drops did not). On 2026-09-18, the user manually tested the final signed
  preview and confirmed that it works as expected. This is manual confirmation,
  not a claim of exhaustive automated drag-direction coverage.
* Removed the temporary verification profile, restored the starting native
  assignment dictionary, and checked that the original profile was semantically
  unchanged. The clean preview is running; diagnostic logging was removed.
  Production app and preferences were not modified.

## Related reports and intended fix

* [#53](https://github.com/teddychan/ice-2-macos/issues/53) reports that collapsing the
  hidden section leaves apps visible on macOS 27 beta. The native backend
  replaces the legacy oversized-divider/window model with bundle-level native
  visibility assertions on macOS 27.
* [#116](https://github.com/teddychan/ice-2-macos/issues/116) reports an Ice Bar stuck at
  “Loading menu bar items…” on 27.0 (26A428). Native discovery no longer waits
  for individual item windows that this build does not expose. Hidden items are
  revealed in the system menu bar, and settings explain that the separate Ice
  Bar is unavailable. This does not restore the below-menu-bar panel on macOS 27.
* The visual editor makes the native app-bundle assignments explicit and keeps
  assignment changes separate from temporary section visibility. Earlier macOS
  versions retain their existing backend and separate Ice Bar.
