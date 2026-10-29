//
//  MenuBarLayoutProfileTests.swift
//  IceTests
//

import Foundation
import Testing
@testable import Ice_2

@MainActor
struct NativeMenuBarPolicyTests {
    @MainActor private final class Assertions {
        var issued = [NSObject]()
        var callbacks = [(Error?) -> Void]()
        var invalidated = [ObjectIdentifier]()

        func manager() -> NativeMenuBarManager {
            NativeMenuBarManager(activate: { _, _, completion in
                let handle = NSObject()
                self.issued.append(handle)
                self.callbacks.append(completion)
                return handle
            }, invalidate: { handle in
                if let handle { self.invalidated.append(ObjectIdentifier(handle)) }
            })
        }
    }

    @Test func assertionReplacementKeepsOldStateUntilSuccess() async {
        let assertions = Assertions()
        let manager = assertions.manager()
        let first = NativeMenuBarPolicy.Configuration(bundles: ["one"], systemItems: [0])
        let second = NativeMenuBarPolicy.Configuration(bundles: ["two"], systemItems: [0])
        manager.apply(first)
        assertions.callbacks[0](nil)
        // The bridge callback is delivered to the main actor asynchronously.
        await Task.yield()
        manager.apply(second)
        #expect(assertions.invalidated.isEmpty)
        assertions.callbacks[1](nil)
        await Task.yield()
        #expect(assertions.invalidated == [ObjectIdentifier(assertions.issued[0])])
        manager.restore()
        #expect(assertions.invalidated == assertions.issued.map(ObjectIdentifier.init))
    }

    @Test func staleFailureCannotCancelReplacement() async {
        let assertions = Assertions()
        let manager = assertions.manager()
        manager.apply(.init(bundles: ["one"], systemItems: [0]))
        manager.apply(.init(bundles: ["two"], systemItems: [0]))
        assertions.callbacks[0](NSError(domain: "test", code: 1))
        assertions.callbacks[1](nil)
        await Task.yield()
        #expect(manager.errorMessage == nil)
        #expect(assertions.invalidated == [ObjectIdentifier(assertions.issued[0])])
        manager.restore()
    }

    @Test func activationFailureRestoresOldAndPendingAssertions() async {
        let assertions = Assertions()
        let manager = assertions.manager()
        manager.apply(.init(bundles: ["one"], systemItems: [0]))
        assertions.callbacks[0](nil)
        await Task.yield()
        manager.apply(.init(bundles: ["two"], systemItems: [0]))
        assertions.callbacks[1](NSError(domain: "test", code: 1))
        await Task.yield()
        #expect(manager.errorMessage != nil)
        #expect(Set(assertions.invalidated) == Set(assertions.issued.map(ObjectIdentifier.init)))
    }

    @Test func showAllInvalidatesPendingAndIgnoresItsLateCallback() async {
        let assertions = Assertions()
        let manager = assertions.manager()
        manager.apply(.init(bundles: ["one"], systemItems: [0]))
        manager.apply(nil)
        assertions.callbacks[0](nil)
        await Task.yield()
        manager.restore()
        #expect(assertions.invalidated == [ObjectIdentifier(assertions.issued[0])])
    }

    @Test func unchangedConfigurationDoesNotReassert() {
        let assertions = Assertions()
        let manager = assertions.manager()
        let config = NativeMenuBarPolicy.Configuration(bundles: ["one"], systemItems: [0])
        manager.apply(config)
        manager.apply(config)
        #expect(assertions.issued.count == 1)
        manager.restore()
    }

    private func configuration(
        _ assignments: [String: MenuBarSection.Name],
        shown: Bool = false,
        alwaysShown: Bool = false,
        alwaysEnabled: Bool = true,
        running: Set<String> = ["com.example.one", "com.example.two"]
    ) -> NativeMenuBarPolicy.Configuration? {
        NativeMenuBarPolicy.configuration(
            assignments: assignments, runningBundles: running,
            hiddenShown: shown, alwaysHiddenShown: alwaysShown, alwaysHiddenEnabled: alwaysEnabled
        )
    }

    @Test func noHiddenItemsDoesNotActivateAssessment() {
        #expect(configuration([:]) == nil)
        #expect(configuration(["bundle:com.example.one": .visible]) == nil)
        #expect(configuration(["bundle:com.absent": .hidden]) == nil)
    }

