// menubar-probe.swift
//
// A standalone, permission-free probe for issue #53 (menu bar items not hidden
// on macOS 27). It exercises the single private API that Ice's entire menu bar
// model rests on — `CGSGetProcessMenuBarWindowList` — and reports how many
// windows the WindowServer says the menu bar is made of.
//
// On macOS 26 and earlier, every menu bar item is its own window, so the list
// contains one entry per item plus the main menu bar itself. If macOS 27 has
// collapsed the menu bar into a single window, the list collapses to just the
// main menu bar and Ice sees zero items.
//
// Requires no Accessibility and no Screen Recording permission. It reads window
// metadata only: it creates nothing, moves nothing, and changes no setting.
//
// Run it without cloning the repository:
//
//   curl -fsSL https://raw.githubusercontent.com/teddychan/ice-2-macos/main/scripts/menubar-probe.swift \
//     -o /tmp/menubar-probe.swift &&
//     swiftc -O /tmp/menubar-probe.swift -o /tmp/menubar-probe &&
//     /tmp/menubar-probe
//
// Or from a checkout:
//
//   swiftc -O scripts/menubar-probe.swift -o /tmp/menubar-probe && /tmp/menubar-probe
//
// Must run in a normal logged-in GUI session — it needs a WindowServer
// connection, so it will not work over SSH or on a headless CI runner.

import CoreGraphics
import Foundation

typealias CGSConnectionID = Int32

@_silgen_name("CGSMainConnectionID")
func CGSMainConnectionID() -> CGSConnectionID

@_silgen_name("CGSGetWindowCount")
func CGSGetWindowCount(
    _ cid: CGSConnectionID,
    _ targetCID: CGSConnectionID,
    _ outCount: inout Int32
) -> CGError

@_silgen_name("CGSGetProcessMenuBarWindowList")
func CGSGetProcessMenuBarWindowList(
    _ cid: CGSConnectionID,
    _ targetCID: CGSConnectionID,
    _ count: Int32,
    _ list: UnsafeMutablePointer<CGWindowID>,
    _ outCount: inout Int32
) -> CGError

@_silgen_name("CGSGetWindowLevel")
func CGSGetWindowLevel(
    _ cid: CGSConnectionID,
    _ wid: CGWindowID,
    _ outLevel: inout CGWindowLevel
) -> CGError

@_silgen_name("CGSGetScreenRectForWindow")
func CGSGetScreenRectForWindow(
    _ cid: CGSConnectionID,
    _ wid: CGWindowID,
    _ outRect: inout CGRect
) -> CGError

let connection = CGSMainConnectionID()
let mainMenuLevel = CGWindowLevelForKey(.mainMenuWindow)

// MARK: Environment

let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
print("macOS: \(osVersion)")
print("main menu window level: \(mainMenuLevel)")
print("CGSMainConnectionID: \(connection)")

guard connection != 0 else {
    print("\nRESULT: FAILED — no WindowServer connection. Run this from a normal")
    print("logged-in GUI session, not over SSH and not from a headless CI runner.")
    exit(1)
}

// MARK: The probe

var capacity: Int32 = 0
let countResult = CGSGetWindowCount(connection, 0, &capacity)
guard countResult == .success else {
    print("\nRESULT: FAILED — CGSGetWindowCount returned \(countResult.rawValue)")
    exit(1)
}

var list = [CGWindowID](repeating: 0, count: Int(capacity))
var returnedCount: Int32 = 0
let listResult = CGSGetProcessMenuBarWindowList(connection, 0, capacity, &list, &returnedCount)
guard listResult == .success else {
    print("\nRESULT: FAILED — CGSGetProcessMenuBarWindowList returned \(listResult.rawValue)")
    print("If this symbol is gone or now returns an error, that alone explains #53.")
    exit(1)
}

let windowIDs = [CGWindowID](list[..<Int(returnedCount)])

// MARK: Report

print("\nCGSGetProcessMenuBarWindowList returned \(windowIDs.count) window(s):\n")

var itemWindowCount = 0
for windowID in windowIDs {
    var level: CGWindowLevel = 0
    let levelResult = CGSGetWindowLevel(connection, windowID, &level)
    var frame = CGRect.zero
    let frameResult = CGSGetScreenRectForWindow(connection, windowID, &frame)

    let isMainMenuBar = levelResult == .success && level == mainMenuLevel
    if !isMainMenuBar {
        itemWindowCount += 1
    }

    let levelText = levelResult == .success ? "\(level)" : "err \(levelResult.rawValue)"
    let frameText = frameResult == .success
        ? "x=\(Int(frame.minX)) y=\(Int(frame.minY)) w=\(Int(frame.width)) h=\(Int(frame.height))"
        : "frame err \(frameResult.rawValue)"
    let kind = isMainMenuBar ? "MAIN MENU BAR" : "item"

    print("  wid \(windowID)  level \(levelText)  \(frameText)  <- \(kind)")
}

print("\n--- summary ---")
print("total menu bar windows : \(windowIDs.count)")
print("individual item windows: \(itemWindowCount)")

if itemWindowCount == 0 {
    print("""

    RESULT: REPRODUCED the root cause of issue #53.

    The WindowServer reports no per-item menu bar windows. Ice enumerates menu
    bar items exclusively through CGSGetProcessMenuBarWindowList and filters out
    the main menu bar window, so it sees an empty item list. That is why the Ice
    icon still appears (a plain NSStatusItem, unaffected) while nothing hides,
    and why the layout view spins on "loading menu bar items" forever.

    Expanding the control item to 10,000pt cannot hide anything either: with a
    single consolidated menu bar window there are no sibling item windows to push
    off the left edge.
    """)
} else {
    print("""

    RESULT: NOT reproduced on this system.

    \(itemWindowCount) per-item menu bar windows are present, which is the layout
    Ice is built for. Hiding works here by expanding the hidden control item so
    the item windows to its left overflow past the left edge of the menu bar.
    """)
}
