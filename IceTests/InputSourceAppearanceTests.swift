//
//  InputSourceAppearanceTests.swift
//  Ice
//

import AppKit
import Carbon
import Foundation
import Testing
@testable import Ice_2

@MainActor
struct InputSourceAppearanceTests {
    @Test func inputIconPreservesOpaqueMonochromeImages() throws {
        let bitmap = try #require(NSBitmapImageRep(data: png()))
        var black = [0, 0, 0, 255]
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide { bitmap.setPixel(&black, atX: x, y: y) }
        }
        let data = try #require(bitmap.representation(using: .png, properties: [:]))
        #expect(!InputSourceAppearance.isTemplateCompatible(try #require(NSImage(data: data))))
    }

    @Test func inputIconRetainsColorsButTemplatesMonochromeImages() throws {
        let colored = try #require(NSImage(data: png()))
        #expect(!InputSourceAppearance.isTemplateCompatible(colored))
        let bitmap = try #require(NSBitmapImageRep(data: png(transparent: true)))
        var black = [0, 0, 0, 255]
        for y in 8..<24 {
            for x in 16..<48 { bitmap.setPixel(&black, atX: x, y: y) }
        }
        let data = try #require(bitmap.representation(using: .png, properties: [:]))
        let monochrome = try #require(NSImage(data: data))
        #expect(InputSourceAppearance.isTemplateCompatible(monochrome))
    }

    @Test func inputIconHandlesIncorrectResourceExtensionAndMissingFiles() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let actual = directory.appendingPathComponent("input.png")
        try png().write(to: actual)
        #expect(InputSourceAppearance.loadIcon(at: directory.appendingPathComponent("input.pdf")) != nil)
        #expect(InputSourceAppearance.loadIcon(at: directory.appendingPathComponent("missing.png")) == nil)
    }

    @Test func inputMenuUsesTheSelectedInputSourceWhenAvailable() throws {
        // Headless CI may not have a selected keyboard input source.
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return }
        let item = try #require(MenuBarItem(id: "bundle:com.apple.TextInputMenuAgent", name: "TextInputMenuAgent"))
        if let pointer = TISGetInputSourceProperty(source, kTISPropertyLocalizedName) {
            let name = Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
            #expect(ItemAppearance.name(for: item) == name)
        }
        if let pointer = TISGetInputSourceProperty(source, kTISPropertyIconImageURL) {
            let url = Unmanaged<CFURL>.fromOpaque(pointer).takeUnretainedValue() as URL
            if let expected = NSImage(contentsOf: url) {
                #expect(ItemAppearance.icon(for: item).tiffRepresentation == expected.tiffRepresentation)
            } else {
                #expect(ItemAppearance.icon(for: item).isValid)
            }
        }
    }

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
}
