//
//  MenuBarIconTests.swift
//  Ice
//

import AppKit
import DragonKit
import Foundation
import Testing
@testable import Ice_2

@MainActor
struct MenuBarIconTests {

    private func png(transparent: Bool = false, width: Int = 64, height: Int = 32) throws -> Data {
        let bitmap = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ))
        var pixel: [Int] = transparent ? [0, 0, 0, 0] : [255, 0, 0, 255]
        for y in 0..<height {
            for x in 0..<width {
                bitmap.setPixel(&pixel, atX: x, y: y)
            }
        }
        return try #require(bitmap.representation(using: .png, properties: [:]))
    }

    @Test func customImportKeepsAspectRatioAndTransparency() throws {
        let data = try MenuBarIconRenderer.normalizedPNG(png())
        let bitmap = try #require(NSBitmapImageRep(data: data))
        #expect(bitmap.pixelsWide == 36)
        #expect(bitmap.pixelsHigh == 36)
        #expect(bitmap.colorAt(x: 18, y: 0)?.alphaComponent == 0)
        #expect(bitmap.colorAt(x: 18, y: 18)?.alphaComponent == 1)
        #expect(data.count < 10_000)
    }

    @Test func invalidOversizedAndInvisibleImagesAreRejected() throws {
        #expect(throws: MenuBarIconImportError.self) {
            try MenuBarIconRenderer.normalizedPNG(Data("not a PNG".utf8))
        }
        #expect(throws: MenuBarIconImportError.self) {
            try MenuBarIconRenderer.normalizedPNG(Data(repeating: 0, count: 5 * 1024 * 1024 + 1))
        }
        let invisible = try png(transparent: true)
        #expect(throws: MenuBarIconImportError.self) {
            try MenuBarIconRenderer.normalizedPNG(invisible)
        }
        let tooWide = try png(width: 4097, height: 1)
        #expect(throws: MenuBarIconImportError.self) {
            try MenuBarIconRenderer.normalizedPNG(tooWide)
        }
    }

    @Test func importedIconIsIndependentOfItsFileAndNotifiesLiveChanges() throws {
        let (_, suite) = ScratchDefaults.make(label: "Icon")
        defer { ScratchDefaults.destroy(suite) }
        let defaults = UserDefaults(suiteName: suite)!
        let model = SettingsModel(suiteName: suite, legacyDefaults: defaults)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: url) }
        try png().write(to: url)
        var changes = 0
        model.onMenuBarIconChange = { changes += 1 }
        try model.importMenuBarIcon(from: url)
        #expect(changes == 1)
        model.menuBarIconUsesOriginalColors = true
        #expect(changes == 2)
        let imported = model.settings.menuBarIcon.customPNG
        #expect(imported != nil)
        try FileManager.default.removeItem(at: url)
        let restored = SettingsModel(suiteName: suite, legacyDefaults: defaults)
        #expect(restored.menuBarIconChoice == .custom)
        #expect(restored.menuBarIconUsesOriginalColors)
        #expect(restored.settings.menuBarIcon.customPNG == imported)
        #expect(!MenuBarIconRenderer.image(for: restored.settings.menuBarIcon).isTemplate)
        model.menuBarIconChoice = .pixelDiamond
        model.menuBarIconChoice = .custom
        #expect(model.settings.menuBarIcon.customPNG == imported)
        let previous = model.settings
        #expect(throws: (any Error).self) { try model.importMenuBarIcon(from: url) }
        #expect(model.settings == previous)
        #expect(changes == 4)
    }

    @Test func presetImagesSupportTemplatesAndPixelColors() throws {
        for choice in MenuBarIconChoice.allCases where choice != .custom {
            var configuration = MenuBarIconConfiguration(selection: choice.rawValue)
            let template = MenuBarIconRenderer.image(for: configuration)
            #expect(template.isTemplate)
            #expect(template.isValid)
            if let rows = choice.pixelRows {
                #expect(rows.allSatisfy { $0.count == rows.count })
                configuration.appearance = "original"
                let colored = MenuBarIconRenderer.image(for: configuration)
                #expect(!colored.isTemplate)
                #expect(colored.size == NSSize(width: 18, height: 18))
            }
        }
    }

    @Test func missingCustomAndUnknownSelectionsFallBackToVisibleTemplate() {
        #expect(MenuBarIconConfiguration(selection: "custom").choice == .dot)
        for choice in ["custom", "unknown"] {
            let configuration = MenuBarIconConfiguration(selection: choice, appearance: "original", customPNG: Data([0]))
            let image = MenuBarIconRenderer.image(for: configuration)
            #expect(image.isTemplate)
            #expect(image.isValid)
        }
    }

    @Test func iconChoiceSurvivesSettingsBackup() throws {
        let (defaults, suite) = ScratchDefaults.make(label: "IconBackup")
        defer { ScratchDefaults.destroy(suite) }
        defaults.set(Data(#"{"menuBarIcon":{"selection":"pixelHeart","appearance":"original","customPNG":"AQID"},"hidden":["system:6"]}"#.utf8), forKey: "settings.v1")
        let store = DragonSettingsStore(suiteName: suite, defaultValue: IceSettings())
        let loaded = store.load()
        let encoded = try JSONEncoder().encode(loaded)
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let icon = try #require(object["menuBarIcon"] as? [String: Any])
        #expect(icon["selection"] as? String == "pixelHeart")
        #expect(icon["appearance"] as? String == "original")
        #expect(icon["customPNG"] as? String == "AQID")
        #expect(loaded.hidden == ["system:6"])
        store.save(loaded)
        #expect(store.load() == loaded)
    }
}
