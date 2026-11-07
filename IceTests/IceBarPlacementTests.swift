//
//  IceBarPlacementTests.swift
//  IceTests
//

import CoreGraphics
import Testing
@testable import Ice_2

/// The Ice Bar sits just under the menu bar, centred on the Ice icon. macOS 27 reports a status
/// item's window frame as zero, so the anchor is where the icon was clicked.
struct IceBarPlacementTests {
    /// A 1920×1080 screen with a 30 pt menu bar (AppKit coordinates: origin bottom left).
    private let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    private let visible = CGRect(x: 0, y: 0, width: 1920, height: 1050)
    private let size = CGSize(width: 200, height: 36)

    @Test func centredUnderTheIconJustBelowTheMenuBar() {
        let origin = IceBarPlacement.origin(anchorX: 1556, size: size, screen: screen, visibleFrame: visible)
        #expect(origin.x == 1456)
        #expect(origin.y == 1008) // menu bar bottom 1050, gap 6, height 36
    }

    @Test func keptOnScreenNearTheRightEdge() {
        let origin = IceBarPlacement.origin(anchorX: 1910, size: size, screen: screen, visibleFrame: visible)
        #expect(origin.x == 1712) // screen edge 1920, margin 8, width 200
    }

    @Test func keptOnScreenNearTheLeftEdge() {
        let origin = IceBarPlacement.origin(anchorX: 20, size: size, screen: screen, visibleFrame: visible)
        #expect(origin.x == 8)
    }

    @Test func followsAScreenThatIsNotAtTheOrigin() {
        let second = CGRect(x: 1920, y: 200, width: 1440, height: 900)
        let secondVisible = CGRect(x: 1920, y: 200, width: 1440, height: 870)
        let origin = IceBarPlacement.origin(anchorX: 3000, size: size, screen: second, visibleFrame: secondVisible)
        #expect(origin.x == 2900)
        #expect(origin.y == 1028) // menu bar bottom 1070, gap 6, height 36
    }
}
