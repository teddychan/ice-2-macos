//
//  MinimumSystemVersionTests.swift
//  IceTests
//

import Foundation
import Testing

/// 3.x must only ever be offered to macOS 27: the shipped app's `LSMinimumSystemVersion` comes
/// from `ICE_MINIMUM_SYSTEM_VERSION`, and Sparkle copies it into the appcast. Debug says 26.0 only
/// so these tests can host on CI's macOS 26 runners, so the Release value is checked in the
/// project file itself rather than in the (Debug) test host.
struct MinimumSystemVersionTests {
    private func projectFile() throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appending(path: "Ice.xcodeproj/project.pbxproj"), encoding: .utf8)
    }

    @Test func releaseRequiresMacOS27() throws {
        let project = try projectFile()
        let release = project.components(separatedBy: "/* Release */ = {").dropFirst()
            .filter { $0.contains("PRODUCT_BUNDLE_IDENTIFIER = com.dragonapp.ice;") }
        #expect(release.count == 1, "exactly one Release configuration builds the shipped app")
        #expect(release.first?.contains("ICE_MINIMUM_SYSTEM_VERSION = 27.0;") == true)
    }

    @Test func theInfoPlistTakesTheMinimumFromTheBuildSetting() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let plist = try String(contentsOf: root.appending(path: "App/Info.plist"), encoding: .utf8)
        #expect(plist.contains("<string>$(ICE_MINIMUM_SYSTEM_VERSION)</string>"))
    }
}
