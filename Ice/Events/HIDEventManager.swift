//
//  HIDEventManager.swift
//  Ice
//

import Cocoa
import Combine

/// Manager that monitors input events and implements the features
/// that are triggered by them, such as showing hidden items on
/// click/hover/scroll.
@MainActor
final class HIDEventManager: ObservableObject {
    /// A Boolean value that indicates whether the user is dragging
    /// a menu bar item.
    @Published private(set) var isDraggingMenuBarItem = false

    /// The shared app state.
    private weak var appState: AppState?

    /// Storage for internal observers.
    private var cancellables = Set<AnyCancellable>()

    /// History of the manager's enabled states.
    private var enabledStateStack = [Bool]()

    /// A Boolean value that indicates whether the manager is enabled.
    private var isEnabled = false {
        didSet {
            if isEnabled {
                for monitor in allMonitors {
                    monitor.start()
                }
            } else {
                for monitor in allMonitors {
                    monitor.stop()
                }
            }
            updateMouseMovedTap()
        }
    }

    // MARK: Monitors

    /// Monitor for mouse down events.
    private(set) lazy var mouseDownMonitor = EventMonitor.universal(
        for: [.leftMouseDown, .rightMouseDown]
    ) { [weak self] event in
        guard let self, isEnabled, let appState, let screen = bestScreen(appState: appState) else {
            return event
        }
        if handleOpenSettingsFallback(with: event, appState: appState, screen: screen) {
            return event
        }
        switch event.type {
        case .leftMouseDown:
            handleShowOnClick(with: event, appState: appState, screen: screen)
            handleSmartRehide(with: event, appState: appState, screen: screen)
        case .rightMouseDown:
            handleSecondaryContextMenu(appState: appState, screen: screen)
        default:
            return event
        }
        handlePreventShowOnHover(with: event, appState: appState, screen: screen)
        return event
    }

    /// Monitor for mouse up events.
    private(set) lazy var mouseUpMonitor = EventMonitor.universal(
        for: .leftMouseUp
    ) { [weak self] event in
        guard let self, isEnabled else {
            return event
        }
        handleMenuBarItemDragStop()
        return event
    }

    /// Monitor for mouse dragged events.
    private(set) lazy var mouseDraggedMonitor = EventMonitor.universal(
        for: .leftMouseDragged
    ) { [weak self] event in
        if let self, isEnabled, let appState, let screen = bestScreen(appState: appState) {
            handleMenuBarItemDragStart(with: event, appState: appState, screen: screen)
        }
        return event
    }

    /// Tap for mouse moved events.
    private(set) lazy var mouseMovedTap = EventTap(
        type: .mouseMoved,
        location: .hidEventTap,
        placement: .tailAppendEventTap,
        option: .listenOnly
    ) { [weak self] _, event in
        if let self, isEnabled, let appState, let screen = bestScreen(appState: appState) {
            handleShowOnHover(appState: appState, screen: screen)
        }
        return event
    }

    /// Monitor for scroll wheel events.
    private(set) lazy var scrollWheelMonitor = EventMonitor.universal(
        for: .scrollWheel
    ) { [weak self] event in
        if let self, isEnabled, let appState, let screen = bestScreen(appState: appState) {
            handleShowOnScroll(with: event, appState: appState, screen: screen)
        }
        return event
    }

    // MARK: All Monitors

    /// All monitors maintained by the manager.
    ///
    /// The mouse-moved tap is deliberately excluded here and managed
    /// separately by ``updateMouseMovedTap()``, so it only runs when a
    /// feature that needs per-movement tracking is actually enabled.
    private lazy var allMonitors: [any EventMonitorProtocol] = [
        mouseDownMonitor,
        mouseUpMonitor,
        mouseDraggedMonitor,
        scrollWheelMonitor,
    ]

    /// A Boolean value that indicates whether any enabled feature relies on
    /// tracking mouse movement.
    private var needsMouseMovedTap: Bool {
        guard let appState else {
            return false
        }
        return appState.settings.general.showOnHoverEmptyMenuBar
            || appState.settings.general.showOnHoverOverIceIcon
    }

