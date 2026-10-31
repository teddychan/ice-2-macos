//
//  AXHelpers.swift
//  Shared
//

import AXSwift
import Cocoa

enum AXHelpers {
    /// Process-wide Accessibility IPC timeout in seconds. Prevents synchronous
    /// queries from stalling the main thread for the 6-second HIServices default
    /// when a target application is unresponsive.
    static let defaultMessagingTimeout: Float = 0.2

    private static let queue: DispatchQueue = {
        UIElement.globalMessagingTimeout = defaultMessagingTimeout
        return DispatchQueue.targetingGlobal(
            label: "AXHelpers.queue",
            qos: .userInteractive,
            attributes: .concurrent
        )
    }()

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
