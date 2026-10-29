//
//  MenuBarItemManager.swift
//  Ice
//

import Cocoa
import Combine
import DragonKit
import OSLog
import Semaphore

/// Manager for menu bar items.
@MainActor
final class MenuBarItemManager: ObservableObject {
    /// The current cache of menu bar items.
    @Published private(set) var itemCache = ItemCache(displayID: nil)

    /// A Boolean value indicating whether an item cache attempt has completed.
    @Published private(set) var hasCompletedInitialCache = false

    /// Logger for the menu bar item manager.
    private nonisolated let logger = Logger.menuBarItemManager

    /// Semaphore to prevent overlapping event operations.
    private nonisolated let eventSemaphore = AsyncSemaphore(value: 1)

    /// Actor for managing menu bar item cache operations.
    private let cacheActor = CacheActor()

    /// Contexts for temporarily shown menu bar items.
    private var temporarilyShownItemContexts = [TemporarilyShownItemContext]()

    /// A timer for rehiding temporarily shown menu bar items.
    private var rehideTimer: Timer?

    /// Timestamp of the most recent menu bar item move operation.
    private var lastMoveOperationTimestamp: ContinuousClock.Instant?

    /// Cached timeouts for move operations.
    private var moveOperationTimeouts = [MenuBarItemTag: Duration]()

    /// A Boolean value that indicates whether a new item placement pass is
    /// currently running.
    ///
    /// The pass re-caches when it finishes, and caching runs the pass, so this
    /// is what stops the two from recurring into each other.
    private var isPlacingNewItems = false

    /// Storage for internal observers.
    private var cancellables = Set<AnyCancellable>()

    /// The shared app state.
    private(set) weak var appState: AppState?

    /// Sets up the manager.
    func performSetup(with appState: AppState) async {
        self.appState = appState
        if NativeMenuBarManager.usesNativeBackend {
            hasCompletedInitialCache = true
            return
        }
        await cacheItemsRegardless()
        configureCancellables(with: appState)
    }

    /// Configures the internal observers for the manager.
    private func configureCancellables(with appState: AppState) {
        var c = Set<AnyCancellable>()

        // Re-cache when the running apps change (an app launched or quit),
        // after a short delay to let the system settle.
        let runningAppsChanged = NSWorkspace.shared.publisher(for: \.runningApplications)
            .delay(for: 0.25, scheduler: DispatchQueue.main)
            .replace(with: ())

        // Re-cache immediately on the other events that commonly change the
        // menu bar item set but carry no dedicated add/remove notification.
        let spaceChanged = NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
            .replace(with: ())
        let screenParametersChanged = NotificationCenter.default
            .publisher(for: NSApplication.didChangeScreenParametersNotification)
            .replace(with: ())
        let frontmostAppChanged = NSWorkspace.shared.publisher(for: \.frontmostApplication)
            .replace(with: ())

        // Fallback poll for changes that emit no event at all, such as a
        // running app toggling its own status item. The event sources above
        // catch the common cases, so this can run infrequently.
        let fallbackPoll = Timer.publish(every: 30, on: .main, in: .default)
            .autoconnect()
            .replace(with: ())

        Publishers.Merge5(
            runningAppsChanged,
            spaceChanged,
            screenParametersChanged,
            frontmostAppChanged,
            fallbackPoll
        )
        .debounce(for: 1, scheduler: DispatchQueue.main)
        .sink { [weak self] in
            guard let self else {
                return
            }
            Task {
                await self.cacheItemsIfNeeded()
            }
        }
        .store(in: &c)

        appState.navigationState.$settingsNavigationIdentifier
            .sink { [weak self] identifier in
                guard let self, identifier == .rendersMenuBarItemImages else {
                    return
                }
                Task {
                    await self.cacheItemsRegardless()
                }
            }
            .store(in: &c)

        // New item placement is inert without screen recording permission, and
        // being granted it changes nothing the cache watches. Without this, a
        // user who grants the permission without relaunching gets no placement
        // until something else happens to change the menu bar item set — and if
        // the known-items registry is still absent, the next app to launch would
        // become the seed, recording that genuinely new icon as pre-existing.
        appState.permissions.screenRecording.$hasPermission
            .removeDuplicates()
            .dropFirst() // Only transitions; the initial value is handled by setup.
            .filter { $0 }
            .sink { [weak self] _ in
                guard let self else {
                    return
                }
                Task {
                    await self.cacheItemsRegardless()
                }
            }
            .store(in: &c)

        cancellables = c
    }

    /// Returns a Boolean value that indicates whether the most recent
    /// menu bar item move operation occurred within the given duration.
    func lastMoveOperationOccurred(within duration: Duration) -> Bool {
        guard let timestamp = lastMoveOperationTimestamp else {
            return false
        }
        return timestamp.duration(to: .now) <= duration
    }
}

// MARK: - Item Cache

extension MenuBarItemManager {
    /// An actor that manages menu bar item cache operations.
    private final actor CacheActor {
        /// Stored task for the current cache operation.
        private var cacheTask: Task<Void, Never>?

        /// A list of the menu bar item window identifiers at the time
        /// of the previous cache.
        private(set) var cachedItemWindowIDs = [CGWindowID]()

        /// Runs the given async closure as a task and waits for it to
        /// complete before returning.
        ///
        /// If a task from a previous call to this method is currently
        /// running, that task is cancelled and replaced.
        func runCacheTask(_ operation: @escaping () async -> Void) async {
            cacheTask.take()?.cancel()
            let task = Task(operation: operation)
            cacheTask = task
            await task.value
        }

        /// Updates the list of cached menu bar item window identifiers.
        func updateCachedItemWindowIDs(_ itemWindowIDs: [CGWindowID]) {
            cachedItemWindowIDs = itemWindowIDs
        }

        /// Clears the list of cached menu bar item window identifiers.
        func clearCachedItemWindowIDs() {
            cachedItemWindowIDs.removeAll()
        }
    }

    /// Cache for menu bar items.
    struct ItemCache: Hashable {
        /// Storage for cached menu bar items, keyed by section.
        private var storage = [MenuBarSection.Name: [MenuBarItem]]()

        /// The identifier of the display with the active menu bar at
        /// the time this cache was created.
        let displayID: CGDirectDisplayID?

        /// The cached menu bar items as an array.
        var managedItems: [MenuBarItem] {
            MenuBarSection.Name.allCases.reduce(into: []) { result, section in
                guard let items = storage[section] else {
                    return
                }
                result.append(contentsOf: items)
            }
        }

        /// Creates a cache with the given display identifier.
        init(displayID: CGDirectDisplayID?) {
            self.displayID = displayID
        }

        /// Returns the address for the menu bar item with the given identity,
        /// if it exists in the cache.
        func address(for item: MenuBarItem) -> (section: MenuBarSection.Name, index: Int)? {
            for (section, items) in storage {
                guard let index = items.firstIndex(where: { $0.windowID == item.windowID }) else {
                    continue
                }
                return (section, index)
            }
            return nil
        }

        /// Inserts the given menu bar item into the cache at the specified
        /// destination.
        mutating func insert(_ item: MenuBarItem, at destination: MoveDestination) {
            let targetTag = destination.targetItem.tag

            if targetTag == .hiddenControlItem {
                switch destination {
                case .leftOfItem:
                    self[.hidden].append(item)
                case .rightOfItem:
                    self[.visible].insert(item, at: 0)
                }
                return
            }

            if targetTag == .alwaysHiddenControlItem {
                switch destination {
                case .leftOfItem:
                    self[.alwaysHidden].append(item)
                case .rightOfItem:
                    self[.hidden].insert(item, at: 0)
                }
                return
            }

            guard case (let section, var index)? = address(for: destination.targetItem) else {
                return
            }

            if case .rightOfItem = destination {
                let range = self[section].startIndex...self[section].endIndex
                index = (index + 1).clamped(to: range)
            }

            self[section].insert(item, at: index)
        }

        /// Accesses the items in the given section.
        subscript(section: MenuBarSection.Name) -> [MenuBarItem] {
            get { storage[section, default: []] }
            set { storage[section] = newValue }
        }
    }

    /// A pair of control items, taken from a list of menu bar items
    /// during a menu bar item cache operation.
    private struct ControlItemPair {
        let hidden: MenuBarItem
        let alwaysHidden: MenuBarItem?

        init?(items: inout [MenuBarItem]) {
            guard let hidden = items.removeFirst(matching: .hiddenControlItem) else {
                return nil
            }
            self.hidden = hidden
            self.alwaysHidden = items.removeFirst(matching: .alwaysHiddenControlItem)
        }
    }

    /// Context maintained during a menu bar item cache operation.
    private struct CacheContext {
        let controlItems: ControlItemPair

        var cache: ItemCache
        var temporarilyShownItems = [(MenuBarItem, MoveDestination)]()
        var shouldClearCachedItemWindowIDs = false

        private(set) lazy var hiddenControlItemBounds = bestBounds(for: controlItems.hidden)
        private(set) lazy var alwaysHiddenControlItemBounds = controlItems.alwaysHidden.map(bestBounds)

