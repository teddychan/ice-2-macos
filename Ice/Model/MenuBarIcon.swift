//
//  MenuBarIcon.swift
//  Ice
//

import AppKit
import ImageIO
import UniformTypeIdentifiers

struct MenuBarIconConfiguration: Codable, Equatable, Sendable {
    var selection = MenuBarIconChoice.dot.rawValue
    var appearance = "automatic"
    var customPNG: Data?

    var choice: MenuBarIconChoice {
        let selected = MenuBarIconChoice(rawValue: selection) ?? .dot
        return selected == .custom && customPNG == nil ? .dot : selected
    }
    var usesOriginalColors: Bool { appearance == "original" }
}

enum MenuBarIconChoice: String, CaseIterable, Sendable {
    case dot, heart, star, arrowDown, doubleArrow, menu, snowflake
    case pixelHeart, pixelCreeper, pixelDiamond, pixelPickaxe, pixelGrass
    case custom

    var titleKey: String { "app.icon.\(rawValue)" }
    var supportsColor: Bool { pixelRows != nil || self == .custom }

    var symbol: String {
        switch self {
        case .dot: "circle.fill"
        case .heart: "heart.fill"
        case .star: "star.fill"
        case .arrowDown: "arrow.down"
        case .doubleArrow: "chevron.down.2"
        case .menu: "line.3.horizontal"
        case .snowflake: "snowflake"
        default: "photo"
        }
    }

    // 手绘像素图案，不依赖外部素材；每个字符代表一个像素。
    var pixelRows: [String]? {
        switch self {
        case .pixelHeart:
            [
                "............",
                "..xx....xx..",
                ".xrrx..xrrx.",
                "xrlrrxxrrrrx",
                "xrllrrrrrrrx",
                "xrrrrrrrrrdx",
                ".xrrrrrrrdx.",
                "..xrrrrrdx..",
                "...xrrrdx...",
                "....xrdx....",
                ".....xx.....",
                "............",
            ]
        case .pixelCreeper:
            [
                "............",
                ".gggggggggg.",
                ".glggggglgg.",
                ".gxxxggxxxg.",
                ".gxxxggxxxg.",
                ".ggggxxgggg.",
                ".gggxxxxggg.",
                ".ggxxxxxxgg.",
                ".ggxxggxxgg.",
                ".ggxggggxgg.",
                ".gggggggggg.",
                "............",
            ]
        case .pixelDiamond:
            [
                "............",
                "....xxxx....",
                "...xllccx...",
                "..xlcccttx..",
                ".xlcccttttx.",
                ".xccttttttx.",
                "..xctttttx..",
                "...xttttx...",
                "....xttx....",
                ".....xx.....",
                "............",
                "............",
            ]
        case .pixelPickaxe:
            [
                "..xxxxxxx...",
                "..xcccccxx..",
                "...xxxcttcx.",
                "......xbxtcx",
                ".....xbxxtcx",
                "....xbx..xtx",
                "...xbx...xtx",
                "..xbx.....x.",
                ".xbx........",
                "xbx.........",
                "xx..........",
                "............",
            ]
        case .pixelGrass:
            [
                "............",
                ".xxxxxxxxxx.",
                ".xgglggglgx.",
                ".xglggggggx.",
                ".xggggggggx.",
                ".xbggbgbggx.",
                ".xbbgbbbbgx.",
                ".xbdblbbdbx.",
                ".xbbbbdbbbx.",
                ".xdbbblbbdx.",
                ".xxxxxxxxxx.",
                "............",
            ]
        default: nil
        }
    }
}

enum MenuBarIconImportError: Error {
    case tooLarge, invalidPNG, invisible

    var messageKey: String {
        switch self {
        case .tooLarge: "app.icon.error.tooLarge"
        case .invalidPNG: "app.icon.error.invalidPNG"
        case .invisible: "app.icon.error.invisible"
        }
    }
}

enum MenuBarIconRenderer {
    static let maximumFileSize = 5 * 1024 * 1024
    private static let pixels = 36
    private static let size = NSSize(width: 18, height: 18)

