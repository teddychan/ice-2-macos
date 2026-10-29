//
//  MenuBarLayoutProfilesSettings.swift
//  Ice
//

import Combine
import Foundation
import OSLog

struct MenuBarLayoutProfile: Codable, Hashable, Identifiable {
    struct SectionSnapshot: Codable, Hashable {
        var section: MenuBarSection.Name
        var itemTags: [MenuBarItemTag]
    }

    var id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date
    var sections: [SectionSnapshot]

    func itemTags(for section: MenuBarSection.Name) -> [MenuBarItemTag] {
        sections.first { $0.section == section }?.itemTags ?? []
    }

    func itemCount(for section: MenuBarSection.Name) -> Int {
        itemTags(for: section).count
    }

    /// Builds the per-section snapshots for a layout profile from the current
    /// menu bar layout, expressed as item tags keyed by section.
    ///
    /// There is exactly one snapshot per section, in canonical section order,
    /// even for sections with no items. Ice's own spacer items are excluded:
    /// they are positioned by AppKit via their status-item autosave names, not
    /// by the layout system, so capturing them would have profile-apply
    /// synthetically move them (and surface phantom "Spacer" entries to the
    /// user).
    static func makeSectionSnapshots(
        from tagsBySection: [MenuBarSection.Name: [MenuBarItemTag]]
    ) -> [SectionSnapshot] {
        MenuBarSection.Name.allCases.map { section in
            SectionSnapshot(
                section: section,
                itemTags: (tagsBySection[section] ?? []).filter { !$0.isSpacerItem }
            )
        }
    }
}

@MainActor
final class MenuBarLayoutProfilesSettings: ObservableObject {
    @Published private(set) var profiles = [MenuBarLayoutProfile]()

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private var cancellables = Set<AnyCancellable>()

    private(set) weak var appState: AppState?

    /// Returns the user's current menu bar layout as item tags per section,
    /// refreshing the underlying item cache first so the result reflects the
    /// latest arrangement rather than a stale cache.
    ///
    /// This is the single source of truth for capturing a layout profile, and
    /// is injectable so the capture, create, and update logic can be
    /// unit-tested without a live menu bar. The default implementation is
    /// installed in `performSetup(with:)`.
    var captureCurrentLayout: () async -> [MenuBarSection.Name: [MenuBarItemTag]] = { [:] }

    func performSetup(with appState: AppState) {
        self.appState = appState
        captureCurrentLayout = { [weak appState] in
            guard let appState else {
                return [:]
            }
            if NativeMenuBarManager.usesNativeBackend {
                await appState.menuBarManager.nativeManager.refresh()
                return appState.menuBarManager.nativeManager.captureLayout()
            }
            // Refresh first: rearranging items in the layout bar does not
            // update the item cache on its own, so without this the capture
            // would read the pre-rearrangement layout (the "Update doesn't
            // save my changes" bug).
            await appState.itemManager.refreshCacheAfterItemMoves()
            var tagsBySection = [MenuBarSection.Name: [MenuBarItemTag]]()
            for section in MenuBarSection.Name.allCases {
                tagsBySection[section] = appState.itemManager.itemCache[section]
                    .map(\.tag)
            }
            return tagsBySection
        }
        loadInitialState()
        configureCancellables()
    }

    private func loadInitialState() {
        guard let data = Defaults.data(forKey: .menuBarLayoutProfiles) else {
            return
        }
        do {
            profiles = try decoder.decode([MenuBarLayoutProfile].self, from: data)
        } catch {
            Logger.serialization.error("Error decoding menu bar layout profiles: \(error, privacy: .public)")
        }
    }

    private func configureCancellables() {
        $profiles
            .encode(encoder: encoder)
            .receive(on: DispatchQueue.main)
            .sink { completion in
                if case .failure(let error) = completion {
                    Logger.serialization.error("Error encoding menu bar layout profiles: \(error, privacy: .public)")
                }
            } receiveValue: { data in
                Defaults.set(data, forKey: .menuBarLayoutProfiles)
            }
            .store(in: &cancellables)
    }

    func createProfile(named name: String) async {
        let tagsBySection = await captureCurrentLayout()
        profiles.append(makeProfile(name: name, tagsBySection: tagsBySection))
    }

    func updateProfile(_ profile: MenuBarLayoutProfile) async {
        let tagsBySection = await captureCurrentLayout()
        // A capture with no items in any section means the refresh failed (no
        // app state, revoked permission, or a cleared cache) rather than a real
        // layout — control items are never filtered out of a capture, so a
        // genuine layout always has at least one item. Don't overwrite a saved
        // profile with an empty capture.
        guard tagsBySection.values.contains(where: { !$0.isEmpty }) else {
            return
        }
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else {
            return
        }
        profiles[index] = makeProfile(
            id: profile.id,
            name: profile.name,
            createdAt: profile.createdAt,
            tagsBySection: tagsBySection
        )
    }

    func deleteProfile(_ profile: MenuBarLayoutProfile) {
        profiles.removeAll { $0.id == profile.id }
    }

    func applyProfile(_ profile: MenuBarLayoutProfile) async throws {
        guard let appState else {
            throw ApplyError.missingAppState
        }
        if NativeMenuBarManager.usesNativeBackend {
            try await appState.menuBarManager.nativeManager.applyProfile(profile)
            return
        }
        if
            !appState.settings.advanced.enableAlwaysHiddenSection,
            !profile.itemTags(for: .alwaysHidden).isEmpty
        {
            appState.settings.advanced.enableAlwaysHiddenSection = true
            try? await Task.sleep(for: .milliseconds(250))
        }
        try await appState.itemManager.applyLayoutProfile(profile)
    }

    private func makeProfile(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        tagsBySection: [MenuBarSection.Name: [MenuBarItemTag]]
    ) -> MenuBarLayoutProfile {
        MenuBarLayoutProfile(
            id: id,
            name: normalizedProfileName(name),
            createdAt: createdAt,
            updatedAt: updatedAt,
            sections: MenuBarLayoutProfile.makeSectionSnapshots(from: tagsBySection)
        )
    }

    private func normalizedProfileName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty else {
            return trimmed
        }
        return uniqueDefaultName(prefix: "Layout Profile", existing: profiles.map(\.name))
    }

    /// Returns "<prefix> N" using the smallest N that is not already taken,
    /// so default names stay unique even after profiles are deleted.
    private func uniqueDefaultName(prefix: String, existing: [String]) -> String {
        let taken = Set(existing)
        var index = 1
        while taken.contains("\(prefix) \(index)") {
            index += 1
        }
        return "\(prefix) \(index)"
    }
}

extension MenuBarLayoutProfilesSettings {
    enum ApplyError: LocalizedError {
        case missingAppState

        var errorDescription: String? {
            switch self {
            case .missingAppState: localizedErrorText("app.error.layoutProfiles.notReady")
            }
        }
    }
}
