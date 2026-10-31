//
//  UtilityHelpersTests.swift
//  IceTests
//

import Foundation
import Testing
@testable import Ice_2

struct UtilityHelpersTests {
    // MARK: withMutableCopy

    @Test func withMutableCopyReturnsMutatedCopy() {
        let result = withMutableCopy(of: [1, 2, 3]) { $0.append(4) }
        #expect(result == [1, 2, 3, 4])
    }

    @Test func withMutableCopyLeavesOriginalUntouched() {
        let original = [1, 2, 3]
        _ = withMutableCopy(of: original) { $0.removeAll() }
        #expect(original == [1, 2, 3])
    }

    @Test func withMutableCopyPropagatesThrownError() {
        struct Boom: Error {}
        #expect(throws: Boom.self) {
            try withMutableCopy(of: 0) { _ in throw Boom() }
        }
    }

    // MARK: LocalizedErrorWrapper

    @Test func wrapperPassesThroughLocalizedErrorFields() {
        struct Detailed: LocalizedError {
            var errorDescription: String? { "desc" }
            var failureReason: String? { "reason" }
            var helpAnchor: String? { "anchor" }
            var recoverySuggestion: String? { "suggestion" }
        }
        let wrapped = LocalizedErrorWrapper(Detailed())
        #expect(wrapped.errorDescription == "desc")
        #expect(wrapped.failureReason == "reason")
        #expect(wrapped.helpAnchor == "anchor")
        #expect(wrapped.recoverySuggestion == "suggestion")
    }

    @Test func wrapperUsesLocalizedDescriptionForPlainError() {
        let plain = NSError(domain: "IceTests", code: 7, userInfo: [NSLocalizedDescriptionKey: "plain failure"])
        let wrapped = LocalizedErrorWrapper(plain)
        #expect(wrapped.errorDescription == "plain failure")
        #expect(wrapped.failureReason == nil)
        #expect(wrapped.helpAnchor == nil)
        #expect(wrapped.recoverySuggestion == nil)
    }

    // MARK: SystemAppearance

    @MainActor
    @Test func systemAppearanceTitles() {
        withEnglish {
            #expect(SystemAppearance.light.localized == "Light Appearance")
            #expect(SystemAppearance.dark.localized == "Dark Appearance")
        }
    }

    @MainActor
    @Test func currentSystemAppearanceResolvesToALightOrDarkTitle() {
        // Exercises the exact/best-match resolution against the host appearance.
        withEnglish {
            let title = SystemAppearance.current.localized
            #expect(title == "Light Appearance" || title == "Dark Appearance")
        }
    }

    // MARK: AXHelpers.isMenuExtra

    @Test func isMenuExtraDetectsDirectHitAndAdjacentStatusItemPadding() {
        let displayBounds = CGRect(x: 0, y: 0, width: 1512, height: 982)
        // Simulate two status items at x=1283...1309 and x=1326...1351 with a 17pt gap between them.
        let statusItemRanges: [ClosedRange<CGFloat>] = [1040...1275, 1283...1309, 1326...1351, 1368...1491]
        let probe: (CGPoint) -> Bool = { point in
            point.y == 14 && statusItemRanges.contains { $0.contains(point.x) }
        }

        // Empty menu bar space and application menu region are not status items.
        #expect(!AXHelpers.isMenuExtra(at: CGPoint(x: 120, y: 12), in: displayBounds, isMenuExtraAtPoint: probe))
        #expect(!AXHelpers.isMenuExtra(at: CGPoint(x: 600, y: 12), in: displayBounds, isMenuExtraAtPoint: probe))
        #expect(!AXHelpers.isMenuExtra(at: CGPoint(x: 950, y: 12), in: displayBounds, isMenuExtraAtPoint: probe))

        // Direct hits on status items return true regardless of pointer Y within the menu bar.
        #expect(AXHelpers.isMenuExtra(at: CGPoint(x: 1055, y: 2), in: displayBounds, isMenuExtraAtPoint: probe))
        #expect(AXHelpers.isMenuExtra(at: CGPoint(x: 1335, y: 30), in: displayBounds, isMenuExtraAtPoint: probe))
        #expect(AXHelpers.isMenuExtra(at: CGPoint(x: 1420, y: 14), in: displayBounds, isMenuExtraAtPoint: probe))

        // Narrow inter-item gaps (e.g. x=1317 between Battery and Control Center) and trailing margin return true.
        #expect(AXHelpers.isMenuExtra(at: CGPoint(x: 1317, y: 14), in: displayBounds, isMenuExtraAtPoint: probe))
        #expect(AXHelpers.isMenuExtra(at: CGPoint(x: 1500, y: 14), in: displayBounds, isMenuExtraAtPoint: { _ in false }))

        // Empty display bounds fail closed.
        #expect(!AXHelpers.isMenuExtra(at: CGPoint(x: 100, y: 14), in: .zero, isMenuExtraAtPoint: { _ in true }))
    }
}
