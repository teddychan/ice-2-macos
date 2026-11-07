//
//  MenuBarController.swift
//  Ice
//

import AppKit
import Combine
import DragonKit
import OSLog

/// Discovers the menu bar's items and hides the hidden ones.
///
/// Discovery walks MenuBarAgent's accessibility tree. Hiding holds one runtime-loaded
/// `MenuBarClientCore` assessment-mode assertion whose configuration allows everything except
/// the hidden items (see ``HidingPolicy``). Every failure fails open: the assertion is released
/// and everything shows, so a private-API change can never strand an item.
@MainActor
@Observable
final class MenuBarController {
    /// Why hiding is off right now, or nil when it works.
    private(set) var errorMessage: String?

    @ObservationIgnored private let model: SettingsModel
    @ObservationIgnored private var assertion: AnyObject?
    @ObservationIgnored private var pendingAssertion: AnyObject?
    @ObservationIgnored private var configuration: HidingPolicy.Configuration?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var activationTimeout: Task<Void, Never>?
    @ObservationIgnored private var isRefreshing = false
    @ObservationIgnored private var cancellables = Set<AnyCancellable>()
    @ObservationIgnored private let logger = Logger(category: "MenuBar")

    // Notification Center bridge state. See the extension at the end of this file.
    @ObservationIgnored fileprivate var isSuspendedForNotificationCenter = false
    @ObservationIgnored fileprivate var notificationCenterTap: CFMachPort?
    @ObservationIgnored fileprivate var notificationCenterWatch: Task<Void, Never>?

    init(model: SettingsModel) {
        self.model = model
    }

    func start() {
        model.onHiddenChange = { [weak self] in self?.synchronize() }
        NSWorkspace.shared.publisher(for: \.runningApplications)
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.synchronize()
                Task { await self?.refresh() }
            }
            .store(in: &cancellables)
        Timer.publish(every: 15, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in Task { await self?.refresh() } }
            .store(in: &cancellables)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification)
            .sink { [weak self] _ in self?.restore() }
            .store(in: &cancellables)
        // No Space-change observer: assertions keep hiding across Spaces, and re-taking them
        // there would flash every hidden item.
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.restore()
                Task { await self?.refresh() }
            }
            .store(in: &cancellables)
        Task { await refresh() }
    }

    /// Re-reads the items on screen. Hidden items are absent from the tree, which is why
    /// the settings keep hidden ids even when discovery doesn't return them.
    func refresh() async {
        guard !isRefreshing else {
            return
        }
        guard ICEMenuBarAgentAvailable() else {
            failOpen(L("app.menuBar.unavailable"))
            return
        }
        guard AXIsProcessTrusted() else {
            failOpen(L("app.menuBar.needsAccessibility"))
            return
        }
        installNotificationCenterBridgeIfNeeded()
        isRefreshing = true
        defer { isRefreshing = false }
        let snapshot = await Task.detached(priority: .utility) { ICEMenuBarAgentSnapshot() }.value
        model.update(discovered: snapshot.compactMap { row in
            MenuBarItem(bundle: row["bundle"], identifier: row["identifier"], name: row["name"] ?? "")
        })
        synchronize()
    }

    /// Brings the assertion in line with the hidden items.
    func synchronize(revealing: String? = nil) {
        // Notification Center is open; the bridge re-synchronizes when it closes.
        guard !isSuspendedForNotificationCenter else {
            return
        }
        guard ICEMenuBarAgentAvailable() else {
            failOpen(L("app.menuBar.unavailable"))
            return
        }
        guard AXIsProcessTrusted() else {
            failOpen(L("app.menuBar.needsAccessibility"))
            return
        }
        apply(HidingPolicy.configuration(
            hidden: model.settings.hidden,
            runningBundles: Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)),
            revealing: revealing
        ))
    }

    private func apply(_ desired: HidingPolicy.Configuration?) {
        guard desired != configuration else {
            return
        }
        guard let desired else {
            restore()
            errorMessage = nil
            return
        }
        // Keep the previous assertion until the replacement is active: releasing it first
        // would briefly show every hidden item on each change.
        generation += 1
        activationTimeout?.cancel()
        ICEMenuBarAgentInvalidate(pendingAssertion)
        pendingAssertion = nil
        configuration = desired
        let request = generation
        pendingAssertion = ICEMenuBarAgentActivate(
            desired.systemItems.map { NSNumber(value: $0) },
            desired.bundles
        ) { [weak self] error in
            Task { @MainActor in
                guard let self, self.generation == request else {
                    return
                }
                self.activationTimeout?.cancel()
                self.activationTimeout = nil
                if let error {
                    self.failOpen(error.localizedDescription)
                } else {
                    ICEMenuBarAgentInvalidate(self.assertion)
                    self.assertion = self.pendingAssertion
                    self.pendingAssertion = nil
                    self.errorMessage = nil
                }
            }
        } as AnyObject?
        guard pendingAssertion != nil else {
            failOpen(L("app.menuBar.unavailable"))
            return
        }
        activationTimeout = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(5))
            } catch {
                return
            }
            guard let self, generation == request else {
                return
            }
            failOpen(L("app.menuBar.timeout"))
        }
    }

    /// Releases the assertion so everything shows. Called on quit and before sleep.
    func restore() {
        generation += 1
        activationTimeout?.cancel()
        activationTimeout = nil
        ICEMenuBarAgentInvalidate(assertion)
        ICEMenuBarAgentInvalidate(pendingAssertion)
        assertion = nil
        pendingAssertion = nil
        configuration = nil
    }

    private func failOpen(_ message: String) {
        restore()
        if errorMessage != message {
            logger.error("\(message, privacy: .public)")
        }
        errorMessage = message
    }
}

