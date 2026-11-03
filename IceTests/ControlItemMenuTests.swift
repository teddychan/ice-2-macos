//
//  ControlItemMenuTests.swift
//  IceTests
//

import Cocoa
import Testing
@testable import Ice_2

struct ControlItemMenuTests {
    // macOS 27 hides a menu item's icon unless the item asks to keep it. The property is read by
    // name because CI builds with the macOS 26 SDK, which does not declare it.
    @MainActor
    @Test func everyIconInTheIceMenuStaysVisible() {
        let menu = ControlItem(identifier: .visible).createMenu(with: AppState())
        let imagedItems = menu.items.filter { $0.image != nil }
        #expect(!imagedItems.isEmpty)
        if #available(macOS 27, *) {
            for item in imagedItems {
                #expect(item.value(forKey: "preferredImageVisibility") as? Int == 1, "\(item.title)")
            }
        }
    }
}