    /// Enables the mouse-moved tap only when the manager is enabled and a
    /// feature that needs per-movement tracking is active.
    ///
    /// A `.mouseMoved` event tap fires on every pointer movement, which wakes
    /// the app constantly. Leaving it running when no "show on hover" feature
    /// is enabled burns energy for no benefit, so the tap is toggled to match
    /// the features that actually need it.
    private func updateMouseMovedTap() {
        if isEnabled && needsMouseMovedTap {
            mouseMovedTap.start()
        } else {
            mouseMovedTap.stop()
        }
    }

    // MARK: Setup

    /// Sets up the manager.
    func performSetup(with appState: AppState) {
        self.appState = appState
        startAll()
        configureCancellables()
    }

    /// Configures the internal observers for the manager.
    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        if let appState, let hiddenSection = appState.menuBarManager.section(withName: .hidden) {
            // In fullscreen mode, the menu bar slides down from the top on hover. Observe the
            // frame of the hidden section's control item, which we know will always be in the
            // menu bar, and run the show-on-hover check when it changes.
            Publishers.CombineLatest3(
                hiddenSection.controlItem.$frame,
                appState.$activeSpace.map(\.isFullscreen),
                appState.menuBarManager.$isMenuBarHiddenBySystem
            )
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak appState] _, isFullscreen, isMenuBarHiddenBySystem in
                guard let self, isEnabled, let appState, isFullscreen || isMenuBarHiddenBySystem else {
                    return
                }
                if let screen = bestScreen(appState: appState) {
                    handleShowOnHover(appState: appState, screen: screen)
                }
            }
            .store(in: &c)

            // Toggle the mouse-moved tap whenever the features that depend on
            // it change, so it never runs when no "show on hover" trigger is on.
            Publishers.Merge(
                appState.settings.general.$showOnHoverEmptyMenuBar.replace(with: ()),
                appState.settings.general.$showOnHoverOverIceIcon.replace(with: ())
            )
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.updateMouseMovedTap()
            }
            .store(in: &c)
        }

        cancellables = c
    }

    // MARK: Start/Stop

    /// Starts all monitors.
    func startAll() {
        isEnabled = enabledStateStack.popLast() ?? true
    }

    /// Stops all monitors.
    func stopAll() {
        enabledStateStack.append(isEnabled)
        isEnabled = false
    }
}

// MARK: - Handler Methods

extension HIDEventManager {

    // MARK: Handle Show On Click

    private func handleShowOnClick(with event: NSEvent, appState: AppState, screen: NSScreen) {
        let modifierFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let alwaysHiddenSection = appState.menuBarManager.section(withName: .alwaysHidden)
        let canOptionToggleAlwaysHidden =
            modifierFlags == .option &&
            alwaysHiddenSection?.isEnabled == true

        guard
            appState.settings.general.showOnClick || canOptionToggleAlwaysHidden,
            isMouseInsideEmptyMenuBarSpace(appState: appState, screen: screen)
        else {
            return
        }

        if appState.activeSpace.isFullscreen && !screen.hasNotch {
            let windows = WindowInfo.createWindows(option: .onScreen)
            guard WindowInfo.menuBarWindow(from: windows, for: screen.displayID) != nil else {
                return
            }
        }

        Task {
            if modifierFlags == .control {
                handleSecondaryContextMenu(appState: appState, screen: screen)
                return
            }

            let targetSection: MenuBarSection

            if canOptionToggleAlwaysHidden, let alwaysHiddenSection {
                targetSection = alwaysHiddenSection
            } else if
                let hiddenSection = appState.menuBarManager.section(withName: .hidden),
                hiddenSection.isEnabled
            {
                targetSection = hiddenSection
            } else {
                return
            }

            targetSection.toggle()
        }
    }

    // MARK: Handle Smart Rehide