        init(controlItems: ControlItemPair, displayID: CGDirectDisplayID?) {
            self.controlItems = controlItems
            self.cache = ItemCache(displayID: displayID)
        }

        func bestBounds(for item: MenuBarItem) -> CGRect {
            Bridging.getWindowBounds(for: item.windowID) ?? item.bounds
        }

        func isValidForCaching(_ item: MenuBarItem) -> Bool {
            if !item.canBeHidden {
                return false
            }
            if item.isSystemClone {
                return false
            }
            if item.isControlItem, item.tag != .visibleControlItem {
                return false
            }
            return true
        }

        mutating func findSection(for item: MenuBarItem) -> MenuBarSection.Name? {
            lazy var itemBounds = bestBounds(for: item)
            return MenuBarSection.Name.allCases.first { section in
                switch section {
                case .visible:
                    return itemBounds.minX >= hiddenControlItemBounds.maxX
                case .hidden:
                    if let alwaysHiddenControlItemBounds {
                        return itemBounds.maxX <= hiddenControlItemBounds.minX &&
                        itemBounds.minX >= alwaysHiddenControlItemBounds.maxX
                    } else {
                        return itemBounds.maxX <= hiddenControlItemBounds.minX
                    }
                case .alwaysHidden:
                    if let alwaysHiddenControlItemBounds {
                        return itemBounds.maxX <= alwaysHiddenControlItemBounds.minX
                    } else {
                        return false
                    }
                }
            }
        }
    }

    /// Caches the given menu bar items, without ensuring that the provided
    /// control items are correctly ordered.
    private func uncheckedCacheItems(
        items: [MenuBarItem],
        controlItems: ControlItemPair,
        displayID: CGDirectDisplayID?
    ) async {
        var context = CacheContext(controlItems: controlItems, displayID: displayID)

        for item in items where context.isValidForCaching(item) {
            if item.sourcePID == nil {
                logger.warning("Missing sourcePID for \(item.logString, privacy: .public)")
            }

            if let temp = temporarilyShownItemContexts.first(where: { $0.windowID == item.windowID }) {
                // Cache temporarily shown items as if they were in their original locations.
                // Keep track of them separately and use their return destinations to insert
                // them into the cache once all other items have been handled.
                context.temporarilyShownItems.append((item, temp.returnDestination))
                continue
            }

            if let section = context.findSection(for: item) {
                context.cache[section].append(item)
                continue
            }

            logger.warning("Couldn't find section for caching \(item.logString, privacy: .public)")
            context.shouldClearCachedItemWindowIDs = true
        }

        for (item, destination) in context.temporarilyShownItems {
            context.cache.insert(item, at: destination)
        }

        if context.shouldClearCachedItemWindowIDs {
            logger.info("Clearing cached menu bar item windowIDs")
            await cacheActor.clearCachedItemWindowIDs() // Ensure next cache isn't skipped.
        }

        guard itemCache != context.cache else {
            logger.debug("Not updating menu bar item cache, as items haven't changed")
            return
        }

        itemCache = context.cache
        logger.debug("Updated menu bar item cache")
    }

    /// Caches the current menu bar items, regardless of whether the
    /// items have changed since the previous cache.
    ///
    /// Before caching, this method ensures that the control items for
    /// the hidden and always-hidden sections are correctly ordered,
    /// arranging them into valid positions if needed.
    func cacheItemsRegardless(_ currentItemWindowIDs: [CGWindowID]? = nil) async {
        if NativeMenuBarManager.usesNativeBackend {
            await appState?.menuBarManager.nativeManager.refresh()
            hasCompletedInitialCache = true
            return
        }
        await cacheActor.runCacheTask { [weak self] in
            guard let self else {
                return
            }

            guard !lastMoveOperationOccurred(within: .seconds(1)) else {
                logger.debug("Skipping menu bar item cache due to recent item movement")
                return
            }

            let displayID = Bridging.getActiveMenuBarDisplayID()
            var items = await MenuBarItem.getMenuBarItems(option: .activeSpace)

            let itemWindowIDs = currentItemWindowIDs ?? items.reversed().map { $0.windowID }
            await cacheActor.updateCachedItemWindowIDs(itemWindowIDs)

            guard let controlItems = ControlItemPair(items: &items) else {
                // ???: Is clearing the cache the best thing to do here?
                logger.warning("Missing control item for hidden section, clearing menu bar item cache")
                itemCache = ItemCache(displayID: nil)
                hasCompletedInitialCache = true
                return
            }

            await enforceControlItemOrder(controlItems: controlItems)
            await uncheckedCacheItems(items: items, controlItems: controlItems, displayID: displayID)
            hasCompletedInitialCache = true
        }

        // Outside the cache task on purpose: the pass re-caches when it has moved
        // something, and `runCacheTask` cancels the previous task before starting
        // a new one, so a nested call would cancel the task it was called from.
        await placeNewItemsIfNeeded()
    }

    /// Caches the current menu bar items, if the items have changed
    /// since the previous cache.
    ///
    /// Before caching, this method ensures that the control items for
    /// the hidden and always-hidden sections are correctly ordered,
    /// arranging them into valid positions if needed.
    func cacheItemsIfNeeded() async {
        if NativeMenuBarManager.usesNativeBackend {
            await appState?.menuBarManager.nativeManager.refresh()
            return
        }
        let itemWindowIDs = Bridging.getMenuBarWindowList(option: [.itemsOnly, .activeSpace])
        if await cacheActor.cachedItemWindowIDs != itemWindowIDs {
            await cacheItemsRegardless(itemWindowIDs)
        }
    }

    /// Refreshes the item cache so it reflects the user's current menu bar
    /// layout, then returns.
    ///
    /// Moving items posts move events but does not itself update the cache;
    /// the cache is otherwise only refreshed by debounced system events, and
    /// `cacheItemsRegardless` intentionally skips for one second after a move.
    /// This method waits out that window (so the forced cache below is not
    /// skipped and reads settled item positions) and then forces a cache.
    ///
    /// Any caller that has just finished moving items must use this rather
    /// than `cacheItemsRegardless` directly, or its cache is guaranteed to be
    /// skipped: capturing a profile (so the snapshot reflects the latest
    /// arrangement) and applying one (so the layout bar reflects the moves it
    /// just performed).
    func refreshCacheAfterItemMoves() async {
        let sinceLastMove = lastMoveOperationTimestamp?.duration(to: .now)
        let delay = Self.cacheRefreshDelayAfterMoves(sinceLastMove: sinceLastMove)
        if delay > .zero {
            try? await Task.sleep(for: delay)
        }
        await cacheItemsRegardless()
    }

    /// Returns how long to wait before force-caching after item moves, given
    /// how long ago the most recent move operation occurred (`nil` if there
    /// has been no move).
    ///
    /// The wait ensures that, once elapsed, more than one second has passed
    /// since the last move, so the subsequent cache is not skipped by the
    /// post-move guard in `cacheItemsRegardless`. Returns zero when the last
    /// move is already old enough or never happened.
    nonisolated static func cacheRefreshDelayAfterMoves(sinceLastMove: Duration?) -> Duration {
        guard let sinceLastMove else {
            return .zero
        }
        // Slightly longer than the one-second post-move skip window so the
        // guard is guaranteed to have elapsed, not merely reached.
        let window = Duration.seconds(1) + .milliseconds(50)
        return max(window - sinceLastMove, .zero)
    }
}

// MARK: - Event Helpers

extension MenuBarItemManager {
    /// Allows event-tap callbacks and cancellation handlers to race without
    /// resuming the same checked continuation more than once.
    private final class EventContinuation {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Void, Error>?

        init(_ continuation: CheckedContinuation<Void, Error>) {
            self.continuation = continuation
        }

        func resume() {
            lock.lock()
            let continuation = continuation
            self.continuation = nil
            lock.unlock()

            continuation?.resume()
        }

        func resume(throwing error: Error) {
            lock.lock()
            let continuation = continuation
            self.continuation = nil
            lock.unlock()

            continuation?.resume(throwing: error)
        }
    }

    /// An error that can occur during menu bar item event operations.
    enum EventError: CustomStringConvertible, LocalizedError {
        /// A generic indication of a failure.
        case cannotComplete
        /// An event source cannot be created or is otherwise invalid.
        case invalidEventSource
        /// The location of the mouse cannot be found.
        case missingMouseLocation
        /// A failure during the creation of an event.
        case eventCreationFailure(MenuBarItem)
        /// A timeout during an event operation.
        case eventOperationTimeout(MenuBarItem)
        /// A menu bar item is not movable.
        case itemNotMovable(MenuBarItem)
        /// A timeout waiting for a menu bar item to respond to an event.
        case itemResponseTimeout(MenuBarItem)
        /// A menu bar item's bounds cannot be found.
        case missingItemBounds(MenuBarItem)

