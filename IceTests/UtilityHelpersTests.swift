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

    // MARK: Permission polling

    @MainActor
    @Test func optionalMissingPermissionDoesNotPollInBackground() async throws {
        var checkCalls = 0
        let optionalPermission = Permission(
            title: "test.optional",
            details: [],
            isRequired: false,
            check: {
                checkCalls += 1
                return false
            },
            request: {}
        )
        defer { optionalPermission.stopCheck() }

        // Initial check runs once during init; no background timer should fire afterwards.
        #expect(checkCalls == 1)
        try await Task.sleep(for: .milliseconds(50))
        #expect(checkCalls == 1)
    }
}
