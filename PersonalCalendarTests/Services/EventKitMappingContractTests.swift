import EventKit
import XCTest
@testable import PersonalCalendar

@MainActor
final class EventKitMappingContractTests: XCTestCase {
    private let unsupportedRepeat = "This repeat pattern can’t be edited here."
    private let unsupportedAlert = "This alert pattern can’t be edited here."

    // Break caught: EventKit's unset/default first weekday is Monday, not Sunday;
    // accepting other native weekday values would silently erase provider semantics.
    func testFirstDayOfWeekRepresentabilityAcceptsUnsetDefaultAndNativeMondayOnly() {
        XCTAssertTrue(EventKitRecurrenceMapper.isRepresentableFirstDayOfTheWeek(0))
        XCTAssertEqual(EKWeekday.monday.rawValue, 2)
        XCTAssertTrue(EventKitRecurrenceMapper.isRepresentableFirstDayOfTheWeek(EKWeekday.monday.rawValue))

        for firstDayOfTheWeek in [1, 3, 4, 5, 6, 7] {
            XCTAssertFalse(
                EventKitRecurrenceMapper.isRepresentableFirstDayOfTheWeek(firstDayOfTheWeek),
                "firstDayOfTheWeek=\(firstDayOfTheWeek) must remain unsupported"
            )
        }
    }

    func testSupportedRulesRoundTripExactly() throws {
        let end = Date(timeIntervalSince1970: 1_000)
        let drafts: [RecurrenceRuleDraft] = [
            .init(frequency: .daily, interval: 2, weekdays: [], endDate: nil),
            .init(frequency: .weekly, interval: 1, weekdays: [1, 3, 7], endDate: end),
            .init(frequency: .monthly, interval: 3, weekdays: [], endDate: nil),
            .init(frequency: .yearly, interval: 4, weekdays: [], endDate: end)
        ]

        for draft in drafts {
            let rule = try EventKitRecurrenceMapper.makeRule(from: draft, startsAt: nil)
            XCTAssertEqual(
                EventKitRecurrenceMapper.snapshot(from: [rule]),
                .editable(draft),
                "Canonical EventKit rule values: calendarIdentifier=\(rule.calendarIdentifier), firstDayOfTheWeek=\(rule.firstDayOfTheWeek)"
            )
        }
    }

    func testNoRulesMapsToNoneAndBothCanonicalEndShapesRemainEditable() throws {
        let start = Date(timeIntervalSince1970: 500)
        let noEnd = try EventKitRecurrenceMapper.makeRule(
            from: .init(frequency: .daily, interval: 1, weekdays: [], endDate: nil),
            startsAt: start
        )
        let datedEnd = try EventKitRecurrenceMapper.makeRule(
            from: .init(frequency: .daily, interval: 1, weekdays: [], endDate: start.addingTimeInterval(60)),
            startsAt: start
        )

        XCTAssertEqual(EventKitRecurrenceMapper.snapshot(from: []), .none)
        XCTAssertEqual(EventKitRecurrenceMapper.snapshot(from: [noEnd], startsAt: start), .editable(.init(frequency: .daily, interval: 1, weekdays: [], endDate: nil)))
        XCTAssertEqual(EventKitRecurrenceMapper.snapshot(from: [datedEnd], startsAt: start), .editable(.init(frequency: .daily, interval: 1, weekdays: [], endDate: start.addingTimeInterval(60))))
    }

    func testDateEndBeforeTheItemAnchorIsUnsupported() {
        let rule = EKRecurrenceRule(
            recurrenceWith: .daily,
            interval: 1,
            end: EKRecurrenceEnd(end: Date(timeIntervalSince1970: 100))
        )

        XCTAssertEqual(
            EventKitRecurrenceMapper.snapshot(from: [rule], startsAt: Date(timeIntervalSince1970: 101)),
            .unsupported(summary: unsupportedRepeat)
        )
    }

    func testNonWeeklyWeekdaysAreRejectedBeforeCreatingRule() {
        let invalidDrafts: [RecurrenceRuleDraft] = [
            .init(frequency: .daily, interval: 1, weekdays: [2], endDate: nil),
            .init(frequency: .daily, interval: 0, weekdays: [], endDate: nil),
            .init(frequency: .weekly, interval: -1, weekdays: [], endDate: nil),
            .init(frequency: .weekly, interval: 1, weekdays: [0], endDate: nil),
            .init(frequency: .weekly, interval: 1, weekdays: [8], endDate: nil)
        ]

        for draft in invalidDrafts {
            XCTAssertThrowsError(try EventKitRecurrenceMapper.makeRule(from: draft, startsAt: nil)) { error in
                XCTAssertEqual(error as? DraftValidationError, .invalidRecurrence)
            }
        }
    }