        var description: String {
            switch self {
            case .cannotComplete:
                "\(Self.self).cannotComplete"
            case .invalidEventSource:
                "\(Self.self).invalidEventSource"
            case .missingMouseLocation:
                "\(Self.self).missingMouseLocation"
            case .eventCreationFailure(let item):
                "\(Self.self).eventCreationFailure(item: \(item.tag))"
            case .eventOperationTimeout(let item):
                "\(Self.self).eventOperationTimeout(item: \(item.tag))"
            case .itemNotMovable(let item):
                "\(Self.self).itemNotMovable(item: \(item.tag))"
            case .itemResponseTimeout(let item):
                "\(Self.self).itemResponseTimeout(item: \(item.tag))"
            case .missingItemBounds(let item):
                "\(Self.self).missingItemBounds(item: \(item.tag))"
            }
        }

        var errorDescription: String? {
            switch self {
            case .cannotComplete:
                localizedErrorText("app.error.moveItem.cannotComplete")
            case .invalidEventSource:
                localizedErrorText("app.error.moveItem.invalidEventSource")
            case .missingMouseLocation:
                localizedErrorText("app.error.moveItem.missingMouseLocation")
            case .eventCreationFailure(let item):
                String(format: localizedErrorText("app.error.moveItem.eventCreationFailure"), item.displayName)
            case .eventOperationTimeout(let item):
                String(format: localizedErrorText("app.error.moveItem.eventOperationTimeout"), item.displayName)
            case .itemNotMovable(let item):
                String(format: localizedErrorText("app.error.moveItem.itemNotMovable"), item.displayName)
            case .itemResponseTimeout(let item):
                String(format: localizedErrorText("app.error.moveItem.itemResponseTimeout"), item.displayName)
            case .missingItemBounds(let item):
                String(format: localizedErrorText("app.error.moveItem.missingItemBounds"), item.displayName)
            }
        }

        var recoverySuggestion: String? {
            if case .itemNotMovable = self { return nil }
            return localizedErrorText("app.error.moveItem.tryAgain")
        }
    }

    /// Returns a Boolean value that indicates whether the user has
    /// paused input for at least the given duration.
    ///
    /// - Parameter duration: The duration that certain types of input
    ///   events must not have occured within in order to return `true`.
    private nonisolated func hasUserPausedInput(for duration: Duration) -> Bool {
        NSEvent.modifierFlags.isEmpty &&
        !MouseHelpers.lastMovementOccurred(within: duration) &&
        !MouseHelpers.lastScrollWheelOccurred(within: duration) &&
        !MouseHelpers.isButtonPressed()
    }

    /// Waits asynchronously for the user to pause input.
    private nonisolated func waitForUserToPauseInput() async throws {
        let waitTask = Task {
            while true {
                try Task.checkCancellation()
                if hasUserPausedInput(for: .milliseconds(50)) {
                    break
                }
                try await Task.sleep(for: .milliseconds(250))
            }
        }
        do {
            try await waitTask.value
        } catch {
            throw EventError.cannotComplete
        }
    }

    /// Waits between move operations for a dynamic amount of time,
    /// based on the timestamp of the last move operation.
    private nonisolated func waitForMoveOperationBuffer() async throws {
        if let timestamp = await lastMoveOperationTimestamp {
            let buffer = max(.milliseconds(25) - timestamp.duration(to: .now), .zero)
            logger.debug("Move operation buffer: \(buffer)")
            do {
                try await Task.sleep(for: buffer)
            } catch {
                throw EventError.cannotComplete
            }
        }
    }

    /// Waits for the given duration between event operations.
    ///
    /// Since most event operations must perform cleanup or otherwise
    /// run to completion, this method ignores task cancellation.
    private nonisolated func eventSleep(for duration: Duration = .milliseconds(25)) async {
        let task = Task {
            try? await Task.sleep(for: duration)
        }
        await task.value
    }

    /// Returns the current bounds for the given item.
    private nonisolated func getCurrentBounds(for item: MenuBarItem) async throws -> CGRect {
        let task = Task.detached(priority: .userInitiated) {
            guard let bounds = Bridging.getWindowBounds(for: item.windowID) else {
                throw EventError.missingItemBounds(item)
            }
            return bounds
        }
        return try await task.value
    }

    /// Returns the current mouse location.
    private nonisolated func getMouseLocation() throws -> CGPoint {
        guard let location = MouseHelpers.locationCoreGraphics else {
            throw EventError.missingMouseLocation
        }
        return location
    }

    /// Returns the process identifier that can be used to create
    /// and post a menu bar item event.
    private nonisolated func getEventPID(for item: MenuBarItem) -> pid_t {
        item.sourcePID ?? item.ownerPID
    }

    /// Returns an event source for a menu bar item event operation.
    private func getEventSource(
        with stateID: CGEventSourceStateID = .hidSystemState
    ) throws -> CGEventSource {
        enum Context {
            static var cache = [CGEventSourceStateID: CGEventSource]()
        }
        if let source = Context.cache[stateID] {
            return source
        }
        guard let source = CGEventSource(stateID: stateID) else {
            throw EventError.invalidEventSource
        }
        Context.cache[stateID] = source
        return source
    }

    /// Prevents local events from being suppressed.
    private func permitLocalEvents() throws {
        let source = try getEventSource(with: .combinedSessionState)
        let states: [CGEventSuppressionState] = [
            .eventSuppressionStateRemoteMouseDrag,
            .eventSuppressionStateSuppressionInterval,
        ]
        for state in states {
            source.setLocalEventsFilterDuringSuppressionState(.permitAllEvents, state: state)
        }
        source.localEventsSuppressionInterval = 0
    }

    /// Posts an event to the given menu bar item and waits until
    /// it is received before returning.
    ///
    /// - Parameters:
    ///   - event: The event to post.
    ///   - item: The menu bar item that the event targets.
    ///   - timeout: The base duration to wait before throwing an error.
    ///     The value of this parameter is multiplied by `count` to
    ///     produce the actual timeout duration.
    ///   - count: The number of times to repeat the operation. As it
    ///     is considerably more efficient, prefer increasing this value
    ///     over repeatedly calling `postEventWithBarrier`.
    private nonisolated func postEventWithBarrier(
        _ event: CGEvent,
        to item: MenuBarItem,
        timeout: Duration,
        repeating count: Int = 1
    ) async throws {
        MouseHelpers.hideCursor()
        defer {
            MouseHelpers.showCursor()
        }

        guard
            let entryEvent = CGEvent.uniqueNullEvent(),
            let exitEvent = CGEvent.uniqueNullEvent()
        else {
            throw EventError.eventCreationFailure(item)
        }

        let pid = getEventPID(for: item)
        event.setTargetPID(pid)

        let firstLocation = EventTap.Location.pid(pid)
        let secondLocation = EventTap.Location.sessionEventTap

        var count = count
        var eventTaps = [EventTap]()

        let timeoutTask = Task(timeout: timeout * count) {
            try await withCheckedThrowingContinuation { continuation in
                let resumer = EventContinuation(continuation)
                // Listen for the following events at the first location
                // and perform the following actions:
                //
                // - Entry event: Decrement the count and post the real
                //   event to the second location (handled in EventTap 2).
                // - Exit event: Resume the continuation.
                //
                // These events serve as start (or continue) and stop
                // signals, and are discarded.
                let eventTap1 = EventTap(
                    label: "EventTap 1",
                    type: .null,
                    location: firstLocation,
                    placement: .headInsertEventTap,
                    option: .defaultTap
                ) { tap, rEvent in
                    if rEvent.matches(entryEvent, byIntegerFields: [.eventSourceUserData]) {
                        count -= 1
                        event.post(to: secondLocation)
                        return nil
                    }
                    if rEvent.matches(exitEvent, byIntegerFields: [.eventSourceUserData]) {
                        tap.disable()
                        resumer.resume()
                        return nil
                    }
                    return rEvent
                }

                // Listen for the real event at the second location and,
                // depending on the count, post either the entry or exit
                // event to the first location (handled in EventTap 1).
                let eventTap2 = EventTap(
                    label: "EventTap 2",
                    type: event.type,
                    location: secondLocation,
                    placement: .tailAppendEventTap,
                    option: .listenOnly
                ) { tap, rEvent in
                    guard rEvent.matches(event, byIntegerFields: CGEventField.menuBarItemEventFields) else {
                        return rEvent
                    }
                    if count <= 0 {
                        tap.disable()
                        exitEvent.post(to: firstLocation)
                    } else {
                        entryEvent.post(to: firstLocation)
                    }
                    rEvent.setTargetPID(pid)
                    return rEvent
                }

                // Keep the taps alive.
                eventTaps.append(eventTap1)
                eventTaps.append(eventTap2)

                Task {
                    await withTaskCancellationHandler {
                        eventTap1.enable()
                        eventTap2.enable()
                        entryEvent.post(to: firstLocation)
                    } onCancel: {
                        eventTap1.disable()
                        eventTap2.disable()
                        resumer.resume(throwing: CancellationError())
                    }
                }
            }
        }
        do {
            try await timeoutTask.value
        } catch is TaskTimeoutError {
            throw EventError.eventOperationTimeout(item)
        } catch {
            throw EventError.cannotComplete
        }
    }

