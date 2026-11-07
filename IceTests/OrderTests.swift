//
//  OrderTests.swift
//  IceTests
//

import Testing
@testable import Ice_2

/// One order is shared by the Ice Bar and Settings, but each shows only part of it: Settings
/// leaves out shown apps that quit, and the Ice Bar shows only hidden items. Reordering a part
/// must move items only within the places that part holds, leaving the rest where they were.
struct OrderTests {
    @Test func reorderingTheWholeOrderReplacesIt() {
        var settings = IceSettings()
        settings.order = ["a", "b", "c"]

        settings.reorder(["c", "a", "b"])

        #expect(settings.order == ["c", "a", "b"])
    }

    @Test func reorderingAPartLeavesTheOtherItemsInPlace() {
        var settings = IceSettings()
        settings.order = ["a", "x", "b", "y", "c"]

        // The Ice Bar shows a, b and c; the user drags c to the front.
        settings.reorder(["c", "a", "b"])

        #expect(settings.order == ["c", "x", "a", "y", "b"])
    }

    @Test func aListThatIsNotARearrangementOfThePartIsIgnored() {
        var settings = IceSettings()
        settings.order = ["a", "b", "c"]

        settings.reorder(["a", "b", "z"])
        #expect(settings.order == ["a", "b", "c"])

        settings.reorder(["a", "a", "b"])
        #expect(settings.order == ["a", "b", "c"])
    }

    @Test func droppingAnItemOntoAnEarlierOneTakesItsPlace() {
        var settings = IceSettings()
        settings.order = ["a", "x", "b", "c"]

        // Dropping c onto a in the Ice Bar (which shows a, b, c) puts c first.
        settings.move("c", onto: "a", within: ["a", "b", "c"])

        #expect(settings.order == ["c", "x", "a", "b"])
    }

    @Test func droppingAnItemOntoALaterOneTakesItsPlace() {
        var settings = IceSettings()
        settings.order = ["a", "b", "c"]

        // Dropping a onto c puts a last, which "before c" never could.
        settings.move("a", onto: "c", within: ["a", "b", "c"])

        #expect(settings.order == ["b", "c", "a"])
    }

    @Test func droppingAnItemOntoItselfChangesNothing() {
        var settings = IceSettings()
        settings.order = ["a", "b", "c"]
        settings.move("b", onto: "b", within: ["a", "b", "c"])
        #expect(settings.order == ["a", "b", "c"])
    }
}
