import XCTest
@testable import PersonalCalendar

@MainActor
final class AppSettingsStoreTests: XCTestCase {
    func testFreshAndLegacyEmptySelectionsAreImplicitAll() {
        let fresh = AppSettingsStore(defaults: .ephemeral)
        XCTAssertFalse(fresh.calendarSelectionIsExplicit)
        XCTAssertEqual(fresh.visibleCalendarIDs(availableIDs: ["a", "b"]), ["a", "b"])

        let defaults = makeDefaults()
        defaults.set([], forKey: "selectedCalendarIDs")
        let legacy = AppSettingsStore(defaults: defaults)
        XCTAssertFalse(legacy.calendarSelectionIsExplicit)
        XCTAssertEqual(legacy.visibleCalendarIDs(availableIDs: ["a", "b"]), ["a", "b"])
    }

    func testLegacyNonemptySelectionMigratesToExplicitAndPersistsMarker() {
        let defaults = makeDefaults()
        defaults.set(["home"], forKey: "selectedCalendarIDs")

        let subject = AppSettingsStore(defaults: defaults)

        XCTAssertTrue(subject.calendarSelectionIsExplicit)
        XCTAssertEqual(subject.visibleCalendarIDs(availableIDs: ["home", "work"]), ["home"])
        XCTAssertEqual(defaults.object(forKey: "selectedCalendarIDsAreExplicit") as? Bool, true)
    }

    func testFirstToggleSeedsAllCurrentSourcesThenAppliesAndPreventsRemovingLastCurrentSource() {
        let subject = AppSettingsStore(defaults: .ephemeral)
        let available: Set<String> = ["home", "work"]

        subject.toggleCalendar(id: "home", availableIDs: available)

        XCTAssertTrue(subject.calendarSelectionIsExplicit)
        XCTAssertEqual(subject.selectedCalendarIDs, ["work"])
        subject.toggleCalendar(id: "work", availableIDs: available)
        XCTAssertEqual(subject.selectedCalendarIDs, ["work"])
    }

    func testExplicitAllDoesNotBecomeImplicitWhenANewSourceAppears() {
        let subject = AppSettingsStore(defaults: .ephemeral)
        subject.replaceSelectedCalendarIDs(["home", "work"], availableIDs: ["home", "work"])

        XCTAssertTrue(subject.calendarSelectionIsExplicit)
        XCTAssertEqual(subject.visibleCalendarIDs(availableIDs: ["home", "work", "new"]), ["home", "work"])
    }

    func testEmptyCalendarReplacementPreservesExplicitSubsetAndPersistence() {
        let defaults = makeDefaults()
        let subject = AppSettingsStore(defaults: defaults)
        subject.replaceSelectedCalendarIDs(["home"], availableIDs: ["home", "work"])

        subject.replaceSelectedCalendarIDs([], availableIDs: ["home", "work"])

        XCTAssertEqual(subject.selectedCalendarIDs, ["home"])
        XCTAssertTrue(subject.calendarSelectionIsExplicit)
        XCTAssertEqual(defaults.stringArray(forKey: "selectedCalendarIDs"), ["home"])
        XCTAssertEqual(defaults.object(forKey: "selectedCalendarIDsAreExplicit") as? Bool, true)
    }

    func testStaleOnlyCalendarReplacementPreservesExplicitSubsetAndPersistence() {
        let defaults = makeDefaults()
        let subject = AppSettingsStore(defaults: defaults)
        subject.replaceSelectedCalendarIDs(["home"], availableIDs: ["home", "work"])

        subject.replaceSelectedCalendarIDs(["gone"], availableIDs: ["home", "work"])

        XCTAssertEqual(subject.selectedCalendarIDs, ["home"])
        XCTAssertTrue(subject.calendarSelectionIsExplicit)
        XCTAssertEqual(defaults.stringArray(forKey: "selectedCalendarIDs"), ["home"])
        XCTAssertEqual(defaults.object(forKey: "selectedCalendarIDsAreExplicit") as? Bool, true)
    }

    func testEmptyReminderReplacementPreservesExplicitSubsetAndPersistence() {
        let defaults = makeDefaults()
        let subject = AppSettingsStore(defaults: defaults)
        subject.replaceSelectedReminderListIDs(["inbox"], availableIDs: ["inbox", "work"])

        subject.replaceSelectedReminderListIDs([], availableIDs: ["inbox", "work"])

        XCTAssertEqual(subject.selectedReminderListIDs, ["inbox"])
        XCTAssertTrue(subject.reminderSelectionIsExplicit)
        XCTAssertEqual(defaults.stringArray(forKey: "selectedReminderListIDs"), ["inbox"])
        XCTAssertEqual(defaults.object(forKey: "selectedReminderListIDsAreExplicit") as? Bool, true)
    }