    /// Casts forbidden magic to make a menu bar item receive and
    /// respond to an event during a move operation.
    ///
    /// - Parameters:
    ///   - event: The event to post.
    ///   - item: The menu bar item that the event targets.
    ///   - timeout: The base duration to wait before throwing an error.
    ///     The value of this parameter is multiplied by `count` to
    ///     produce the actual timeout duration.
    ///   - count: The number of times to repeat the operation. As it
    ///     is considerably more efficient, prefer increasing this value
    ///     over repeatedly calling `scrombleEvent`.
    private nonisolated func scrombleEvent(
        _ event: CGEvent,
        item: MenuBarItem,
        timeout: Duration,
        repeating count: Int = 1
    ) async throws {
        MouseHelpers.hideCursor()
        defer {
            MouseHelpers.showCursor()
        }

        guard
            let entryEvent = CGEvent.uniqueNullEvent(),
            let exitEvent = CGEvent.uniqueNullEvent()
        else {
            throw EventError.eventCreationFailure(item)
        }

        let pid = getEventPID(for: item)
        event.setTargetPID(pid)

        let firstLocation = EventTap.Location.pid(pid)
        let secondLocation = EventTap.Location.sessionEventTap

        var count = count
        var eventTaps = [EventTap]()

        let timeoutTask = Task(timeout: timeout * count) {
            try await withCheckedThrowingContinuation { continuation in
                let resumer = EventContinuation(continuation)
                // Listen for the following events at the first location
                // and perform the following actions:
                //
                // - Entry event: Decrement the count and post the real
                //   event to the second location (handled in EventTap 2).
                // - Exit event: Resume the continuation.
                //
                // These events serve as start (or continue) and stop
                // signals, and are discarded.
                let eventTap1 = EventTap(
                    label: "EventTap 1",
                    type: .null,
                    location: firstLocation,
                    placement: .headInsertEventTap,
                    option: .defaultTap
                ) { tap, rEvent in
                    if rEvent.matches(entryEvent, byIntegerFields: [.eventSourceUserData]) {
                        count -= 1
                        event.post(to: secondLocation)
                        return nil
                    }
                    if rEvent.matches(exitEvent, byIntegerFields: [.eventSourceUserData]) {
                        tap.disable()
                        resumer.resume()
                        return nil
                    }
                    return rEvent
                }

                // Listen for the real event at the second location and
                // post the real event to the first location (handled in
                // EventTap 3).
                let eventTap2 = EventTap(
                    label: "EventTap 2",
                    type: event.type,
                    location: secondLocation,
                    placement: .tailAppendEventTap,
                    option: .listenOnly
                ) { tap, rEvent in
                    guard rEvent.matches(event, byIntegerFields: CGEventField.menuBarItemEventFields) else {
                        return rEvent
                    }
                    if count <= 0 {
                        tap.disable()
                    }
                    event.post(to: firstLocation)
                    rEvent.setTargetPID(pid)
                    return rEvent
                }

                // Listen for the real event at the first location and,
                // depending on the count, post either the entry or exit
                // event to the first location (handled in EventTap 1).
                let eventTap3 = EventTap(
                    label: "EventTap 3",
                    type: event.type,
                    location: firstLocation,
                    placement: .headInsertEventTap,
                    option: .listenOnly
                ) { tap, rEvent in
                    guard rEvent.matches(event, byIntegerFields: CGEventField.menuBarItemEventFields) else {
                        return rEvent
                    }
                    if count <= 0 {
                        tap.disable()
                        exitEvent.post(to: firstLocation)
                    } else {
                        entryEvent.post(to: firstLocation)
                    }
                    rEvent.setTargetPID(pid)
                    return rEvent
                }

                // Keep the taps alive.
                eventTaps.append(eventTap1)
                eventTaps.append(eventTap2)
                eventTaps.append(eventTap3)

                Task {
                    await withTaskCancellationHandler {
                        eventTap1.enable()
                        eventTap2.enable()
                        eventTap3.enable()
                        entryEvent.post(to: firstLocation)
                    } onCancel: {
                        eventTap1.disable()
                        eventTap2.disable()
                        eventTap3.disable()
                        resumer.resume(throwing: CancellationError())
                    }
                }
            }
        }
        do {
            try await timeoutTask.value
        } catch is TaskTimeoutError {
            throw EventError.eventOperationTimeout(item)
        } catch {
            throw EventError.cannotComplete
        }
    }
}

// MARK: - Moving Items

extension MenuBarItemManager {
    /// Destinations for menu bar item move operations.
    enum MoveDestination {
        /// The destination to the left of the given target item.
        case leftOfItem(MenuBarItem)
        /// The destination to the right of the given target item.
        case rightOfItem(MenuBarItem)

        /// The destination's target item.
        var targetItem: MenuBarItem {
            switch self {
            case .leftOfItem(let item), .rightOfItem(let item): item
            }
        }

        /// A string to use for logging purposes.
        var logString: String {
            switch self {
            case .leftOfItem(let item): "left of \(item.logString)"
            case .rightOfItem(let item): "right of \(item.logString)"
            }
        }
    }

    /// Returns the default timeout for move operations associated
    /// with the given item.
    private func getDefaultMoveOperationTimeout(for item: MenuBarItem) -> Duration {
        if item.isBentoBox {
            // Bento Boxes (i.e. Control Center groups) generally
            // take a little longer to respond.
            return .milliseconds(150)
        }
        return .milliseconds(100)
    }

    /// Returns the cached timeout for move operations associated
    /// with the given item.
    private func getMoveOperationTimeout(for item: MenuBarItem) -> Duration {
        if let timeout = moveOperationTimeouts[item.tag] {
            return timeout
        }
        return getDefaultMoveOperationTimeout(for: item)
    }

    /// Updates the cached timeout for move operations associated
    /// with the given item.
    private func updateMoveOperationTimeout(_ timeout: Duration, for item: MenuBarItem) {
        let current = getMoveOperationTimeout(for: item)
        let average = (timeout + current) / 2
        let clamped = average.clamped(min: .milliseconds(50), max: .milliseconds(300))
        moveOperationTimeouts[item.tag] = clamped
    }

    /// Returns the target points for creating the events needed to
    /// move a menu bar item to the given destination.
    private nonisolated func getTargetPoints(
        forMoving item: MenuBarItem,
        to destination: MoveDestination
    ) async throws -> (start: CGPoint, end: CGPoint) {
        let itemBounds = try await getCurrentBounds(for: item)
        let targetBounds = try await getCurrentBounds(for: destination.targetItem)
        switch destination {
        case .leftOfItem:
            var start = CGPoint(x: targetBounds.minX, y: targetBounds.minY)
            var end = start
            if itemBounds.maxX <= targetBounds.minX {
                // Direction of movement: ->
                end.x -= itemBounds.width
            } else {
                // Direction of movement: <-
                start.x -= 1
            }
            return (start, end)
        case .rightOfItem:
            var start = CGPoint(x: targetBounds.maxX, y: targetBounds.minY)
            var end = start
            if itemBounds.minX <= targetBounds.maxX {
                // Direction of movement: ->
                end.x -= itemBounds.width
            } else {
                // Direction of movement: <-
                start.x += 1
            }
            return (start, end)
        }
    }

    /// Returns a Boolean value that indicates whether the given menu bar
    /// item has the correct position, relative to the given destination.
    private nonisolated func itemHasCorrectPosition(
        item: MenuBarItem,
        for destination: MoveDestination
    ) async throws -> Bool {
        let itemBounds = try await getCurrentBounds(for: item)
        let targetBounds = try await getCurrentBounds(for: destination.targetItem)
        let tolerance: CGFloat = 1
        return switch destination {
        case .leftOfItem: abs(itemBounds.maxX - targetBounds.minX) <= tolerance
        case .rightOfItem: abs(itemBounds.minX - targetBounds.maxX) <= tolerance
        }
    }

    /// Waits for a menu bar item to respond to a series of previously
    /// posted move events.
    ///
    /// - Parameters:
    ///   - item: The item to check for a response.
    ///   - initialOrigin: The origin of the item before the events were posted.
    ///   - timeout: The duration to wait before throwing an error.
    private nonisolated func waitForMoveEventResponse(
        from item: MenuBarItem,
        initialOrigin: CGPoint,
        timeout: Duration
    ) async throws -> CGPoint {
        MouseHelpers.hideCursor()
        defer {
            MouseHelpers.showCursor()
        }
        let responseTask = Task.detached {
            while true {
                try Task.checkCancellation()
                let origin = try await self.getCurrentBounds(for: item).origin
                if origin != initialOrigin {
                    return origin
                }
                try await Task.sleep(for: .milliseconds(5))
            }
        }
        let timeoutTask = Task(timeout: timeout) {
            try await withTaskCancellationHandler {
                try await responseTask.value
            } onCancel: {
                responseTask.cancel()
            }
        }
        do {
            let origin = try await timeoutTask.value
            logger.debug(
                """
                Item responded to events with new origin: \
                \(String(describing: origin), privacy: .public)
                """
            )
            return origin
        } catch let error as EventError {
            throw error
        } catch is TaskTimeoutError {
            throw EventError.itemResponseTimeout(item)
        } catch {
            throw EventError.cannotComplete
        }
    }

