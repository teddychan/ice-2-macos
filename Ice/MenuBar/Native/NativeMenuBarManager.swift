//
//  NativeMenuBarManager.swift
//  Ice
//

import Cocoa
import Combine
import DragonKit
import OSLog

@MainActor
final class NativeMenuBarManager: ObservableObject {
    nonisolated static var usesNativeBackend: Bool { ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27 }

    @Published private(set) var items = [NativeMenuBarItem]()
    @Published private(set) var assignments = [String: MenuBarSection.Name]()
    @Published private(set) var errorMessage: String?
    @Published private(set) var profileNotice: String?
    @Published private(set) var isRefreshing = false

    @Published private(set) var appIcons = [String: NSImage]()
    private var appNames = [String: String]()

    func displayName(for item: NativeMenuBarItem) -> String {
        appNames[item.id] ?? item.name
    }

    /// Resolve against current discovery; stale or foreign drag payloads cannot create assignments.
    @discardableResult
    func moveItem(id: String, to section: MenuBarSection.Name) -> Bool {
        guard let item = items.first(where: { $0.id == id }), item.canAssign else { return false }
        setSection(section, for: item)
        return true
    }

    private weak var appState: AppState?
    private var assertion: AnyObject?
    private var pendingAssertion: AnyObject?
    private var configuration: NativeMenuBarPolicy.Configuration?
    private var generation = 0
    private var activationTimeout: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private let logger = Logger(category: "NativeMenuBar")
    private let activate: ([NSNumber], [String], @escaping (Error?) -> Void) -> AnyObject?
    private let invalidate: (AnyObject?) -> Void

    // Notification Center bridge state. See the extension at the end of this file.
    fileprivate var isSuspendedForNotificationCenter = false
    fileprivate var notificationCenterTap: CFMachPort?
    fileprivate var notificationCenterTapSource: CFRunLoopSource?
    fileprivate var notificationCenterWatch: Task<Void, Never>?
    fileprivate var isSwallowingClockMouseUp = false

    init(
        activate: @escaping ([NSNumber], [String], @escaping (Error?) -> Void) -> AnyObject? = { systems, bundles, completion in
            ICENativeMenuBarActivate(systems, bundles, completion) as AnyObject?
        },
        invalidate: @escaping (AnyObject?) -> Void = { ICENativeMenuBarInvalidate($0) }
    ) {
        self.activate = activate
        self.invalidate = invalidate
    }

