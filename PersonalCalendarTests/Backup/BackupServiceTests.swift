import SwiftData
import XCTest
@testable import PersonalCalendar

@MainActor
final class BackupServiceTests: XCTestCase {
    func testRoundTripRestoresAppOwnedDataWithoutEventKitDependencies() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: RoutineRecord.self,
            RoutineCompletionRecord.self,
            CategoryRecord.self,
            ExternalCategoryLinkRecord.self,
            ProfileRecord.self,
            configurations: configuration
        )
        let context = container.mainContext
        let settings = AppSettingsStore(defaults: .ephemeral)
        let routines = SwiftDataRoutineRepository(context: context)
        let categories = SwiftDataCategoryRepository(context: context)
        let profiles = SwiftDataProfileRepository(context: context)
        let categoryID = try categories.create(name: "Personal", colorHex: "#3A8D7C")
        let routineID = try routines.create(.init(
            title: "Read",
            weekdays: [1, 2, 3, 4, 5, 6, 7],
            window: .evening,
            reminderHour: 18,
            reminderMinute: 30,
            categoryID: categoryID
        ))
        let completedDay = LocalDay(year: 2026, month: 8, day: 25)
        try routines.setCompleted(routineID: routineID, day: completedDay, completed: true)
        let profileID = try profiles.create(.init(
            name: "Personal",
            colorHex: "#3A8D7C",
            symbolName: "person.fill",
            calendarIDs: ["calendar-1"],
            reminderListIDs: ["list-1"],
            routineIDs: [routineID],
            defaultCalendarID: nil,
            defaultReminderListID: nil
        ))
        settings.replaceSelectedCalendarIDs(["calendar-1"], availableIDs: ["calendar-1"])
        settings.replaceSelectedReminderListIDs(["list-1"], availableIDs: ["list-1"])
        settings.didSeedCategories = true
        settings.didCompleteOnboarding = true
        settings.morningSummaryEnabled = true
        settings.morningSummaryHour = 7
        settings.morningSummaryMinute = 45
        settings.showNextItemOnLockScreen = true
        settings.setClassAlertPreference(
            .init(enabled: true, leadMinutes: 20),
            for: profileID
        )
        let quickEntryHistory = settings.quickEntryHistory
        let quickEntryUsedAt = Date(timeIntervalSinceReferenceDate: 123_456)
        quickEntryHistory.record(
            text: "Plan a study session",
            profileIdentity: .saved(profileID),
            at: quickEntryUsedAt
        )
        quickEntryHistory.setPreference(
            .init(
                durationMinutes: 90,
                categoryID: categoryID,
                destinationID: "calendar-1"
            ),
            profileID: profileID,
            kind: .event
        )

        let service = BackupService(context: context, settings: settings)
        let data = try service.exportData()
        try routines.delete(id: routineID)
        try categories.delete(id: categoryID, reassignedTo: nil)
        settings.didSeedCategories = false
        settings.didCompleteOnboarding = false
        settings.morningSummaryEnabled = false
        settings.morningSummaryHour = 8
        settings.morningSummaryMinute = 0
        settings.showNextItemOnLockScreen = false
        settings.setClassAlertPreference(
            .init(enabled: false, leadMinutes: 10),
            for: profileID
        )
        quickEntryHistory.record(
            text: "This was added after export",
            profileIdentity: .saved(profileID),
            at: Date(timeIntervalSinceReferenceDate: 999_999)
        )
        quickEntryHistory.setPreference(
            .init(
                durationMinutes: 30,
                categoryID: nil,
                destinationID: "calendar-added-later"
            ),
            profileID: profileID,
            kind: .event
        )

        try service.restore(data: data)

        XCTAssertEqual(try routines.list(includeArchived: true).map(\.title), ["Read"])
        XCTAssertEqual(try categories.list().map(\.name), ["Personal"])
        XCTAssertEqual(try profiles.list().map(\.name), ["Personal"])
        XCTAssertTrue(try routines.isCompleted(routineID: routineID, day: completedDay))
        XCTAssertEqual(try routines.list(includeArchived: true).first?.categoryID, categoryID)
        XCTAssertEqual(settings.selectedCalendarIDs, ["calendar-1"])
        XCTAssertEqual(settings.selectedReminderListIDs, ["list-1"])
        XCTAssertTrue(settings.calendarSelectionIsExplicit)
        XCTAssertTrue(settings.reminderSelectionIsExplicit)
        XCTAssertTrue(settings.didSeedCategories)
        XCTAssertTrue(settings.didCompleteOnboarding)
        XCTAssertTrue(settings.morningSummaryEnabled)
        XCTAssertEqual(settings.morningSummaryHour, 7)
        XCTAssertEqual(settings.morningSummaryMinute, 45)
        XCTAssertTrue(settings.showNextItemOnLockScreen)
        XCTAssertEqual(
            settings.classAlertPreference(for: profileID),
            .init(enabled: true, leadMinutes: 20)
        )
        let restoredQuickEntry = settings.quickEntryHistory
        let restoredItems = restoredQuickEntry.items(for: .saved(profileID))
        XCTAssertEqual(restoredItems.count, 1)
        guard let restoredItem = restoredItems.first else { return }
        XCTAssertEqual(restoredItem.text, "Plan a study session")
        XCTAssertEqual(restoredItem.profileIdentity, .saved(profileID))
        XCTAssertEqual(restoredItem.lastUsedAt, quickEntryUsedAt)
        XCTAssertEqual(
            restoredQuickEntry.preference(profileID: profileID, kind: .event),
            QuickEntryRememberedChoices(
                durationMinutes: 90,
                categoryID: categoryID,
                destinationID: "calendar-1"
            )
        )
    }
}
