import EventKit
import XCTest
@testable import PersonalCalendar

@MainActor
final class EventKitServiceMappingTests: XCTestCase {
    // Break caught: accepting an empty reminder title would create an unusable task.
    func testReminderDraftRejectsBlankTitle() {
        XCTAssertThrowsError(
            try ReminderDraftValidator.validate(
                .init(title: "\n", notes: nil, dueDate: nil, priority: 0, listID: nil)
            )
        )
    }

    // Break caught: recurring reminders with no due date cannot have a valid recurrence start.
    func testReminderDraftRejectsRecurringRuleWithoutDueDate() {
        XCTAssertThrowsError(try ReminderDraftValidator.validate(.init(title: "Pay bill", notes: nil, dueDate: nil, priority: 0, recurrence: .replace(.init(frequency: .monthly, interval: 1, weekdays: [], endDate: nil)))) ) { error in
            XCTAssertEqual(error as? DraftValidationError, .recurringReminderRequiresDueDate)
        }
    }

    // Break caught: a recurring EventKit occurrence would be expanded into unsupplied future snapshots.
    func testMapsOneSuppliedRecurringOccurrenceToExactlyOneSnapshot() {
        let occurrence = ReminderOccurrenceInput(
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

        let snapshots = ReminderSnapshotMapper.snapshots(from: [occurrence])

        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(snapshots.first?.id, "r1")
        XCTAssertTrue(snapshots.first?.hasRecurrence == true)
    }

    // Break caught: non-Gregorian device calendars could be assigned to EventKit and date-only reminders could gain a time.
    func testDueComponentBuilderUsesGregorianCalendarAndPreservesDeviceTimeZone() {
        let timeZone = try! XCTUnwrap(TimeZone(identifier: "Asia/Singapore"))
        var buddhist = Calendar(identifier: .buddhist)
        buddhist.timeZone = timeZone
        let date = Date(timeIntervalSince1970: 1_704_067_506)

        let timed = ReminderDueComponentBuilder.components(
            for: date,
            dueHasTime: true,
            preferredCalendar: buddhist
        )
        let dateOnly = ReminderDueComponentBuilder.components(
            for: date,
            dueHasTime: false,
            preferredCalendar: buddhist
        )
        var expectedGregorian = Calendar(identifier: .gregorian)
        expectedGregorian.timeZone = timeZone
        let expectedTimed = expectedGregorian.dateComponents([.year, .month, .day, .hour, .minute], from: date)

        XCTAssertEqual(timed.calendar?.identifier, .gregorian)
        XCTAssertEqual(timed.timeZone, timeZone)
        XCTAssertEqual(timed.year, expectedTimed.year)
        XCTAssertEqual(timed.month, expectedTimed.month)
        XCTAssertEqual(timed.day, expectedTimed.day)
        XCTAssertEqual(timed.hour, expectedTimed.hour)
        XCTAssertEqual(timed.minute, expectedTimed.minute)
        XCTAssertEqual(dateOnly.calendar?.identifier, .gregorian)
        XCTAssertEqual(dateOnly.timeZone, timeZone)
        XCTAssertEqual(dateOnly.year, expectedTimed.year)
        XCTAssertEqual(dateOnly.month, expectedTimed.month)
        XCTAssertEqual(dateOnly.day, expectedTimed.day)
        XCTAssertNil(dateOnly.hour)
        XCTAssertNil(dateOnly.minute)
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
        XCTAssertNil(item.sortDate)
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

    // Break caught: Date accepts NaN and infinity, but EventKit cannot safely persist either as an event range or alert offset.
    func testEventDraftRejectsNonFiniteDatesAndReplacementAlarmOffsets() {
        let validStart = Date(timeIntervalSince1970: 100)
        let invalidDates = [Date(timeIntervalSinceReferenceDate: .nan), Date(timeIntervalSinceReferenceDate: .infinity)]

        for invalidDate in invalidDates {
            XCTAssertThrowsError(try EventDraftValidator.validate(.init(title: "Dentist", start: invalidDate, end: validStart, isAllDay: false, calendarID: nil)))
            XCTAssertThrowsError(try EventDraftValidator.validate(.init(title: "Dentist", start: validStart, end: invalidDate, isAllDay: false, calendarID: nil)))
        }
        XCTAssertThrowsError(try EventDraftValidator.validate(.init(title: "Dentist", start: validStart, end: validStart.addingTimeInterval(60), isAllDay: false, calendarID: nil, alarms: .replace([-Double.infinity]))))
    }

    // Break caught: malformed reminder schedules, priorities, and absolute alerts would reach EventKit as invalid provider values.
    func testReminderDraftRejectsInvalidLegacySchedulePriorityAndNonFiniteDates() {
        let validDate = Date(timeIntervalSince1970: 100)
        let legacy = ReminderDraft(title: "Pay bill", notes: nil, dueDate: nil, dueHasTime: true, priority: 0)

        XCTAssertThrowsError(try ReminderDraftValidator.validate(legacy))
        XCTAssertThrowsError(try ReminderDraftValidator.validate(.init(title: "Pay bill", notes: nil, dueDate: validDate, priority: -1)))
        XCTAssertThrowsError(try ReminderDraftValidator.validate(.init(title: "Pay bill", notes: nil, dueDate: validDate, priority: 10)))
        XCTAssertThrowsError(try ReminderDraftValidator.validate(.init(title: "Pay bill", notes: nil, dueDate: Date(timeIntervalSinceReferenceDate: .nan), priority: 0)))
        XCTAssertThrowsError(try ReminderDraftValidator.validate(.init(title: "Pay bill", notes: nil, dueDate: validDate, priority: 0, alarm: .replace(Date(timeIntervalSinceReferenceDate: .infinity)))))
    }

    func testAuthorizationMappingRequiresFullAccess() {
        XCTAssertEqual(EventKitAccessMapper.map(.fullAccess), .granted)
        XCTAssertEqual(EventKitAccessMapper.map(.denied), .denied)
        XCTAssertEqual(EventKitAccessMapper.map(.writeOnly), .restricted)
    }

    // Break caught: a detail view for an event without a mutable EventKit address would disappear instead of remaining viewable.
    func testEventDetailResolverFallsBackToCalendarItemIdentityAsViewOnlySnapshot() {
        let displayID = "calendar-item-only"
        let event = EKEvent(eventStore: EKEventStore())
        event.title = "Shared holiday"
        event.startDate = Date(timeIntervalSince1970: 1_000)
        event.endDate = Date(timeIntervalSince1970: 1_600)

        let resolver = EventKitEventDetailResolver(
            eventForIdentifier: { _ in nil },
            calendarItemForIdentifier: { identifier in identifier == displayID ? event : nil }
        )

        let snapshot = resolver.requiredEvent(id: displayID)

        XCTAssertEqual(snapshot?.id, displayID)
        XCTAssertEqual(snapshot?.title, "Shared holiday")
        XCTAssertFalse(snapshot?.isAddressable ?? true)
        XCTAssertFalse(snapshot?.allowsModification ?? true)
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
