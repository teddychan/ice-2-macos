//
//  HidingPolicyTests.swift
//  IceTests
//

import Testing
@testable import Ice_2

/// The assessment-mode assertion shows only what it allows, so the allowed set is everything
/// except the hidden items. No assertion is taken when nothing needs hiding, because assessment
/// mode has side effects (it can also hide Focus).
struct HidingPolicyTests {
    private let running: Set<String> = ["com.getdropbox.dropbox", "eu.exelban.Stats", "com.dragonapp.ice"]

    @Test func nothingHiddenTakesNoAssertion() {
        #expect(HidingPolicy.configuration(hidden: [], runningBundles: running) == nil)
    }

    @Test func aHiddenRunningAppIsLeftOutOfTheAllowedApps() throws {
        let configuration = try #require(HidingPolicy.configuration(
            hidden: ["bundle:com.getdropbox.dropbox"], runningBundles: running
        ))
        #expect(!configuration.bundles.contains("com.getdropbox.dropbox"))
        #expect(configuration.bundles.contains("eu.exelban.Stats"))
        #expect(configuration.systemItems == [0, 1, 2, 3, 4, 5, 6, 7, 8])
    }

    @Test func iceItselfIsAlwaysAllowed() throws {
        let configuration = try #require(HidingPolicy.configuration(
            hidden: ["bundle:com.getdropbox.dropbox"], runningBundles: running
        ))
        #expect(configuration.bundles.contains("com.dragonapp.ice"))
        #expect(configuration.bundles.contains("com.dragonapp.ice.debug"))
    }

    @Test func aHiddenAppThatIsNotRunningNeedsNoAssertion() {
        #expect(HidingPolicy.configuration(hidden: ["bundle:com.example.gone"], runningBundles: running) == nil)
    }

    @Test func aHiddenSystemItemIsLeftOutOfTheAllowedSystemItems() throws {
        let configuration = try #require(HidingPolicy.configuration(hidden: ["system:1"], runningBundles: running))
        #expect(configuration.systemItems == [0, 2, 3, 4, 5, 6, 7, 8])
        #expect(configuration.bundles.contains("com.getdropbox.dropbox"))
    }

    @Test func revealingAHiddenAppAllowsJustThatApp() throws {
        let configuration = try #require(HidingPolicy.configuration(
            hidden: ["bundle:com.getdropbox.dropbox", "bundle:eu.exelban.Stats"],
            runningBundles: running,
            revealing: "bundle:com.getdropbox.dropbox"
        ))
        #expect(configuration.bundles.contains("com.getdropbox.dropbox"))
        #expect(!configuration.bundles.contains("eu.exelban.Stats"))
    }

    @Test func revealingAHiddenSystemItemAllowsIt() throws {
        let configuration = try #require(HidingPolicy.configuration(
            hidden: ["system:1", "system:6"], runningBundles: running, revealing: "system:1"
        ))
        #expect(configuration.systemItems == [0, 1, 2, 3, 4, 5, 7, 8])
    }
}