    /// Creates and posts a series of events to move a menu bar item
    /// to the given destination.
    ///
    /// - Parameters:
    ///   - item: The menu bar item to move.
    ///   - destination: The destination to move the menu bar item.
    private func postMoveEvents(item: MenuBarItem, destination: MoveDestination) async throws {
        try await eventSemaphore.waitUnlessCancelled()
        defer {
            eventSemaphore.signal()
        }

        var itemOrigin = try await getCurrentBounds(for: item).origin
        let targetPoints = try await getTargetPoints(forMoving: item, to: destination)
        let mouseLocation = try getMouseLocation()
        let source = try getEventSource()

        try permitLocalEvents()

        guard
            let mouseDown = CGEvent.menuBarItemEvent(
                item: item,
                source: source,
                type: .move(.mouseDown),
                location: targetPoints.start
            ),
            let mouseUp = CGEvent.menuBarItemEvent(
                item: destination.targetItem,
                source: source,
                type: .move(.mouseUp),
                location: targetPoints.end
            )
        else {
            throw EventError.eventCreationFailure(item)
        }

        var timeout = getMoveOperationTimeout(for: item)
        logger.debug("Move operation timeout: \(timeout)")

        lastMoveOperationTimestamp = .now
        MouseHelpers.hideCursor()
        defer {
            MouseHelpers.warpCursor(to: mouseLocation)
            MouseHelpers.showCursor()
            lastMoveOperationTimestamp = .now
            updateMoveOperationTimeout(timeout, for: item)
        }

        do {
            try await scrombleEvent(
                mouseDown,
                item: item,
                timeout: timeout
            )
            itemOrigin = try await waitForMoveEventResponse(
                from: item,
                initialOrigin: itemOrigin,
                timeout: timeout
            )
            try await scrombleEvent(
                mouseUp,
                item: item,
                timeout: timeout,
                repeating: 2 // Double mouse up prevents invalid item state.
            )
            itemOrigin = try await waitForMoveEventResponse(
                from: item,
                initialOrigin: itemOrigin,
                timeout: timeout
            )
            timeout -= timeout / 4
        } catch {
            do {
                logger.warning("Move events failed, posting fallback")
                try await scrombleEvent(
                    mouseUp,
                    item: item,
                    timeout: .milliseconds(100), // Fixed timeout for fallback.
                    repeating: 2 // Double mouse up prevents invalid item state.
                )
            } catch {
                // Catch this for logging purposes only. We want to propagate
                // the original error.
                logger.error("Fallback failed with error: \(error, privacy: .public)")
            }
            timeout += timeout / 2
            throw error
        }
    }

    /// Moves a menu bar item to the given destination.
    ///
    /// - Parameters:
    ///   - item: The menu bar item to move.
    ///   - destination: The destination to move the item to.
    func move(item: MenuBarItem, to destination: MoveDestination) async throws {
        guard item.isMovable else {
            throw EventError.itemNotMovable(item)
        }
        guard let appState else {
            throw EventError.cannotComplete
        }

        try await waitForUserToPauseInput()

        appState.hidEventManager.stopAll()
        defer {
            appState.hidEventManager.startAll()
        }

        try await waitForMoveOperationBuffer()

        logger.log(
            """
            Moving \(item.logString, privacy: .public) to \
            \(destination.logString, privacy: .public)
            """
        )

        guard try await !itemHasCorrectPosition(item: item, for: destination) else {
            logger.debug("Item has correct position, cancelling move")
            return
        }

        MouseHelpers.hideCursor()
        defer {
            MouseHelpers.showCursor()
        }

        let maxAttempts = 8
        for n in 1...maxAttempts {
            guard !Task.isCancelled else {
                throw EventError.cannotComplete
            }
            do {
                if try await itemHasCorrectPosition(item: item, for: destination) {
                    logger.debug("Item has correct position, finished with move")
                    return
                }
                try await postMoveEvents(item: item, destination: destination)
                logger.debug("Attempt \(n, privacy: .public) succeeded, finished with move")
                return
            } catch {
                logger.debug("Attempt \(n, privacy: .public) failed: \(error, privacy: .public)")
                if n < maxAttempts {
                    try await waitForMoveOperationBuffer()
                    continue
                }
                if error is EventError {
                    throw error
                }
                throw EventError.cannotComplete
            }
        }
    }
}

// MARK: - Clicking Items

extension MenuBarItemManager {
    /// Returns the equivalent event subtypes for clicking a menu bar
    /// item with the given mouse button.
    private nonisolated func getClickSubtypes(
        for mouseButton: CGMouseButton
    ) -> (down: MenuBarItemEventType.ClickSubtype, up: MenuBarItemEventType.ClickSubtype) {
        switch mouseButton {
        case .left: (.leftMouseDown, .leftMouseUp)
        case .right: (.rightMouseDown, .rightMouseUp)
        default: (.otherMouseDown, .otherMouseUp)
        }
    }

    /// Creates and posts a series of events to click a menu bar item.
    ///
    /// - Parameters:
    ///   - item: The menu bar item to click.
    ///   - mouseButton: The mouse button to click the item with.
    private func postClickEvents(item: MenuBarItem, mouseButton: CGMouseButton) async throws {
        try await eventSemaphore.waitUnlessCancelled()
        defer {
            eventSemaphore.signal()
        }

        let clickPoint = try await getCurrentBounds(for: item).center
        let mouseLocation = try getMouseLocation()
        let source = try getEventSource()

        try permitLocalEvents()

        let clickTypes = getClickSubtypes(for: mouseButton)
        let timeout = Duration.milliseconds(250)

        guard
            let mouseDown = CGEvent.menuBarItemEvent(
                item: item,
                source: source,
                type: .click(clickTypes.down),
                location: clickPoint
            ),
            let mouseUp = CGEvent.menuBarItemEvent(
                item: item,
                source: source,
                type: .click(clickTypes.up),
                location: clickPoint
            )
        else {
            throw EventError.eventCreationFailure(item)
        }

        MouseHelpers.hideCursor()
        defer {
            MouseHelpers.warpCursor(to: mouseLocation)
            MouseHelpers.showCursor()
        }

        do {
            try await postEventWithBarrier(
                mouseDown,
                to: item,
                timeout: timeout
            )
            try await postEventWithBarrier(
                mouseUp,
                to: item,
                timeout: timeout,
                repeating: 2 // Double mouse up prevents invalid item state.
            )
        } catch {
            do {
                logger.warning("Click events failed, posting fallback")
                try await postEventWithBarrier(
                    mouseUp,
                    to: item,
                    timeout: timeout,
                    repeating: 2 // Double mouse up prevents invalid item state.
                )
            } catch {
                // Catch this for logging purposes only. We want to propagate
                // the original error.
                logger.error("Fallback failed with error: \(error, privacy: .public)")
            }
            throw error
        }
    }

    /// Clicks a menu bar item with the given mouse button.
    ///
    /// - Parameters:
    ///   - item: The menu bar item to click.
    ///   - mouseButton: The mouse button to click the item with.
    func click(item: MenuBarItem, with mouseButton: CGMouseButton) async throws {
        guard let appState else {
            throw EventError.cannotComplete
        }

        try await waitForUserToPauseInput()

        logger.log(
            """
            Clicking \(item.logString, privacy: .public) with \
            \(mouseButton.logString, privacy: .public)
            """
        )

        appState.hidEventManager.stopAll()
        defer {
            appState.hidEventManager.startAll()
        }

        let maxAttempts = 4
        for n in 1...maxAttempts {
            guard !Task.isCancelled else {
                throw EventError.cannotComplete
            }
            do {
                try await postClickEvents(item: item, mouseButton: mouseButton)
                logger.debug("Attempt \(n, privacy: .public) succeeded, finished with click")
                return
            } catch {
                logger.debug("Attempt \(n, privacy: .public) failed: \(error, privacy: .public)")
                if n < maxAttempts {
                    await eventSleep()
                    continue
                }
                if error is EventError {
                    throw error
                }
                throw EventError.cannotComplete
            }
        }
    }
}

// MARK: - Layout Profiles