    @Test func hiddenAndAlwaysHiddenRevealIndependently() throws {
        let assignments: [String: MenuBarSection.Name] = ["bundle:com.example.one": .hidden, "bundle:com.example.two": .alwaysHidden]
        let collapsed = try #require(configuration(assignments))
        #expect(!collapsed.bundles.contains("com.example.one"))
        #expect(!collapsed.bundles.contains("com.example.two"))
        let partial = try #require(configuration(assignments, shown: true))
        #expect(partial.bundles.contains("com.example.one"))
        #expect(!partial.bundles.contains("com.example.two"))
        #expect(configuration(assignments, shown: true, alwaysShown: true) == nil)
        #expect(configuration(assignments, shown: true, alwaysEnabled: false) == nil)
    }

    @Test func newlyLaunchedAppsStayVisibleAndIceCannotHideItself() throws {
        let config = try #require(configuration(
            ["bundle:com.example.one": .hidden, "bundle:com.dragonapp.ice": .hidden],
            running: ["com.example.one", "com.newapp", "com.dragonapp.ice"]
        ))
        #expect(config.bundles.contains("com.newapp"))
        #expect(config.bundles.contains("com.dragonapp.ice"))
        #expect(config.bundles.contains("com.dragonapp.ice.debug"))
    }

    @Test func systemVisibilityIsIndependentAndProtectedItemsStayAllowed() throws {
        let config = try #require(configuration(["system:0": .hidden, "system:2": .hidden, "system:8": .alwaysHidden]))
        #expect(!config.systemItems.contains(0))
        #expect(config.systemItems.contains(2))
        #expect(config.systemItems.contains(8))
        #expect(config.bundles.contains("com.example.one"))
        #expect(configuration(["system:2": .hidden, "system:99": .hidden, "unmanaged:focus": .hidden]) == nil)
    }

    @Test func discoveryGroupsAppIconsWithoutInventingWindowIDs() {
        let item = NativeMenuBarPolicy.item(bundle: "com.example.one", identifier: nil, name: "One")
        #expect(item?.id == "bundle:com.example.one")
        #expect(item?.canAssign == true)
        #expect(NativeMenuBarPolicy.item(bundle: "com.dragonapp.ice.debug", identifier: nil, name: "Ice") == nil)
        #expect(NativeMenuBarPolicy.item(bundle: "com.apple.TextInputMenuAgent", identifier: nil, name: "Input")?.id == "system:4")
        #expect(NativeMenuBarPolicy.item(bundle: nil, identifier: "com.apple.menuextra.focusmode", name: "Focus")?.canAssign == false)
    }

    @Test func nativeProfileTagsRoundTrip() {
        for id in ["bundle:com.example.one", "system:0", "system:7"] {
            let tag = NativeMenuBarPolicy.tag(for: id)
            #expect(tag.flatMap(NativeMenuBarPolicy.nativeID(for:)) == id)
        }
    }

    @Test func oldProfileMigrationPrefersVisibleAndPreservesSource() {
        let first = MenuBarItemTag(namespace: .string("com.example.one"), title: "A")
        let second = MenuBarItemTag(namespace: .string("com.example.one"), title: "B")
        let unknown = MenuBarItemTag(namespace: .uuid(UUID()), title: "Unknown")
        let battery = MenuBarItemTag(namespace: .controlCenter, title: "Battery")
        let profile = MenuBarLayoutProfile(id: UUID(), name: "Old", createdAt: .distantPast, updatedAt: .distantPast, sections: [
            .init(section: .visible, itemTags: [first, .visibleControlItem]),
            .init(section: .hidden, itemTags: [second, battery, unknown]),
            .init(section: .alwaysHidden, itemTags: [second]),
        ])
        let original = profile
        let result = NativeMenuBarPolicy.migrate(profile)
        #expect(result.assignments["bundle:com.example.one"] == .visible)
        #expect(result.assignments["system:0"] == .hidden)
        #expect(result.conflicts == ["bundle:com.example.one"])
        #expect(result.unmatched == 1)
        #expect(profile == original)
    }

    @Test func hiddenWinsOverAlwaysHiddenInConflictingLegacyProfile() {
        let tag = MenuBarItemTag(namespace: .string("com.example.one"), title: "A")
        let profile = MenuBarLayoutProfile(id: UUID(), name: "Old", createdAt: .distantPast, updatedAt: .distantPast, sections: [
            .init(section: .alwaysHidden, itemTags: [tag]),
            .init(section: .hidden, itemTags: [tag]),
        ])
        #expect(NativeMenuBarPolicy.migrate(profile).assignments["bundle:com.example.one"] == .hidden)
    }

    @Test func sectionAssignmentsSurviveCodableRoundTrip() throws {
        let assignments: [String: MenuBarSection.Name] = ["bundle:com.example.one": .alwaysHidden, "system:5": .hidden]
        let data = try JSONEncoder().encode(assignments)
        #expect(try JSONDecoder().decode([String: MenuBarSection.Name].self, from: data) == assignments)
    }

    @Test func applyingUnmappableProfileDoesNotReplaceAssignments() async throws {
        let manager = NativeMenuBarManager()
        let profile = MenuBarLayoutProfile(id: UUID(), name: "Unmappable", createdAt: .distantPast, updatedAt: .distantPast, sections: [
            .init(section: .hidden, itemTags: [.init(namespace: .uuid(UUID()), title: "Unknown")]),
        ])
        do {
            try await manager.applyProfile(profile)
            Issue.record("An unmappable profile must fail without saving an empty native layout")
        } catch {
            #expect(manager.assignments.isEmpty)
        }
    }
}

