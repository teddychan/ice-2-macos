//
//  AppState.swift
//  Ice
//

import Combine
import OSLog
import SwiftUI

/// The model for app-wide state.
@MainActor
final class AppState: ObservableObject {
    /// Information for the active space.
    @Published private(set) var activeSpace = SpaceInfo.activeSpace()

    /// A Boolean value that indicates whether the user is dragging a menu bar item.
    @Published private(set) var isDraggingMenuBarItem = false

    /// Model for the app's settings.
    let settings = AppSettings()

    /// Model for the app's permissions.
    let permissions = AppPermissions()

    /// Model for app-wide navigation.
    let navigationState = AppNavigationState()

    /// Manager for the state of the menu bar.
    let menuBarManager = MenuBarManager()

    /// Manager for the menu bar's appearance.
    let appearanceManager = MenuBarAppearanceManager()

    /// Manager for menu bar item spacing.
    let spacingManager = MenuBarItemSpacingManager()

    /// Manager for individual menu bar spacer items.
    let spacerManager = MenuBarSpacerManager()

    /// Manager for menu bar items.
    let itemManager = MenuBarItemManager()

    /// Global cache for menu bar item images.
    let imageCache = MenuBarItemImageCache()

    /// Manager for input events received by the app.
    let hidEventManager = HIDEventManager()

    /// Manager for app updates.
    let updatesManager = UpdatesManager()

    /// Storage for internal observers.
    private var cancellables = Set<AnyCancellable>()

    /// Logger for the app state.
    private let logger = Logger(category: "AppState")

    /// Async setup actions, run once on first access.
    private lazy var setupTask = Task {
        settings.performSetup(with: self)
        menuBarManager.performSetup(with: self)

        if !NativeMenuBarManager.usesNativeBackend {
            await MenuBarItemService.Connection.shared.start()
        }

        spacerManager.performSetup(with: self)
        appearanceManager.performSetup(with: self)
        hidEventManager.performSetup(with: self)
        await itemManager.performSetup(with: self)
        imageCache.performSetup(with: self)
        updatesManager.performSetup(with: self)

        configureCancellables()
    }

    /// Performs app state setup.
    ///
    /// - Parameter hasPermissions: If `true`, continues with setup normally.
    ///   If `false`, prompts the user to grant permissions.
    func performSetup(hasPermissions: Bool) {
        if hasPermissions {
            Task {
                logger.debug("Setting up app state")
                await setupTask.value
                logger.debug("Finished setting up app state")
            }
        } else {
            Task {
                // Delay to prevent conflicts with the app delegate.
                try? await Task.sleep(for: .milliseconds(100))
                activate(withPolicy: .regular)
                dismissWindow(.settings) // Shouldn't be open anyway.
                openWindow(.permissions)
            }
        }
    }

    /// Relaunches the app from its current bundle location.
    ///
    /// The reopen cannot be handed to `NSWorkspace` before quitting. This process is
    /// still alive at that point, so LaunchServices activates *this* instance instead
    /// of starting a new one, reports success, and the terminate that follows then
    /// leaves nothing running at all — the app quits and never comes back.
    ///
    /// So the reopen goes to a detached `/bin/sh` that outlives this process: it waits
    /// for us to exit, then opens the bundle.
    func relaunch() {
        let process = Process()
        process.executableURL = URL(filePath: "/bin/sh")
        process.arguments = Self.relaunchHelperArguments(
            bundlePath: Bundle.main.bundleURL.path,
            pid: ProcessInfo.processInfo.processIdentifier
        )

        do {
            try process.run()
        } catch {
            // Nothing has been torn down yet, so staying up is the safe failure.
            logger.error("Failed to start relaunch helper - \(error.localizedDescription)")
            return
        }

        NSApp.terminate(nil)
    }

    /// Arguments for the detached `/bin/sh` that reopens the bundle at `bundlePath`
    /// once the process with `pid` has exited.
    ///
    /// `bundlePath` is passed as a positional argument rather than interpolated into
    /// the script, so a path containing spaces or quotes can't break out of it — and
    /// the debug build's path always contains one.
    ///
    /// `open -n` rather than plain `open`: more than one bundle can claim the same id
    /// (stale builds in other DerivedData folders do), and `-n` launches the bundle at
    /// this exact path instead of whichever one LaunchServices resolves the id to.
    static func relaunchHelperArguments(bundlePath: String, pid: Int32) -> [String] {
        [
            "-c",
            "while kill -0 \(pid) 2>/dev/null; do sleep 0.1; done; exec /usr/bin/open -n \"$1\"",
            "sh", // $0
            bundlePath, // $1
        ]
    }

