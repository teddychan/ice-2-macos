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

    static func subrole(for element: UIElement) -> String? {
        queue.sync { try? element.attribute(.subrole) }
    }

    static func parent(of element: UIElement) -> UIElement? {
        queue.sync { try? element.attribute(.parent) }
    }

    /// Returns a Boolean value that indicates whether the AX element at or near
    /// the given point within `displayBounds` is a menu bar status item (`AXMenuExtra`).
    static func isMenuExtra(
        at point: CGPoint,
        in displayBounds: CGRect,
        isMenuExtraAtPoint: (CGPoint) -> Bool = { probePoint in
            guard var element = element(at: probePoint) else {
                return false
            }
            for _ in 0..<4 {
                if subrole(for: element) == "AXMenuExtra" {
                    return true
                }
                guard let next = parent(of: element) else {
                    break
                }
                element = next
            }
            return false
        }
    ) -> Bool {
        guard displayBounds.width > 0 else {
            return false
        }
        if point.x >= displayBounds.maxX - 24 {
            return true
        }
        let probeY = displayBounds.minY + 14
        for offsetX: CGFloat in [0, -10, 10] {
            let probePoint = CGPoint(x: point.x + offsetX, y: probeY)
            if displayBounds.contains(probePoint), isMenuExtraAtPoint(probePoint) {
                return true
            }
        }
        return false
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