extension MenuBarItemManager {
    /// Applies a saved menu bar layout profile to the current menu bar items.
    ///
    /// Profiles are intentionally matched by ``MenuBarItemTag`` and applied
    /// through normal move operations. Items that are not currently available
    /// are skipped so profiles remain useful when apps are not running.
    func applyLayoutProfile(_ profile: MenuBarLayoutProfile) async throws {
        // The cache read below decides which items get moved where, so it has to
        // be current. `cacheItemsRegardless` would be skipped if the user had
        // just dragged something in the layout bar and hit Apply within a second
        // of it, and the profile would then be applied against a stale layout.
        await refreshCacheAfterItemMoves()

        let items = await MenuBarItem.getMenuBarItems(option: .activeSpace)
        guard let hiddenControlItem = items.first(matching: .hiddenControlItem) else {
            throw EventError.cannotComplete
        }

        let alwaysHiddenControlItem = items.first(matching: .alwaysHiddenControlItem)
        var availableItems = itemCache.managedItems

        func takeItem(matching tag: MenuBarItemTag) -> MenuBarItem? {
            guard let index = availableItems.firstIndex(matching: tag) else {
                return nil
            }
            return availableItems.remove(at: index)
        }

        let visibleItems = profile.itemTags(for: .visible).compactMap(takeItem)
        try await applyVisibleLayout(visibleItems, hiddenControlItem: hiddenControlItem)

        let hiddenItems = profile.itemTags(for: .hidden).compactMap(takeItem)
        try await applyHiddenLayout(hiddenItems, controlItem: hiddenControlItem)

        if let alwaysHiddenControlItem {
            let alwaysHiddenItems = profile.itemTags(for: .alwaysHidden).compactMap(takeItem)
            try await applyHiddenLayout(alwaysHiddenItems, controlItem: alwaysHiddenControlItem)
        }

        // Not `cacheItemsRegardless`: the moves above finished microseconds ago,
        // so its post-move guard skips every time and the layout bar keeps
        // showing the pre-apply arrangement until an unrelated event happens to
        // trigger a cache — up to the 30s fallback poll.
        await refreshCacheAfterItemMoves()
    }

    private func applyVisibleLayout(
        _ items: [MenuBarItem],
        hiddenControlItem: MenuBarItem
    ) async throws {
        var previousItem = hiddenControlItem
        for item in items where item.isMovable && !item.isSpacerItem {
            try await move(item: item, to: .rightOfItem(previousItem))
            previousItem = item
        }
    }

    private func applyHiddenLayout(
        _ items: [MenuBarItem],
        controlItem: MenuBarItem
    ) async throws {
        var nextItem = controlItem
        for item in items.reversed() where item.isMovable && !item.isSpacerItem {
            try await move(item: item, to: .leftOfItem(nextItem))
            nextItem = item
        }
    }
}

// MARK: - Temporarily Showing Items

extension MenuBarItemManager {
    /// Context for a temporarily shown menu bar item.
    private final class TemporarilyShownItemContext {
        /// The tag associated with the item.
        let tag: MenuBarItemTag

        /// The window identifier associated with the item.
        let windowID: CGWindowID

        /// The destination to return the item to.
        let returnDestination: MoveDestination

        /// The window of the item's shown interface.
        var shownInterfaceWindow: WindowInfo?

        /// The number of attempts that have been made to rehide the item.
        var rehideAttempts = 0

        /// A Boolean value that indicates whether the menu bar item's
        /// interface is showing.
        var isShowingInterface: Bool {
            guard
                let window = shownInterfaceWindow,
                let current = WindowInfo(windowID: window.windowID)
            else {
                // Window no longer exists, so assume closed.
                return false
            }
            if
                current.layer != CGWindowLevelForKey(.popUpMenuWindow),
                current.layer != CGWindowLevelForKey(.popUpMenuWindow) - 1,
                current.layer != CGWindowLevelForKey(.statusWindow),
                current.layer != CGWindowLevelForKey(.mainMenuWindow),
                let app = current.owningApplication
            {
                return app.isActive && current.isOnScreen
            }
            return current.isOnScreen
        }

        init(item: MenuBarItem, returnDestination: MoveDestination) {
            self.tag = item.tag
            self.windowID = item.windowID
            self.returnDestination = returnDestination
        }
    }

    /// Gets the destination to return the given item to after it is
    /// temporarily shown.
    private func getReturnDestination(for item: MenuBarItem, in items: [MenuBarItem]) -> MoveDestination? {
        guard let index = items.firstIndex(where: { $0.windowID == item.windowID }) else {
            return nil
        }
        if items.indices.contains(index + 1) {
            return .leftOfItem(items[index + 1])
        }
        if items.indices.contains(index - 1) {
            return .rightOfItem(items[index - 1])
        }
        return nil
    }

    /// Schedules a timer for the given interval that rehides the
    /// temporarily shown items when fired.
    private func runRehideTimer(for interval: TimeInterval? = nil) {
        guard let appState else {
            return
        }
        let interval = interval ?? appState.settings.advanced.tempShowInterval
        logger.debug("Running rehide timer for interval: \(interval, format: .fixed, privacy: .public)")
        rehideTimer?.invalidate()
        rehideTimer = .scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            logger.debug("Rehide timer fired")
            Task {
                await self.rehideTemporarilyShownItems()
            }
        }
    }

    /// Temporarily shows the given item.
    ///
    /// The item is cached and returned to its original location after the
    /// time interval specified by ``AdvancedSettings/tempShowInterval``.
    ///
    /// - Parameters:
    ///   - item: The item to temporarily show.
    ///   - mouseButton: The mouse button to click the item with.
    func temporarilyShow(item: MenuBarItem, clickingWith mouseButton: CGMouseButton) async {
        guard let appState else {
            logger.error("Missing AppState, so not showing \(item.logString, privacy: .public)")
            return
        }
        guard let screen = NSScreen.screenWithActiveMenuBar else {
            logger.error("No active menu bar screen, so not showing \(item.logString, privacy: .public)")
            return
        }

        guard let applicationMenuFrame = screen.getApplicationMenuFrame() else {
            logger.error("No application menu frame, so not showing \(item.logString, privacy: .public)")
            return
        }

        var items = await MenuBarItem.getMenuBarItems(option: .activeSpace)

        guard let destination = getReturnDestination(for: item, in: items) else {
            logger.error("No return destination for \(item.logString, privacy: .public)")
            return
        }

        // Remove all items up to and including the hidden control item.
        if let index = items.firstIndex(matching: .hiddenControlItem) {
            items.removeSubrange(...index)
        }

        let maxX: CGFloat = {
            var maxX = applicationMenuFrame.maxX
            if let frameOfNotch = screen.frameOfNotch {
                maxX = max(maxX, frameOfNotch.maxX + 30)
            }
            return maxX + item.bounds.width
        }()

        // Remove items until we have enough room to show this item.
        items.trimPrefix { item in
            if item.isOnScreen && item.canBeHidden {
                return item.bounds.minX <= maxX
            }
            return true
        }

        guard let targetItem = items.first else {
            logger.warning("Not enough room to show \(item.logString, privacy: .public)")
            let alert = NSAlert()
            alert.messageText = String(
                format: L("app.layout.alert.notEnoughRoom.title"),
                item.displayName
            )
            alert.runModal()
            return
        }

        appState.hidEventManager.stopAll()
        defer {
            appState.hidEventManager.startAll()
        }

        logger.debug("Temporarily showing \(item.logString, privacy: .public)")

        do {
            try await move(item: item, to: .leftOfItem(targetItem))
        } catch {
            logger.error("Error showing item: \(error, privacy: .public)")
            return
        }

        let context = TemporarilyShownItemContext(item: item, returnDestination: destination)
        temporarilyShownItemContexts.append(context)

        rehideTimer?.invalidate()
        defer {
            runRehideTimer()
        }

        await eventSleep(for: .milliseconds(100))
        let idsBeforeClick = Set(Bridging.getWindowList(option: .onScreen))

        do {
            try await click(item: item, with: mouseButton)
        } catch {
            logger.error("Error clicking item: \(error, privacy: .public)")
            return
        }

        await eventSleep(for: .milliseconds(250))
        let windowsAfterClick = WindowInfo.createWindows(option: .onScreen)
        let interfaceOwnerPID = item.sourcePID ?? item.ownerPID

        context.shownInterfaceWindow = windowsAfterClick.first { window in
            window.ownerPID == interfaceOwnerPID && !idsBeforeClick.contains(window.windowID)
        }
    }

    /// Rehides all temporarily shown items.
    ///
    /// If an item is currently showing its interface, this method waits
    /// for the interface to close before hiding the items.
    func rehideTemporarilyShownItems() async {
        guard let appState else {
            logger.error("Missing AppState, so not rehiding")
            return
        }
        guard !temporarilyShownItemContexts.isEmpty else {
            return
        }
        guard !temporarilyShownItemContexts.contains(where: { $0.isShowingInterface }) else {
            logger.debug("Menu bar item interface is shown, so waiting to rehide")
            runRehideTimer(for: 3)
            return
        }
        guard hasUserPausedInput(for: .milliseconds(250)) else {
            logger.debug("Found recent user input, so waiting to rehide")
            runRehideTimer(for: 1)
            return
        }

        var currentContexts = temporarilyShownItemContexts
        temporarilyShownItemContexts.removeAll()

        let items = await MenuBarItem.getMenuBarItems(option: .activeSpace)
        var failedContexts = [TemporarilyShownItemContext]()

        appState.hidEventManager.stopAll()
        defer {
            appState.hidEventManager.startAll()
        }

        await eventSleep(for: .milliseconds(250))

        logger.debug("Rehiding temporarily shown items")

        MouseHelpers.hideCursor()
        defer {
            MouseHelpers.showCursor()
        }

        while let context = currentContexts.popLast() {
            // Prefer the precise window identifier, but fall back to the tag if
            // the owning process recreated the item's status window (which gives
            // it a new CGWindowID) while it was temporarily shown. Without the
            // fallback the item would be stranded in its shown position and
            // never returned to its original location.
            guard
                let item = items.first(where: { $0.windowID == context.windowID })
                    ?? items.first(where: { $0.tag == context.tag })
            else {
                continue
            }
            do {
                try await move(item: item, to: context.returnDestination)
            } catch {
                context.rehideAttempts += 1
                logger.warning(
                    """
                    Attempt \(context.rehideAttempts, privacy: .public) to rehide \
                    \(item.logString, privacy: .public) failed with error: \
                    \(error, privacy: .public)
                    """
                )
                if context.rehideAttempts < 3 {
                    currentContexts.append(context) // Try again.
                } else {
                    // Failed contexts are ultimately added back to the array
                    // and rehidden after a longer delay, so reset the count.
                    context.rehideAttempts = 0
                    failedContexts.append(context)
                }
            }
        }

        if failedContexts.isEmpty {
            logger.debug("All items were successfully rehidden")
        } else {
            logger.error(
                """
                Some items failed to rehide: \
                \(failedContexts.map { $0.windowID }, privacy: .public)
                """
            )
            temporarilyShownItemContexts.append(contentsOf: failedContexts.reversed())
            runRehideTimer(for: 3)
        }
    }

    /// Removes a temporarily shown item from the cache, ensuring that
    /// the item is _not_ returned to its original location.
    func removeTemporarilyShownItemFromCache(for item: MenuBarItem) {
        while let index = temporarilyShownItemContexts.firstIndex(where: { $0.windowID == item.windowID }) {
            logger.debug(
                """
                Removing temporarily shown item from cache: \
                \(item.logString, privacy: .public)
                """
            )
            temporarilyShownItemContexts.remove(at: index)
        }
    }
}