    /// Configures the internal observers for the app state.
    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        // Listen for changes to the active space. We need handle some special
        // cases that NSWorkspace.shared.notificationCenter seems to miss.
        //
        // Special cases:
        //
        // * Changes to the frontmost application -- may indicate that a space
        //   on another display was made active.
        // * Left mouse down -- user may have clicked into a fullscreen space.
        //   To account for variations in system timing, we publish a value
        //   immediately upon receipt of the event, then publish another value
        //   after a delay.
        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
            .discardMerge(NSWorkspace.shared.publisher(for: \.frontmostApplication))
            .discardMerge(EventMonitor.publish(events: .leftMouseDown, scope: .universal).flatMap { _ in
                let initial = Just(())
                let delayed = initial.delay(for: 0.1, scheduler: DispatchQueue.main)
                return Publishers.Merge(initial, delayed)
            })
            .replace { Bridging.getActiveSpaceID() }
            .removeDuplicates()
            .sink { [weak self] spaceID in
                self?.activeSpace = SpaceInfo(spaceID: spaceID)
            }
            .store(in: &c)

        NSWorkspace.shared.publisher(for: \.frontmostApplication)
            .receive(on: DispatchQueue.main)
            .map { $0 == .current }
            .removeDuplicates()
            .sink { [weak self] isFrontmost in
                self?.navigationState.isAppFrontmost = isFrontmost
            }
            .store(in: &c)

        publisherForWindow(.settings)
            .removeNil()
            .flatMap { $0.publisher(for: \.isVisible) }
            .replaceEmpty(with: false)
            .throttle(for: 0.1, scheduler: DispatchQueue.main, latest: true)
            .removeDuplicates()
            .sink { [weak self] isPresented in
                self?.navigationState.isSettingsPresented = isPresented
            }
            .store(in: &c)

        hidEventManager.$isDraggingMenuBarItem
            .removeDuplicates()
            .sink { [weak self] isDragging in
                self?.isDraggingMenuBarItem = isDragging
            }
            .store(in: &c)

        Publishers.CombineLatest(
            navigationState.$isAppFrontmost,
            navigationState.$isSettingsPresented
        )
        .map { $0 && $1 }
        .throttle(for: 0.1, scheduler: DispatchQueue.main, latest: true)
        .merge(with: Just(true).delay(for: 1, scheduler: DispatchQueue.main))
        .sink { [weak self] shouldUpdate in
            guard let self, shouldUpdate else {
                return
            }
            Task {
                await self.imageCache.updateCacheWithoutChecks(sections: MenuBarSection.Name.allCases)
            }
        }
        .store(in: &c)

        menuBarManager.objectWillChange
            .sink { [weak self] in
                self?.objectWillChange.send()
            }
            .store(in: &c)
        permissions.objectWillChange
            .sink { [weak self] in
                self?.objectWillChange.send()
            }
            .store(in: &c)
        settings.objectWillChange
            .sink { [weak self] in
                self?.objectWillChange.send()
            }
            .store(in: &c)

        cancellables = c
    }

    /// Returns a Boolean value indicating whether the app has been
    /// granted the permission associated with the given key.
    func hasPermission(_ key: AppPermissions.PermissionKey) -> Bool {
        switch key {
        case .accessibility:
            permissions.accessibility.hasPermission
        case .screenRecording:
            permissions.screenRecording.hasPermission
        }
    }

    /// Returns a publisher for the window with the given identifier.
    func publisherForWindow(_ id: IceWindowIdentifier) -> some Publisher<NSWindow?, Never> {
        NSApp.publisher(for: \.windows).mergeMap { window in
            window.publisher(for: \.identifier)
                .map { [weak window] identifier in
                    guard identifier?.rawValue == id.rawValue else {
                        return nil
                    }
                    return window
                }
                .first { $0 != nil }
                .replaceEmpty(with: nil)
        }
    }

    /// Opens the window with the given identifier.
    func openWindow(_ id: IceWindowIdentifier) {
        // Async prevents conflicts with SwiftUI.
        DispatchQueue.main.async {
            self.logger.debug("Opening window with id: \(id, privacy: .public)")
            EnvironmentValues().openWindow(id: id)
        }
    }

    /// Dismisses the window with the given identifier.
    func dismissWindow(_ id: IceWindowIdentifier) {
        // Async prevents conflicts with SwiftUI.
        DispatchQueue.main.async {
            self.logger.debug("Dismissing window with id: \(id, privacy: .public)")
            EnvironmentValues().dismissWindow(id: id)
        }
    }

    /// Activates the app and sets its activation policy.
    func activate(withPolicy policy: NSApplication.ActivationPolicy? = nil) {
        if let policy {
            NSApp.setActivationPolicy(policy)
        }
        // NSApplication.activate(ignoringOtherApps:) is deprecated, with
        // no suitable alternative for explicit activation, so we activate
        // through NSRunningApplication.current for now.
        guard let frontmost = NSWorkspace.shared.frontmostApplication else {
            NSRunningApplication.current.activate()
            return
        }
        NSRunningApplication.current.activate(from: frontmost)
    }

    /// Deactivates the app and sets its activation policy.
    func deactivate(withPolicy policy: NSApplication.ActivationPolicy? = nil) {
        if let policy {
            NSApp.setActivationPolicy(policy)
        }
        NSApp.deactivate()
    }
}
