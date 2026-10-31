//
//  WindowInfoTests.swift
//  IceTests
//

import Cocoa
import Testing
@testable import Ice_2

/// Covers how Ice identifies the two system windows it depends on: the
/// menu bar window (used for capture, appearance overlays and height
/// measurement) and the wallpaper window (used for average-color tinting).
struct WindowInfoTests {
    /// Mirrors `WindowInfo`'s stored properties so fixtures can be built
    /// through its synthesized `Codable` conformance — the type itself has
    /// no memberwise initializer.
    private struct Fixture: Encodable {
        var windowID: CGWindowID = 1
        var ownerPID: pid_t = 501
        var bounds: CGRect = .zero
        var layer: Int = 0
        var title: String?
        var ownerName: String?
        var isOnScreen: Bool = true
    }

    private func makeWindow(_ fixture: Fixture) throws -> WindowInfo {
        let data = try JSONEncoder().encode(fixture)
        return try JSONDecoder().decode(WindowInfo.self, from: data)
    }

    /// A rect guaranteed to sit inside the main display.
    private var boundsInsideMainDisplay: CGRect {
        CGDisplayBounds(CGMainDisplayID()).insetBy(dx: 10, dy: 10)
    }

    /// A rect guaranteed to sit outside the main display.
    private var boundsOutsideMainDisplay: CGRect {
        let displayBounds = CGDisplayBounds(CGMainDisplayID())
        return CGRect(x: displayBounds.maxX + 1000, y: displayBounds.maxY + 1000, width: 100, height: 24)
    }

    /// A window that satisfies every menu bar window criterion.
    private func makeMenuBarWindow(
        windowID: CGWindowID = 1,
        title: String? = "Menubar",
        ownerName: String? = "Window Server",
        layer: Int = Int(kCGMainMenuWindowLevel),
        isOnScreen: Bool = true,
        bounds: CGRect? = nil
    ) throws -> WindowInfo {
        try makeWindow(Fixture(
            windowID: windowID,
            bounds: bounds ?? boundsInsideMainDisplay,
            layer: layer,
            title: title,
            ownerName: ownerName,
            isOnScreen: isOnScreen
        ))
    }

    // MARK: Codable

    @Test func codableRoundTripPreservesEveryField() throws {
        let bounds = CGRect(x: 10, y: 20, width: 300, height: 24)
        let window = try makeWindow(Fixture(
            windowID: 42,
            ownerPID: 777,
            bounds: bounds,
            layer: 25,
            title: "Menubar",
            ownerName: "Window Server",
            isOnScreen: true
        ))
        #expect(window.windowID == 42)
        #expect(window.ownerPID == 777)
        #expect(window.bounds == bounds)
        #expect(window.layer == 25)
        #expect(window.title == "Menubar")
        #expect(window.ownerName == "Window Server")
        #expect(window.isOnScreen)

        let reencoded = try JSONEncoder().encode(window)
        let decoded = try JSONDecoder().decode(WindowInfo.self, from: reencoded)
        #expect(decoded.windowID == window.windowID)
        #expect(decoded.bounds == window.bounds)
        #expect(decoded.title == window.title)
        #expect(decoded.ownerName == window.ownerName)
        #expect(decoded.layer == window.layer)
        #expect(decoded.isOnScreen == window.isOnScreen)
    }

    @Test func absentTitleAndOwnerNameDecodeToNil() throws {
        let window = try makeWindow(Fixture())
        #expect(window.title == nil)
        #expect(window.ownerName == nil)
    }

    // MARK: isWindowServerWindow

    @Test func windowServerWindowIsIdentifiedByOwnerName() throws {
        #expect(try makeWindow(Fixture(ownerName: "Window Server")).isWindowServerWindow)
        #expect(!(try makeWindow(Fixture(ownerName: "Dock")).isWindowServerWindow))
        #expect(!(try makeWindow(Fixture(ownerName: nil)).isWindowServerWindow))
        // The check is exact, not a prefix or case-insensitive match.
        #expect(!(try makeWindow(Fixture(ownerName: "window server")).isWindowServerWindow))
    }