struct MenuBarLayoutProfileTests {
    private func tag(_ title: String) -> MenuBarItemTag {
        MenuBarItemTag(namespace: .string("com.example"), title: title)
    }

    private func sampleProfile() -> MenuBarLayoutProfile {
        MenuBarLayoutProfile(
            id: UUID(),
            name: "Work",
            createdAt: Date(timeIntervalSince1970: 1000),
            updatedAt: Date(timeIntervalSince1970: 2000),
            sections: [
                .init(section: .visible, itemTags: [tag("A"), tag("B")]),
                .init(section: .hidden, itemTags: [tag("C")]),
                .init(section: .alwaysHidden, itemTags: []),
            ]
        )
    }

    @Test func itemTagsAndCountsPerSection() {
        let profile = sampleProfile()
        #expect(profile.itemTags(for: .visible) == [tag("A"), tag("B")])
        #expect(profile.itemCount(for: .visible) == 2)
        #expect(profile.itemTags(for: .hidden) == [tag("C")])
        #expect(profile.itemCount(for: .alwaysHidden) == 0)
    }

    @Test func missingSectionReturnsEmpty() {
        let profile = MenuBarLayoutProfile(
            id: UUID(), name: "Empty",
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0),
            sections: []
        )
        #expect(profile.itemTags(for: .visible).isEmpty)
        #expect(profile.itemCount(for: .hidden) == 0)
    }

    @Test func profileCodableRoundTrip() throws {
        let profile = sampleProfile()
        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(MenuBarLayoutProfile.self, from: data)
        #expect(decoded == profile)
    }

}

// MARK: - Section snapshot capture

struct MenuBarLayoutSectionSnapshotTests {
    private func tag(_ title: String) -> MenuBarItemTag {
        MenuBarItemTag(namespace: .string("com.example"), title: title)
    }

    private func spacerTag(_ suffix: String) -> MenuBarItemTag {
        MenuBarItemTag(namespace: .ice, title: MenuBarSpacer.autosaveNamePrefix + suffix)
    }

    @Test func snapshotsCoverEverySectionInCanonicalOrder() {
        let snapshots = MenuBarLayoutProfile.makeSectionSnapshots(from: [:])
        #expect(snapshots.map(\.section) == MenuBarSection.Name.allCases)
        #expect(snapshots.allSatisfy { $0.itemTags.isEmpty })
    }

    @Test func snapshotsPreserveTagOrderWithinSection() {
        let snapshots = MenuBarLayoutProfile.makeSectionSnapshots(from: [
            .visible: [tag("A"), tag("B"), tag("C")],
        ])
        let visible = snapshots.first { $0.section == .visible }
        #expect(visible?.itemTags == [tag("A"), tag("B"), tag("C")])
    }

    @Test func snapshotsExcludeSpacerItems() {
        let snapshots = MenuBarLayoutProfile.makeSectionSnapshots(from: [
            .visible: [tag("A"), spacerTag("1"), tag("B")],
            .hidden: [spacerTag("2")],
        ])
        let visible = snapshots.first { $0.section == .visible }
        let hidden = snapshots.first { $0.section == .hidden }
        #expect(visible?.itemTags == [tag("A"), tag("B")])
        #expect(hidden?.itemTags == [])
    }
}

// MARK: - Create / update capture behavior

@MainActor
struct MenuBarLayoutProfileCaptureTests {
    private func tag(_ title: String) -> MenuBarItemTag {
        MenuBarItemTag(namespace: .string("com.example"), title: title)
    }