    func performSetup(with appState: AppState) {
        guard Self.usesNativeBackend else { return }
        self.appState = appState
        if let data = Defaults.data(forKey: .nativeMenuBarSections) {
            do {
                assignments = try JSONDecoder().decode([String: MenuBarSection.Name].self, from: data)
            } catch {
                errorMessage = L("app.native.invalidSavedLayout")
            }
        }
        NSWorkspace.shared.publisher(for: \.runningApplications)
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.synchronizeVisibility()
                Task { await self?.refresh() }
            }
            .store(in: &cancellables)
        Timer.publish(every: 15, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in Task { await self?.refresh() } }
            .store(in: &cancellables)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification)
            .sink { [weak self] _ in self?.restore() }
            .store(in: &cancellables)
        Publishers.Merge(
            NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification),
            NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in
            self?.restore()
            Task { await self?.refresh() }
        }
        .store(in: &cancellables)
        Task { await refresh() }
    }

    func refresh() async {
        guard !isRefreshing, appState != nil else { return }
        guard ICENativeMenuBarAvailable() else {
            failOpen(L("app.native.unavailable"))
            return
        }
        guard AXIsProcessTrusted() else {
            failOpen(L("app.native.needsAccessibility"))
            return
        }
        installNotificationCenterBridgeIfNeeded()
        isRefreshing = true
        defer { isRefreshing = false }
        let snapshot = await Task.detached(priority: .utility) { ICENativeMenuBarSnapshot() }.value
        let discovered = snapshot.compactMap { row in
            NativeMenuBarPolicy.item(bundle: row["bundle"], identifier: row["identifier"], name: row["name"] ?? "")
        }
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        // Hidden AX nodes disappear. Retain known rows while their app is running,
        // and retain saved identities even when the app is not currently running.
        var merged = Dictionary(items.filter { item in
            !item.id.hasPrefix("bundle:") || running.contains(String(item.id.dropFirst(7))) || assignments[item.id] != nil
        }.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for item in discovered { merged[item.id] = item }
        for id in assignments.keys where merged[id] == nil {
            let name: String
            if id.hasPrefix("bundle:") {
                name = String(id.dropFirst(7))
            } else if id.hasPrefix("system:"), let number = Int(id.dropFirst(7)), (0...8).contains(number) {
                name = NativeMenuBarPolicy.systemNames[number]
            } else {
                continue
            }
            merged[id] = NativeMenuBarItem(id: id, name: name)
        }
        items = merged.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        for item in items where item.id.hasPrefix("bundle:") && appIcons[item.id] == nil {
            let bundle = String(item.id.dropFirst(7))
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) {
                appIcons[item.id] = NSWorkspace.shared.icon(forFile: url.path)
                appNames[item.id] = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
            }
        }
        synchronizeVisibility()
    }

    func setSection(_ section: MenuBarSection.Name, for item: NativeMenuBarItem) {
        guard item.canAssign else { return }
        if section == .alwaysHidden { appState?.settings.advanced.enableAlwaysHiddenSection = true }
        assignments[item.id] = section
        save()
        synchronizeVisibility()
    }

    private func save() {
        do {
            Defaults.set(try JSONEncoder().encode(assignments), forKey: .nativeMenuBarSections)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func captureLayout() -> [MenuBarSection.Name: [MenuBarItemTag]] {
        var result = [MenuBarSection.Name: [MenuBarItemTag]]()
        let ids = Set(assignments.keys).union(items.filter(\.canAssign).map(\.id))
        for id in ids.sorted() {
            if let tag = NativeMenuBarPolicy.tag(for: id) {
                result[assignments[id] ?? .visible, default: []].append(tag)
            }
        }
        return result
    }

    func applyProfile(_ profile: MenuBarLayoutProfile) async throws {
        let migration = NativeMenuBarPolicy.migrate(profile)
        guard !migration.assignments.isEmpty else {
            throw NSError(domain: "Ice.NativeProfile", code: 1, userInfo: [NSLocalizedDescriptionKey: L("app.native.noProfileMatches")])
        }
        if migration.assignments.values.contains(.alwaysHidden) {
            appState?.settings.advanced.enableAlwaysHiddenSection = true
        }
        // Existing saved profiles are never rewritten by migration.
        assignments = migration.assignments
        profileNotice = String(format: L("app.native.profileResult"), migration.conflicts.count, migration.unmatched)
        save()
        synchronizeVisibility()
        await refresh()
    }

    func synchronizeVisibility() {
        guard Self.usesNativeBackend, let appState else { return }
        // Notification Center is open; the bridge re-synchronizes when it closes.
        guard !isSuspendedForNotificationCenter else { return }
        guard ICENativeMenuBarAvailable() else {
            failOpen(L("app.native.unavailable"))
            return
        }
        guard AXIsProcessTrusted() else {
            failOpen(L("app.native.needsAccessibility"))
            return
        }
        let desired = NativeMenuBarPolicy.configuration(
            assignments: assignments,
            runningBundles: Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)),
            hiddenShown: appState.menuBarManager.section(withName: .hidden)?.controlItem.state == .showSection,
            alwaysHiddenShown: appState.menuBarManager.section(withName: .alwaysHidden)?.controlItem.state == .showSection,
            alwaysHiddenEnabled: appState.settings.advanced.enableAlwaysHiddenSection
        )
        apply(desired)
    }

    /// Kept separate from discovery so assertion replacement and stale callbacks
    /// can be tested without changing the real menu bar.
    func apply(_ desired: NativeMenuBarPolicy.Configuration?) {
        guard desired != configuration else { return }
        guard let desired else {
            restore()
            return
        }
        // Keep the previous hide state until the replacement is active. Releasing
        // it first would briefly expose always-hidden apps on every toggle.
        generation += 1
        activationTimeout?.cancel()
        invalidate(pendingAssertion)
        pendingAssertion = nil
        configuration = desired
        let request = generation
        pendingAssertion = activate(desired.systemItems.map { NSNumber(value: $0) }, desired.bundles) { [weak self] error in
            Task { @MainActor in
                guard let self, self.generation == request else { return }
                self.activationTimeout?.cancel()
                self.activationTimeout = nil
                if let error {
                    self.failOpen(error.localizedDescription)
                } else {
                    self.invalidate(self.assertion)
                    self.assertion = self.pendingAssertion
                    self.pendingAssertion = nil
                    self.errorMessage = nil
                }
            }
        }
        guard pendingAssertion != nil else {
            failOpen(L("app.native.unavailable"))
            return
        }
        activationTimeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
            guard let self, generation == request else { return }
            failOpen(L("app.native.timeout"))
        }
    }

    /// Also called before sleep and before the app's other termination work.
    func restore() {
        generation += 1
        activationTimeout?.cancel()
        activationTimeout = nil
        invalidate(assertion)
        invalidate(pendingAssertion)
        assertion = nil
        pendingAssertion = nil
        configuration = nil
    }

    private func failOpen(_ message: String) {
        restore()
        if errorMessage != message { logger.error("\(message, privacy: .public)") }
        errorMessage = message
        // Keep the icon and section toggles consistent with the restored bar.
        for section in appState?.menuBarManager.sections ?? [] where section.controlItem.state != .showSection {
            section.controlItem.state = .showSection
        }
    }
}

// MARK: - Notification Center bridge