    // MARK: menuBarWindow

    @Test func menuBarWindowMatchesAFullyQualifyingWindow() throws {
        let window = try makeMenuBarWindow()
        let found = WindowInfo.menuBarWindow(from: [window], for: CGMainDisplayID())
        #expect(found?.windowID == window.windowID)
    }

    @Test func menuBarWindowRejectsOffScreenWindows() throws {
        let window = try makeMenuBarWindow(isOnScreen: false)
        #expect(WindowInfo.menuBarWindow(from: [window], for: CGMainDisplayID()) == nil)
    }

    @Test func menuBarWindowRejectsTheWrongLayer() throws {
        let window = try makeMenuBarWindow(layer: Int(kCGMainMenuWindowLevel) - 1)
        #expect(WindowInfo.menuBarWindow(from: [window], for: CGMainDisplayID()) == nil)
    }

    @Test func menuBarWindowRejectsTheWrongTitle() throws {
        #expect(WindowInfo.menuBarWindow(from: [try makeMenuBarWindow(title: "Menu Bar")], for: CGMainDisplayID()) == nil)
        #expect(WindowInfo.menuBarWindow(from: [try makeMenuBarWindow(title: nil)], for: CGMainDisplayID()) == nil)
    }

    @Test func menuBarWindowRejectsNonWindowServerOwners() throws {
        let window = try makeMenuBarWindow(ownerName: "Dock")
        #expect(WindowInfo.menuBarWindow(from: [window], for: CGMainDisplayID()) == nil)
    }

    @Test func menuBarWindowRejectsWindowsOutsideTheDisplay() throws {
        let window = try makeMenuBarWindow(bounds: boundsOutsideMainDisplay)
        #expect(WindowInfo.menuBarWindow(from: [window], for: CGMainDisplayID()) == nil)
    }

    @Test func menuBarWindowSkipsNonMatchesAndReturnsTheFirstMatch() throws {
        let decoys = [
            try makeMenuBarWindow(windowID: 10, title: "Backstop"),
            try makeMenuBarWindow(windowID: 11, ownerName: "Dock"),
            try makeMenuBarWindow(windowID: 12, isOnScreen: false),
        ]
        let matches = [
            try makeMenuBarWindow(windowID: 13),
            try makeMenuBarWindow(windowID: 14),
        ]
        let found = WindowInfo.menuBarWindow(from: decoys + matches, for: CGMainDisplayID())
        #expect(found?.windowID == 13)
    }

    @Test func menuBarWindowOnEmptyListIsNil() {
        #expect(WindowInfo.menuBarWindow(from: [], for: CGMainDisplayID()) == nil)
    }

    // MARK: wallpaperWindow

    @Test func wallpaperWindowRejectsNonDockOwners() throws {
        // Owned by this test process, so it can't be the Dock's wallpaper window.
        let window = try makeWindow(Fixture(
            ownerPID: ProcessInfo.processInfo.processIdentifier,
            bounds: boundsInsideMainDisplay,
            title: "Wallpaper-1"
        ))
        #expect(WindowInfo.wallpaperWindow(from: [window], for: CGMainDisplayID()) == nil)
    }

    @Test func wallpaperWindowRequiresTheWallpaperTitlePrefix() throws {
        guard let dockPID = NSRunningApplication.dockPID else {
            return // No Dock running; nothing deterministic to assert.
        }
        let wrongTitle = try makeWindow(Fixture(
            ownerPID: dockPID,
            bounds: boundsInsideMainDisplay,
            title: "Desktop Picture"
        ))
        #expect(WindowInfo.wallpaperWindow(from: [wrongTitle], for: CGMainDisplayID()) == nil)

        let noTitle = try makeWindow(Fixture(ownerPID: dockPID, bounds: boundsInsideMainDisplay))
        #expect(WindowInfo.wallpaperWindow(from: [noTitle], for: CGMainDisplayID()) == nil)
    }