    @Test func createProfileCapturesCurrentLayout() async {
        let settings = MenuBarLayoutProfilesSettings()
        settings.captureCurrentLayout = {
            [.visible: [self.tag("A"), self.tag("B")], .hidden: [self.tag("C")]]
        }

        await settings.createProfile(named: "Work")

        #expect(settings.profiles.count == 1)
        let profile = settings.profiles[0]
        #expect(profile.name == "Work")
        #expect(profile.itemCount(for: .visible) == 2)
        #expect(profile.itemCount(for: .hidden) == 1)
        #expect(profile.itemCount(for: .alwaysHidden) == 0)
    }

    /// The core regression test for the bug: after rearranging items, clicking
    /// "Update" must re-capture the *current* layout, not keep the layout that
    /// was stored when the profile was first saved.
    @Test func updateProfileRecapturesCurrentLayout() async {
        let settings = MenuBarLayoutProfilesSettings()

        // Saved when the layout had a single visible item.
        settings.captureCurrentLayout = { [.visible: [self.tag("A")]] }
        await settings.createProfile(named: "Work")
        let original = settings.profiles[0]
        #expect(original.itemCount(for: .visible) == 1)
        #expect(original.itemCount(for: .alwaysHidden) == 0)

        // User rearranges: one item moves to the always-hidden section.
        settings.captureCurrentLayout = {
            [.visible: [self.tag("A")], .alwaysHidden: [self.tag("B")]]
        }
        await settings.updateProfile(original)

        #expect(settings.profiles.count == 1)
        let updated = settings.profiles[0]
        #expect(updated.id == original.id)
        #expect(updated.name == original.name)
        #expect(updated.createdAt == original.createdAt)
        #expect(updated.itemCount(for: .visible) == 1)
        #expect(updated.itemCount(for: .alwaysHidden) == 1)
        #expect(updated.itemTags(for: .alwaysHidden) == [tag("B")])
    }

    @Test func updateProfileLeavesOtherProfilesUntouched() async {
        let settings = MenuBarLayoutProfilesSettings()
        settings.captureCurrentLayout = { [.visible: [self.tag("A")]] }
        await settings.createProfile(named: "First")
        settings.captureCurrentLayout = { [.visible: [self.tag("B")]] }
        await settings.createProfile(named: "Second")

        let second = settings.profiles[1]
        settings.captureCurrentLayout = { [.visible: [self.tag("B"), self.tag("C")]] }
        await settings.updateProfile(second)

        #expect(settings.profiles[0].itemTags(for: .visible) == [tag("A")])
        #expect(settings.profiles[1].itemTags(for: .visible) == [tag("B"), tag("C")])
    }

    @Test func updateUnknownProfileIsNoOp() async {
        let settings = MenuBarLayoutProfilesSettings()
        settings.captureCurrentLayout = { [.visible: [self.tag("A")]] }
        await settings.createProfile(named: "Work")

        let stranger = MenuBarLayoutProfile(
            id: UUID(), name: "Ghost",
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0),
            sections: []
        )
        settings.captureCurrentLayout = { [.visible: [self.tag("Z")]] }
        await settings.updateProfile(stranger)