    private func handleSmartRehide(with event: NSEvent, appState: AppState, screen: NSScreen) {
        guard
            appState.settings.general.autoRehide,
            case .smart = appState.settings.general.rehideStrategy
        else {
            return
        }

        // Make sure clicking the Ice icon doesn't trigger rehide.
        if let iceIcon = appState.menuBarManager.controlItem(withName: .visible) {
            guard event.window !== iceIcon.window else {
                return
            }
        }

        // Only continue if the click is not inside the Ice Bar, at
        // least one section is visible, and the mouse is not inside
        // the menu bar.
        guard
            event.window !== appState.menuBarManager.iceBarPanel,
            appState.menuBarManager.hasVisibleSection,
            !isMouseInsideMenuBar(appState: appState, screen: screen)
        else {
            return
        }

        let initialSpaceID = Bridging.getActiveSpaceID()

        Task {
            // Give the window under the mouse a chance to focus.
            try await Task.sleep(for: .milliseconds(250))

            // Don't bother checking the window if the click caused
            // a space change.
            if Bridging.getActiveSpaceID() != initialSpaceID {
                for section in appState.menuBarManager.sections {
                    section.hide()
                }
                return
            }

            // Get the window that was clicked.
            guard
                let mouseLocation = MouseHelpers.locationCoreGraphics,
                let windowUnderMouse = WindowInfo.createWindows(option: .onScreen)
                    .filter({ $0.layer < CGWindowLevelForKey(.cursorWindow) })
                    .first(where: { $0.bounds.contains(mouseLocation) && $0.title?.isEmpty == false }),
                let owningApplication = windowUnderMouse.owningApplication
            else {
                return
            }

            // Note: The Dock is an exception to the following check.
            if owningApplication.bundleIdentifier != "com.apple.dock" {
                // Only continue if the clicked app is active, and has
                // a regular activation policy.
                guard
                    owningApplication.isActive,
                    owningApplication.activationPolicy == .regular
                else {
                    return
                }
            }

            // All checks have passed, hide the sections.
            for section in appState.menuBarManager.sections {
                section.hide()
            }
        }
    }

    // MARK: Handle Secondary Context Menu

    private func handleSecondaryContextMenu(appState: AppState, screen: NSScreen) {
        Task {
            guard
                appState.settings.advanced.enableSecondaryContextMenu,
                isMouseInsideEmptyMenuBarSpace(appState: appState, screen: screen),
                let mouseLocation = MouseHelpers.locationAppKit
            else {
                return
            }
            // Delay prevents the menu from immediately closing.
            try await Task.sleep(for: .milliseconds(100))
            appState.menuBarManager.showSecondaryContextMenu(at: mouseLocation)
        }
    }

    // MARK: Handle Open Settings Fallback

    private func handleOpenSettingsFallback(with event: NSEvent, appState: AppState, screen: NSScreen) -> Bool {
        guard
            !appState.settings.advanced.enableSecondaryContextMenu,
            event.type == .leftMouseDown || event.type == .rightMouseDown,
            isMouseInsideMenuBar(appState: appState, screen: screen)
        else {
            return false
        }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers.contains([.option, .command]) else {
            return false
        }

        appState.activate(withPolicy: .regular)
        appState.openWindow(.settings)
        return true
    }

    // MARK: Handle Menu Bar Item Drag Stop

    private func handleMenuBarItemDragStop() {
        if isDraggingMenuBarItem {
            isDraggingMenuBarItem = false
        }
    }

    // MARK: Handle Menu Bar Item Drag Start

    private func handleMenuBarItemDragStart(with event: NSEvent, appState: AppState, screen: NSScreen) {
        guard
            !isDraggingMenuBarItem,
            event.modifierFlags.contains(.command),
            isMouseInsideMenuBar(appState: appState, screen: screen)
        else {
            return
        }

        isDraggingMenuBarItem = true

        if appState.settings.advanced.showAllSectionsOnUserDrag {
            for section in appState.menuBarManager.sections {
                section.controlItem.state = .showSection
            }
        }
    }

    // MARK: Handle Show On Hover

