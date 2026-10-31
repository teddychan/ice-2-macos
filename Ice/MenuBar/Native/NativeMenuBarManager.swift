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
    private var needsFollowUpRefresh = false
    private var activationTimeout: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private let logger = Logger(category: "NativeMenuBar")
    private let activate: ([NSNumber], [String], @escaping (Error?) -> Void) -> AnyObject?
    private let invalidate: (AnyObject?) -> Void

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
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.restore()
                Task { await self?.refresh() }
            }
            .store(in: &cancellables)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.synchronizeVisibility()
                Task { await self?.refresh() }
            }
            .store(in: &cancellables)
        Task { await refresh() }
    }

    func refresh() async {
        guard appState != nil else { return }
        if isRefreshing {
            needsFollowUpRefresh = true
            return
        }
        guard ICENativeMenuBarAvailable() else {
            failOpen(L("app.native.unavailable"))
            return
        }
        guard AXIsProcessTrusted() else {
            failOpen(L("app.native.needsAccessibility"))
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }
        repeat {
            needsFollowUpRefresh = false
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
        } while needsFollowUpRefresh && appState != nil && ICENativeMenuBarAvailable() && AXIsProcessTrusted()
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