// MARK: - Notification Center bridge

// While an `MBAssessmentModeAssertion` is active, macOS 27 does not open Notification
// Center: clicking the clock and the "Show Notification Center" keyboard shortcut do
// nothing, whatever system items and bundles the configuration allows (the restriction
// comes from assessment mode itself). So the bridge watches for those two gestures,
// releases the assertion, replays the gesture, and keeps the assertion released while
// the panel is open. Hidden items are visible during that time, then concealed again.
// The trackpad gesture cannot be detected and is not bridged.
extension MenuBarController {
    /// Marks events posted by the bridge so that its own tap ignores them.
    private static let replayMarker: Int64 = 0x1CE2_0C0C
    private static let clockIdentifier = "com.apple.menuextra.clock"
    private static let notificationCenterBundle = "com.apple.notificationcenterui"
    /// `com.apple.symbolichotkeys` entry for "Show Notification Center".
    private static let showNotificationCenterHotKey = "163"

    private enum NotificationCenterGesture {
        case click(CGPoint)
        case key(CGKeyCode, CGEventFlags)
    }

    fileprivate func installNotificationCenterBridgeIfNeeded() {
        guard notificationCenterTap == nil else {
            if let tap = notificationCenterTap, !CGEvent.tapIsEnabled(tap: tap) {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return
        }
        let mask = (1 << CGEventType.leftMouseDown.rawValue) | (1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            if let refcon {
                let controller = Unmanaged<MenuBarController>.fromOpaque(refcon).takeUnretainedValue()
                // The tap's source is on the main run loop, so this runs on the main thread.
                MainActor.assumeIsolated {
                    controller.handleNotificationCenterEvent(type: type, event: event)
                }
            }
            return Unmanaged.passUnretained(event)
        }
        // Listen only: the gesture does nothing while the assertion is active, so it needs
        // no swallowing, and a filtering tap would hold every click and keystroke on the
        // system until this app's main thread got to it.
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            logger.error("Notification Center bridge: could not create the event tap")
            return
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        notificationCenterTap = tap
    }

    private func handleNotificationCenterEvent(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = notificationCenterTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return
        }
        guard
            isConcealing,
            !isSuspendedForNotificationCenter,
            event.getIntegerValueField(.eventSourceUserData) != Self.replayMarker
        else {
            return
        }
        switch type {
        case .leftMouseDown:
            let location = event.location
            if isInMenuBar(location), ICEMenuBarAgentElementHasIdentifier(location, Self.clockIdentifier) {
                suspendForNotificationCenter(replaying: .click(location))
            }
        case .keyDown:
            guard
                event.getIntegerValueField(.keyboardEventAutorepeat) == 0,
                let hotKey = notificationCenterHotKey()
            else {
                return
            }
            let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
            let relevant: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
            if keyCode == hotKey.keyCode, event.flags.intersection(relevant) == hotKey.flags.intersection(relevant) {
                suspendForNotificationCenter(replaying: .key(keyCode, event.flags))
            }
        default:
            break
        }
    }