    private func handleShowOnHover(appState: AppState, screen: NSScreen) {
        let showOnHoverEmptyMenuBar = appState.settings.general.showOnHoverEmptyMenuBar
        let showOnHoverOverIceIcon = appState.settings.general.showOnHoverOverIceIcon

        // Make sure at least one "ShowOnHover" trigger is enabled and the
        // feature is allowed.
        guard
            showOnHoverEmptyMenuBar || showOnHoverOverIceIcon,
            appState.menuBarManager.showOnHoverAllowed
        else {
            return
        }

        // Only continue if we have a hidden section (we should).
        guard let hiddenSection = appState.menuBarManager.section(withName: .hidden) else {
            return
        }

        let emptyMenuBarDelay = appState.settings.general.showOnHoverEmptyMenuBarDelay
        let iceIconDelay = appState.settings.general.showOnHoverOverIceIconDelay

        if hiddenSection.isHidden {
            // The Ice icon is a menu bar item, so it is never inside the
            // "empty menu bar space"; the two triggers are mutually exclusive
            // positions.
            if
                showOnHoverEmptyMenuBar,
                isMouseInsideEmptyMenuBarSpace(appState: appState, screen: screen)
            {
                Task {
                    try await Task.sleep(for: .seconds(emptyMenuBarDelay))
                    // Make sure the mouse is still inside.
                    guard isMouseInsideEmptyMenuBarSpace(appState: appState, screen: screen) else {
                        return
                    }
                    hiddenSection.show()
                }
            } else if
                showOnHoverOverIceIcon,
                isMouseInsideIceIcon(appState: appState)
            {
                Task {
                    try await Task.sleep(for: .seconds(iceIconDelay))
                    // Make sure the mouse is still inside the Ice icon.
                    guard isMouseInsideIceIcon(appState: appState) else {
                        return
                    }
                    hiddenSection.show()
                }
            }
        } else {
            guard
                !isMouseInsideMenuBar(appState: appState, screen: screen),
                !isMouseInsideIceBar(appState: appState),
                !isMouseInsideIceBarTransitArea(appState: appState, screen: screen)
            else {
                return
            }
            // Use the larger of the enabled delays as the rehide debounce so
            // items never vanish faster than the slowest trigger reacts.
            let rehideDelay = max(
                showOnHoverEmptyMenuBar ? emptyMenuBarDelay : 0,
                showOnHoverOverIceIcon ? iceIconDelay : 0
            )
            Task {
                try await Task.sleep(for: .seconds(rehideDelay))
                // Make sure the mouse is still outside.
                guard
                    !isMouseInsideMenuBar(appState: appState, screen: screen),
                    !isMouseInsideIceBar(appState: appState),
                    !isMouseInsideIceBarTransitArea(appState: appState, screen: screen)
                else {
                    return
                }
                hiddenSection.hide()
            }
        }
    }

    // MARK: Handle Prevent Show On Hover

    private func handlePreventShowOnHover(with event: NSEvent, appState: AppState, screen: NSScreen) {
        guard
            appState.settings.general.showOnHoverEmptyMenuBar
                || appState.settings.general.showOnHoverOverIceIcon,
            NativeMenuBarManager.usesNativeBackend || !appState.settings.general.useIceBar
        else {
            return
        }

        guard isMouseInsideMenuBar(appState: appState, screen: screen) else {
            return
        }

        if isMouseInsideMenuBarItem(appState: appState, screen: screen) {
            switch event.type {
            case .leftMouseDown:
                if appState.menuBarManager.hasVisibleSection {
                    break
                }
                if isMouseInsideIceIcon(appState: appState) {
                    break
                }
                return
            case .rightMouseDown:
                if appState.menuBarManager.hasVisibleSection {
                    break
                }
                return
            default:
                return
            }
        } else if isMouseInsideApplicationMenu(appState: appState, screen: screen) {
            return
        }

        // Mouse is inside the menu bar, outside an item or application
        // menu, so it must be inside an empty menu bar space.
        appState.menuBarManager.showOnHoverAllowed = false
    }

    // MARK: Handle Show On Scroll

