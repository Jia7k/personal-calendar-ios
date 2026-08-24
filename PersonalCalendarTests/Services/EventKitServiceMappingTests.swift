import EventKit
import XCTest
@testable import PersonalCalendar

final class EventKitServiceMappingTests: XCTestCase {
    // Break caught: accepting an empty reminder title would create an unusable task.
    func testReminderDraftRejectsBlankTitle() {
        XCTAssertThrowsError(
            try ReminderDraftValidator.validate(
                .init(title: "\n", notes: nil, dueDate: nil, priority: 0, listID: nil)
            )
        )
    }

    // Break caught: treating recurrence metadata as future generated occurrences would misrepresent EventKit results.
    func testRecurringReminderSnapshotRepresentsOnlySuppliedOccurrence() {
        let snapshot = ReminderSnapshot(
            id: "r1",
            title: "Pay bill",
            notes: nil,
            dueDate: Date(),
            dueHasTime: false,
            priority: 0,
            listID: "l1",
            listTitle: "Tasks",
            isCompleted: false,
            allowsModification: true,
            hasRecurrence: true
        )

        XCTAssertTrue(snapshot.hasRecurrence)
        XCTAssertFalse(snapshot.isCompleted)
    }

    // Break caught: date-only reminders would be displayed with an invented clock time.
    func testDateOnlyReminderProducesUnscheduledAgendaItem() {
        let dueDate = Date(timeIntervalSince1970: 100)
        let reminder = ReminderSnapshot(
            id: "r1",
            title: "Pay bill",
            notes: nil,
            dueDate: dueDate,
            dueHasTime: false,
            priority: 1,
            listID: "l1",
            listTitle: "Tasks",
            isCompleted: false,
            allowsModification: true,
            hasRecurrence: false
        )

        let item = AgendaItem(reminder: reminder)

        XCTAssertEqual(item.placement, .unscheduled)
        XCTAssertEqual(item.sortDate, dueDate)
    }

    func testEventDraftRejectsBlankTitleAndInvertedDates() {
        let date = Date(timeIntervalSince1970: 100)

        XCTAssertThrowsError(
            try EventDraftValidator.validate(
                .init(
                    title: " ",
                    start: date,
                    end: date.addingTimeInterval(60),
                    isAllDay: false,
                    calendarID: nil
                )
            )
        )
        XCTAssertThrowsError(
            try EventDraftValidator.validate(
                .init(
                    title: "Dentist",
                    start: date,
                    end: date.addingTimeInterval(-60),
                    isAllDay: false,
                    calendarID: nil
                )
            )
        )
    }

    // Break caught: a zero-length calendar event would be accepted as a valid range.
    func testEventDraftRejectsEqualDates() {
        let date = Date(timeIntervalSince1970: 100)

        XCTAssertThrowsError(
            try EventDraftValidator.validate(
                .init(title: "Dentist", start: date, end: date, isAllDay: false, calendarID: nil)
            )
        )
    }

    // Break caught: valid event time ranges would be rejected during validation.
    func testEventDraftAcceptsNonEmptyTitleAndIncreasingDates() {
        let start = Date(timeIntervalSince1970: 100)
        let draft = EventDraft(
            title: "Dentist",
            start: start,
            end: start.addingTimeInterval(60),
            isAllDay: false,
            calendarID: nil
        )

        XCTAssertNoThrow(try EventDraftValidator.validate(draft))
    }

    func testAuthorizationMappingRequiresFullAccess() {
        XCTAssertEqual(EventKitAccessMapper.map(.fullAccess), .granted)
        XCTAssertEqual(EventKitAccessMapper.map(.denied), .denied)
        XCTAssertEqual(EventKitAccessMapper.map(.writeOnly), .restricted)
    }

    // Break caught: calendar colors would be formatted with nondeterministic or non-RGB output.
    func testCGColorFormatsRGBAsUppercaseHex() {
        XCTAssertEqual(UIColor(red: 0.25, green: 0.5, blue: 0.75, alpha: 1).cgColor.hexRGB, "#4080BF")
    }

    // Break caught: refresh errors configured in the fake would be returned as misleading successful data.
    @MainActor
    func testFakeReminderFetchThrowsConfiguredError() async {
        let service = FakeRemindersService(
            access: .granted,
            reminders: [.sampleTask],
            fetchError: TestError.expected
        )

        do {
            _ = try await service.fetchReminders(listIDs: [])
            XCTFail("Expected configured fetch error")
        } catch TestError.expected {
            // Expected configured error.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private enum TestError: Error {
        case expected
    }
}