        #expect(settings.profiles.count == 1)
        #expect(settings.profiles[0].itemTags(for: .visible) == [tag("A")])
    }

    /// If the capture comes back with no items at all (refresh failed, revoked
    /// permission, or a cleared cache), Update must not clobber the saved
    /// profile with an empty layout.
    @Test func updateProfileIgnoresEmptyDictCapture() async {
        let settings = MenuBarLayoutProfilesSettings()
        settings.captureCurrentLayout = { [.visible: [self.tag("A"), self.tag("B")]] }
        await settings.createProfile(named: "Work")
        let original = settings.profiles[0]

        settings.captureCurrentLayout = { [:] }
        await settings.updateProfile(original)

        #expect(settings.profiles.count == 1)
        #expect(settings.profiles[0].itemTags(for: .visible) == [tag("A"), tag("B")])
    }

    @Test func updateProfileIgnoresAllSectionsEmptyCapture() async {
        let settings = MenuBarLayoutProfilesSettings()
        settings.captureCurrentLayout = { [.visible: [self.tag("A")]] }
        await settings.createProfile(named: "Work")
        let original = settings.profiles[0]

        settings.captureCurrentLayout = { [.visible: [], .hidden: [], .alwaysHidden: []] }
        await settings.updateProfile(original)

        #expect(settings.profiles[0].itemTags(for: .visible) == [tag("A")])
    }

    @Test func updateProfileAdvancesUpdatedAtButKeepsCreatedAt() async {
        let settings = MenuBarLayoutProfilesSettings()
        settings.captureCurrentLayout = { [.visible: [self.tag("A")]] }
        await settings.createProfile(named: "Work")
        let original = settings.profiles[0]

        settings.captureCurrentLayout = { [.visible: [self.tag("A"), self.tag("B")]] }
        await settings.updateProfile(original)
        let updated = settings.profiles[0]

        #expect(updated.createdAt == original.createdAt)
        #expect(updated.updatedAt >= original.updatedAt)
    }

    @Test func blankNameGetsUniqueDefault() async {
        let settings = MenuBarLayoutProfilesSettings()
        settings.captureCurrentLayout = { [.visible: [self.tag("A")]] }
        await settings.createProfile(named: "   ")
        await settings.createProfile(named: "")
        #expect(settings.profiles[0].name == "Layout Profile 1")
        #expect(settings.profiles[1].name == "Layout Profile 2")
    }

    @Test func blankNameFillsSmallestFreeIndexAfterDelete() async {
        let settings = MenuBarLayoutProfilesSettings()
        settings.captureCurrentLayout = { [.visible: [self.tag("A")]] }
        await settings.createProfile(named: "")   // "Layout Profile 1"
        await settings.createProfile(named: "")   // "Layout Profile 2"
        settings.deleteProfile(settings.profiles[0]) // frees "Layout Profile 1"
        await settings.createProfile(named: "")
        #expect(settings.profiles.contains { $0.name == "Layout Profile 1" })
    }

    @Test func nonEmptyNameIsTrimmed() async {
        let settings = MenuBarLayoutProfilesSettings()
        settings.captureCurrentLayout = { [.visible: [self.tag("A")]] }
        await settings.createProfile(named: "  Work  ")
        #expect(settings.profiles[0].name == "Work")
    }

    @Test func deleteRemovesOnlyTheTargetProfile() async {
        let settings = MenuBarLayoutProfilesSettings()
        settings.captureCurrentLayout = { [.visible: [self.tag("A")]] }
        await settings.createProfile(named: "First")
        await settings.createProfile(named: "Second")
        let first = settings.profiles[0]
        settings.deleteProfile(first)
        #expect(settings.profiles.count == 1)
        #expect(settings.profiles[0].name == "Second")
        settings.deleteProfile(first) // already gone → no-op
        #expect(settings.profiles.count == 1)
    }

    // MARK: - Apply guards without a live AppState

    @Test func applyProfileWithoutAppStateThrows() async {
        let settings = MenuBarLayoutProfilesSettings()
        let profile = MenuBarLayoutProfile(
            id: UUID(), name: "X",
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0),
            sections: []
        )
        await #expect(throws: MenuBarLayoutProfilesSettings.ApplyError.self) {
            try await settings.applyProfile(profile)
        }
    }

    @Test func applyErrorHasUserFacingDescription() {
        withEnglish {
            #expect(
                MenuBarLayoutProfilesSettings.ApplyError.missingAppState.errorDescription
                    == "Ice 2 is not ready to apply layout profiles."
            )
        }
    }
}

// MARK: - Post-move cache refresh delay

struct MenuBarCacheRefreshDelayTests {
    @Test func noMoveMeansNoDelay() {
        #expect(MenuBarItemManager.cacheRefreshDelayAfterMoves(sinceLastMove: nil) == .zero)
    }

    @Test func recentMoveWaitsOutTheSkipWindow() {
        // Window is 1s + 50ms; a move 200ms ago must wait the remaining 850ms.
        let delay = MenuBarItemManager.cacheRefreshDelayAfterMoves(sinceLastMove: .milliseconds(200))
        #expect(delay == .milliseconds(850))
    }

    @Test func oldMoveMeansNoDelay() {
        let delay = MenuBarItemManager.cacheRefreshDelayAfterMoves(sinceLastMove: .seconds(2))
        #expect(delay == .zero)
    }

    @Test func moveAtExactWindowMeansNoDelay() {
        // The skip window is exactly 1s + 50ms; a move at the boundary needs no wait.
        #expect(MenuBarItemManager.cacheRefreshDelayAfterMoves(sinceLastMove: .milliseconds(1050)) == .zero)
    }

    @Test func moveJustInsideWindowWaitsRemainder() {
        #expect(MenuBarItemManager.cacheRefreshDelayAfterMoves(sinceLastMove: .milliseconds(1000)) == .milliseconds(50))
    }
}
