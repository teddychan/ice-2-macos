//
//  SmokeTests.swift
//  IceTests
//

import Foundation
import Testing
// The Ice app target's product name is "Ice 2", so its Swift module is `Ice_2`.
@testable import Ice_2

/// Proves the test target links against the Ice app host and that
/// `@testable import Ice_2` resolves the app's internal types.
struct SmokeTests {
    /// The tests run *inside* the app host, so `UserDefaults.standard` and the settings suite
    /// (`<bundle id>.settings`) resolve to whatever domain the host bundle claims. If that were the release id, a test run would read and
    /// write the settings of the Ice 2 the user actually has installed.
    ///
    /// The Debug configuration therefore builds the app as `com.dragonapp.ice.debug`,
    /// which is what `scripts/run-debug.sh` already gives manual debug runs. This pins
    /// that: the release domain has to stay unreachable from the suite, so restoring
    /// the release id to the Debug configuration fails here instead of silently.
    ///
    /// Asserted as equality rather than `!= "com.dragonapp.ice"` so it can't pass on a
    /// host with no bundle id at all.
    @Test func testHostNeverOwnsTheReleaseSettingsDomain() {
        #expect(Bundle.main.bundleIdentifier == "com.dragonapp.ice.debug")
    }

    /// Ice never lists or hides itself, and that covers the other build too: hiding the
    /// installed release from the debug build would leave the user without a way back.
    @Test func everyIceBuildIsRecognizedAsOurOwn() {
        #expect(Constants.isIceBundleID("com.dragonapp.ice"))
        #expect(Constants.isIceBundleID("com.dragonapp.ice.debug"))
        // The running build is always one of ours, whichever build the suite is hosted in.
        #expect(Constants.isIceBundleID(Constants.bundleIdentifier))
        // Neither an unrelated app that merely starts with the same letters, nor a missing id.
        #expect(!Constants.isIceBundleID("com.dragonapp.iceberg"))
        #expect(!Constants.isIceBundleID("com.apple.controlcenter"))
        #expect(!Constants.isIceBundleID(nil))
    }
}