    // Break caught: non-finite recurrence anchors or end dates would be handed to EventKit despite being invalid dates.
    func testRecurrenceValidationRejectsNonFiniteAnchorAndEndDate() {
        let draft = RecurrenceRuleDraft(frequency: .daily, interval: 1, weekdays: [], endDate: nil)
        XCTAssertThrowsError(try EventKitRecurrenceMapper.makeRule(from: draft, startsAt: Date(timeIntervalSinceReferenceDate: .nan)))
        XCTAssertThrowsError(try EventKitRecurrenceMapper.makeRule(from: .init(frequency: .daily, interval: 1, weekdays: [], endDate: Date(timeIntervalSinceReferenceDate: .infinity)), startsAt: nil))
    }

    func testRichOrPartialRulesAreTypedUnsupported() {
        let ordinal = EKRecurrenceDayOfWeek(.monday, weekNumber: 2)
        let rich = EKRecurrenceRule(
            recurrenceWith: .monthly,
            interval: 1,
            daysOfTheWeek: [ordinal],
            daysOfTheMonth: [1],
            monthsOfTheYear: nil,
            weeksOfTheYear: nil,
            daysOfTheYear: nil,
            setPositions: nil,
            end: nil
        )
        let simple = EKRecurrenceRule(recurrenceWith: .daily, interval: 1, end: nil)

        XCTAssertEqual(EventKitRecurrenceMapper.snapshot(from: [rich]), .unsupported(summary: unsupportedRepeat))
        XCTAssertEqual(EventKitRecurrenceMapper.snapshot(from: [simple, simple]), .unsupported(summary: unsupportedRepeat))
    }

    func testEveryAdvancedSelectorAndCountEndIsTypedUnsupported() {
        let countEnd = EKRecurrenceRule(recurrenceWith: .weekly, interval: 1, end: EKRecurrenceEnd(occurrenceCount: 3))
        let selectors: [EKRecurrenceRule] = [
            .init(recurrenceWith: .monthly, interval: 1, daysOfTheWeek: nil, daysOfTheMonth: [1], monthsOfTheYear: nil, weeksOfTheYear: nil, daysOfTheYear: nil, setPositions: nil, end: nil),
            .init(recurrenceWith: .yearly, interval: 1, daysOfTheWeek: nil, daysOfTheMonth: nil, monthsOfTheYear: [1], weeksOfTheYear: nil, daysOfTheYear: nil, setPositions: nil, end: nil),
            .init(recurrenceWith: .yearly, interval: 1, daysOfTheWeek: nil, daysOfTheMonth: nil, monthsOfTheYear: nil, weeksOfTheYear: [1], daysOfTheYear: nil, setPositions: nil, end: nil),
            .init(recurrenceWith: .yearly, interval: 1, daysOfTheWeek: nil, daysOfTheMonth: nil, monthsOfTheYear: nil, weeksOfTheYear: nil, daysOfTheYear: [1], setPositions: nil, end: nil),
            .init(recurrenceWith: .monthly, interval: 1, daysOfTheWeek: nil, daysOfTheMonth: nil, monthsOfTheYear: nil, weeksOfTheYear: nil, daysOfTheYear: nil, setPositions: [1], end: nil)
        ]

        XCTAssertEqual(EventKitRecurrenceMapper.snapshot(from: [countEnd]), .unsupported(summary: unsupportedRepeat))
        for rule in selectors {
            XCTAssertEqual(EventKitRecurrenceMapper.snapshot(from: [rule]), .unsupported(summary: unsupportedRepeat))
        }
    }

    func testAlarmMappingsOnlyExposePreciselyEditableShapes() {
        let relative = [EKAlarm(relativeOffset: -900), EKAlarm(relativeOffset: -60)]
        let absolute = Date(timeIntervalSince1970: 2_000)
        let structured = EKAlarm(relativeOffset: -60)
        structured.structuredLocation = EKStructuredLocation(title: "Home")
        structured.proximity = .enter

        XCTAssertEqual(eventAlarmSnapshot(nil), .none)
        XCTAssertEqual(eventAlarmSnapshot(relative), .editable([-900, -60]))
        XCTAssertEqual(eventAlarmSnapshot([EKAlarm(absoluteDate: absolute)]), .unsupported(summary: unsupportedAlert))
        XCTAssertEqual(eventAlarmSnapshot([structured]), .unsupported(summary: unsupportedAlert))
        XCTAssertEqual(reminderAlarmSnapshot(nil), .none)
        XCTAssertEqual(reminderAlarmSnapshot([EKAlarm(absoluteDate: absolute)]), .editable(absolute))
        XCTAssertEqual(reminderAlarmSnapshot(relative), .unsupported(summary: unsupportedAlert))
        XCTAssertEqual(reminderAlarmSnapshot([EKAlarm(absoluteDate: absolute), EKAlarm(absoluteDate: absolute.addingTimeInterval(60))]), .unsupported(summary: unsupportedAlert))
        XCTAssertEqual(reminderAlarmSnapshot([structured]), .unsupported(summary: unsupportedAlert))
    }