    private func handleShowOnScroll(with event: NSEvent, appState: AppState, screen: NSScreen) {
        guard
            appState.settings.general.showOnScroll,
            isMouseInsideMenuBar(appState: appState, screen: screen),
            let hiddenSection = appState.menuBarManager.section(withName: .hidden)
        else {
            return
        }

        let delta = if abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX) {
            event.scrollingDeltaY
        } else {
            event.scrollingDeltaX
        }
        let threshold = event.hasPreciseScrollingDeltas ? 5.0 : 0.5

        if delta > threshold {
            hiddenSection.show()
        } else if delta < -threshold {
            hiddenSection.hide()
        }
    }
}

// MARK: - Helper Methods

extension HIDEventManager {
    /// Returns the best screen to use for event manager calculations.
    func bestScreen(appState: AppState) -> NSScreen? {
        if let screen = NSScreen.screenWithMouse {
            if appState.activeSpace.isFullscreen || NSScreen.screensHaveSeparateSpaces {
                return screen
            }
        }
        return NSScreen.screenWithActiveMenuBar ?? NSScreen.main
    }

    /// A Boolean value that indicates whether the mouse pointer is within
    /// the bounds of the menu bar.
    func isMouseInsideMenuBar(appState: AppState, screen: NSScreen) -> Bool {
        // Ice icon must be vertically visible. Otherwise, we can infer
        // that the menu bar is hidden and the mouse is not inside.
        guard
            let iceIcon = appState.menuBarManager.controlItem(withName: .visible),
            let iceIconFrame = iceIcon.frame,
            iceIconFrame.maxY <= screen.frame.maxY,
            let mouseLocation = MouseHelpers.locationAppKit
        else {
            return false
        }

        if
            !NSScreen.screensHaveSeparateSpaces,
            let activeMenuBarScreen = NSScreen.screenWithActiveMenuBar,
            screen.displayID != activeMenuBarScreen.displayID
        {
            return false
        }

        if NSScreen.screenWithMouse?.displayID != screen.displayID {
            return false
        }

        if
            appState.activeSpace.isFullscreen,
            !screen.hasNotch,
            appState.menuBarManager.isMenuBarHiddenBySystem
        {
            return false
        }

        let menuBarMinY = appState.activeSpace.isFullscreen ? iceIconFrame.minY - 1 : screen.visibleFrame.maxY

        // Infer the menu bar frame from the screen frame.
        return mouseLocation.x >= screen.frame.minX &&
        mouseLocation.x <= screen.frame.maxX &&
        mouseLocation.y <= screen.frame.maxY &&
        mouseLocation.y >= menuBarMinY
    }

    /// A Boolean value that indicates whether the mouse pointer is within
    /// the bounds of the current application menu.
    func isMouseInsideApplicationMenu(appState: AppState, screen: NSScreen) -> Bool {
        guard
            let mouseLocation = MouseHelpers.locationCoreGraphics,
            var applicationMenuFrame = screen.getApplicationMenuFrame()
        else {
            return false
        }
        applicationMenuFrame.size.width += applicationMenuFrame.origin.x - screen.frame.origin.x
        applicationMenuFrame.origin.x = screen.frame.origin.x
        return applicationMenuFrame.contains(mouseLocation)
    }

    /// A Boolean value that indicates whether the mouse pointer is within
    /// the bounds of a menu bar item.
    func isMouseInsideMenuBarItem(appState: AppState, screen: NSScreen) -> Bool {
        if isMouseInsideIceIcon(appState: appState) {
            return true
        }
        guard let mouseLocation = MouseHelpers.locationCoreGraphics else {
            return false
        }
        if NativeMenuBarManager.usesNativeBackend {
            return AXHelpers.isMenuExtra(at: mouseLocation, in: CGDisplayBounds(screen.displayID))
        }
        let windowIDs = Bridging.getMenuBarWindowList(option: [.onScreen, .activeSpace, .itemsOnly])
        return windowIDs.contains { windowID in
            guard let bounds = Bridging.getWindowBounds(for: windowID) else {
                return false
            }
            return bounds.contains(mouseLocation)
        }
    }