    /// True while an assertion is hiding (or about to hide) items.
    private var isConcealing: Bool {
        assertion != nil || pendingAssertion != nil
    }

    /// Cheap pre-check so the Accessibility hit test only runs for clicks in a menu bar.
    private func isInMenuBar(_ point: CGPoint) -> Bool {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else {
            return false
        }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displays, &count) == .success else {
            return false
        }
        return displays.prefix(Int(count)).contains { display in
            let bounds = CGDisplayBounds(display)
            return point.x >= bounds.minX && point.x < bounds.maxX
                && point.y >= bounds.minY && point.y < bounds.minY + 60
        }
    }

    /// The user's "Show Notification Center" shortcut, if one is set and enabled.
    private func notificationCenterHotKey() -> (keyCode: CGKeyCode, flags: CGEventFlags)? {
        guard
            let hotKeys = UserDefaults(suiteName: "com.apple.symbolichotkeys")?
                .dictionary(forKey: "AppleSymbolicHotKeys"),
            let entry = hotKeys[Self.showNotificationCenterHotKey] as? [String: Any],
            (entry["enabled"] as? Bool) == true || (entry["enabled"] as? Int) == 1,
            let value = entry["value"] as? [String: Any],
            let parameters = value["parameters"] as? [Int], parameters.count == 3,
            parameters[1] != 65535
        else {
            return nil
        }
        return (CGKeyCode(parameters[1]), CGEventFlags(rawValue: UInt64(parameters[2])))
    }

    private func suspendForNotificationCenter(replaying gesture: NotificationCenterGesture) {
        isSuspendedForNotificationCenter = true
        restore()
        notificationCenterWatch?.cancel()
        notificationCenterWatch = Task { [weak self] in
            // MenuBarAgent needs a moment after the release before the gesture works.
            try? await Task.sleep(for: .milliseconds(200))
            guard let self, !Task.isCancelled else {
                return
            }
            self.replay(gesture)
            await self.waitForNotificationCenterToClose()
            guard !Task.isCancelled else {
                return
            }
            self.isSuspendedForNotificationCenter = false
            self.synchronize()
        }
    }

    private func replay(_ gesture: NotificationCenterGesture) {
        let source = CGEventSource(stateID: .hidSystemState)
        var events = [CGEvent?]()
        switch gesture {
        case .click(let point):
            for type in [CGEventType.leftMouseDown, .leftMouseUp] {
                events.append(CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left))
            }
        case .key(let keyCode, let flags):
            for keyDown in [true, false] {
                let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: keyDown)
                event?.flags = flags
                events.append(event)
            }
        }
        for event in events.compactMap({ $0 }) {
            event.setIntegerValueField(.eventSourceUserData, value: Self.replayMarker)
            event.post(tap: .cghidEventTap)
        }
    }

    /// Waits up to two seconds for the panel to appear, then for as long as it stays open.
    private func waitForNotificationCenterToClose() async {
        var opened = false
        let deadline = ContinuousClock.now + .seconds(2)
        while !Task.isCancelled {
            let open = isNotificationCenterOpen()
            if open {
                opened = true
            }
            if opened ? !open : ContinuousClock.now > deadline {
                return
            }
            try? await Task.sleep(for: .milliseconds(200))
        }
    }

    private func isNotificationCenterOpen() -> Bool {
        let pids = Set(NSRunningApplication
            .runningApplications(withBundleIdentifier: Self.notificationCenterBundle)
            .map(\.processIdentifier))
        guard
            !pids.isEmpty,
            let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]
        else {
            return false
        }
        // The panel is a large window above the normal levels; the desktop widgets the same
        // process keeps on screen sit at a negative level.
        return windows.contains { window in
            guard
                let pid = window[kCGWindowOwnerPID as String] as? pid_t, pids.contains(pid),
                let layer = window[kCGWindowLayer as String] as? Int, layer > 0,
                let bounds = window[kCGWindowBounds as String] as? [String: CGFloat]
            else {
                return false
            }
            return (bounds["Height"] ?? 0) > 200
        }
    }
}
