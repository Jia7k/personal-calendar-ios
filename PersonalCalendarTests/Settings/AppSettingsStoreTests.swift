import XCTest
@testable import PersonalCalendar

@MainActor
final class AppSettingsStoreTests: XCTestCase {
    func testSelectedSourcesAndDefaultsRoundTrip() {
        let suite = "AppSettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let subject = AppSettingsStore(defaults: defaults)

        subject.selectedCalendarIDs = ["home"]
        subject.selectedReminderListIDs = ["tasks"]
        subject.defaultCalendarID = "home"
        subject.defaultReminderListID = "tasks"

        let reloaded = AppSettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.selectedCalendarIDs, ["home"])
        XCTAssertEqual(reloaded.selectedReminderListIDs, ["tasks"])
        XCTAssertEqual(reloaded.defaultCalendarID, "home")
        XCTAssertEqual(reloaded.defaultReminderListID, "tasks")
    }

    func testSeparateSuitesDoNotShareSourceSelectionsOrDefaults() {
        let firstSuite = "AppSettingsStoreTests.\(UUID().uuidString)"
        let secondSuite = "AppSettingsStoreTests.\(UUID().uuidString)"
        let firstDefaults = UserDefaults(suiteName: firstSuite)!
        let secondDefaults = UserDefaults(suiteName: secondSuite)!
        defer {
            firstDefaults.removePersistentDomain(forName: firstSuite)
            secondDefaults.removePersistentDomain(forName: secondSuite)
        }

        let firstStore = AppSettingsStore(defaults: firstDefaults)
        firstStore.selectedCalendarIDs = ["home"]
        firstStore.defaultReminderListID = "tasks"

        let secondStore = AppSettingsStore(defaults: secondDefaults)
        XCTAssertEqual(secondStore.selectedCalendarIDs, [])
        XCTAssertEqual(secondStore.selectedReminderListIDs, [])
        XCTAssertNil(secondStore.defaultCalendarID)
        XCTAssertNil(secondStore.defaultReminderListID)
    }
}
