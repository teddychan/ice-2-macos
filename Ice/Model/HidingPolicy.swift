//
//  HidingPolicy.swift
//  Ice
//

import Foundation

/// Turns the hidden items into an assessment-mode configuration.
///
/// Assessment mode shows only what its configuration allows, so the allowed set is every running
/// app and every system item, minus the hidden ones.
enum HidingPolicy {
    struct Configuration: Equatable {
        /// Bundle identifiers allowed to show.
        let bundles: [String]
        /// Assessment-mode system item numbers allowed to show.
        let systemItems: [Int]
    }

    /// Every system item number assessment mode knows, including the clock (2) and Control
    /// Center (8), which are always allowed.
    static let allSystemItems = Array(0...8)

    /// Both Ice builds are always allowed, so the Ice icon can't hide itself or the other build.
    static let ownBundles: Set<String> = [Constants.releaseBundleIdentifier, "\(Constants.releaseBundleIdentifier).debug"]

    /// The configuration that hides `hidden`, or nil when nothing on screen needs hiding.
    ///
    /// - Parameters:
    ///   - revealing: one hidden item to allow anyway, while its menu is open.
    ///   - cameraInUse: whether a camera is running. Assessment mode removes Control Center's
    ///     camera indicator whatever the configuration allows, so hiding pauses while a camera
    ///     is in use and the indicator always shows.
    static func configuration(
        hidden: Set<String>,
        runningBundles: Set<String>,
        revealing: String? = nil,
        cameraInUse: Bool = false
    ) -> Configuration? {
        guard !cameraInUse else {
            return nil
        }
        let hiding = hidden.subtracting(revealing.map { [$0] } ?? [])
        let items = hiding.compactMap { MenuBarItem(id: $0, name: "") }
        let hiddenBundles = Set(items.compactMap(\.bundleIdentifier)).subtracting(ownBundles)
        let hiddenSystems = Set(items.compactMap(\.systemNumber))
        // Taking no assertion at all avoids assessment mode's side effects when nothing on
        // screen is hidden.
        guard !hiddenBundles.isDisjoint(with: runningBundles) || !hiddenSystems.isEmpty else {
            return nil
        }
        return Configuration(
            bundles: runningBundles.union(ownBundles).subtracting(hiddenBundles).sorted(),
            systemItems: allSystemItems.filter { !hiddenSystems.contains($0) }
        )
    }
}
