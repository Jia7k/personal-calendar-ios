import XCTest
@testable import PersonalCalendar

@MainActor
final class FakesTests: XCTestCase {
    func testCalendarFetchFiltersSelectedSourcesAndTreatsEmptySelectionAsAll() throws {
        let home = event(id: "home-event", calendarID: "home")
        let work = event(id: "work-event", calendarID: "work")
        let subject = FakeCalendarService(access: .granted, events: [home, work])
        let interval = DateInterval(start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 100))

        XCTAssertEqual(try subject.fetchEvents(in: interval, calendarIDs: ["home"]).map(\.id), ["home-event"])
        XCTAssertEqual(try subject.fetchEvents(in: interval, calendarIDs: ["missing"]), [])
        XCTAssertEqual(try subject.fetchEvents(in: interval, calendarIDs: []).map(\.id), ["home-event", "work-event"])
    }

    func testReminderFetchFiltersSelectedSourcesAndTreatsEmptySelectionAsAll() async throws {
        let home = reminder(id: "home-task", listID: "home")
        let work = reminder(id: "work-task", listID: "work")
        let subject = FakeRemindersService(access: .granted, reminders: [home, work])

        let selected = try await subject.fetchReminders(listIDs: ["home"])
        let missing = try await subject.fetchReminders(listIDs: ["missing"])
        let all = try await subject.fetchReminders(listIDs: [])

        XCTAssertEqual(selected.map(\.id), ["home-task"])
        XCTAssertEqual(missing, [])
        XCTAssertEqual(all.map(\.id), ["home-task", "work-task"])
    }

    func testCalendarUpdateAppliesAllEditableDetailsAndRecurrenceAtomically() throws {
        let original = CalendarEventSnapshot(id: "event", mutationID: "opaque-address", title: "Before", start: Date(timeIntervalSince1970: 10), end: Date(timeIntervalSince1970: 20), isAllDay: false, calendarID: "home", calendarTitle: "Home", allowsModification: true, hasRecurrence: true, recurrence: .editable(.init(frequency: .daily, interval: 1, weekdays: [], endDate: nil)))
        let subject = FakeCalendarService(access: .granted, events: [original], descriptors: [.init(id: "home", title: "Home", colorHex: "#000000", allowsContentModifications: true)])
        let rule = RecurrenceRuleDraft(frequency: .weekly, interval: 1, weekdays: [2], endDate: nil)
        let draft = EventDraft(title: "After", start: Date(timeIntervalSince1970: 30), end: Date(timeIntervalSince1970: 50), isAllDay: false, calendarID: nil, notes: "Notes", location: "Place", url: URL(string: "https://example.com"), alarms: .replace([-300]), recurrence: .replace(rule))

        try subject.updateEvent(id: "opaque-address", draft: draft, scope: .futureOccurrences)

        XCTAssertEqual(subject.event(id: "opaque-address"), .init(id: "event", mutationID: "opaque-address", title: "After", start: Date(timeIntervalSince1970: 30), end: Date(timeIntervalSince1970: 50), isAllDay: false, calendarID: "home", calendarTitle: "Home", allowsModification: true, hasRecurrence: true, notes: "Notes", location: "Place", url: URL(string: "https://example.com"), alarms: .editable([-300]), recurrence: .editable(rule)))
    }

    func testReminderUpdatePreservesExistingScheduleAndRequiresWritableDestinationWithoutPartialWrite() throws {
        let due = Date(timeIntervalSince1970: 100)
        let original = ReminderSnapshot(id: "task", title: "Before", notes: nil, dueDate: due, dueHasTime: true, priority: 1, listID: "home", listTitle: "Home", isCompleted: false, allowsModification: true, hasRecurrence: false)
        let subject = FakeRemindersService(access: .granted, reminders: [original], descriptors: [.init(id: "home", title: "Home", colorHex: "#000000", allowsContentModifications: true), .init(id: "locked", title: "Locked", colorHex: "#111111", allowsContentModifications: false)])
        var draft = ReminderDraft(title: "After", notes: "Notes", dueDate: nil, priority: 9, listID: "locked", alarm: .replace(Date(timeIntervalSince1970: 40)))
        draft.schedule = .preserve(current: .init(date: due, hasTime: true))

        XCTAssertThrowsError(try subject.updateReminder(id: "task", draft: draft)) { XCTAssertEqual($0 as? DraftValidationError, .readOnlyDestination) }
        XCTAssertEqual(subject.reminder(id: "task"), original)
        XCTAssertEqual(subject.successfulWriteCount, 0)
    }

    func testReminderCreateAppliesRecurrenceOnceAndExplicitDestination() throws {
        let subject = FakeRemindersService(access: .granted, descriptors: [.init(id: "later", title: "Later", colorHex: "#000000", allowsContentModifications: true)])
        let due = Date(timeIntervalSince1970: 100)
        let rule = RecurrenceRuleDraft(frequency: .daily, interval: 1, weekdays: [], endDate: nil)
        let draft = ReminderDraft(title: "Repeat", notes: "N", dueDate: due, dueHasTime: true, priority: 3, listID: "later", alarm: .replace(Date(timeIntervalSince1970: 80)), recurrence: .replace(rule))

        let id = try XCTUnwrap(try subject.createReminder(draft))

        XCTAssertEqual(subject.reminders, [.init(id: id, title: "Repeat", notes: "N", dueDate: due, dueHasTime: true, priority: 3, listID: "later", listTitle: "Later", isCompleted: false, allowsModification: true, hasRecurrence: true, alarm: .editable(Date(timeIntervalSince1970: 80)), recurrence: .editable(rule))])
        XCTAssertEqual(subject.successfulWriteCount, 1)
    }

    func testFakeUpdateAndDeleteFailuresLeaveStateAndSuccessfulWriteCountUntouched() throws {
        let original = reminder(id: "task", listID: "home")
        let subject = FakeRemindersService(access: .granted, reminders: [original], descriptors: [.init(id: "home", title: "Home", colorHex: "#000000", allowsContentModifications: true)])
        subject.updateError = FakeMutationError.failed
        let draft = ReminderDraft(title: "Changed", notes: "N", dueDate: nil, priority: 5, listID: nil)

        XCTAssertThrowsError(try subject.updateReminder(id: "task", draft: draft))
        XCTAssertEqual(subject.reminder(id: "task"), original)
        XCTAssertEqual(subject.successfulWriteCount, 0)

        subject.updateError = nil
        try subject.updateReminder(id: "task", draft: draft)
        let updated = try XCTUnwrap(subject.reminder(id: "task"))
        XCTAssertEqual(updated.title, "Changed")
        XCTAssertEqual(subject.successfulWriteCount, 1)
        subject.deleteError = FakeMutationError.failed
        XCTAssertThrowsError(try subject.deleteReminder(id: "task"))
        XCTAssertEqual(subject.reminder(id: "task"), updated)
        XCTAssertEqual(subject.successfulWriteCount, 1)
        subject.deleteError = nil
        try subject.deleteReminder(id: "task")
        XCTAssertNil(subject.reminder(id: "task"))
        XCTAssertEqual(subject.successfulWriteCount, 2)
    }

    func testFakeCompletionPreservesUnsupportedAlarmAndRecurrenceDetail() throws {
        let original = ReminderSnapshot(id: "task", title: "Task", notes: "N", dueDate: Date(timeIntervalSince1970: 1), dueHasTime: true, priority: 1, listID: "home", listTitle: "Home", isCompleted: false, allowsModification: true, hasRecurrence: true, alarm: .unsupported(summary: "provider alarm"), recurrence: .unsupported(summary: "provider recurrence"))
        let subject = FakeRemindersService(access: .granted, reminders: [original])

        try subject.setCompleted(id: "task", completed: true)

        XCTAssertEqual(subject.reminder(id: "task")?.alarm, original.alarm)
        XCTAssertEqual(subject.reminder(id: "task")?.recurrence, original.recurrence)
    }

    func testFakeDeniedAndRestrictedWritesAreAtomicAndNeverRecorded() throws {
        for access in [AccessState.denied, .restricted] {
            let original = reminder(id: "task", listID: "home")
            let subject = FakeRemindersService(access: access, reminders: [original])

            XCTAssertThrowsError(try subject.createReminder(.init(title: "New", notes: nil, dueDate: nil, priority: 0)))
            XCTAssertThrowsError(try subject.setCompleted(id: "task", completed: true))
            XCTAssertThrowsError(try subject.deleteReminder(id: "task"))
            XCTAssertEqual(subject.reminders, [original])
            XCTAssertTrue(subject.createdDrafts.isEmpty)
            XCTAssertTrue(subject.completedCalls.isEmpty)
            XCTAssertEqual(subject.successfulWriteCount, 0)
        }
    }

    func testFakeEventScopeAndClearIntentsFollowCurrentStateRules() throws {
        let start = Date(timeIntervalSince1970: 100)
        let nonrecurring = CalendarEventSnapshot(id: "event", mutationID: "opaque", title: "One", start: start, end: start.addingTimeInterval(60), isAllDay: false, calendarID: "home", calendarTitle: "Home", allowsModification: true, hasRecurrence: false)
        let subject = FakeCalendarService(access: .granted, events: [nonrecurring])
        let rule = RecurrenceRuleDraft(frequency: .daily, interval: 1, weekdays: [], endDate: nil)
        let replacement = EventDraft(title: "Repeat", start: start, end: start.addingTimeInterval(60), isAllDay: false, calendarID: nil, recurrence: .replace(rule))

        XCTAssertThrowsError(try subject.updateEvent(id: "opaque", draft: replacement, scope: .futureOccurrences))
        try subject.updateEvent(id: "opaque", draft: replacement, scope: .thisOccurrence)
        XCTAssertEqual(subject.event(id: "opaque")?.recurrence, .editable(rule))
    }

    func testFakeDestinationAndReadOnlyFailuresRemainDistinctAndAtomic() throws {
        let locked = reminder(id: "locked", listID: "home")
        let immutable = ReminderSnapshot(id: "immutable", title: "Immutable", notes: nil, dueDate: nil, dueHasTime: false, priority: 0, listID: "home", listTitle: "Home", isCompleted: false, allowsModification: false, hasRecurrence: false)
        let descriptors = [
            ReminderListDescriptor(id: "home", title: "Home", colorHex: "#000000", allowsContentModifications: true),
            ReminderListDescriptor(id: "readonly", title: "Readonly", colorHex: "#111111", allowsContentModifications: false)
        ]
        let subject = FakeRemindersService(access: .granted, reminders: [locked, immutable], descriptors: descriptors)
        let replacement = ReminderDraft(title: "Changed", notes: nil, dueDate: nil, priority: 0, listID: "missing")

        XCTAssertThrowsError(try subject.updateReminder(id: "locked", draft: replacement)) { XCTAssertEqual($0 as? DraftValidationError, .invalidDestination) }
        XCTAssertThrowsError(try subject.updateReminder(id: "locked", draft: .init(title: "Changed", notes: nil, dueDate: nil, priority: 0, listID: "readonly"))) { XCTAssertEqual($0 as? DraftValidationError, .readOnlyDestination) }
        XCTAssertThrowsError(try subject.updateReminder(id: "immutable", draft: .init(title: "Changed", notes: nil, dueDate: nil, priority: 0))) { XCTAssertEqual($0 as? DraftValidationError, .readOnlyDestination) }
        XCTAssertEqual(subject.reminders, [locked, immutable])
        XCTAssertEqual(subject.successfulWriteCount, 0)
    }

    func testFakeReminderClearAndReplaceIntentsReplaceEntireCollections() throws {
        let due = Date(timeIntervalSince1970: 100)
        let oldRule = RecurrenceRuleDraft(frequency: .daily, interval: 1, weekdays: [], endDate: nil)
        let replacementRule = RecurrenceRuleDraft(frequency: .weekly, interval: 2, weekdays: [2], endDate: nil)
        let original = ReminderSnapshot(id: "task", title: "Task", notes: nil, dueDate: due, dueHasTime: true, priority: 1, listID: "home", listTitle: "Home", isCompleted: false, allowsModification: true, hasRecurrence: true, alarm: .editable(Date(timeIntervalSince1970: 90)), recurrence: .editable(oldRule))
        let subject = FakeRemindersService(access: .granted, reminders: [original])
        var replace = ReminderDraft(title: "Task", notes: nil, dueDate: due, dueHasTime: true, priority: 1, alarm: .replace(Date(timeIntervalSince1970: 80)), recurrence: .replace(replacementRule))
        replace.schedule = .replace(.init(date: due, hasTime: true))
        try subject.updateReminder(id: "task", draft: replace)
        XCTAssertEqual(subject.reminder(id: "task")?.alarm, .editable(Date(timeIntervalSince1970: 80)))
        XCTAssertEqual(subject.reminder(id: "task")?.recurrence, .editable(replacementRule))

        var clear = ReminderDraft(title: "Task", notes: nil, dueDate: due, dueHasTime: true, priority: 1, alarm: .clear, recurrence: .clear)
        clear.schedule = .preserve(current: .init(date: due, hasTime: true))
        try subject.updateReminder(id: "task", draft: clear)
        XCTAssertEqual(subject.reminder(id: "task")?.alarm, .some(ReminderAlarmSnapshot.none))
        XCTAssertEqual(subject.reminder(id: "task")?.recurrence, .some(RecurrenceSnapshot.none))
    }

    func testFakeServicesTrimTitlesOnCreateAndUpdate() throws {
        let start = Date(timeIntervalSince1970: 1_000)
        let calendars = FakeCalendarService(access: .granted, descriptors: [.init(id: "calendar", title: "Calendar", colorHex: "#000000", allowsContentModifications: true)], defaultCalendarID: "calendar")
        let eventID = try XCTUnwrap(try calendars.createEvent(.init(title: "  Event  ", start: start, end: start.addingTimeInterval(60), isAllDay: false, calendarID: nil)))
        XCTAssertEqual(calendars.event(id: eventID)?.title, "Event")
        try calendars.updateEvent(id: eventID, draft: .init(title: "  Edited  ", start: start, end: start.addingTimeInterval(120), isAllDay: false, calendarID: nil), scope: .thisOccurrence)
        XCTAssertEqual(calendars.event(id: eventID)?.title, "Edited")

        let reminders = FakeRemindersService(access: .granted, descriptors: [.init(id: "tasks", title: "Tasks", colorHex: "#000000", allowsContentModifications: true)], defaultListID: "tasks")
        let reminderID = try XCTUnwrap(try reminders.createReminder(.init(title: "  Task  ", notes: nil, dueDate: nil, priority: 0)))
        XCTAssertEqual(reminders.reminder(id: reminderID)?.title, "Task")
        try reminders.updateReminder(id: reminderID, draft: .init(title: "  Changed  ", notes: nil, dueDate: nil, priority: 0))
        XCTAssertEqual(reminders.reminder(id: reminderID)?.title, "Changed")
    }

    func testFakeEventPreserveClearAndReplaceIntentsReplaceEntireCollections() throws {
        let start = Date(timeIntervalSince1970: 1_500)
        let oldRule = RecurrenceRuleDraft(frequency: .daily, interval: 1, weekdays: [], endDate: nil)
        let replacementRule = RecurrenceRuleDraft(frequency: .weekly, interval: 1, weekdays: [2], endDate: nil)
        let original = CalendarEventSnapshot(id: "event", mutationID: "opaque", title: "Event", start: start, end: start.addingTimeInterval(60), isAllDay: false, calendarID: "home", calendarTitle: "Home", allowsModification: true, hasRecurrence: true, alarms: .editable([-60]), recurrence: .editable(oldRule))
        let subject = FakeCalendarService(access: .granted, events: [original])

        try subject.updateEvent(id: "opaque", draft: .init(title: "Preserve", start: start, end: start.addingTimeInterval(60), isAllDay: false, calendarID: nil), scope: .thisOccurrence)
        XCTAssertEqual(subject.event(id: "opaque")?.alarms, .editable([-60]))
        XCTAssertEqual(subject.event(id: "opaque")?.recurrence, .editable(oldRule))

        try subject.updateEvent(id: "opaque", draft: .init(title: "Clear", start: start, end: start.addingTimeInterval(60), isAllDay: false, calendarID: nil, alarms: .clear, recurrence: .clear), scope: .futureOccurrences)
        XCTAssertEqual(subject.event(id: "opaque")?.alarms, .some(EventAlarmSnapshot.none))
        XCTAssertEqual(subject.event(id: "opaque")?.recurrence, .some(RecurrenceSnapshot.none))

        try subject.updateEvent(id: "opaque", draft: .init(title: "Replace", start: start, end: start.addingTimeInterval(60), isAllDay: false, calendarID: nil, alarms: .replace([-120, -30]), recurrence: .replace(replacementRule)), scope: .thisOccurrence)
        XCTAssertEqual(subject.event(id: "opaque")?.alarms, .editable([-120, -30]))
        XCTAssertEqual(subject.event(id: "opaque")?.recurrence, .editable(replacementRule))
    }

    func testFakeEventFailuresAreAtomicAndRetryAfterClearingInjection() throws {
        let start = Date(timeIntervalSince1970: 2_000)
        let draft = EventDraft(title: "Event", start: start, end: start.addingTimeInterval(60), isAllDay: false, calendarID: nil)
        let subject = FakeCalendarService(access: .granted, descriptors: [.init(id: "calendar", title: "Calendar", colorHex: "#000000", allowsContentModifications: true)], createError: FakeMutationError.failed, defaultCalendarID: "calendar")
        XCTAssertThrowsError(try subject.createEvent(draft))
        XCTAssertTrue(subject.events.isEmpty)
        XCTAssertEqual(subject.successfulWriteCount, 0)
        subject.createError = nil
        let id = try XCTUnwrap(try subject.createEvent(draft))

        let original = try XCTUnwrap(subject.event(id: id))
        subject.updateError = FakeMutationError.failed
        XCTAssertThrowsError(try subject.updateEvent(id: id, draft: .init(title: "Changed", start: start, end: start.addingTimeInterval(120), isAllDay: false, calendarID: nil), scope: .thisOccurrence))
        XCTAssertEqual(subject.event(id: id), original)
        XCTAssertEqual(subject.successfulWriteCount, 1)
        subject.updateError = nil
        try subject.updateEvent(id: id, draft: .init(title: "Changed", start: start, end: start.addingTimeInterval(120), isAllDay: false, calendarID: nil), scope: .thisOccurrence)

        subject.deleteError = FakeMutationError.failed
        let updated = try XCTUnwrap(subject.event(id: id))
        XCTAssertThrowsError(try subject.deleteEvent(id: id, scope: .thisOccurrence))
        XCTAssertEqual(subject.event(id: id), updated)
        XCTAssertEqual(subject.successfulWriteCount, 2)
        subject.deleteError = nil
        try subject.deleteEvent(id: id, scope: .thisOccurrence)
        XCTAssertNil(subject.event(id: id))
        XCTAssertEqual(subject.successfulWriteCount, 3)
    }

    func testFakeReminderCreateFailureIsAtomicAndRetryAfterClearingInjection() throws {
        let subject = FakeRemindersService(access: .granted, descriptors: [.init(id: "tasks", title: "Tasks", colorHex: "#000000", allowsContentModifications: true)], defaultListID: "tasks")
        subject.createError = FakeMutationError.failed
        let draft = ReminderDraft(title: "Task", notes: nil, dueDate: nil, priority: 0)

        XCTAssertThrowsError(try subject.createReminder(draft))
        XCTAssertTrue(subject.reminders.isEmpty)
        XCTAssertTrue(subject.createdDrafts.isEmpty)
        XCTAssertEqual(subject.successfulWriteCount, 0)
        subject.createError = nil
        let id = try XCTUnwrap(try subject.createReminder(draft))
        XCTAssertNotNil(subject.reminder(id: id))
        XCTAssertEqual(subject.successfulWriteCount, 1)
    }

    func testFakeReminderCreateRejectsSchedulePreservationWithoutCurrentValueAtomically() throws {
        let subject = FakeRemindersService(access: .granted, descriptors: [.init(id: "tasks", title: "Tasks", colorHex: "#000000", allowsContentModifications: true)], defaultListID: "tasks")
        var draft = ReminderDraft(title: "Task", notes: nil, dueDate: nil, priority: 0)
        draft.schedule = .preserve(current: nil)

        XCTAssertThrowsError(try subject.createReminder(draft))
        XCTAssertTrue(subject.reminders.isEmpty)
        XCTAssertTrue(subject.createdDrafts.isEmpty)
        XCTAssertEqual(subject.successfulWriteCount, 0)
    }

    func testFakeNilDestinationsChooseInjectedWritableDefault() throws {
        let calendars = FakeCalendarService(access: .granted, descriptors: [.init(id: "locked", title: "Locked", colorHex: "#000000", allowsContentModifications: false), .init(id: "home", title: "Home", colorHex: "#111111", allowsContentModifications: true)], defaultCalendarID: "home")
        let start = Date(timeIntervalSince1970: 3_000)
        let eventID = try XCTUnwrap(try calendars.createEvent(.init(title: "Event", start: start, end: start.addingTimeInterval(60), isAllDay: false, calendarID: nil)))
        XCTAssertEqual(calendars.event(id: eventID)?.calendarID, "home")

        let reminders = FakeRemindersService(access: .granted, descriptors: [.init(id: "locked", title: "Locked", colorHex: "#000000", allowsContentModifications: false), .init(id: "tasks", title: "Tasks", colorHex: "#111111", allowsContentModifications: true)], defaultListID: "tasks")
        let reminderID = try XCTUnwrap(try reminders.createReminder(.init(title: "Task", notes: nil, dueDate: nil, priority: 0)))
        XCTAssertEqual(reminders.reminder(id: reminderID)?.listID, "tasks")
    }

    func testFakeCalendarMutationRequiresMatchingNonblankOpaqueIDAndRecordsTypedCalls() throws {
        let start = Date(timeIntervalSince1970: 4_000)
        let original = CalendarEventSnapshot(id: "display-fallback", mutationID: "opaque-event", title: "Original", start: start, end: start.addingTimeInterval(60), isAllDay: false, calendarID: "home", calendarTitle: "Home", allowsModification: true, hasRecurrence: false)
        let draft = EventDraft(title: "Changed", start: start, end: start.addingTimeInterval(120), isAllDay: false, calendarID: nil)
        let subject = FakeCalendarService(access: .granted, events: [original])

        XCTAssertThrowsError(try subject.updateEvent(id: "display-fallback", draft: draft, scope: .thisOccurrence))
        XCTAssertEqual(subject.events, [original])
        XCTAssertTrue(subject.eventUpdateCalls.isEmpty)
        XCTAssertEqual(subject.successfulWriteCount, 0)

        subject.updateError = FakeMutationError.failed
        XCTAssertThrowsError(try subject.updateEvent(id: "opaque-event", draft: draft, scope: .thisOccurrence))
        XCTAssertTrue(subject.eventUpdateCalls.isEmpty)
        XCTAssertEqual(subject.events, [original])
        subject.updateError = nil
        try subject.updateEvent(id: "opaque-event", draft: draft, scope: .thisOccurrence)
        XCTAssertEqual(subject.events.first?.title, "Changed")
        XCTAssertEqual(subject.eventUpdateCalls, [.init(id: "opaque-event", draft: draft, scope: .thisOccurrence)])

        subject.deleteError = FakeMutationError.failed
        XCTAssertThrowsError(try subject.deleteEvent(id: "opaque-event", scope: .thisOccurrence))
        XCTAssertEqual(subject.events.count, 1)
        XCTAssertTrue(subject.eventDeleteCalls.isEmpty)
        subject.deleteError = nil
        try subject.deleteEvent(id: "opaque-event", scope: .thisOccurrence)
        XCTAssertEqual(subject.eventDeleteCalls, [.init(id: "opaque-event", scope: .thisOccurrence)])
        XCTAssertTrue(subject.events.isEmpty)
    }

    func testFakeCalendarRoutesWhitespacePaddedOpaqueMutationIDsOnlyVerbatim() throws {
        let start = Date(timeIntervalSince1970: 4_250)
        let opaqueMutationID = " \nopaque-event\t "
        let original = CalendarEventSnapshot(id: "display-fallback", mutationID: opaqueMutationID, title: "Original", start: start, end: start.addingTimeInterval(60), isAllDay: false, calendarID: "home", calendarTitle: "Home", allowsModification: true, hasRecurrence: false)
        let draft = EventDraft(title: "Changed", start: start, end: start.addingTimeInterval(120), isAllDay: false, calendarID: nil)
        let subject = FakeCalendarService(access: .granted, events: [original])

        XCTAssertThrowsError(try subject.updateEvent(id: "opaque-event", draft: draft, scope: .thisOccurrence))
        XCTAssertEqual(subject.events, [original])
        XCTAssertTrue(subject.eventUpdateCalls.isEmpty)
        XCTAssertEqual(subject.successfulWriteCount, 0)

        try subject.updateEvent(id: opaqueMutationID, draft: draft, scope: .thisOccurrence)

        XCTAssertEqual(subject.events.first?.mutationID, opaqueMutationID)
        XCTAssertEqual(subject.events.first?.title, "Changed")
        XCTAssertEqual(subject.eventUpdateCalls, [.init(id: opaqueMutationID, draft: draft, scope: .thisOccurrence)])
        XCTAssertEqual(subject.successfulWriteCount, 1)
    }

    func testFakeCalendarRejectsMissingAndBlankMutationIDsWithoutWrites() throws {
        let start = Date(timeIntervalSince1970: 4_500)
        let draft = EventDraft(title: "Changed", start: start, end: start.addingTimeInterval(120), isAllDay: false, calendarID: nil)
        for mutationID in [String?.none, .some(""), .some("   ")] {
            let event = CalendarEventSnapshot(id: "display", mutationID: mutationID, title: "Original", start: start, end: start.addingTimeInterval(60), isAllDay: false, calendarID: "home", calendarTitle: "Home", allowsModification: true, hasRecurrence: false)
            let subject = FakeCalendarService(access: .granted, events: [event])

            XCTAssertThrowsError(try subject.updateEvent(id: "display", draft: draft, scope: .thisOccurrence))
            XCTAssertThrowsError(try subject.deleteEvent(id: "display", scope: .thisOccurrence))
            XCTAssertEqual(subject.events, [event])
            XCTAssertTrue(subject.eventUpdateCalls.isEmpty)
            XCTAssertTrue(subject.eventDeleteCalls.isEmpty)
            XCTAssertEqual(subject.successfulWriteCount, 0)
        }
    }

    func testFakeCalendarReturnsViewOnlyDetailByDisplayIDButNeverMutatesIt() throws {
        let start = Date(timeIntervalSince1970: 4_600)
        let viewOnly = CalendarEventSnapshot(id: "display-only", mutationID: nil, title: "View only", start: start, end: start.addingTimeInterval(60), isAllDay: false, calendarID: "shared", calendarTitle: "Shared", allowsModification: false, hasRecurrence: false)
        let draft = EventDraft(title: "Changed", start: start, end: start.addingTimeInterval(120), isAllDay: false, calendarID: nil)
        let subject = FakeCalendarService(access: .granted, events: [viewOnly])

        XCTAssertEqual(subject.event(id: "display-only"), viewOnly)
        XCTAssertThrowsError(try subject.updateEvent(id: "display-only", draft: draft, scope: .thisOccurrence))
        XCTAssertThrowsError(try subject.deleteEvent(id: "display-only", scope: .thisOccurrence))
        XCTAssertEqual(subject.events, [viewOnly])
        XCTAssertTrue(subject.eventUpdateCalls.isEmpty)
        XCTAssertTrue(subject.eventDeleteCalls.isEmpty)
        XCTAssertEqual(subject.successfulWriteCount, 0)
    }

    func testFakeReminderSuccessfulUpdateAndDeleteRecordExactlyOnceAfterRetry() throws {
        let original = reminder(id: "opaque-reminder", listID: "tasks")
        let draft = ReminderDraft(title: "Changed", notes: "N", dueDate: nil, priority: 1)
        let subject = FakeRemindersService(access: .granted, reminders: [original])
        subject.updateError = FakeMutationError.failed

        XCTAssertThrowsError(try subject.updateReminder(id: "opaque-reminder", draft: draft))
        XCTAssertTrue(subject.reminderUpdateCalls.isEmpty)
        subject.updateError = nil
        try subject.updateReminder(id: "opaque-reminder", draft: draft)
        XCTAssertEqual(subject.reminderUpdateCalls, [.init(id: "opaque-reminder", draft: draft)])

        subject.deleteError = FakeMutationError.failed
        XCTAssertThrowsError(try subject.deleteReminder(id: "opaque-reminder"))
        XCTAssertTrue(subject.reminderDeleteCalls.isEmpty)
        subject.deleteError = nil
        try subject.deleteReminder(id: "opaque-reminder")
        XCTAssertEqual(subject.reminderDeleteCalls, ["opaque-reminder"])
    }

    func testFakeCreatesUseInjectedAuthoritativeDefaultsInsteadOfDescriptorOrder() throws {
        let start = Date(timeIntervalSince1970: 5_000)
        let calendars = [
            CalendarDescriptor(id: "first", title: "First", colorHex: "#000000", allowsContentModifications: true),
            CalendarDescriptor(id: "authoritative", title: "Authoritative", colorHex: "#111111", allowsContentModifications: true)
        ]
        let calendar = FakeCalendarService(access: .granted, descriptors: calendars, defaultCalendarID: "authoritative")
        let eventID = try XCTUnwrap(try calendar.createEvent(.init(title: "Event", start: start, end: start.addingTimeInterval(60), isAllDay: false, calendarID: nil)))
        XCTAssertEqual(calendar.event(id: eventID)?.calendarID, "authoritative")

        let lists = [
            ReminderListDescriptor(id: "first", title: "First", colorHex: "#000000", allowsContentModifications: true),
            ReminderListDescriptor(id: "authoritative", title: "Authoritative", colorHex: "#111111", allowsContentModifications: true)
        ]
        let reminders = FakeRemindersService(access: .granted, descriptors: lists, defaultListID: "authoritative")
        let reminderID = try XCTUnwrap(try reminders.createReminder(.init(title: "Task", notes: nil, dueDate: nil, priority: 0)))
        XCTAssertEqual(reminders.reminder(id: reminderID)?.listID, "authoritative")
    }

    func testFakeCreateRejectsAbsentMissingAndReadOnlyAuthoritativeDefaultsAtomically() throws {
        let start = Date(timeIntervalSince1970: 5_500)
        let eventDraft = EventDraft(title: "Event", start: start, end: start.addingTimeInterval(60), isAllDay: false, calendarID: nil)
        let reminderDraft = ReminderDraft(title: "Task", notes: nil, dueDate: nil, priority: 0)
        let eventDescriptors = [CalendarDescriptor(id: "locked", title: "Locked", colorHex: "#000000", allowsContentModifications: false)]
        let reminderDescriptors = [ReminderListDescriptor(id: "locked", title: "Locked", colorHex: "#000000", allowsContentModifications: false)]

        for defaultID in [String?.none, .some("missing"), .some("locked")] {
            let calendar = FakeCalendarService(access: .granted, descriptors: eventDescriptors, defaultCalendarID: defaultID)
            XCTAssertThrowsError(try calendar.createEvent(eventDraft))
            XCTAssertTrue(calendar.events.isEmpty)
            XCTAssertTrue(calendar.createdDrafts.isEmpty)
            XCTAssertEqual(calendar.successfulWriteCount, 0)

            let reminders = FakeRemindersService(access: .granted, descriptors: reminderDescriptors, defaultListID: defaultID)
            XCTAssertThrowsError(try reminders.createReminder(reminderDraft))
            XCTAssertTrue(reminders.reminders.isEmpty)
            XCTAssertTrue(reminders.createdDrafts.isEmpty)
            XCTAssertEqual(reminders.successfulWriteCount, 0)
        }
    }

    func testFakeDeniedAndRestrictedReadsReturnNoMetadataContentOrDetail() async throws {
        let start = Date(timeIntervalSince1970: 6_000)
        let interval = DateInterval(start: start.addingTimeInterval(-1), end: start.addingTimeInterval(61))
        for access in [AccessState.denied, .restricted] {
            let event = CalendarEventSnapshot(id: "display", mutationID: "opaque", title: "Event", start: start, end: start.addingTimeInterval(60), isAllDay: false, calendarID: "home", calendarTitle: "Home", allowsModification: true, hasRecurrence: false)
            let calendar = FakeCalendarService(access: access, events: [event], descriptors: [.init(id: "home", title: "Home", colorHex: "#000000", allowsContentModifications: true)])
            XCTAssertEqual(calendar.calendars(), [])
            XCTAssertEqual(try calendar.fetchEvents(in: interval, calendarIDs: []), [])
            XCTAssertNil(calendar.event(id: "opaque"))

            let item = reminder(id: "task", listID: "tasks")
            let reminders = FakeRemindersService(access: access, reminders: [item], descriptors: [.init(id: "tasks", title: "Tasks", colorHex: "#000000", allowsContentModifications: true)])
            let fetchedReminders = try await reminders.fetchReminders(listIDs: [])
            XCTAssertEqual(reminders.lists(), [])
            XCTAssertEqual(fetchedReminders, [])
            XCTAssertNil(reminders.reminder(id: "task"))
        }
    }

    private func event(id: String, calendarID: String) -> CalendarEventSnapshot {
        .init(id: id, title: id, start: Date(timeIntervalSince1970: 10), end: Date(timeIntervalSince1970: 20), isAllDay: false, calendarID: calendarID, calendarTitle: calendarID, allowsModification: true, hasRecurrence: false)
    }

    private func reminder(id: String, listID: String) -> ReminderSnapshot {
        .init(id: id, title: id, notes: nil, dueDate: nil, dueHasTime: false, priority: 0, listID: listID, listTitle: listID, isCompleted: false, allowsModification: true, hasRecurrence: false)
    }
}

private enum FakeMutationError: Error { case failed }
