//
//  AXHelpers.swift
//  Shared
//

import AXSwift
import Cocoa

enum AXHelpers {
    private static let queue = DispatchQueue.targetingGlobal(
        label: "AXHelpers.queue",
        qos: .userInteractive,
        attributes: .concurrent
    )

    @discardableResult
    static func isProcessTrusted(prompt: Bool = false) -> Bool {
        queue.sync { checkIsProcessTrusted(prompt: prompt) }
    }

    static func element(at point: CGPoint) -> UIElement? {
        queue.sync { try? systemWideElement.elementAtPosition(Float(point.x), Float(point.y)) }
    }

    static func application(for runningApp: NSRunningApplication) -> Application? {
        queue.sync { Application(runningApp) }
    }

    static func extrasMenuBar(for app: Application) -> UIElement? {
        queue.sync { try? app.attribute(.extrasMenuBar) }
    }

    static func children(for element: UIElement) -> [UIElement] {
        queue.sync { try? element.arrayAttribute(.children) } ?? []
    }

    static func isEnabled(_ element: UIElement) -> Bool {
        queue.sync { try? element.attribute(.enabled) } ?? false
    }

    static func frame(for element: UIElement) -> CGRect? {
        queue.sync { try? element.attribute(.frame) }
    }

    static func role(for element: UIElement) -> Role? {
        queue.sync { try? element.role() }
    }

    static func parent(of element: UIElement) -> UIElement? {
        queue.sync { try? element.attribute(.parent) }
    }

    /// Returns the screen frames (in CoreGraphics global coordinates) of the
    /// status items hosted by `MenuBarAgent` on the given display.
    static func menuExtraFrames(
        on display: CGDirectDisplayID,
        matchingControlItemFrame controlItemFrame: CGRect? = nil
    ) -> [CGRect] {
        guard
            let agent = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.MenuBarAgent").first,
            let app = application(for: agent)
        else {
            return []
        }
        let displayBounds = CGDisplayBounds(display)
        var fallbackFrames = [CGRect]()

        for window in children(for: app) {
            guard
                role(for: window) == .window,
                let windowFrame = frame(for: window),
                displayBounds.intersects(windowFrame)
            else {
                continue
            }
            let itemFrames = children(for: window)
                .compactMap { frame(for: $0) }
                .filter { $0.width > 2 && displayBounds.intersects($0) }
            guard !itemFrames.isEmpty else {
                continue
            }
            if
                let controlItemFrame,
                itemFrames.contains(where: { abs($0.minX - controlItemFrame.minX) < 4 })
            {
                return itemFrames
            }
            if fallbackFrames.isEmpty {
                fallbackFrames = itemFrames
            }
        }

        return fallbackFrames
    }

    /// Returns the menu bar AX element near the given display origin.
    static func menuBarElement(nearDisplayOrigin displayOrigin: CGPoint) -> UIElement? {
        let probeOffsets = [
            CGPoint(x: 5, y: 12),
            CGPoint(x: 40, y: 12),
            CGPoint(x: 80, y: 12),
            CGPoint(x: 0, y: 0),
        ]

        for offset in probeOffsets {
            let point = CGPoint(x: displayOrigin.x + offset.x, y: displayOrigin.y + offset.y)
            guard var element = element(at: point) else {
                continue
            }

            for _ in 0..<4 {
                if role(for: element) == .menuBar {
                    return element
                }
                guard let next = parent(of: element) else {
                    break
                }
                element = next
            }
        }

        return nil
    }
}