    func testEventAndReminderSnapshotsMapAllNativeDetailWithoutExpandingRecurrence() {
        let store = EKEventStore()
        let event = EKEvent(eventStore: store)
        let start = Date(timeIntervalSince1970: 4_000)
        event.title = "Planning"
        event.startDate = start
        event.endDate = start.addingTimeInterval(3_600)
        event.notes = "Bring notes"
        event.location = "Desk"
        event.url = URL(string: "https://example.com")
        event.alarms = [EKAlarm(relativeOffset: -300)]
        event.recurrenceRules = [try! EventKitRecurrenceMapper.makeRule(from: .init(frequency: .weekly, interval: 1, weekdays: [2], endDate: nil), startsAt: start)]

        let eventSnapshot = CalendarEventSnapshot(event: event)

        XCTAssertEqual(eventSnapshot.notes, "Bring notes")
        XCTAssertEqual(eventSnapshot.location, "Desk")
        XCTAssertEqual(eventSnapshot.url, URL(string: "https://example.com"))
        XCTAssertEqual(eventSnapshot.alarms, .editable([-300]))
        XCTAssertEqual(eventSnapshot.recurrence, .editable(.init(frequency: .weekly, interval: 1, weekdays: [2], endDate: nil)))
        XCTAssertFalse(eventSnapshot.isAddressable)

        let reminder = EKReminder(eventStore: store)
        reminder.title = "Pay"
        reminder.notes = "Utilities"
        reminder.dueDateComponents = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day, .hour, .minute], from: start)
        reminder.alarms = [EKAlarm(absoluteDate: start.addingTimeInterval(-60))]
        reminder.recurrenceRules = [try! EventKitRecurrenceMapper.makeRule(from: .init(frequency: .monthly, interval: 1, weekdays: [], endDate: nil), startsAt: start)]

        let input = ReminderOccurrenceInput(reminder: reminder)
        let reminders = ReminderSnapshotMapper.snapshots(from: [input])

        XCTAssertEqual(reminders.count, 1)
        XCTAssertEqual(reminders[0].notes, "Utilities")
        XCTAssertEqual(reminders[0].alarm, .editable(start.addingTimeInterval(-60)))
        XCTAssertEqual(reminders[0].recurrence, .editable(.init(frequency: .monthly, interval: 1, weekdays: [], endDate: nil)))
    }

    func testEventSnapshotRetainsViewIdentityButOnlyEventIdentifierIsMutableAddress() {
        let snapshot = CalendarEventSnapshot(
            id: "calendar-item-fallback",
            mutationID: nil,
            title: "Read only identity",
            start: .distantPast,
            end: .distantFuture,
            isAllDay: false,
            calendarID: "calendar",
            calendarTitle: "Calendar",
            allowsModification: true,
            hasRecurrence: false
        )

        XCTAssertEqual(snapshot.id, "calendar-item-fallback")
        XCTAssertNil(snapshot.mutationID)
        XCTAssertFalse(snapshot.isAddressable)
    }

    // Break caught: a calendar-item fallback identity would expose edit/delete affordances even though it is not a safe mutation address.
    func testEventCapabilityRequiresSafeIdentifierAndWritableCalendar() {
        XCTAssertFalse(EventKitEventCapabilityMapper.allowsModification(eventIdentifier: nil, calendarAllowsContentModifications: true))
        XCTAssertFalse(EventKitEventCapabilityMapper.allowsModification(eventIdentifier: "", calendarAllowsContentModifications: true))
        XCTAssertFalse(EventKitEventCapabilityMapper.allowsModification(eventIdentifier: " \n ", calendarAllowsContentModifications: true))
        XCTAssertFalse(EventKitEventCapabilityMapper.allowsModification(eventIdentifier: "event-id", calendarAllowsContentModifications: false))
        XCTAssertTrue(EventKitEventCapabilityMapper.allowsModification(eventIdentifier: "event-id", calendarAllowsContentModifications: true))
    }

    func testReminderSnapshotTreatsMinuteOnlyDueComponentsAsDateOnly() {
        let reminder = EKReminder(eventStore: EKEventStore())
        reminder.dueDateComponents = DateComponents(year: 2026, month: 8, day: 24, minute: 45)

        let snapshots = ReminderSnapshotMapper.snapshots(from: [.init(reminder: reminder)])

        XCTAssertEqual(snapshots.first?.dueHasTime, false)
    }

    func testReminderSnapshotTreatsExplicitMidnightHourAsTimed() {
        let reminder = EKReminder(eventStore: EKEventStore())
        reminder.dueDateComponents = DateComponents(year: 2026, month: 8, day: 24, hour: 0)

        let snapshots = ReminderSnapshotMapper.snapshots(from: [.init(reminder: reminder)])

        XCTAssertEqual(snapshots.first?.dueHasTime, true)
    }
}