// While an `MBAssessmentModeAssertion` is active, macOS 27 does not open Notification
// Center: clicking the clock and the "Show Notification Center" keyboard shortcut do
// nothing, whatever system items and bundles the configuration allows (the restriction
// comes from assessment mode itself). So the bridge holds those two gestures, releases
// the assertion, replays the gesture, and keeps the assertion released while the
// panel is open. Hidden items are visible during that time, then concealed again.
// The trackpad gesture cannot be intercepted and is not bridged.
extension NativeMenuBarManager {
    /// Marks events posted by the bridge so that its own tap lets them through.
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
        let mask = (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.leftMouseUp.rawValue)
            | (1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let manager = Unmanaged<NativeMenuBarManager>.fromOpaque(refcon).takeUnretainedValue()
            // The tap's source is on the main run loop, so this runs on the main thread.
            return MainActor.assumeIsolated {
                manager.handleNotificationCenterEvent(type: type, event: event)
            }
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
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
        notificationCenterTapSource = source
    }

    private func handleNotificationCenterEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let passThrough = Unmanaged.passUnretained(event)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = notificationCenterTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return passThrough
        }
        if event.getIntegerValueField(.eventSourceUserData) == Self.replayMarker {
            return passThrough
        }
        switch type {
        case .leftMouseUp:
            guard isSwallowingClockMouseUp else { return passThrough }
            isSwallowingClockMouseUp = false
            return nil
        case .leftMouseDown:
            guard isConcealing, !isSuspendedForNotificationCenter else { return passThrough }
            let location = event.location
            guard isInMenuBar(location), clockFrames().contains(where: { $0.contains(location) }) else {
                return passThrough
            }
            isSwallowingClockMouseUp = true
            suspendForNotificationCenter(replaying: .click(location))
            return nil
        case .keyDown:
            guard isConcealing, !isSuspendedForNotificationCenter,
                  event.getIntegerValueField(.keyboardEventAutorepeat) == 0,
                  let hotKey = notificationCenterHotKey() else {
                return passThrough
            }
            let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
            let relevant: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
            guard keyCode == hotKey.keyCode,
                  event.flags.intersection(relevant) == hotKey.flags.intersection(relevant) else {
                return passThrough
            }
            suspendForNotificationCenter(replaying: .key(keyCode, event.flags))
            return nil
        default:
            return passThrough
        }
    }

    /// True while an assertion is hiding (or about to hide) items.
    private var isConcealing: Bool {
        assertion != nil || pendingAssertion != nil
    }

    /// Cheap pre-check so the Accessibility lookup only runs for clicks in a menu bar.
    private func isInMenuBar(_ point: CGPoint) -> Bool {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return false }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displays, &count) == .success else { return false }
        return displays.prefix(Int(count)).contains { display in
            let bounds = CGDisplayBounds(display)
            return point.x >= bounds.minX && point.x < bounds.maxX
                && point.y >= bounds.minY && point.y < bounds.minY + 60
        }
    }

    private func clockFrames() -> [CGRect] {
        ICENativeMenuBarFrames(Self.clockIdentifier).map { NSRectToCGRect($0.rectValue) }
    }

    /// The user's "Show Notification Center" shortcut, if one is set and enabled.
    private func notificationCenterHotKey() -> (keyCode: CGKeyCode, flags: CGEventFlags)? {
        guard let hotKeys = UserDefaults(suiteName: "com.apple.symbolichotkeys")?
                .dictionary(forKey: "AppleSymbolicHotKeys"),
              let entry = hotKeys[Self.showNotificationCenterHotKey] as? [String: Any],
              (entry["enabled"] as? Bool) == true || (entry["enabled"] as? Int) == 1,
              let value = entry["value"] as? [String: Any],
              let parameters = value["parameters"] as? [Int], parameters.count == 3,
              parameters[1] != 65535 else {
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
            guard let self, !Task.isCancelled else { return }
            self.replay(gesture)
            await self.waitForNotificationCenterToClose()
            guard !Task.isCancelled else { return }
            self.isSuspendedForNotificationCenter = false
            self.synchronizeVisibility()
        }
    }

    private func replay(_ gesture: NotificationCenterGesture) {
        let source = CGEventSource(stateID: .hidSystemState)
        var events = [CGEvent?]()
        switch gesture {
        case .click(let point):
            events.append(CGEvent(mouseEventSource: source, mouseType: .leftMouseDown,
                                  mouseCursorPosition: point, mouseButton: .left))
            events.append(CGEvent(mouseEventSource: source, mouseType: .leftMouseUp,
                                  mouseCursorPosition: point, mouseButton: .left))
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
            if open { opened = true }
            if opened ? !open : ContinuousClock.now > deadline { return }
            try? await Task.sleep(for: .milliseconds(200))
        }
    }

    private func isNotificationCenterOpen() -> Bool {
        let pids = Set(NSRunningApplication
            .runningApplications(withBundleIdentifier: Self.notificationCenterBundle)
            .map(\.processIdentifier))
        guard !pids.isEmpty,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        // The panel is a large window above the normal levels; the desktop widgets
        // the same process keeps on screen sit at a negative level.
        return windows.contains { window in
            guard let pid = window[kCGWindowOwnerPID as String] as? pid_t, pids.contains(pid),
                  let layer = window[kCGWindowLayer as String] as? Int, layer > 0,
                  let bounds = window[kCGWindowBounds as String] as? [String: CGFloat] else {
                return false
            }
            return (bounds["Height"] ?? 0) > 200
        }
    }
}