    func testStaleOnlyReminderReplacementPreservesExplicitSubsetAndPersistence() {
        let defaults = makeDefaults()
        let subject = AppSettingsStore(defaults: defaults)
        subject.replaceSelectedReminderListIDs(["inbox"], availableIDs: ["inbox", "work"])

        subject.replaceSelectedReminderListIDs(["gone"], availableIDs: ["inbox", "work"])

        XCTAssertEqual(subject.selectedReminderListIDs, ["inbox"])
        XCTAssertTrue(subject.reminderSelectionIsExplicit)
        XCTAssertEqual(defaults.stringArray(forKey: "selectedReminderListIDs"), ["inbox"])
        XCTAssertEqual(defaults.object(forKey: "selectedReminderListIDsAreExplicit") as? Bool, true)
    }

    func testStaleSelectionDoesNotCountAsCurrentSourceAndExplicitEmptyStaysExplicitAfterReload() {
        let defaults = makeDefaults()
        defaults.set(["stale"], forKey: "selectedCalendarIDs")
        defaults.set(true, forKey: "selectedCalendarIDsAreExplicit")
        let subject = AppSettingsStore(defaults: defaults)

        XCTAssertEqual(subject.visibleCalendarIDs(availableIDs: ["current"]), [])
        subject.toggleCalendar(id: "current", availableIDs: ["current"])
        XCTAssertEqual(subject.selectedCalendarIDs, ["current", "stale"])

        defaults.set([], forKey: "selectedReminderListIDs")
        defaults.set(true, forKey: "selectedReminderListIDsAreExplicit")
        let explicitEmpty = AppSettingsStore(defaults: defaults)
        XCTAssertTrue(explicitEmpty.reminderSelectionIsExplicit)
        XCTAssertEqual(explicitEmpty.visibleReminderListIDs(availableIDs: ["tasks"]), [])
    }

    func testSelectionsAndDefaultsRoundTripWithSortedSerialization() {
        let defaults = makeDefaults()
        let subject = AppSettingsStore(defaults: defaults)
        subject.replaceSelectedCalendarIDs(["z", "a"], availableIDs: ["z", "a"])
        subject.replaceSelectedReminderListIDs(["tasks"], availableIDs: ["tasks"])
        subject.setDefaultCalendarID("a", descriptors: [calendar(id: "a", writable: true)], access: .granted)
        subject.setDefaultReminderListID("tasks", descriptors: [list(id: "tasks", writable: true)], access: .granted)

        let reloaded = AppSettingsStore(defaults: defaults)
        XCTAssertEqual(defaults.stringArray(forKey: "selectedCalendarIDs"), ["a", "z"])
        XCTAssertEqual(reloaded.selectedCalendarIDs, ["z", "a"])
        XCTAssertEqual(reloaded.defaultCalendarID, "a")
        XCTAssertEqual(reloaded.defaultReminderListID, "tasks")
    }

    func testSeparateSuitesDoNotShareSourceSelectionsOrDefaults() {
        let first = makeDefaults(); let second = makeDefaults()
        let firstStore = AppSettingsStore(defaults: first)
        firstStore.replaceSelectedCalendarIDs(["home"], availableIDs: ["home"])
        firstStore.setDefaultReminderListID("tasks", descriptors: [list(id: "tasks", writable: true)], access: .granted)

        let secondStore = AppSettingsStore(defaults: second)
        XCTAssertEqual(secondStore.selectedCalendarIDs, [])
        XCTAssertNil(secondStore.defaultReminderListID)
    }

    func testValidatesSavedDefaultsOnlyWithGrantedAuthoritativeDescriptors() {
        let defaults = makeDefaults()
        defaults.set("gone", forKey: "defaultCalendarID")
        defaults.set("read", forKey: "defaultReminderListID")
        let subject = AppSettingsStore(defaults: defaults)

        subject.validateDefaults(calendarAccess: .denied, calendars: [], remindersAccess: .notDetermined, lists: [])
        XCTAssertEqual(subject.defaultCalendarID, "gone")
        XCTAssertEqual(subject.defaultReminderListID, "read")

        subject.validateDefaults(calendarAccess: .granted, calendars: [calendar(id: "home", writable: true)], remindersAccess: .granted, lists: [list(id: "read", writable: false)])
        XCTAssertNil(subject.defaultCalendarID)
        XCTAssertNil(subject.defaultReminderListID)
    }