    static func image(for configuration: MenuBarIconConfiguration) -> NSImage {
        let choice = configuration.choice
        let image: NSImage
        var supportsColor = choice.supportsColor
        if choice == .custom, let data = configuration.customPNG, let custom = NSImage(data: data) {
            custom.size = size
            image = custom
        } else if let rows = choice.pixelRows, let bitmap = pixelImage(rows, original: configuration.usesOriginalColors) {
            image = NSImage(cgImage: bitmap, size: size)
        } else if choice == .dot || choice == .custom {
            supportsColor = false
            image = (NSImage(named: "DotFill")?.copy() as? NSImage)
                ?? NSImage(systemSymbolName: "circle.fill", accessibilityDescription: nil)
                ?? NSImage(size: size)
        } else {
            image = NSImage(systemSymbolName: choice.symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 15, weight: .medium)) ?? NSImage(size: size)
        }
        image.isTemplate = !supportsColor || !configuration.usesOriginalColors
        image.accessibilityDescription = Constants.displayName
        return image
    }

    /// 保存缩小后的 PNG 数据，避免依赖文件路径或把大图片写入设置。
    static func importPNG(from url: URL) throws -> Data {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true else { throw MenuBarIconImportError.invalidPNG }
        guard let count = values.fileSize, count <= maximumFileSize else { throw MenuBarIconImportError.tooLarge }
        return try normalizedPNG(Data(contentsOf: url))
    }

    static func normalizedPNG(_ data: Data) throws -> Data {
        guard data.count <= maximumFileSize else { throw MenuBarIconImportError.tooLarge }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetType(source) as String? == UTType.png.identifier,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0 else { throw MenuBarIconImportError.invalidPNG }
        guard width <= 4096, height <= 4096 else { throw MenuBarIconImportError.tooLarge }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: pixels,
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              let context = bitmapContext() else { throw MenuBarIconImportError.invalidPNG }
        let scale = CGFloat(pixels) / CGFloat(max(thumbnail.width, thumbnail.height))
        let target = CGSize(width: CGFloat(thumbnail.width) * scale, height: CGFloat(thumbnail.height) * scale)
        context.interpolationQuality = .none
        context.draw(thumbnail, in: CGRect(
            x: (CGFloat(pixels) - target.width) / 2,
            y: (CGFloat(pixels) - target.height) / 2,
            width: target.width,
            height: target.height
        ))
        guard let bytes = context.data?.assumingMemoryBound(to: UInt8.self),
              stride(from: 3, to: pixels * pixels * 4, by: 4).contains(where: { bytes[$0] > 0 }) else {
            throw MenuBarIconImportError.invisible
        }
        guard let bitmap = context.makeImage(),
              let png = NSBitmapImageRep(cgImage: bitmap).representation(using: .png, properties: [:]) else {
            throw MenuBarIconImportError.invalidPNG
        }
        return png
    }

    private static func bitmapContext() -> CGContext? {
        CGContext(
            data: nil,
            width: pixels,
            height: pixels,
            bitsPerComponent: 8,
            bytesPerRow: pixels * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        )
    }

    private static func pixelImage(_ rows: [String], original: Bool) -> CGImage? {
        guard let context = bitmapContext() else { return nil }
        let palette: [Character: (CGFloat, CGFloat, CGFloat)] = [
            "x": (0.10, 0.15, 0.16), "r": (0.95, 0.20, 0.28), "d": (0.48, 0.17, 0.14),
            "l": (0.80, 1.00, 0.87), "g": (0.28, 0.73, 0.24), "c": (0.29, 0.94, 0.94),
            "t": (0.06, 0.64, 0.68), "b": (0.59, 0.36, 0.19),
        ]
        let unit = CGFloat(pixels) / CGFloat(rows.count)
        for (y, row) in rows.enumerated() {
            for (x, pixel) in row.enumerated() {
                guard let (red, green, blue) = palette[pixel] else { continue }
                if original {
                    context.setFillColor(red: red, green: green, blue: blue, alpha: 1)
                } else {
                    // 亮暗映射为透明度，让模板图标保留像素图案的内部细节。
                    let alpha = 1 - 0.8 * (0.2126 * red + 0.7152 * green + 0.0722 * blue)
                    context.setFillColor(red: 0, green: 0, blue: 0, alpha: alpha)
                }
                context.fill(CGRect(
                    x: CGFloat(x) * unit,
                    y: CGFloat(rows.count - y - 1) * unit,
                    width: unit,
                    height: unit
                ))
            }
        }
        return context.makeImage()
    }
}