    @Test func wallpaperWindowMatchesADockOwnedWallpaperInsideTheDisplay() throws {
        guard let dockPID = NSRunningApplication.dockPID else {
            return // No Dock running; nothing deterministic to assert.
        }
        let window = try makeWindow(Fixture(
            windowID: 99,
            ownerPID: dockPID,
            bounds: boundsInsideMainDisplay,
            title: "Wallpaper-1-0"
        ))
        #expect(WindowInfo.wallpaperWindow(from: [window], for: CGMainDisplayID())?.windowID == 99)
    }

    @Test func wallpaperWindowRejectsWindowsOutsideTheDisplay() throws {
        guard let dockPID = NSRunningApplication.dockPID else {
            return // No Dock running; nothing deterministic to assert.
        }
        let window = try makeWindow(Fixture(
            ownerPID: dockPID,
            bounds: boundsOutsideMainDisplay,
            title: "Wallpaper-1-0"
        ))
        #expect(WindowInfo.wallpaperWindow(from: [window], for: CGMainDisplayID()) == nil)
    }

    @Test func wallpaperWindowOnEmptyListIsNil() {
        #expect(WindowInfo.wallpaperWindow(from: [], for: CGMainDisplayID()) == nil)
    }

    @Test func wallpaperWindowMatchesFullDisplayDesktopLevelThirdPartyWallpaper() throws {
        let displayBounds = CGDisplayBounds(CGMainDisplayID())
        let desktopLevel = Int(CGWindowLevelForKey(.desktopWindow))
        let backstop = try makeWindow(Fixture(
            windowID: 1,
            bounds: displayBounds,
            layer: desktopLevel - 1,
            title: "Display 1 Backstop",
            ownerName: "Window Server",
            isOnScreen: true
        ))
        let liveWallpaper = try makeWindow(Fixture(
            windowID: 77,
            ownerPID: ProcessInfo.processInfo.processIdentifier,
            bounds: displayBounds,
            layer: desktopLevel,
            title: nil,
            ownerName: "LiveWallpaperApp",
            isOnScreen: true
        ))
        #expect(WindowInfo.wallpaperWindow(from: [backstop, liveWallpaper], for: CGMainDisplayID())?.windowID == 77)
    }

    // MARK: MenuBarOverlayPanel.localContentRect

    @Test func localContentRectConvertsCGCoordinatesAndRejectsDisjointRects() {
        let mainDisplayHeight: CGFloat = 982
        let panelFrame = CGRect(x: 0, y: 944, width: 1512, height: 38)
        let drawableBounds = CGRect(x: 0, y: 5, width: 1512, height: 33)

        // Application menu at top-left in CoreGraphics coordinates (y=0, h=33)
        // maps to y=5, h=33 in the overlay panel's local drawable coordinates.
        let appMenuCG = CGRect(x: 0, y: 0, width: 534, height: 33)
        let converted = MenuBarOverlayPanel.localContentRect(
            forScreenRect: appMenuCG,
            panelFrame: panelFrame,
            drawableBounds: drawableBounds,
            mainDisplayHeight: mainDisplayHeight
        )
        #expect(converted == CGRect(x: 0, y: 5, width: 534, height: 33))

        // Disjoint or null rects return nil instead of CGRect.null (+inf),
        // preventing NSBezierPath(rect:) from throwing in lineToPoint:.
        let disjointCG = CGRect(x: 0, y: 500, width: 200, height: 33)
        #expect(MenuBarOverlayPanel.localContentRect(
            forScreenRect: disjointCG,
            panelFrame: panelFrame,
            drawableBounds: drawableBounds,
            mainDisplayHeight: mainDisplayHeight
        ) == nil)
        #expect(MenuBarOverlayPanel.localContentRect(
            forScreenRect: .null,
            panelFrame: panelFrame,
            drawableBounds: drawableBounds,
            mainDisplayHeight: mainDisplayHeight
        ) == nil)
    }
}

private extension NSRunningApplication {
    /// The process identifier of the running Dock, if it can be found.
    static var dockPID: pid_t? {
        NSWorkspace.shared.runningApplications
            .first { $0.bundleIdentifier == "com.apple.dock" }?
            .processIdentifier
    }
}
