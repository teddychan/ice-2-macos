//
//  AppearanceConfigurationV2Tests.swift
//  IceTests
//

import CoreGraphics
import Foundation
import Testing
@testable import Ice_2

/// Covers the menu bar appearance configuration: its decoder must tolerate
/// settings written by older versions of Ice (every key falls back to a
/// default), and its derived values drive shape/tint rendering.
struct AppearanceConfigurationV2Tests {
    private func decodeConfiguration(_ json: String) throws -> MenuBarAppearanceConfigurationV2 {
        try JSONDecoder().decode(MenuBarAppearanceConfigurationV2.self, from: Data(json.utf8))
    }

    private func decodePartial(_ json: String) throws -> MenuBarAppearancePartialConfiguration {
        try JSONDecoder().decode(MenuBarAppearancePartialConfiguration.self, from: Data(json.utf8))
    }

    // MARK: Decoding with missing keys

    @Test func emptyObjectDecodesToTheDefaultConfiguration() throws {
        // Settings saved before any appearance key existed must still load.
        #expect(try decodeConfiguration("{}") == .defaultConfiguration)
    }

    @Test func missingKeysFallBackIndividually() throws {
        // Only two keys are present; the rest keep their defaults.
        let configuration = try decodeConfiguration(#"{"isInset":false,"isDynamic":true}"#)
        let defaults = MenuBarAppearanceConfigurationV2.defaultConfiguration
        #expect(configuration.isInset == false)
        #expect(configuration.isDynamic == true)
        #expect(configuration.shapeKind == defaults.shapeKind)
        #expect(configuration.removesMenuBarBackground == defaults.removesMenuBarBackground)
        #expect(configuration.roundsScreenCorners == defaults.roundsScreenCorners)
        #expect(configuration.fullShapeInfo == defaults.fullShapeInfo)
        #expect(configuration.splitShapeInfo == defaults.splitShapeInfo)
    }

    @Test func unrecognizedKeysAreIgnored() throws {
        // Settings written by a newer build must not break an older decoder.
        let configuration = try decodeConfiguration(#"{"isInset":false,"someFutureKey":"whatever"}"#)
        #expect(configuration.isInset == false)
    }

    @Test func shapeKindAndShapeInfoDecodeTogether() throws {
        let json = #"{"shapeKind":1,"fullShapeInfo":{"leadingEndCap":0,"trailingEndCap":0}}"#
        let configuration = try decodeConfiguration(json)
        #expect(configuration.shapeKind == .full)
        #expect(configuration.fullShapeInfo.leadingEndCap == .square)
        #expect(configuration.fullShapeInfo.trailingEndCap == .square)
    }

    @Test func partialConfigurationFallsBackPerKey() throws {
        let partial = try decodePartial(#"{"hasBorder":true,"borderWidth":4}"#)
        let defaults = MenuBarAppearancePartialConfiguration.defaultConfiguration
        #expect(partial.hasBorder == true)
        #expect(partial.borderWidth == 4)
        #expect(partial.hasShadow == defaults.hasShadow)
        #expect(partial.tintKind == defaults.tintKind)
        #expect(partial.borderColor == defaults.borderColor)
    }

    @Test func partialConfigurationEmptyObjectIsAllDefaults() throws {
        #expect(try decodePartial("{}") == .defaultConfiguration)
    }

    // MARK: Encoding round trip

    @Test func encodeDecodeRoundTripPreservesScalarSettings() throws {
        var configuration = MenuBarAppearanceConfigurationV2.defaultConfiguration
        configuration.shapeKind = .split
        configuration.isInset = false
        configuration.isDynamic = true
        configuration.removesMenuBarBackground = true
        configuration.roundsScreenCorners = true
        configuration.fullShapeInfo = MenuBarFullShapeInfo(leadingEndCap: .square, trailingEndCap: .round)
        configuration.staticConfiguration.hasShadow = true
        configuration.staticConfiguration.borderWidth = 3
        configuration.staticConfiguration.tintKind = .solid

        let data = try JSONEncoder().encode(configuration)
        let decoded = try JSONDecoder().decode(MenuBarAppearanceConfigurationV2.self, from: data)

        #expect(decoded.shapeKind == .split)
        #expect(decoded.isInset == false)
        #expect(decoded.isDynamic == true)
        #expect(decoded.removesMenuBarBackground == true)
        #expect(decoded.roundsScreenCorners == true)
        #expect(decoded.fullShapeInfo == configuration.fullShapeInfo)
        #expect(decoded.staticConfiguration.hasShadow == true)
        #expect(decoded.staticConfiguration.borderWidth == 3)
        #expect(decoded.staticConfiguration.tintKind == .solid)
    }

    @Test func encodedPayloadCarriesEveryKey() throws {
        let data = try JSONEncoder().encode(MenuBarAppearanceConfigurationV2.defaultConfiguration)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let expectedKeys: Set<String> = [
            "lightModeConfiguration",
            "darkModeConfiguration",
            "staticConfiguration",
            "shapeKind",
            "fullShapeInfo",
            "splitShapeInfo",
            "isInset",
            "isDynamic",
            "removesMenuBarBackground",
            "roundsScreenCorners",
        ]
        #expect(expectedKeys.isSubset(of: Set(object.keys)))
    }

    // MARK: hasRoundedShape

    @Test func noShapeIsNeverRounded() {
        var configuration = MenuBarAppearanceConfigurationV2.defaultConfiguration
        configuration.shapeKind = .noShape
        configuration.fullShapeInfo = .default // rounded, but irrelevant
        configuration.splitShapeInfo = .default
        #expect(!configuration.hasRoundedShape)
    }

    @Test func fullShapeDefersToFullShapeInfo() {
        var configuration = MenuBarAppearanceConfigurationV2.defaultConfiguration
        configuration.shapeKind = .full
        configuration.splitShapeInfo = .default // rounded, but must not be consulted

        configuration.fullShapeInfo = MenuBarFullShapeInfo(leadingEndCap: .square, trailingEndCap: .square)
        #expect(!configuration.hasRoundedShape)

        configuration.fullShapeInfo = MenuBarFullShapeInfo(leadingEndCap: .square, trailingEndCap: .round)
        #expect(configuration.hasRoundedShape)
    }

    @Test func splitShapeDefersToSplitShapeInfo() {
        let squareSide = MenuBarFullShapeInfo(leadingEndCap: .square, trailingEndCap: .square)
        var configuration = MenuBarAppearanceConfigurationV2.defaultConfiguration
        configuration.shapeKind = .split
        configuration.fullShapeInfo = .default // rounded, but must not be consulted

        configuration.splitShapeInfo = MenuBarSplitShapeInfo(leading: squareSide, trailing: squareSide)
        #expect(!configuration.hasRoundedShape)

        configuration.splitShapeInfo = MenuBarSplitShapeInfo(leading: squareSide, trailing: .default)
        #expect(configuration.hasRoundedShape)
    }

    // MARK: current

    @MainActor
    @Test func currentUsesStaticConfigurationWhenNotDynamic() {
        var configuration = MenuBarAppearanceConfigurationV2.defaultConfiguration
        configuration.isDynamic = false
        configuration.staticConfiguration.borderWidth = 11
        configuration.lightModeConfiguration.borderWidth = 22
        configuration.darkModeConfiguration.borderWidth = 33
        #expect(configuration.current.borderWidth == 11)
    }

    @MainActor
    @Test func currentUsesAnAppearanceSpecificConfigurationWhenDynamic() {
        var configuration = MenuBarAppearanceConfigurationV2.defaultConfiguration
        configuration.isDynamic = true
        configuration.staticConfiguration.borderWidth = 11
        // Both appearance branches agree, so the result is host-independent.
        configuration.lightModeConfiguration.borderWidth = 44
        configuration.darkModeConfiguration.borderWidth = 44
        #expect(configuration.current.borderWidth == 44)
    }

    @MainActor
    @Test func currentSelectsTheBranchMatchingTheSystemAppearance() {
        var configuration = MenuBarAppearanceConfigurationV2.defaultConfiguration
        configuration.isDynamic = true
        configuration.lightModeConfiguration.borderWidth = 1
        configuration.darkModeConfiguration.borderWidth = 2
        let expected: Double = switch SystemAppearance.current {
        case .light: 1
        case .dark: 2
        }
        #expect(configuration.current.borderWidth == expected)
    }

    // MARK: needsDesktopWallpaper

    @Test func tintBorderAndShadowDoNotNeedTheWallpaper() {
        // These are drawn on top of the menu bar, so the panel never has to
        // fill anything back in, and never has to capture the screen.
        var configuration = MenuBarAppearanceConfigurationV2.defaultConfiguration
        configuration.staticConfiguration.tintKind = .solid
        configuration.staticConfiguration.hasBorder = true
        configuration.staticConfiguration.hasShadow = true
        #expect(!configuration.needsDesktopWallpaper)
    }

    @Test func cutawayConfigurationsNeedTheWallpaper() {
        for makeConfiguration in [
            { (c: inout MenuBarAppearanceConfigurationV2) in c.removesMenuBarBackground = true },
            { (c: inout MenuBarAppearanceConfigurationV2) in c.roundsScreenCorners = true },
            { (c: inout MenuBarAppearanceConfigurationV2) in c.shapeKind = .full },
            { (c: inout MenuBarAppearanceConfigurationV2) in c.shapeKind = .split },
        ] {
            var configuration = MenuBarAppearanceConfigurationV2.defaultConfiguration
            makeConfiguration(&configuration)
            #expect(configuration.needsDesktopWallpaper)
        }
    }

    @Test func defaultConfigurationDoesNotNeedTheWallpaper() {
        #expect(!MenuBarAppearanceConfigurationV2.defaultConfiguration.needsDesktopWallpaper)
    }

    // MARK: needsOverlayPanels

    @Test func defaultConfigurationDoesNotNeedOverlayPanels() {
        var configuration = MenuBarAppearanceConfigurationV2.defaultConfiguration
        // Non-visual scalar tweaks (such as borderWidth while hasBorder is false)
        // must not keep overlay panels alive once all visual effects are turned off.
        configuration.staticConfiguration.borderWidth = 3
        #expect(!configuration.needsOverlayPanels())
    }

    @Test func anyVisualEffectOrActivePreviewNeedsOverlayPanels() {
        for makeConfiguration in [
            { (c: inout MenuBarAppearanceConfigurationV2) in c.removesMenuBarBackground = true },
            { (c: inout MenuBarAppearanceConfigurationV2) in c.roundsScreenCorners = true },
            { (c: inout MenuBarAppearanceConfigurationV2) in c.shapeKind = .full },
            { (c: inout MenuBarAppearanceConfigurationV2) in c.shapeKind = .split },
            { (c: inout MenuBarAppearanceConfigurationV2) in c.staticConfiguration.hasShadow = true },
            { (c: inout MenuBarAppearanceConfigurationV2) in c.staticConfiguration.hasBorder = true },
            { (c: inout MenuBarAppearanceConfigurationV2) in c.staticConfiguration.tintKind = .solid },
            { (c: inout MenuBarAppearanceConfigurationV2) in c.staticConfiguration.tintKind = .gradient },
        ] {
            var configuration = MenuBarAppearanceConfigurationV2.defaultConfiguration
            makeConfiguration(&configuration)
            #expect(configuration.needsOverlayPanels())
        }

        var preview = MenuBarAppearancePartialConfiguration.defaultConfiguration
        preview.hasBorder = true
        #expect(MenuBarAppearanceConfigurationV2.defaultConfiguration.needsOverlayPanels(with: preview))

        var dynamicConfig = MenuBarAppearanceConfigurationV2.defaultConfiguration
        dynamicConfig.isDynamic = true
        dynamicConfig.darkModeConfiguration.hasShadow = true
        #expect(dynamicConfig.needsOverlayPanels())
    }

    // MARK: Defaults

    @Test func defaultConfigurationIsInsetAndUntinted() {
        let configuration = MenuBarAppearanceConfigurationV2.defaultConfiguration
        #expect(configuration.isInset)
        #expect(!configuration.isDynamic)
        #expect(!configuration.removesMenuBarBackground)
        #expect(!configuration.roundsScreenCorners)
        #expect(configuration.shapeKind == .noShape)
        #expect(configuration.staticConfiguration.tintKind == .noTint)
        #expect(!configuration.staticConfiguration.hasBorder)
        #expect(!configuration.staticConfiguration.hasShadow)
        #expect(configuration.staticConfiguration.borderWidth == 1)
    }
}