// MARK: - Control Item Order

extension MenuBarItemManager {
    /// Enforces the order of the given control items, ensuring that the
    /// control item for the always-hidden section is positioned to the
    /// left of control item for the hidden section.
    private func enforceControlItemOrder(controlItems: ControlItemPair) async {
        let hidden = controlItems.hidden

        guard
            let alwaysHidden = controlItems.alwaysHidden,
            hidden.bounds.maxX <= alwaysHidden.bounds.minX
        else {
            return
        }

        do {
            logger.debug("Control items have incorrect order")
            try await move(item: alwaysHidden, to: .leftOfItem(hidden))
        } catch {
            logger.error("Error enforcing control item order: \(error, privacy: .public)")
        }
    }
}

// MARK: - New Item Placement

extension MenuBarItemManager {
    /// The result of a single placement pass.
    private struct PlacementOutcome {
        /// Whether at least one item was moved and verified in its destination.
        var placedAny = false

        /// Whether the pass left work undone, and so needs another pass.
        var needsRetry = false
    }

    /// Moves menu bar items that Ice has never seen before into the visible
    /// section.
    ///
    /// macOS puts every new status item in the leftmost slot, which lands in the
    /// always-hidden section, so without this a newly installed app's icon is
    /// invisible and looks like it was never installed.
    func placeNewItemsIfNeeded() async {
        guard !isPlacingNewItems else {
            return // The outer pass is running; it will handle the retry.
        }

        // Tags are a namespace plus a window title, and titles read as empty
        // without this permission. Seeding from that state would record
        // identities that change the moment it is granted, and the user's
        // existing items would then look new and be moved. Deliberately does not
        // request a retry: nothing will change until the permission is granted,
        // and the sink in `configureCancellables` covers that.
        guard ScreenCapture.cachedCheckPermissions() else {
            return
        }

        // A menu bar that was being rearranged a moment ago, or that has items
        // parked in their temporarily shown positions, is not one to read item
        // positions from. Every workflow that moves items stamps the move
        // timestamp, so this one check covers all of them without any of them
        // needing to know placement exists.
        guard
            !lastMoveOperationOccurred(within: .seconds(1)),
            temporarilyShownItemContexts.isEmpty
        else {
            logger.debug("Deferring new item placement")
            await cacheActor.clearCachedItemWindowIDs()
            return
        }

        isPlacingNewItems = true
        let outcome = await runPlacementPass()
        if outcome.placedAny {
            // The flag is still set, so the pass this triggers returns immediately.
            await refreshCacheAfterItemMoves()
        }
        isPlacingNewItems = false

        // Must be the last awaited operation. The refresh above re-caches, which
        // rewrites the cached window IDs, so clearing any earlier would be undone
        // and the unplaced items would be stranded by the very mechanism meant to
        // rescue them.
        if outcome.needsRetry {
            await cacheActor.clearCachedItemWindowIDs()
        }
    }

    /// Runs a single placement pass and reports what it managed to do.
    private func runPlacementPass() async -> PlacementOutcome {
        var outcome = PlacementOutcome()

        // Sorted rather than taken as-is: `getMenuBarItems` reverses a window
        // list that is never positionally sorted, so left-to-right order is an
        // assumption. Every other positional decision in this file is made from
        // bounds, and this follows suit.
        //
        // Live bounds, not `MenuBarItem.bounds`, which is a snapshot taken when
        // the window list was read and can be stale for off-screen windows —
        // which is every item in the landing zone. `CacheContext.bestBounds(for:)`
        // makes the same correction for the same reason. Resolved once per item
        // rather than inside the comparator, which would re-read on every
        // comparison.
        let items = await MenuBarItem.getMenuBarItems(option: .activeSpace)
            .map { item in
                (item: item, minX: (Bridging.getWindowBounds(for: item.windowID) ?? item.bounds).minX)
            }
            .sorted { $0.minX < $1.minX }
            .map(\.item)

        guard let hiddenControlItem = items.first(matching: .hiddenControlItem) else {
            // The same signal `applyLayoutProfile` treats as fatal. Acting on a
            // read this degraded is how a working menu bar gets damaged.
            logger.warning("Skipping new item placement, as the read found no hidden control item")
            outcome.needsRetry = true
            return outcome
        }

        let orderedTags = items.map(\.tag)

        guard let knownTags = loadKnownItemTags() else {
            outcome.needsRetry = !(await seedKnownItemTags())
            return outcome
        }

        let candidateTags = NewMenuBarItemPlacement.candidateTags(in: orderedTags, known: knownTags)

        var placedTags = Set<MenuBarItemTag>()
        if !candidateTags.isEmpty {
            var itemsByTag = [MenuBarItemTag: MenuBarItem]()
            for item in items where itemsByTag[item.tag] == nil {
                itemsByTag[item.tag] = item
            }

            // Chained off the divider, in order, so the first candidate ends up
            // immediately right of it and they keep their relative order.
            var previousItem = hiddenControlItem
            for tag in candidateTags {
                guard let item = itemsByTag[tag] else {
                    continue
                }
                let destination = MoveDestination.rightOfItem(previousItem)
                do {
                    try await move(item: item, to: destination)
                    // `move` returns as soon as the item's origin changes; it
                    // never re-checks the destination. A drag beginning after
                    // its input-pause wait can satisfy that while leaving the
                    // item somewhere else entirely.
                    guard try await itemHasCorrectPosition(item: item, for: destination) else {
                        logger.warning("Placed \(item.logString, privacy: .public) did not land at its destination")
                        outcome.needsRetry = true
                        continue
                    }
                    placedTags.insert(tag)
                    previousItem = item
                } catch {
                    logger.error(
                        """
                        Error placing new menu bar item \(item.logString, privacy: .public): \
                        \(error, privacy: .public)
                        """
                    )
                    outcome.needsRetry = true
                }
            }
        }

        let tagsToRecord = NewMenuBarItemPlacement.tagsToRecord(
            seen: orderedTags,
            candidates: candidateTags,
            placed: placedTags
        )
        // Only grows, never replaces: one pass sees a single Space, so dropping
        // the tags it didn't see would re-classify items parked elsewhere as new
        // the next time they come back. Written only when it actually changed —
        // the steady state is a pass that learns nothing, and this runs on every
        // cache.
        let updatedTags = knownTags.union(tagsToRecord)
        if updatedTags != knownTags {
            storeKnownItemTags(updatedTags)
        }

        outcome.placedAny = !placedTags.isEmpty
        return outcome
    }

    /// Records every placeable item currently in the menu bar, without moving
    /// anything, so that only items appearing afterwards count as new.
    ///
    /// - Returns: Whether the seed was written.
    private func seedKnownItemTags() async -> Bool {
        // No `.activeSpace`: unlike a normal pass, this one read decides forever
        // which items count as pre-existing, so it must also see items parked on
        // other Spaces.
        let items = await MenuBarItem.getMenuBarItems(option: [])

        guard items.contains(where: { $0.tag == .hiddenControlItem }) else {
            // Storing an unvalidated seed is the one way this can damage a
            // working menu bar: a partial set makes the next pass, no longer a
            // first run, treat the user's own always-hidden items as new.
            logger.warning("Skipping known menu bar item seed, as the read found no hidden control item")
            return false
        }

        let tags = Set(items.map(\.tag).filter(NewMenuBarItemPlacement.isPlaceable))
        storeKnownItemTags(tags)
        logger.info("Seeded \(tags.count, privacy: .public) known menu bar items")
        return true
    }

