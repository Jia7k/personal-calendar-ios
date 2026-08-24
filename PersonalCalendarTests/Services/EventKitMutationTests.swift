import CoreLocation
import EventKit
import XCTest
@testable import PersonalCalendar

@MainActor
final class EventKitMutationTests: XCTestCase {
    // Break caught: blank EventKit addresses would expose edit controls that cannot safely route a mutation.
    func testCalendarEventSnapshotNormalizesMissingAndBlankMutationIDsToViewOnly() {
        let start = Date(timeIntervalSince1970: 1)

        for mutationID in [nil, "", " \n\t "] {
            let snapshot = CalendarEventSnapshot(
                id: "display-id",
                mutationID: mutationID,
                title: "Shared event",
                start: start,
                end: start.addingTimeInterval(60),
                isAllDay: false,
                calendarID: "calendar",
                calendarTitle: "Calendar",
                allowsModification: true,
                hasRecurrence: false
            )

            XCTAssertFalse(snapshot.isAddressable, "Expected \(String(describing: mutationID)) to be view-only")
            XCTAssertFalse(snapshot.allowsModification, "Expected \(String(describing: mutationID)) to disable mutations")
            XCTAssertFalse(AgendaItem(event: snapshot).allowsModification, "Expected agenda item to remain view-only")
        }

        let editable = CalendarEventSnapshot(
            id: "display-id",
            mutationID: "opaque-event-address",
            title: "Editable event",
            start: start,
            end: start.addingTimeInterval(60),
            isAllDay: false,
            calendarID: "calendar",
            calendarTitle: "Calendar",
            allowsModification: true,
            hasRecurrence: false
        )

        XCTAssertTrue(editable.isAddressable)
        XCTAssertTrue(editable.allowsModification)
        XCTAssertTrue(AgendaItem(event: editable).allowsModification)
    }

    // Break caught: normalizing an opaque EventKit address could make its original byte sequence unaddressable.
    func testCalendarEventSnapshotRetainsNonblankOpaqueMutationIDVerbatim() {
        let start = Date(timeIntervalSince1970: 1)
        let opaqueMutationID = " \nopaque-event-address\t "

        let snapshot = CalendarEventSnapshot(
            id: "display-id",
            mutationID: opaqueMutationID,
            title: "Editable event",
            start: start,
            end: start.addingTimeInterval(60),
            isAllDay: false,
            calendarID: "calendar",
            calendarTitle: "Calendar",
            allowsModification: true,
            hasRecurrence: false
        )

        XCTAssertEqual(snapshot.mutationID, opaqueMutationID)
        XCTAssertTrue(snapshot.isAddressable)
        XCTAssertTrue(snapshot.allowsModification)
        XCTAssertTrue(AgendaItem(event: snapshot).allowsModification)
    }

