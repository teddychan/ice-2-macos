//
//  IceBarPlacement.swift
//  Ice
//

import CoreGraphics

/// Where the Ice Bar goes: just under the menu bar, centred on the Ice icon, kept on screen.
enum IceBarPlacement {
    /// The space between the menu bar and the Ice Bar.
    static let gap: CGFloat = 6
    /// The closest the Ice Bar comes to a screen edge.
    static let margin: CGFloat = 8

    /// The Ice Bar's origin in AppKit screen coordinates.
    ///
    /// - Parameters:
    ///   - anchorX: the horizontal centre of the Ice icon; macOS 27 reports a status item's
    ///     window frame as zero, so this is where the icon was clicked.
    ///   - visibleFrame: the screen's visible frame, whose top edge is the bottom of the menu bar.
    static func origin(anchorX: CGFloat, size: CGSize, screen: CGRect, visibleFrame: CGRect) -> CGPoint {
        let centred = anchorX - size.width / 2
        let x = min(max(centred, screen.minX + margin), screen.maxX - margin - size.width)
        return CGPoint(x: x, y: visibleFrame.maxY - gap - size.height)
    }
}
