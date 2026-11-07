//
//  MenuBarItemTests.swift
//  IceTests
//

import Testing
@testable import Ice_2

/// What counts as an item: on macOS 27 hiding works per process, so an item is a whole app or
/// one of the system items assessment mode can hide. Everything else stays out of the list.
struct MenuBarItemTests {
    @Test func anAppIsOneItemNamedAfterIt() throws {
        let item = try #require(MenuBarItem(bundle: "com.getdropbox.dropbox", identifier: nil, name: "Dropbox"))
        #expect(item.id == "bundle:com.getdropbox.dropbox")
        #expect(item.bundleIdentifier == "com.getdropbox.dropbox")
        #expect(item.name == "Dropbox")
    }

    @Test func iceNeverListsItself() {
        #expect(MenuBarItem(bundle: "com.dragonapp.ice", identifier: nil, name: "Ice 2") == nil)
        #expect(MenuBarItem(bundle: "com.dragonapp.ice.debug", identifier: nil, name: "Ice 2 Debug") == nil)
    }

    @Test func menuBarAgentItselfIsNotAnItem() {
        #expect(MenuBarItem(bundle: "com.apple.MenuBarAgent", identifier: nil, name: "MenuBarAgent") == nil)
    }

    @Test func hideableSystemItemsMapToTheirAssessmentNumber() throws {
        let bluetooth = try #require(MenuBarItem(bundle: nil, identifier: "com.apple.menuextra.bluetooth", name: "Bluetooth"))
        #expect(bluetooth.id == "system:1")
        #expect(bluetooth.systemNumber == 1)
        #expect(MenuBarItem(bundle: nil, identifier: "com.apple.menuextra.wifi", name: "Wi-Fi")?.id == "system:6")
        #expect(MenuBarItem(bundle: nil, identifier: "com.apple.menuextra.volume", name: "Sound")?.id == "system:5")
    }

    @Test func theClockAndControlCenterCannotBeHiddenSoAreNotListed() {
        #expect(MenuBarItem(bundle: nil, identifier: "com.apple.menuextra.clock", name: "Clock") == nil)
        #expect(MenuBarItem(bundle: nil, identifier: "com.apple.menuextra.controlcenter", name: "Control Center") == nil)
    }

    @Test func unmappedSystemItemsAreNotListed() {
        #expect(MenuBarItem(bundle: nil, identifier: "com.apple.menuextra.focusmode", name: "Focus") == nil)
        #expect(MenuBarItem(bundle: nil, identifier: nil, name: "Nothing") == nil)
    }

    @Test func anIdRebuildsTheSameItem() throws {
        #expect(MenuBarItem(id: "bundle:com.getdropbox.dropbox", name: "Dropbox")?.bundleIdentifier == "com.getdropbox.dropbox")
        #expect(MenuBarItem(id: "system:6", name: "")?.systemNumber == 6)
        #expect(MenuBarItem(id: "system:2", name: "") == nil, "the clock is never an item")
        #expect(MenuBarItem(id: "bundle:com.dragonapp.ice", name: "") == nil)
        #expect(MenuBarItem(id: "unmanaged:x", name: "") == nil)
    }
}