    /// Loads the tags of the menu bar items Ice has already seen, or `nil` if
    /// this is a first run.
    private func loadKnownItemTags() -> Set<MenuBarItemTag>? {
        // Not `Defaults.data(forKey:)`, which returns nil for an absent key and
        // for a present value of the wrong type alike. A corrupted registry is
        // worth logging; a fresh install is not.
        guard let object = Defaults.object(forKey: .knownMenuBarItems) else {
            return nil
        }
        guard let data = object as? Data else {
            logger.error("Known menu bar items are not data; treating as a first run")
            return nil
        }
        guard let tags = NewMenuBarItemPlacement.decodeKnownTags(from: data) else {
            logger.error("Couldn't decode known menu bar items; treating as a first run")
            return nil
        }
        return tags
    }

    /// Stores the tags of the menu bar items Ice has seen.
    private func storeKnownItemTags(_ tags: Set<MenuBarItemTag>) {
        guard let data = NewMenuBarItemPlacement.encode(tags) else {
            logger.error("Couldn't encode known menu bar items")
            return
        }
        Defaults.set(data, forKey: .knownMenuBarItems)
    }
}

// MARK: - MenuBarItemEventType

/// Event types for menu bar item events.
private enum MenuBarItemEventType {
    /// The event type for moving a menu bar item.
    case move(MoveSubtype)
    /// The event type for clicking a menu bar item.
    case click(ClickSubtype)

    var cgEventType: CGEventType {
        switch self {
        case .move(let subtype): subtype.cgEventType
        case .click(let subtype): subtype.cgEventType
        }
    }

    var cgEventFlags: CGEventFlags {
        switch self {
        case .move(.mouseDown): .maskCommand
        case .move, .click: []
        }
    }

    var cgMouseButton: CGMouseButton {
        switch self {
        case .move: .left
        case .click(let subtype): subtype.cgMouseButton
        }
    }

    // MARK: Subtypes

    /// Subtype for menu bar item move events.
    enum MoveSubtype {
        case mouseDown
        case mouseUp

        var cgEventType: CGEventType {
            switch self {
            case .mouseDown: .leftMouseDown
            case .mouseUp: .leftMouseUp
            }
        }
    }

    /// Subtype for menu bar item click events.
    enum ClickSubtype {
        case leftMouseDown
        case leftMouseUp
        case rightMouseDown
        case rightMouseUp
        case otherMouseDown
        case otherMouseUp

        var cgEventType: CGEventType {
            switch self {
            case .leftMouseDown: .leftMouseDown
            case .leftMouseUp: .leftMouseUp
            case .rightMouseDown: .rightMouseDown
            case .rightMouseUp: .rightMouseUp
            case .otherMouseDown: .otherMouseDown
            case .otherMouseUp: .otherMouseUp
            }
        }

        var cgMouseButton: CGMouseButton {
            switch self {
            case .leftMouseDown, .leftMouseUp: .left
            case .rightMouseDown, .rightMouseUp: .right
            case .otherMouseDown, .otherMouseUp: .center
            }
        }

        var clickState: Int64 {
            switch self {
            case .leftMouseDown, .rightMouseDown, .otherMouseDown: 1
            case .leftMouseUp, .rightMouseUp, .otherMouseUp: 0
            }
        }
    }
}

// MARK: - CGEventField Helpers

private extension CGEventField {
    /// Key to access a field that contains the event's window identifier.
    static let windowID = CGEventField(rawValue: 0x33)! // swiftlint:disable:this force_unwrapping

    /// Fields that can be used to compare menu bar item events.
    static let menuBarItemEventFields: [CGEventField] = [
        .eventSourceUserData,
        .mouseEventWindowUnderMousePointer,
        .mouseEventWindowUnderMousePointerThatCanHandleThisEvent,
        .windowID,
    ]
}

// MARK: - CGEventFilterMask Helpers

private extension CGEventFilterMask {
    /// Specifies that all events should be permitted during event suppression states.
    static let permitAllEvents: CGEventFilterMask = [
        .permitLocalMouseEvents,
        .permitLocalKeyboardEvents,
        .permitSystemDefinedEvents,
    ]
}

// MARK: - CGEventType Helpers

private extension CGEventType {
    /// A string to use for logging purposes.
    var logString: String {
        switch self {
        case .null: "null event"
        case .leftMouseDown: "leftMouseDown event"
        case .leftMouseUp: "leftMouseUp event"
        case .rightMouseDown: "rightMouseDown event"
        case .rightMouseUp: "rightMouseUp event"
        case .mouseMoved: "mouseMoved event"
        case .leftMouseDragged: "leftMouseDragged event"
        case .rightMouseDragged: "rightMouseDragged event"
        case .keyDown: "keyDown event"
        case .keyUp: "keyUp event"
        case .flagsChanged: "flagsChanged event"
        case .scrollWheel: "scrollWheel event"
        case .tabletPointer: "tabletPointer event"
        case .tabletProximity: "tabletProximity event"
        case .otherMouseDown: "otherMouseDown event"
        case .otherMouseUp: "otherMouseUp event"
        case .otherMouseDragged: "otherMouseDragged event"
        case .tapDisabledByTimeout: "tapDisabledByTimeout event"
        case .tapDisabledByUserInput: "tapDisabledByUserInput event"
        @unknown default: "unknown event"
        }
    }
}

// MARK: - CGMouseButton Helpers

private extension CGMouseButton {
    /// A string to use for logging purposes.
    var logString: String {
        switch self {
        case .left: "left mouse button"
        case .right: "right mouse button"
        case .center: "center mouse button"
        @unknown default: "unknown mouse button"
        }
    }
}

// MARK: - CGEvent Helpers

private extension CGEvent {
    /// Returns an event that can be sent to a menu bar item.
    ///
    /// - Parameters:
    ///   - item: The event's target item.
    ///   - source: The event's source.
    ///   - type: The event's specialized type.
    ///   - location: The event's location. Does not need to be
    ///     within the bounds of the item.
    static func menuBarItemEvent(
        item: MenuBarItem,
        source: CGEventSource,
        type: MenuBarItemEventType,
        location: CGPoint
    ) -> CGEvent? {
        guard let event = CGEvent(
            mouseEventSource: source,
            mouseType: type.cgEventType,
            mouseCursorPosition: location,
            mouseButton: type.cgMouseButton
        ) else {
            return nil
        }
        event.setFlags(for: type)
        event.setUserData(ObjectIdentifier(event))
        event.setWindowID(item.windowID, for: type)
        event.setClickState(for: type)
        return event
    }

    /// Returns a null event with unique user data.
    static func uniqueNullEvent() -> CGEvent? {
        guard let event = CGEvent(source: nil) else {
            return nil
        }
        event.setUserData(ObjectIdentifier(event))
        return event
    }

    /// Posts the event to the given event tap location.
    ///
    /// - Parameter location: The event tap location to post the event to.
    func post(to location: EventTap.Location) {
        let type = self.type
        Logger.menuBarItemManager.debug(
            """
            Posting \(type.logString, privacy: .public) \
            to \(location.logString, privacy: .public)
            """
        )
        switch location {
        case .hidEventTap: post(tap: .cghidEventTap)
        case .sessionEventTap: post(tap: .cgSessionEventTap)
        case .annotatedSessionEventTap: post(tap: .cgAnnotatedSessionEventTap)
        case .pid(let pid): postToPid(pid)
        }
    }

    /// Returns a Boolean value that indicates whether the given integer
    /// fields from this event are equivalent to the same integer fields
    /// from the specified event.
    ///
    /// - Parameters:
    ///   - other: The event to compare with this event.
    ///   - fields: The integer fields to check.
    func matches(_ other: CGEvent, byIntegerFields fields: [CGEventField]) -> Bool {
        fields.allSatisfy { field in
            getIntegerValueField(field) == other.getIntegerValueField(field)
        }
    }

    func setTargetPID(_ pid: pid_t) {
        let targetPID = Int64(pid)
        setIntegerValueField(.eventTargetUnixProcessID, value: targetPID)
    }

    private func setFlags(for type: MenuBarItemEventType) {
        flags = type.cgEventFlags
    }

    private func setUserData(_ bitPattern: ObjectIdentifier) {
        let userData = Int64(Int(bitPattern: bitPattern))
        setIntegerValueField(.eventSourceUserData, value: userData)
    }

    private func setWindowID(_ windowID: CGWindowID, for type: MenuBarItemEventType) {
        let windowID = Int64(windowID)

        setIntegerValueField(.mouseEventWindowUnderMousePointer, value: windowID)
        setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: windowID)

        if case .move = type {
            setIntegerValueField(.windowID, value: windowID)
        }
    }

    private func setClickState(for type: MenuBarItemEventType) {
        if case .click(let subtype) = type {
            setIntegerValueField(.mouseEventClickState, value: subtype.clickState)
        }
    }
}

// MARK: - Logger Helpers

private extension Logger {
    /// Logger for the menu bar item manager.
    static let menuBarItemManager = Logger(category: "MenuBarItemManager")
}