    func testOnlyWritableDefaultsCanBeSavedAndSortingUsesLocalizedCaseInsensitiveTitleThenID() {
        let subject = AppSettingsStore(defaults: .ephemeral)
        let home = calendar(id: "z", title: "Home", writable: true)
        let homeLower = calendar(id: "a", title: "home", writable: true)
        let readOnly = calendar(id: "read", title: "Archive", writable: false)

        subject.setDefaultCalendarID("read", descriptors: [readOnly, home], access: .granted)
        XCTAssertNil(subject.defaultCalendarID)
        subject.setDefaultCalendarID("z", descriptors: [readOnly, home], access: .granted)
        XCTAssertEqual(subject.defaultCalendarID, "z")
        XCTAssertEqual(SourceDescriptorOrdering.calendars([home, homeLower]).map(\.id), ["a", "z"])
        XCTAssertEqual(SourceDescriptorOrdering.calendars([homeLower, home]).map(\.id), ["a", "z"])
    }

    func testCalendarPickerAccessibilityValueUsesSelectedTitleInsteadOfIdentifier() {
        let values = [calendar(id: "opaque-id", title: "Home", writable: true)]

        XCTAssertEqual(SettingsDefaultPickerValue.calendar(selectedID: "opaque-id", writableCalendars: values), "Home")
    }

    func testReminderPickerAccessibilityValueUsesSelectedTitleInsteadOfIdentifier() {
        let values = [ReminderListDescriptor(id: "opaque-id", title: "Family", colorHex: "#000000", allowsContentModifications: true)]

        XCTAssertEqual(SettingsDefaultPickerValue.reminderList(selectedID: "opaque-id", writableLists: values), "Family")
    }

    func testDefaultPickerAccessibilityValueDescribesNoneAndUnavailableStates() {
        let values = [calendar(id: "home", title: "Home", writable: true)]

        XCTAssertEqual(SettingsDefaultPickerValue.calendar(selectedID: nil, writableCalendars: values), "None")
        XCTAssertEqual(SettingsDefaultPickerValue.calendar(selectedID: "missing", writableCalendars: values), "Unavailable calendar")
        XCTAssertEqual(SettingsDefaultPickerValue.calendar(selectedID: nil, writableCalendars: []), "No writable calendar available")
        XCTAssertEqual(SettingsDefaultPickerValue.reminderList(selectedID: nil, writableLists: []), "No writable reminder list available")
    }

    func testClassAlertPreferencesDefaultOffAndPersistOnlyAllowedLeadTimes() {
        let defaults = makeDefaults()
        let profileID = UUID()
        let subject = AppSettingsStore(defaults: defaults)

        XCTAssertEqual(
            subject.classAlertPreference(for: profileID),
            .init(enabled: false, leadMinutes: 10)
        )

        subject.setClassAlertPreference(
            .init(enabled: true, leadMinutes: 20),
            for: profileID
        )
        subject.setClassAlertPreference(
            .init(enabled: true, leadMinutes: 17),
            for: UUID()
        )

        let reloaded = AppSettingsStore(defaults: defaults)
        XCTAssertEqual(
            reloaded.classAlertPreference(for: profileID),
            .init(enabled: true, leadMinutes: 20)
        )
        XCTAssertEqual(reloaded.classAlertPreferences.count, 1)
    }

    func testClassAlertPreferencesRemoveDeletedProfiles() {
        let subject = AppSettingsStore(defaults: makeDefaults())
        let keptID = UUID()
        let deletedID = UUID()
        subject.setClassAlertPreference(
            .init(enabled: true, leadMinutes: 10),
            for: keptID
        )
        subject.setClassAlertPreference(
            .init(enabled: true, leadMinutes: 30),
            for: deletedID
        )

        subject.reconcileClassAlertPreferences(validProfileIDs: [keptID])

        XCTAssertEqual(Set(subject.classAlertPreferences.keys), [keptID])
    }

    func testLiveActivityPreferencePersistsEverythingAndSavedProfiles() {
        let defaults = makeDefaults()
        let profileID = UUID()
        let subject = AppSettingsStore(defaults: defaults)

        subject.setPreferredLiveActivityProfile(
            .everything,
            validProfileIDs: [profileID]
        )
        subject.setAutomaticallyStartsLiveActivityOnForeground(true)

        var reloaded = AppSettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.preferredLiveActivityProfile, .everything)
        XCTAssertTrue(reloaded.automaticallyStartsLiveActivityOnForeground)