    // Break caught: saving an unchanged visible location could discard native coordinates and radius supplied by EventKit.
    func testStructuredLocationPolicyPreservesMatchingNativeLocationAndReplacesOrClearsChanges() throws {
        let event = EKEvent(eventStore: EKEventStore())
        let original = EKStructuredLocation(title: "Home")
        original.geoLocation = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 1.3521, longitude: 103.8198),
            altitude: 15,
            horizontalAccuracy: 4,
            verticalAccuracy: 6,
            timestamp: Date(timeIntervalSince1970: 1)
        )
        original.radius = 80
        event.structuredLocation = original
        let unchangedVisibleLocation = event.location ?? "Home"

        EventKitStructuredLocationPolicy.apply(submittedLocation: unchangedVisibleLocation, to: event)

        XCTAssertTrue(event.structuredLocation === original)
        let preservedStructuredLocation = try XCTUnwrap(event.structuredLocation)
        XCTAssertEqual(preservedStructuredLocation.title, "Home")
        let preservedLocation = try XCTUnwrap(preservedStructuredLocation.geoLocation)
        XCTAssertEqual(preservedLocation.coordinate.latitude, 1.3521, accuracy: 0.0001)
        XCTAssertEqual(preservedLocation.coordinate.longitude, 103.8198, accuracy: 0.0001)
        XCTAssertEqual(preservedStructuredLocation.radius, 80)

        EventKitStructuredLocationPolicy.apply(submittedLocation: "Office", to: event)

        XCTAssertFalse(event.structuredLocation === original)
        XCTAssertEqual(event.structuredLocation?.title, "Office")

        EventKitStructuredLocationPolicy.apply(submittedLocation: nil, to: event)

        XCTAssertNil(event.structuredLocation)
    }

    // Break caught: legacy recurrence metadata could make the editor treat an unknown repeat pattern as no recurrence.
    func testCalendarEventLegacyRecurrenceWithoutTypedValueNormalizesToUnsupported() {
        let start = Date(timeIntervalSince1970: 1)

        let snapshot = CalendarEventSnapshot(id: "event", title: "Event", start: start, end: start.addingTimeInterval(60), isAllDay: false, calendarID: "calendar", calendarTitle: "Calendar", allowsModification: true, hasRecurrence: true)

        XCTAssertEqual(snapshot.recurrence, .unsupported(summary: "This repeat pattern can’t be edited here."))
        XCTAssertTrue(snapshot.hasRecurrence)
    }

    // Break caught: legacy reminder metadata could make the editor overwrite an unknown repeat pattern.
    func testReminderLegacyRecurrenceWithoutTypedValueNormalizesToUnsupported() {
        let snapshot = ReminderSnapshot(id: "reminder", title: "Reminder", notes: nil, dueDate: nil, dueHasTime: false, priority: 0, listID: "list", listTitle: "List", isCompleted: false, allowsModification: true, hasRecurrence: true)

        XCTAssertEqual(snapshot.recurrence, .unsupported(summary: "This repeat pattern can’t be edited here."))
        XCTAssertTrue(snapshot.hasRecurrence)
    }

    // Break caught: a typed editable event recurrence could be hidden when legacy metadata is stale.
    func testCalendarEventEditableRecurrenceForcesHasRecurrence() {
        let start = Date(timeIntervalSince1970: 1)
        let rule = RecurrenceRuleDraft(frequency: .daily, interval: 1, weekdays: [], endDate: nil)

        let snapshot = CalendarEventSnapshot(id: "event", title: "Event", start: start, end: start.addingTimeInterval(60), isAllDay: false, calendarID: "calendar", calendarTitle: "Calendar", allowsModification: true, hasRecurrence: false, recurrence: .editable(rule))

        XCTAssertTrue(snapshot.hasRecurrence)
    }

    // Break caught: a typed editable reminder recurrence could be hidden when legacy metadata is stale.
    func testReminderEditableRecurrenceForcesHasRecurrence() {
        let rule = RecurrenceRuleDraft(frequency: .daily, interval: 1, weekdays: [], endDate: nil)

        let snapshot = ReminderSnapshot(id: "reminder", title: "Reminder", notes: nil, dueDate: nil, dueHasTime: false, priority: 0, listID: "list", listTitle: "List", isCompleted: false, allowsModification: true, hasRecurrence: false, recurrence: .editable(rule))

        XCTAssertTrue(snapshot.hasRecurrence)
    }

    // Break caught: an unsupported event recurrence could be hidden when legacy metadata is stale.
    func testCalendarEventUnsupportedRecurrenceForcesHasRecurrence() {
        let start = Date(timeIntervalSince1970: 1)

        let snapshot = CalendarEventSnapshot(id: "event", title: "Event", start: start, end: start.addingTimeInterval(60), isAllDay: false, calendarID: "calendar", calendarTitle: "Calendar", allowsModification: true, hasRecurrence: false, recurrence: .unsupported(summary: "Provider-defined repeat"))

        XCTAssertTrue(snapshot.hasRecurrence)
    }

    // Break caught: an unsupported reminder recurrence could be hidden when legacy metadata is stale.
    func testReminderUnsupportedRecurrenceForcesHasRecurrence() {
        let snapshot = ReminderSnapshot(id: "reminder", title: "Reminder", notes: nil, dueDate: nil, dueHasTime: false, priority: 0, listID: "list", listTitle: "List", isCompleted: false, allowsModification: true, hasRecurrence: false, recurrence: .unsupported(summary: "Provider-defined repeat"))

        XCTAssertTrue(snapshot.hasRecurrence)
    }

    // Break caught: events with no recurrence could be incorrectly promoted to recurring.
    func testCalendarEventNoneRecurrenceKeepsFalseLegacyFlag() {
        let start = Date(timeIntervalSince1970: 1)

        let snapshot = CalendarEventSnapshot(id: "event", title: "Event", start: start, end: start.addingTimeInterval(60), isAllDay: false, calendarID: "calendar", calendarTitle: "Calendar", allowsModification: true, hasRecurrence: false, recurrence: .none)

        XCTAssertEqual(snapshot.recurrence, .none)
        XCTAssertFalse(snapshot.hasRecurrence)
    }

    // Break caught: reminders with no recurrence could be incorrectly promoted to recurring.
    func testReminderNoneRecurrenceKeepsFalseLegacyFlag() {
        let snapshot = ReminderSnapshot(id: "reminder", title: "Reminder", notes: nil, dueDate: nil, dueHasTime: false, priority: 0, listID: "list", listTitle: "List", isCompleted: false, allowsModification: true, hasRecurrence: false, recurrence: .none)

        XCTAssertEqual(snapshot.recurrence, .none)
        XCTAssertFalse(snapshot.hasRecurrence)
    }

    // Break caught: a weekly rule could silently lose its selected weekdays.
    func testWeeklyRuleConvertsSelectedWeekdays() throws {
        let draft = RecurrenceRuleDraft(
            frequency: .weekly,
            interval: 1,
            weekdays: [2, 6],
            endDate: nil
        )

        let rule = try EventKitRecurrenceMapper.makeRule(from: draft, startsAt: nil)

        XCTAssertEqual(rule.frequency, .weekly)
        XCTAssertEqual(rule.interval, 1)
        XCTAssertEqual(Set(rule.daysOfTheWeek?.map(\.dayOfTheWeek.rawValue) ?? []), [2, 6])
    }

    // Break caught: an unsupported count-limited rule could be offered as an editable date-limited rule.
    func testCountLimitedRuleIsUnsupported() {
        let rule = EKRecurrenceRule(
            recurrenceWith: .weekly,
            interval: 1,
            end: EKRecurrenceEnd(occurrenceCount: 3)
        )

        XCTAssertEqual(
            EventKitRecurrenceMapper.snapshot(from: [rule]),
            .unsupported(summary: "This repeat pattern can’t be edited here.")
        )
    }

    // Break caught: immutable items would expose editing controls that always fail at save time.
    func testImmutableItemDisablesMutation() {
        let capabilities = ItemCapabilities(allowsModification: false, hasRecurrence: true)

        XCTAssertFalse(capabilities.canEdit)
        XCTAssertFalse(capabilities.canDelete)
        XCTAssertEqual(capabilities.explanation, "This item belongs to a read-only source.")
    }

    // Break caught: changing a title could erase a recurrence pattern the editor cannot represent.
    func testPreserveIntentLeavesUnsupportedRecurrenceUntouched() {
        XCTAssertEqual(RecurrenceMutationIntent.preserve, .preserve)
    }

    // Break caught: replacing a series from a single occurrence would silently alter the whole series.
    func testReplacingRecurrenceRequiresFutureOccurrencesScope() {
        XCTAssertThrowsError(
            try RecurrenceMutationIntent.replace(
                .init(frequency: .daily, interval: 1, weekdays: [], endDate: nil)
            ).validate(scope: .thisOccurrence)
        ) { error in
            XCTAssertEqual(error as? DraftValidationError, .invalidRecurrenceScope)
        }
    }

    // Break caught: clearing a recurrence on a single instance would mutate the series.
    func testClearingRecurrenceRequiresFutureOccurrencesScope() {
        XCTAssertThrowsError(try RecurrenceMutationIntent.clear.validate(scope: .thisOccurrence))
        XCTAssertNoThrow(try RecurrenceMutationIntent.clear.validate(scope: .futureOccurrences))
    }

    // Break caught: count ends must not be represented as an editable date end.
    func testOrdinalWeekdayRuleIsUnsupported() {
        let ordinalMonday = EKRecurrenceDayOfWeek(.monday, weekNumber: 2)
        let rule = EKRecurrenceRule(recurrenceWith: .monthly, interval: 1, daysOfTheWeek: [ordinalMonday], daysOfTheMonth: nil, monthsOfTheYear: nil, weeksOfTheYear: nil, daysOfTheYear: nil, setPositions: nil, end: nil)

        guard case .unsupported = EventKitRecurrenceMapper.snapshot(from: [rule]) else {
            return XCTFail("Expected ordinal weekday rule to be unsupported")
        }
    }

    // Break caught: applying a normal edit to an unsupported recurrence could erase it.
    func testEventDraftDefaultsToPreservingRecurrenceAndAlarms() {
        let draft = EventDraft(title: "Dentist", start: Date(), end: Date().addingTimeInterval(60), isAllDay: false, calendarID: nil)

        XCTAssertEqual(draft.recurrence, .preserve)
        XCTAssertEqual(draft.alarms, .preserve)
    }

    // Break caught: recurrence dates before the event start could be saved into EventKit.
    func testRecurrenceEndBeforeStartIsRejected() {
        let start = Date(timeIntervalSince1970: 100)
        let draft = RecurrenceRuleDraft(frequency: .daily, interval: 1, weekdays: [], endDate: Date(timeIntervalSince1970: 99))

        XCTAssertThrowsError(try EventKitRecurrenceMapper.validate(draft, startsAt: start)) { error in
            XCTAssertEqual(error as? DraftValidationError, .invalidRecurrence)
        }
    }

    // Break caught: the in-memory service could report a successful mutation while access is denied.
    @MainActor
    func testFakeCalendarRejectsDeniedMutationWithoutChangingStoredEvent() throws {
        let start = Date(timeIntervalSince1970: 100)
        let event = CalendarEventSnapshot(id: "event", mutationID: "opaque-event", title: "Original", start: start, end: start.addingTimeInterval(60), isAllDay: false, calendarID: "calendar", calendarTitle: "Calendar", allowsModification: true, hasRecurrence: true, recurrence: .unsupported(summary: "Provider-defined repeat"))
        let service = FakeCalendarService(access: .denied, events: [event])
        let replacement = EventDraft(title: "Changed", start: start, end: start.addingTimeInterval(120), isAllDay: false, calendarID: nil)

        XCTAssertThrowsError(try service.updateEvent(id: "opaque-event", draft: replacement, scope: .thisOccurrence))
        XCTAssertNil(service.event(id: "opaque-event"))
    }

    // Break caught: moving to an unknown calendar could partially change the stored event.
    @MainActor
    func testFakeCalendarRejectsMissingDestinationAtomically() throws {
        let start = Date(timeIntervalSince1970: 100)
        let event = CalendarEventSnapshot(id: "event", mutationID: "opaque-event", title: "Original", start: start, end: start.addingTimeInterval(60), isAllDay: false, calendarID: "calendar", calendarTitle: "Calendar", allowsModification: true, hasRecurrence: false)
        let service = FakeCalendarService(access: .granted, events: [event], descriptors: [.init(id: "calendar", title: "Calendar", colorHex: "#000000", allowsContentModifications: true)])
        let replacement = EventDraft(title: "Changed", start: start, end: start.addingTimeInterval(120), isAllDay: false, calendarID: "missing")

        XCTAssertThrowsError(try service.updateEvent(id: "opaque-event", draft: replacement, scope: .thisOccurrence))
        XCTAssertEqual(service.event(id: "opaque-event"), event)
    }

    // Break caught: completion UI reconstruction could silently discard uneditable native detail.
    func testCompletionCopyPreservesUnsupportedNativeDetail() {
        let reminder = ReminderSnapshot(id: "r", title: "Pay", notes: "keep", dueDate: Date(timeIntervalSince1970: 1), dueHasTime: true, priority: 1, listID: "l", listTitle: "List", isCompleted: false, allowsModification: true, hasRecurrence: true, alarm: .unsupported(summary: "Provider alert"), recurrence: .unsupported(summary: "Provider repeat"))

        let completed = reminder.withCompletion(true)

        XCTAssertTrue(completed.isCompleted)
        XCTAssertEqual(completed.alarm, .unsupported(summary: "Provider alert"))
        XCTAssertEqual(completed.recurrence, .unsupported(summary: "Provider repeat"))
    }

    // Break caught: a backing command could lose the explicit recurrence scope before EventKit maps it to a span.
    @MainActor
    func testRecordingBackingCapturesExactFutureEventUpdateRequest() throws {
        let backing = RecordingEventKitMutationBacking()
        let draft = EventDraft(title: "Move", start: Date(timeIntervalSince1970: 1), end: Date(timeIntervalSince1970: 2), isAllDay: false, calendarID: nil)

        try backing.updateEvent(id: "opaque-event-id", request: .init(draft: draft, destination: .preserveCurrent, scope: .futureOccurrences))

        XCTAssertEqual(backing.eventUpdates.count, 1)
        XCTAssertEqual(backing.eventUpdates.first?.0, "opaque-event-id")
        XCTAssertEqual(backing.eventUpdates.first?.1.scope, .futureOccurrences)
        XCTAssertEqual(backing.eventUpdates.first?.1.destination, .preserveCurrent)
    }

    // Break caught: rejected backing commands could still record a write operation.
    @MainActor
    func testRecordingBackingErrorLeavesNoRecordedMutation() {
        enum Expected: Error { case failure }
        let backing = RecordingEventKitMutationBacking()
        backing.error = Expected.failure
        let draft = EventDraft(title: "No", start: Date(timeIntervalSince1970: 1), end: Date(timeIntervalSince1970: 2), isAllDay: false, calendarID: nil)

        XCTAssertThrowsError(try backing.createEvent(.init(draft: draft, destination: .defaultWritable)))
        XCTAssertTrue(backing.eventCreates.isEmpty)
    }

    // Break caught: a service could turn a confirmed persistence result without an addressable ID into a retryable failure.
    func testEventServicePropagatesConfirmedNilMutationIDAsSuccess() throws {
        let backing = RecordingEventKitMutationBacking()
        backing.nextEventID = nil
        let service = EventKitCalendarService(store: EKEventStore(), mutations: backing)
        let draft = EventDraft(title: "Event", start: Date(timeIntervalSince1970: 1), end: Date(timeIntervalSince1970: 2), isAllDay: false, calendarID: nil)

        XCTAssertNil(try service.createEvent(draft))
        XCTAssertEqual(backing.eventCreates.count, 1)
    }

    // Break caught: a service could turn a confirmed persistence result without an addressable ID into a retryable failure.
    func testReminderServicePropagatesConfirmedBlankMutationIDAsSuccess() throws {
        let backing = RecordingEventKitMutationBacking()
        backing.nextReminderID = "   "
        let service = EventKitRemindersService(store: EKEventStore(), mutations: backing)
        let draft = ReminderDraft(title: "Reminder", notes: nil, dueDate: nil, priority: 0, listID: nil)

        XCTAssertNil(try service.createReminder(draft))
        XCTAssertEqual(backing.reminderCreates.count, 1)
    }
}
