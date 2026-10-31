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

    /// Returns a conservative snapshot of the menu extras in the real menu-bar
    /// strip. MenuBarAgent can expose several overlapping copies of that strip;
    /// retaining all their frames protects icons without guessing which is live.
    /// Call off the main thread. An incomplete or timed-out snapshot is unknown.
    static func menuExtraFrames(in menuBarBounds: CGRect) -> [CGRect]? {
        guard
            let agent = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.MenuBarAgent").first,
            let app = application(for: agent)
        else {
            return nil
        }
        let deadline = ContinuousClock.now.advanced(by: .milliseconds(300))
        app.messagingTimeout = 0.05
        guard let windows: [UIElement] = try? app.arrayAttribute(.children), windows.count <= 16 else {
            return nil
        }
        var frames = [CGRect]()
        var remainingItems = 128
        for window in windows {
            guard ContinuousClock.now < deadline else {
                return nil
            }
            window.messagingTimeout = 0.05
            guard let windowFrame: CGRect = try? window.attribute(.frame) else {
                return nil
            }
            guard
                abs(windowFrame.minX - menuBarBounds.minX) < 1,
                abs(windowFrame.minY - menuBarBounds.minY) < 1,
                abs(windowFrame.width - menuBarBounds.width) < 1,
                abs(windowFrame.height - menuBarBounds.height) < 1
            else {
                continue
            }
            guard let items: [UIElement] = try? window.arrayAttribute(.children), items.count <= remainingItems else {
                return nil
            }
            remainingItems -= items.count
            for item in items {
                guard ContinuousClock.now < deadline else {
                    return nil
                }
                item.messagingTimeout = 0.05
                guard let frame: CGRect = try? item.attribute(.frame) else {
                    return nil
                }
                let clippedFrame = frame.intersection(menuBarBounds)
                if !clippedFrame.isNull, clippedFrame.width > 0, clippedFrame.height > 0 {
                    frames.append(clippedFrame)
                }
            }
        }
        guard ContinuousClock.now < deadline, !frames.isEmpty else {
            return nil
        }
        return frames
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
