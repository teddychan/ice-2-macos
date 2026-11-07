//
//  IceBarPanel.swift
//  Ice
//

import AppKit
import DragonKit
import SwiftUI

/// The Ice Bar: a glass panel under the Ice icon that holds the hidden items.
///
/// Non-activating, so opening it leaves the frontmost app frontmost. It can become key only so
/// that Escape closes it.
@MainActor
final class IceBarPanel: NSPanel {
    private let model: SettingsModel
    private let hostingView: NSHostingView<IceBarView>
    private var monitors = [Any]()
    private var anchor: (x: CGFloat, screen: NSScreen)?

    init(model: SettingsModel, onPress: @escaping (MenuBarItem) -> Void) {
        self.model = model
        var close: () -> Void = {}
        self.hostingView = NSHostingView(rootView: IceBarView(
            model: model,
            onPress: { item in
                close()
                onPress(item)
            }
        ))
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        close = { [weak self] in self?.hide() }
        hostingView.rootView.onDrop = { [weak self] in self?.layOut() }
        level = .statusBar
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        let glass = NSGlassEffectView()
        glass.cornerRadius = 14
        glass.contentView = hostingView
        contentView = glass
        setAccessibilityLabel(L("app.iceBar.title"))
    }

    override var canBecomeKey: Bool { true }

    /// Opens the Ice Bar under the Ice icon at `anchorX`, or closes it when it is open.
    func toggle(anchorX: CGFloat) {
        if isVisible {
            hide()
            return
        }
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main else {
            return
        }
        anchor = (anchorX, screen)
        layOut()
        makeKeyAndOrderFront(nil)
        installMonitors()
    }

    func hide() {
        removeMonitors()
        orderOut(nil)
    }

    /// Sizes the panel to its content and places it under the icon.
    private func layOut() {
        guard let anchor else {
            return
        }
        let size = hostingView.fittingSize
        setContentSize(size)
        setFrameOrigin(IceBarPlacement.origin(
            anchorX: anchor.x,
            size: size,
            screen: anchor.screen.frame,
            visibleFrame: anchor.screen.visibleFrame
        ))
    }

    /// Closes on a click in another app or on Escape. A click on the Ice icon toggles instead.
    private func installMonitors() {
        removeMonitors()
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            self?.hide()
        }) {
            monitors.append(monitor)
        }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard event.keyCode == 53 else { // Escape
                return event
            }
            self?.hide()
            return nil
        }) {
            monitors.append(monitor)
        }
    }

    private func removeMonitors() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
    }
}

/// The Ice Bar's content: the hidden items in order. Click one to open its menu, drag one onto
/// another to reorder.
struct IceBarView: View {
    let model: SettingsModel
    let onPress: (MenuBarItem) -> Void
    var onDrop: () -> Void = {}

    var body: some View {
        HStack(spacing: 2) {
            if model.hiddenItems.isEmpty {
                Text(L("app.iceBar.empty"))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .frame(height: 28)
            }
            ForEach(model.hiddenItems) { item in
                Button {
                    onPress(item)
                } label: {
                    ItemIcon(item: item, size: 20)
                        .frame(width: 32, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(ItemAppearance.name(for: item))
                .accessibilityLabel(ItemAppearance.name(for: item))
                .draggable(item.id)
                .dropDestination(for: String.self) { ids, _ in
                    guard
                        let id = ids.first,
                        let dragged = model.hiddenItems.first(where: { $0.id == id })
                    else {
                        return false
                    }
                    model.move(dragged, onto: item)
                    onDrop()
                    return true
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .dragonLocalized()
    }
}
