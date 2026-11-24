//
//  ItemAppearance.swift
//  Ice
//

import AppKit
import Carbon
import Combine
import DragonKit
import Observation

/// How an item is drawn: the app's own icon and name, or a symbol and localized name for a
/// system item. macOS 27 offers no reliable per-icon image of the menu bar, so Ice shows the
/// app icon instead.
@MainActor
enum ItemAppearance {
    private static var icons = [String: NSImage]()
    private static let inputSource = InputSourceAppearance()

    static func icon(for item: MenuBarItem) -> NSImage {
        if item.bundleIdentifier == "com.apple.TextInputMenuAgent" {
            return inputSource.icon
        }
        if let cached = icons[item.id] {
            return cached
        }
        let image: NSImage
        if let bundle = item.bundleIdentifier, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) {
            image = NSWorkspace.shared.icon(forFile: url.path)
        } else {
            image = NSImage(systemSymbolName: item.systemSymbol, accessibilityDescription: nil) ?? NSImage()
            image.isTemplate = true
        }
        icons[item.id] = image
        return image
    }

    /// Apple background agents whose process names mean nothing to a person.
    private static let agentNameKeys = [
        "com.apple.TextInputMenuAgent": "app.system.inputMenu",
        "com.apple.SSMenuAgent": "app.system.screenSharing",
    ]

    static func name(for item: MenuBarItem) -> String {
        if item.bundleIdentifier == "com.apple.TextInputMenuAgent", !inputSource.name.isEmpty {
            return inputSource.name
        }
        if let key = item.systemNameKey ?? item.bundleIdentifier.flatMap({ agentNameKeys[$0] }) {
            return L(key)
        }
        if !item.name.isEmpty {
            return item.name
        }
        // An app seen before Ice recorded its name (for example after an upgrade from 2.x).
        if let bundle = item.bundleIdentifier, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) {
            return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        }
        return item.bundleIdentifier ?? item.id
    }
}

/// 输入菜单由系统代理托管，图标和名称必须随当前输入法变化。
@MainActor
@Observable
final class InputSourceAppearance {
    private(set) var name = ""
    private(set) var icon = NSImage(systemSymbolName: "keyboard", accessibilityDescription: nil) ?? NSImage()
    @ObservationIgnored private var observer: AnyCancellable?

    init() {
        refresh()
        observer = DistributedNotificationCenter.default()
            .publisher(for: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String))
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
    }

    private func refresh() {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return }
        if let pointer = TISGetInputSourceProperty(source, kTISPropertyLocalizedName) {
            name = Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
        } else {
            name = ""
        }
        var image: NSImage?
        if let pointer = TISGetInputSourceProperty(source, kTISPropertyIconImageURL) {
            let url = Unmanaged<CFURL>.fromOpaque(pointer).takeUnretainedValue() as URL
            image = Self.loadIcon(at: url)
        }
        if image == nil, let pointer = TISGetInputSourceProperty(source, kTISPropertyIconRef) {
            image = NSImage(iconRef: OpaquePointer(pointer))
        }
        if image == nil, let pointer = TISGetInputSourceProperty(source, kTISPropertyBundleID) {
            let bundle = Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) {
                image = NSWorkspace.shared.icon(forFile: url.path)
            }
        }
        let resolved = image ?? NSImage(systemSymbolName: "keyboard", accessibilityDescription: nil) ?? NSImage()
        resolved.isTemplate = Self.isTemplateCompatible(resolved)
        icon = resolved
    }

    static func loadIcon(at url: URL) -> NSImage? {
        if let image = NSImage(contentsOf: url) { return image }
        // 输入法声明的扩展名可能与资源不符，按系统接口约定尝试常用扩展名。
        for ext in ["tiff", "tif", "png", "pdf", "icns"] where ext != url.pathExtension.lowercased() {
            if let image = NSImage(contentsOf: url.deletingPathExtension().appendingPathExtension(ext)) {
                return image
            }
        }
        return nil
    }

    static func isTemplateCompatible(_ image: NSImage) -> Bool {
        guard let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let context = CGContext(
                  data: nil,
                  width: 32,
                  height: 32,
                  bitsPerComponent: 8,
                  bytesPerRow: 128,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
              ),
              let data = context.data?.assumingMemoryBound(to: UInt8.self) else { return false }
        context.draw(source, in: CGRect(x: 0, y: 0, width: 32, height: 32))
        var hasTransparentPixels = false
        var hasVisiblePixels = false
        for offset in stride(from: 0, to: 32 * 32 * 4, by: 4) {
            if data[offset + 3] <= 20 {
                hasTransparentPixels = true
                continue
            }
            hasVisiblePixels = true
            let channels = [Int(data[offset]), Int(data[offset + 1]), Int(data[offset + 2])]
            if (channels.max() ?? 0) - (channels.min() ?? 0) > 20 { return false }
        }
        return hasTransparentPixels && hasVisiblePixels
    }
}
