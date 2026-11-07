//
//  BackupContentsTests.swift
//  IceTests
//

import Testing
@testable import Ice_2

/// Backup & Restore lists what a backup holds. A backup is the whole ``IceSettings`` value, so
/// every stored setting needs a line, and a setting added later can't slip past the list.
struct BackupContentsTests {
    @Test func everyStoredSettingHasALine() {
        let stored = Set(Mirror(reflecting: IceSettings()).children.compactMap(\.label))
        let listed = Set(IceSettings.backupContentKeys.map(\.property))
        // `names` only remembers how to label apps that aren't running; it is not a choice the
        // user makes, so it has no line of its own.
        #expect(stored.subtracting(["names"]) == listed)
    }

    @Test func linesFollowTheSettingsOrder() {
        #expect(IceSettings.backupContentKeys.map(\.property) == ["launchAtLogin", "hidden", "order"])
    }
}
