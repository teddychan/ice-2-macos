//
//  Constants.swift
//  Ice
//

import Foundation

enum Constants {
    /// The bundle identifier of the installed release, which the local debug build extends with
    /// `.debug`. Use it only to ask which build is which.
    static let releaseBundleIdentifier = "com.dragonapp.ice"

    /// The running build's bundle identifier.
    static var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? releaseBundleIdentifier
    }

    /// The app's display name: "Ice 2", or "Ice 2 Debug" for a local build.
    static var displayName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "Ice 2"
    }

    /// Whether `bundleID` belongs to any build of Ice 2. Ice never lists or hides itself.
    static func isIceBundleID(_ bundleID: String?) -> Bool {
        guard let bundleID else {
            return false
        }
        return bundleID == releaseBundleIdentifier || bundleID.hasPrefix("\(releaseBundleIdentifier).")
    }
}