    /// A Boolean value that indicates whether the mouse pointer is within
    /// the bounds of the screen's notch, if it has one.
    ///
    /// If the screen does not have a notch, this property returns `false`.
    func isMouseInsideNotch(appState: AppState, screen: NSScreen) -> Bool {
        guard
            let mouseLocation = MouseHelpers.locationAppKit,
            var frameOfNotch = screen.frameOfNotch
        else {
            return false
        }
        frameOfNotch.size.height += 1
        return frameOfNotch.contains(mouseLocation)
    }

    /// A Boolean value that indicates whether the mouse pointer is within
    /// the bounds of an empty space in the menu bar.
    func isMouseInsideEmptyMenuBarSpace(appState: AppState, screen: NSScreen) -> Bool {
        isMouseInsideMenuBar(appState: appState, screen: screen) &&
        !isMouseInsideApplicationMenu(appState: appState, screen: screen) &&
        !isMouseInsideMenuBarItem(appState: appState, screen: screen) &&
        !isMouseInsideNotch(appState: appState, screen: screen) &&
        !isMouseInsideOverlayAboveMenuBar()
    }

    /// A Boolean value that indicates whether the mouse pointer is occluded
    /// by a third-party window whose level is above the menu bar.
    private func isMouseInsideOverlayAboveMenuBar() -> Bool {
        guard let mouseLocation = MouseHelpers.locationCoreGraphics else {
            return false
        }
        let pid = ProcessInfo.processInfo.processIdentifier
        let menuBarLevel = Int(CGWindowLevelForKey(.mainMenuWindow))
        let cursorLevel = Int(CGWindowLevelForKey(.cursorWindow))
        return WindowInfo.createWindows(option: .onScreen).contains { window in
            window.ownerPID != pid &&
            window.layer > menuBarLevel &&
            window.layer < cursorLevel &&
            window.bounds.contains(mouseLocation)
        }
    }

    /// A Boolean value that indicates whether the mouse pointer is within
    /// the bounds of the Ice Bar panel.
    func isMouseInsideIceBar(appState: AppState) -> Bool {
        guard let mouseLocation = MouseHelpers.locationAppKit else {
            return false
        }
        let panel = appState.menuBarManager.iceBarPanel
        // Pad the frame to be more forgiving if the user accidentally
        // moves their mouse outside of the Ice Bar.
        let paddedFrame = panel.frame.insetBy(dx: -15, dy: -15)
        return paddedFrame.contains(mouseLocation)
    }

    /// A Boolean value that indicates whether the pointer is in the gap
    /// between the menu bar and the Ice Bar while moving toward the panel.
    func isMouseInsideIceBarTransitArea(appState: AppState, screen: NSScreen) -> Bool {
        guard
            appState.settings.general.useIceBar,
            appState.navigationState.isIceBarPresented,
            let mouseLocation = MouseHelpers.locationAppKit
        else {
            return false
        }

        let panelFrame = appState.menuBarManager.iceBarPanel.frame
        guard !panelFrame.isEmpty else {
            return false
        }

        let horizontalRange = panelFrame.insetBy(dx: -48, dy: 0)
        return mouseLocation.x >= horizontalRange.minX &&
        mouseLocation.x <= horizontalRange.maxX &&
        mouseLocation.y <= screen.visibleFrame.maxY &&
        mouseLocation.y >= panelFrame.maxY - 16
    }

    /// A Boolean value that indicates whether the mouse pointer is within
    /// the bounds of the Ice icon.
    func isMouseInsideIceIcon(appState: AppState) -> Bool {
        guard
            let visibleSection = appState.menuBarManager.section(withName: .visible),
            let iceIconFrame = visibleSection.controlItem.frame,
            let mouseLocation = MouseHelpers.locationAppKit
        else {
            return false
        }
        return iceIconFrame.contains(mouseLocation)
    }
}

// MARK: - EventMonitor Helpers

/// Helper protocol to enable group operations across event
/// monitoring types.
@MainActor
private protocol EventMonitorProtocol {
    func start()
    func stop()
}

extension EventMonitor: EventMonitorProtocol { }

extension EventTap: EventMonitorProtocol {
    fileprivate func start() {
        enable()
    }

    fileprivate func stop() {
        disable()
    }
}
