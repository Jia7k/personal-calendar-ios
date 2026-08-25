import XCTest
@testable import PersonalCalendar

@MainActor
final class ProfileSettingsStateTests: XCTestCase {
    func testLegacySnapshotDoesNotChangeWhenLegacyReconciliationRuns() {
        let defaults = makeDefaults()
        defaults.set(["school", "birthdays"], forKey: "selectedCalendarIDs")
        defaults.set(["assignments", "personal"], forKey: "selectedReminderListIDs")
        defaults.set("school", forKey: "defaultCalendarID")
        defaults.set("assignments", forKey: "defaultReminderListID")
        defaults.set(true, forKey: "selectedCalendarIDsAreExplicit")
        defaults.set(true, forKey: "selectedReminderListIDsAreExplicit")
        let subject = AppSettingsStore(defaults: defaults)

        subject.reconcileSources(
            calendarAccess: .granted,
            calendars: [calendar(id: "school")],
            remindersAccess: .granted,
            lists: [list(id: "assignments")]
        )

        XCTAssertEqual(
            subject.legacyProfileSelection,
            LegacyProfileSelectionSnapshot(
                calendarIDs: ["school", "birthdays"],
                reminderListIDs: ["assignments", "personal"],
                defaultCalendarID: "school",
                defaultReminderListID: "assignments",
                calendarSelectionWasExplicit: true,
                reminderSelectionWasExplicit: true
            )
        )
        XCTAssertEqual(subject.selectedCalendarIDs, ["school"])
        XCTAssertEqual(subject.selectedReminderListIDs, ["assignments"])
    }

    func testTypedProfileSelectionAndLastSavedProfileRoundTripIndependently() {
        let defaults = makeDefaults()
        let id = UUID(uuidString: "66666666-6666-6666-6666-666666666666")!
        let subject = AppSettingsStore(defaults: defaults)

        XCTAssertEqual(subject.activeProfileIdentity, .everything)
        XCTAssertNil(subject.lastActiveSavedProfileID)
        subject.setActiveProfile(.saved(id))
        subject.setActiveProfile(.everything)

        let restored = AppSettingsStore(defaults: defaults)
        XCTAssertEqual(restored.activeProfileIdentity, .everything)
        XCTAssertEqual(restored.lastActiveSavedProfileID, id)
        restored.setActiveProfile(.saved(id))
        XCTAssertEqual(AppSettingsStore(defaults: defaults).activeProfileIdentity, .saved(id))
    }

    func testMigrationPartsPersistIndependentlyAndDisableOnlyTheirLegacyReconciliation() {
        let defaults = makeDefaults()
        defaults.set(["old-calendar"], forKey: "selectedCalendarIDs")
        defaults.set(["old-list"], forKey: "selectedReminderListIDs")
        let subject = AppSettingsStore(defaults: defaults)

        subject.markProfileMigrationComplete(.calendar)
        subject.reconcileSources(
            calendarAccess: .granted,
            calendars: [calendar(id: "new-calendar")],
            remindersAccess: .granted,
            lists: [list(id: "new-list")]
        )

        XCTAssertTrue(subject.didMigrateProfilePart(.calendar))
        XCTAssertFalse(subject.didMigrateProfilePart(.reminders))
        XCTAssertEqual(subject.selectedCalendarIDs, ["old-calendar"])
        XCTAssertEqual(subject.selectedReminderListIDs, ["new-list"])
        let restored = AppSettingsStore(defaults: defaults)
        XCTAssertTrue(restored.didMigrateProfilePart(.calendar))
        XCTAssertFalse(restored.didMigrateProfilePart(.reminders))
    }

    func testResetMigrationReplacesCapturedLegacyInputAndClearsEveryMarker() {
        let subject = AppSettingsStore(defaults: makeDefaults())
        for part in ProfileMigrationPart.allCases {
            subject.markProfileMigrationComplete(part)
        }
        let replacement = LegacyProfileSelectionSnapshot(
            calendarIDs: ["restored-calendar"],
            reminderListIDs: ["restored-list"],
            defaultCalendarID: "restored-calendar",
            defaultReminderListID: "restored-list",
            calendarSelectionWasExplicit: true,
            reminderSelectionWasExplicit: true
        )

        subject.resetProfileMigration(legacy: replacement)

        XCTAssertEqual(subject.legacyProfileSelection, replacement)
        XCTAssertTrue(ProfileMigrationPart.allCases.allSatisfy {
            !subject.didMigrateProfilePart($0)
        })
    }

    private func makeDefaults() -> UserDefaults {
        let suite = "ProfileSettingsStateTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }

    private func calendar(id: String) -> CalendarDescriptor {
        .init(id: id, title: id, colorHex: "#000000", allowsContentModifications: true)
    }

    private func list(id: String) -> ReminderListDescriptor {
        .init(id: id, title: id, colorHex: "#000000", allowsContentModifications: true)
    }
}