        reloaded.setPreferredLiveActivityProfile(
            .saved(profileID),
            validProfileIDs: [profileID]
        )

        reloaded = AppSettingsStore(defaults: defaults)
        XCTAssertEqual(
            reloaded.preferredLiveActivityProfile,
            .saved(profileID)
        )
        XCTAssertTrue(reloaded.automaticallyStartsLiveActivityOnForeground)
    }

    func testLiveActivityPreferenceFailsClosedWhenProfileIsMissingOrDeleted() {
        let defaults = makeDefaults()
        let keptID = UUID()
        let deletedID = UUID()
        let subject = AppSettingsStore(defaults: defaults)

        subject.setPreferredLiveActivityProfile(
            .saved(deletedID),
            validProfileIDs: [keptID, deletedID]
        )
        subject.setAutomaticallyStartsLiveActivityOnForeground(true)
        subject.reconcileLiveActivityPreference(validProfileIDs: [keptID])

        XCTAssertNil(subject.preferredLiveActivityProfile)
        XCTAssertFalse(subject.automaticallyStartsLiveActivityOnForeground)
        let reloaded = AppSettingsStore(defaults: defaults)
        XCTAssertNil(reloaded.preferredLiveActivityProfile)
        XCTAssertFalse(reloaded.automaticallyStartsLiveActivityOnForeground)

        subject.setPreferredLiveActivityProfile(
            .saved(deletedID),
            validProfileIDs: [keptID]
        )
        subject.setAutomaticallyStartsLiveActivityOnForeground(true)

        XCTAssertNil(subject.preferredLiveActivityProfile)
        XCTAssertFalse(subject.automaticallyStartsLiveActivityOnForeground)
    }

    func testMalformedStoredLiveActivityPreferenceFailsClosedAndRepairsDefaults() {
        let defaults = makeDefaults()
        defaults.set(
            "saved:not-a-uuid",
            forKey: "preferredLiveActivityProfile"
        )
        defaults.set(
            true,
            forKey: "automaticallyStartsLiveActivityOnForeground"
        )

        let subject = AppSettingsStore(defaults: defaults)

        XCTAssertNil(subject.preferredLiveActivityProfile)
        XCTAssertFalse(subject.automaticallyStartsLiveActivityOnForeground)
        XCTAssertNil(defaults.string(forKey: "preferredLiveActivityProfile"))
        XCTAssertFalse(
            defaults.bool(
                forKey: "automaticallyStartsLiveActivityOnForeground"
            )
        )
    }

    func testNotificationHealthDefaultsAndPersistsPauseThenSuccessfulRefresh() {
        let defaults = makeDefaults()
        let subject = AppSettingsStore(defaults: defaults)
        let refreshDate = Date(timeIntervalSince1970: 1_777_777_777)

        XCTAssertFalse(subject.notificationsPausedForStaleInput)
        XCTAssertNil(subject.lastSuccessfulNotificationRefresh)

        subject.markNotificationsPausedForStaleInput()
        var reloaded = AppSettingsStore(defaults: defaults)
        XCTAssertTrue(reloaded.notificationsPausedForStaleInput)
        XCTAssertNil(reloaded.lastSuccessfulNotificationRefresh)

        reloaded.markNotificationRefreshSuccessful(at: refreshDate)
        reloaded = AppSettingsStore(defaults: defaults)
        XCTAssertFalse(reloaded.notificationsPausedForStaleInput)
        XCTAssertEqual(reloaded.lastSuccessfulNotificationRefresh, refreshDate)
    }

    func testNotificationHealthIsExcludedFromManualBackup() throws {
        let subject = AppSettingsStore(defaults: makeDefaults())
        subject.markNotificationsPausedForStaleInput()
        subject.markNotificationRefreshSuccessful(
            at: Date(timeIntervalSince1970: 1_777_777_777)
        )

        let encoded = try JSONEncoder().encode(subject.backupValueV4)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        let serialized = String(describing: object)

        XCTAssertFalse(serialized.contains("notificationsPausedForStaleInput"))
        XCTAssertFalse(serialized.contains("lastSuccessfulNotificationRefresh"))
    }

    private func makeDefaults() -> UserDefaults {
        let suite = "AppSettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }
    private func calendar(id: String, title: String = "Calendar", writable: Bool) -> CalendarDescriptor { .init(id: id, title: title, colorHex: "#000000", allowsContentModifications: writable) }
    private func list(id: String, writable: Bool) -> ReminderListDescriptor { .init(id: id, title: id, colorHex: "#000000", allowsContentModifications: writable) }
}
