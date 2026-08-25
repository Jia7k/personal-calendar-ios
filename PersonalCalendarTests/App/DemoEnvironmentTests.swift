import SwiftData
import XCTest
@testable import PersonalCalendar

@MainActor
final class DemoEnvironmentTests: XCTestCase {
    func testReduceMotionOverrideRequiresExplicitDemoArgument() {
        XCTAssertFalse(AppEnvironment.live(container: makeContainer()).reduceMotionOverride)
        XCTAssertFalse(AppEnvironment.demo(container: makeContainer(), arguments: []).reduceMotionOverride)
        XCTAssertTrue(AppEnvironment.demo(container: makeContainer(), arguments: ["-reduce-motion"]).reduceMotionOverride)
    }

    func testDemoSkipsOnboardingUnlessExplicitlyRequested() {
        XCTAssertTrue(AppEnvironment.demo(container: makeContainer(), arguments: []).settings.didCompleteOnboarding)
        XCTAssertFalse(AppEnvironment.demo(container: makeContainer(), arguments: ["-show-onboarding"]).settings.didCompleteOnboarding)
    }

    func testFixedQuickEntryContextUsesStableSingaporeDateAndTimeZone() {
        let environment = AppEnvironment.demo(
            container: makeContainer(),
            arguments: ["-quick-entry-fixed-context"]
        )

        let first = environment.quickEntryContext()
        let second = environment.quickEntryContext()
        let components = first.calendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: first.now
        )

        XCTAssertEqual(first.now, second.now)
        XCTAssertEqual(first.timeZone.identifier, "Asia/Singapore")
        XCTAssertEqual(first.locale.identifier, "en_SG")
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 8)
        XCTAssertEqual(components.day, 25)
        XCTAssertEqual(components.hour, 12)
        XCTAssertEqual(components.minute, 0)
    }

    func testCalendarDenialLeavesDemoRemindersAndRoutinesUsable() async throws {
        let environment = AppEnvironment.demo(container: makeContainer(), arguments: ["-calendar-denied"])
        let day = LocalDay(year: 2026, month: 8, day: 24)
        let interval = DateInterval(start: day.startDate(in: .current), end: day.startDate(in: .current).addingTimeInterval(86_400))

        let reminders = try await environment.reminders.fetchReminders(listIDs: [])
        XCTAssertEqual(try environment.calendar.fetchEvents(in: interval, calendarIDs: []), [])
        XCTAssertEqual(reminders.map(\.id), ["demo-task"])
        XCTAssertEqual(try environment.routines.list(includeArchived: false).map(\.title), ["Read"])
    }

    func testDemoSourcesFilterSelectedIDsAndTreatEmptySelectionAsAll() async throws {
        let environment = AppEnvironment.demo(container: makeContainer(), arguments: [])
        let now = Date()
        let interval = DateInterval(start: now.addingTimeInterval(-86_400), end: now.addingTimeInterval(86_400))

        let missingReminders = try await environment.reminders.fetchReminders(listIDs: ["missing"])
        let allReminders = try await environment.reminders.fetchReminders(listIDs: [])
        XCTAssertEqual(try environment.calendar.fetchEvents(in: interval, calendarIDs: ["missing"]), [])
        XCTAssertEqual(try environment.calendar.fetchEvents(in: interval, calendarIDs: []).map(\.id), ["demo-event"])
        XCTAssertEqual(missingReminders, [])
        XCTAssertEqual(allReminders.map(\.id), ["demo-task"])
    }

    func testMultiSourceDemoKeepsOtherCalendarContentWhenOneSourceIsHidden() throws {
        let subject = DemoCalendarService(access: .granted, multipleSources: true)
        let now = Date()
        let interval = DateInterval(start: now.addingTimeInterval(-86_400), end: now.addingTimeInterval(86_400))

        XCTAssertEqual(subject.calendars().map(\.id), ["demo-calendar", "demo-calendar-work"])
        XCTAssertEqual(try subject.fetchEvents(in: interval, calendarIDs: ["demo-calendar-work"]).map(\.title), ["Planning"])
        XCTAssertEqual(try subject.fetchEvents(in: interval, calendarIDs: ["demo-calendar"]).map(\.title), ["Coffee"])
    }

    func testMultiSourceDemoEnvironmentIncludesAlternateReminderList() {
        let environment = AppEnvironment.demo(container: makeContainer(), arguments: ["-demo-multiple-sources"])

        XCTAssertEqual(environment.reminders.lists().map(\.id), ["demo-list", "demo-list-alternate"])
    }

    func testDeniedAndRestrictedDemoRequestsAndMutationsDoNotGrantOrChangeContent() async throws {
        for access in [AccessState.denied, .restricted] {
            let calendar = DemoCalendarService(access: access)
            let reminders = DemoRemindersService(access: access)
            let interval = DateInterval(start: .distantPast, end: .distantFuture)
            let calendarResult = await calendar.requestFullAccess()
            let reminderResult = await reminders.requestFullAccess()
            XCTAssertEqual(calendarResult, access)
            XCTAssertEqual(reminderResult, access)
            XCTAssertThrowsError(try calendar.createEvent(.init(title: "No", start: .now, end: .now.addingTimeInterval(60), isAllDay: false, calendarID: nil)))
            XCTAssertThrowsError(try reminders.createReminder(.init(title: "No", notes: nil, dueDate: nil, priority: 0)))
            XCTAssertThrowsError(try reminders.setCompleted(id: "demo-task", completed: true))
            let values = try await reminders.fetchReminders(listIDs: [])
            XCTAssertEqual(calendar.calendars(), [])
            XCTAssertEqual(try calendar.fetchEvents(in: interval, calendarIDs: []), [])
            XCTAssertNil(calendar.event(id: "demo-event"))
            XCTAssertEqual(reminders.lists(), [])
            XCTAssertEqual(values, [])
            XCTAssertNil(reminders.reminder(id: "demo-task"))
        }
    }

    func testDemoEventCreationPersistsInFetchedEvents() throws {
        let subject = DemoCalendarService(access: .granted)
        let start = Date(timeIntervalSince1970: 10_000)
        let id = try XCTUnwrap(try subject.createEvent(.init(title: "Walk", start: start, end: start.addingTimeInterval(1_800), isAllDay: false, calendarID: nil)))

        let fetched = try subject.fetchEvents(in: DateInterval(start: start.addingTimeInterval(-1), end: start.addingTimeInterval(1_801)), calendarIDs: [])
        XCTAssertEqual(id, "demo-event-2")
        XCTAssertEqual(fetched.map(\.id), ["demo-event-2"])
        XCTAssertEqual(fetched.first?.title, "Walk")
        XCTAssertEqual(fetched.first?.calendarID, "demo-calendar")
        XCTAssertEqual(fetched.first?.calendarTitle, "Personal")
        XCTAssertEqual(fetched.first?.mutationID, id)
    }

    func testDemoEditableEventsAreAddressableAndMutationTitlesAreTrimmed() throws {
        let subject = DemoCalendarService(access: .granted, multipleSources: true)
        XCTAssertEqual(subject.event(id: "demo-event")?.mutationID, "demo-event")
        XCTAssertEqual(subject.event(id: "demo-event-work")?.mutationID, "demo-event-work")
        let start = Date(timeIntervalSince1970: 40_000)

        let id = try XCTUnwrap(try subject.createEvent(.init(title: "  Walk  ", start: start, end: start.addingTimeInterval(60), isAllDay: false, calendarID: nil)))
        XCTAssertEqual(subject.event(id: id)?.mutationID, id)
        XCTAssertEqual(subject.event(id: id)?.title, "Walk")
        try subject.updateEvent(id: id, draft: .init(title: "  Run  ", start: start, end: start.addingTimeInterval(120), isAllDay: false, calendarID: nil), scope: .thisOccurrence)
        XCTAssertEqual(subject.event(id: id)?.title, "Run")
    }

    func testDemoEventCreationUsesExactWritableDestinationAndRejectsInvalidIDs() throws {
        let subject = DemoCalendarService(access: .granted, multipleSources: true, includeReadOnlySource: true)
        let start = Date(timeIntervalSince1970: 20_000)

        let id = try XCTUnwrap(try subject.createEvent(.init(title: "Work", start: start, end: start.addingTimeInterval(600), isAllDay: false, calendarID: "demo-calendar-work")))

        let fetched = try subject.fetchEvents(in: DateInterval(start: start.addingTimeInterval(-1), end: start.addingTimeInterval(601)), calendarIDs: ["demo-calendar-work"])
        XCTAssertEqual(fetched.first(where: { $0.id == id })?.calendarID, "demo-calendar-work")
        XCTAssertEqual(fetched.first(where: { $0.id == id })?.calendarTitle, "Work")
        XCTAssertThrowsError(try subject.createEvent(.init(title: "Missing", start: start, end: start.addingTimeInterval(60), isAllDay: false, calendarID: "missing"))) { XCTAssertEqual($0 as? DraftValidationError, .invalidDestination) }
        XCTAssertThrowsError(try subject.createEvent(.init(title: "Read only", start: start, end: start.addingTimeInterval(60), isAllDay: false, calendarID: "demo-calendar-read-only"))) { XCTAssertEqual($0 as? DraftValidationError, .readOnlyDestination) }
    }

    func testDemoReminderCreationAndCompletionPersistInFetchedReminders() async throws {
        let subject = DemoRemindersService(access: .granted)
        let id = try XCTUnwrap(try subject.createReminder(.init(title: "Call", notes: "Mom", dueDate: nil, priority: 1)))
        try subject.setCompleted(id: id, completed: true)

        let fetched = try await subject.fetchReminders(listIDs: [])
        XCTAssertEqual(fetched.map(\.id), ["demo-task", "demo-task-2"])
        XCTAssertEqual(fetched.first(where: { $0.id == id })?.title, "Call")
        XCTAssertEqual(fetched.first(where: { $0.id == id })?.isCompleted, true)
        XCTAssertEqual(fetched.first(where: { $0.id == id })?.listID, "demo-list")
        XCTAssertEqual(fetched.first(where: { $0.id == id })?.listTitle, "Tasks")
    }

    func testDemoReminderCreationUsesExactWritableDestinationAndRejectsInvalidIDs() async throws {
        let subject = DemoRemindersService(access: .granted, multipleSources: true, includeReadOnlySource: true)

        let id = try XCTUnwrap(try subject.createReminder(.init(title: "Alternate", notes: nil, dueDate: nil, priority: 1, listID: "demo-list-alternate")))

        let fetched = try await subject.fetchReminders(listIDs: ["demo-list-alternate"])
        XCTAssertEqual(fetched.first(where: { $0.id == id })?.listID, "demo-list-alternate")
        XCTAssertEqual(fetched.first(where: { $0.id == id })?.listTitle, "Alternate")
        XCTAssertThrowsError(try subject.createReminder(.init(title: "Missing", notes: nil, dueDate: nil, priority: 1, listID: "missing"))) { XCTAssertEqual($0 as? DraftValidationError, .invalidDestination) }
        XCTAssertThrowsError(try subject.createReminder(.init(title: "Read only", notes: nil, dueDate: nil, priority: 1, listID: "demo-list-read-only"))) { XCTAssertEqual($0 as? DraftValidationError, .readOnlyDestination) }
    }

    func testDemoReminderCreateRejectsSchedulePreservationWithoutCurrentValueAtomically() throws {
        let subject = DemoRemindersService(access: .granted)
        var draft = ReminderDraft(title: "Task", notes: nil, dueDate: nil, priority: 0)
        draft.schedule = .preserve(current: nil)

        XCTAssertThrowsError(try subject.createReminder(draft))
        XCTAssertNil(subject.reminder(id: "demo-task-2"))
        XCTAssertEqual(subject.successfulWriteCount, 0)
    }

    func testDemoCalendarReturnsViewOnlyDetailByDisplayIDButNeverMutatesIt() throws {
        let subject = DemoCalendarService(access: .granted, includeReadOnlySource: true)
        let viewOnly = try XCTUnwrap(subject.event(id: "demo-event-nonaddressable"))
        let draft = EventDraft(title: "Changed", start: viewOnly.start, end: viewOnly.end.addingTimeInterval(60), isAllDay: viewOnly.isAllDay, calendarID: nil)

        XCTAssertNil(viewOnly.mutationID)
        XCTAssertFalse(viewOnly.allowsModification)
        XCTAssertEqual(subject.event(id: viewOnly.id), viewOnly)
        XCTAssertThrowsError(try subject.updateEvent(id: viewOnly.id, draft: draft, scope: .thisOccurrence))
        XCTAssertThrowsError(try subject.deleteEvent(id: viewOnly.id, scope: .thisOccurrence))
        XCTAssertEqual(subject.event(id: viewOnly.id), viewOnly)
        XCTAssertEqual(subject.successfulWriteCount, 0)
    }

    func testDemoEditorFixturesSeparateReadOnlyAndNonaddressableEvents() throws {
        let environment = AppEnvironment.demo(
            container: makeContainer(),
            arguments: ["-demo-editor-read-only"]
        )

        let readOnly = try XCTUnwrap(environment.calendar.event(id: "demo-event-read-only"))
        let nonaddressable = try XCTUnwrap(environment.calendar.event(id: "demo-event-nonaddressable"))

        XCTAssertEqual(readOnly.mutationID, "demo-event-read-only")
        XCTAssertFalse(readOnly.allowsModification)
        XCTAssertNil(nonaddressable.mutationID)
        XCTAssertFalse(nonaddressable.allowsModification)
        XCTAssertNotEqual(readOnly.id, nonaddressable.id)
    }

    func testDemoUnsupportedEditorFixturesPreserveProviderValuesOnTitleOnlyEdit() throws {
        let environment = AppEnvironment.demo(
            container: makeContainer(),
            arguments: ["-demo-editor-unsupported"]
        )
        let event = try XCTUnwrap(environment.calendar.event(id: "demo-event-unsupported"))
        let eventMutationID = try XCTUnwrap(event.mutationID)
        let reminder = try XCTUnwrap(environment.reminders.reminder(id: "demo-task-unsupported"))

        XCTAssertEqual(event.alarms, .unsupported(summary: "Provider-defined alerts"))
        XCTAssertEqual(event.recurrence, .unsupported(summary: "Provider-defined repeat"))
        XCTAssertEqual(reminder.alarm, .unsupported(summary: "Provider-defined alert"))
        XCTAssertEqual(reminder.recurrence, .unsupported(summary: "Provider-defined repeat"))

        try environment.calendar.updateEvent(
            id: eventMutationID,
            draft: .init(
                title: "Renamed provider event",
                start: event.start,
                end: event.end,
                isAllDay: event.isAllDay,
                calendarID: nil,
                notes: event.notes,
                location: event.location,
                url: event.url
            ),
            scope: .thisOccurrence
        )
        var reminderDraft = ReminderDraft(
            title: "Renamed provider task",
            notes: reminder.notes,
            dueDate: reminder.dueDate,
            dueHasTime: reminder.dueHasTime,
            priority: reminder.priority,
            listID: nil
        )
        reminderDraft.schedule = .preserve(
            current: reminder.dueDate.map { .init(date: $0, hasTime: reminder.dueHasTime) }
        )
        try environment.reminders.updateReminder(id: reminder.id, draft: reminderDraft)

        let savedEvent = try XCTUnwrap(environment.calendar.event(id: event.id))
        let savedReminder = try XCTUnwrap(environment.reminders.reminder(id: reminder.id))
        XCTAssertEqual(savedEvent.title, "Renamed provider event")
        XCTAssertEqual(savedEvent.alarms, event.alarms)
        XCTAssertEqual(savedEvent.recurrence, event.recurrence)
        XCTAssertEqual(savedReminder.title, "Renamed provider task")
        XCTAssertEqual(savedReminder.alarm, reminder.alarm)
        XCTAssertEqual(savedReminder.recurrence, reminder.recurrence)
    }

    func testDemoReminderUpdatePreservesScheduleAndAppliesAlarmAndRecurrence() throws {
        let subject = DemoRemindersService(access: .granted)
        let due = Date(timeIntervalSince1970: 20_000)
        let rule = RecurrenceRuleDraft(frequency: .daily, interval: 1, weekdays: [], endDate: nil)
        let id = try XCTUnwrap(try subject.createReminder(.init(title: "Original", notes: nil, dueDate: due, dueHasTime: true, priority: 1, recurrence: .replace(rule))))
        var edit = ReminderDraft(title: "Changed", notes: "Keep time", dueDate: nil, priority: 9, alarm: .replace(Date(timeIntervalSince1970: 19_000)))
        edit.schedule = .preserve(current: .init(date: due, hasTime: true))

        try subject.updateReminder(id: id, draft: edit)

        XCTAssertEqual(subject.reminder(id: id)?.dueDate, due)
        XCTAssertEqual(subject.reminder(id: id)?.alarm, .editable(Date(timeIntervalSince1970: 19_000)))
        XCTAssertEqual(subject.reminder(id: id)?.recurrence, .editable(rule))
    }

    func testDemoEventUpdateFailureIsAtomic() throws {
        let subject = DemoCalendarService(access: .granted, failFirstUpdate: true)
        let original = try XCTUnwrap(subject.event(id: "demo-event"))
        let draft = EventDraft(title: "Changed", start: original.start, end: original.end.addingTimeInterval(60), isAllDay: false, calendarID: nil, notes: "new")

        XCTAssertThrowsError(try subject.updateEvent(id: original.id, draft: draft, scope: .thisOccurrence))
        XCTAssertEqual(subject.event(id: original.id), original)
        XCTAssertEqual(subject.successfulWriteCount, 0)
        try subject.updateEvent(id: original.id, draft: draft, scope: .thisOccurrence)
        XCTAssertEqual(subject.event(id: original.id)?.title, "Changed")
        XCTAssertEqual(subject.successfulWriteCount, 1)
    }

    func testDemoReminderDeleteFailureIsAtomic() throws {
        let subject = DemoRemindersService(access: .granted, failFirstDelete: true)
        let original = try XCTUnwrap(subject.reminder(id: "demo-task"))

        XCTAssertThrowsError(try subject.deleteReminder(id: original.id))
        XCTAssertEqual(subject.reminder(id: original.id), original)
        XCTAssertEqual(subject.successfulWriteCount, 0)
        try subject.deleteReminder(id: original.id)
        XCTAssertNil(subject.reminder(id: original.id))
        XCTAssertEqual(subject.successfulWriteCount, 1)
    }

    func testDemoCreateFailuresAreAtomicAndRetryOnceForBothItemTypes() throws {
        let start = Date(timeIntervalSince1970: 50_000)
        let calendar = DemoCalendarService(access: .granted, failFirstCreate: true)
        XCTAssertThrowsError(try calendar.createEvent(.init(title: "  Event  ", start: start, end: start.addingTimeInterval(60), isAllDay: false, calendarID: nil)))
        XCTAssertEqual(calendar.events.map(\.id), ["demo-event"])
        XCTAssertEqual(calendar.successfulWriteCount, 0)
        let eventID = try XCTUnwrap(try calendar.createEvent(.init(title: "  Event  ", start: start, end: start.addingTimeInterval(60), isAllDay: false, calendarID: nil)))
        XCTAssertEqual(calendar.event(id: eventID)?.title, "Event")
        XCTAssertEqual(calendar.successfulWriteCount, 1)

        let reminders = DemoRemindersService(access: .granted, failFirstCreate: true)
        XCTAssertThrowsError(try reminders.createReminder(.init(title: "  Task  ", notes: nil, dueDate: nil, priority: 0)))
        XCTAssertNil(reminders.reminder(id: "demo-task-2"))
        XCTAssertEqual(reminders.successfulWriteCount, 0)
        let reminderID = try XCTUnwrap(try reminders.createReminder(.init(title: "  Task  ", notes: nil, dueDate: nil, priority: 0)))
        XCTAssertEqual(reminders.reminder(id: reminderID)?.title, "Task")
        XCTAssertEqual(reminders.successfulWriteCount, 1)
    }

    func testDemoReminderUpdateFailureIsAtomicAndRetryTrimsTitle() throws {
        let subject = DemoRemindersService(access: .granted, failFirstUpdate: true)
        let original = try XCTUnwrap(subject.reminder(id: "demo-task"))
        let draft = ReminderDraft(title: "  Updated  ", notes: "N", dueDate: original.dueDate, dueHasTime: original.dueHasTime, priority: 1)

        XCTAssertThrowsError(try subject.updateReminder(id: original.id, draft: draft))
        XCTAssertEqual(subject.reminder(id: original.id), original)
        XCTAssertEqual(subject.successfulWriteCount, 0)
        try subject.updateReminder(id: original.id, draft: draft)
        XCTAssertEqual(subject.reminder(id: original.id)?.title, "Updated")
        XCTAssertEqual(subject.successfulWriteCount, 1)
    }

    func testDemoEventDeleteFailureIsAtomicAndRetrySucceeds() throws {
        let subject = DemoCalendarService(access: .granted, failFirstDelete: true)
        let original = try XCTUnwrap(subject.event(id: "demo-event"))

        XCTAssertThrowsError(try subject.deleteEvent(id: original.id, scope: .thisOccurrence))
        XCTAssertEqual(subject.event(id: original.id), original)
        XCTAssertEqual(subject.successfulWriteCount, 0)
        try subject.deleteEvent(id: original.id, scope: .thisOccurrence)
        XCTAssertNil(subject.event(id: original.id))
        XCTAssertEqual(subject.successfulWriteCount, 1)
    }

    func testDemoEventPreserveClearAndReplaceIntentsRoundTrip() throws {
        let subject = DemoCalendarService(access: .granted)
        let start = Date(timeIntervalSince1970: 60_000)
        let oldRule = RecurrenceRuleDraft(frequency: .daily, interval: 1, weekdays: [], endDate: nil)
        let newRule = RecurrenceRuleDraft(frequency: .weekly, interval: 1, weekdays: [2], endDate: nil)
        let id = try XCTUnwrap(try subject.createEvent(.init(title: "Event", start: start, end: start.addingTimeInterval(60), isAllDay: false, calendarID: nil, alarms: .replace([-60]), recurrence: .replace(oldRule))))

        try subject.updateEvent(id: id, draft: .init(title: "Preserve", start: start, end: start.addingTimeInterval(60), isAllDay: false, calendarID: nil), scope: .thisOccurrence)
        XCTAssertEqual(subject.event(id: id)?.alarms, .editable([-60]))
        XCTAssertEqual(subject.event(id: id)?.recurrence, .editable(oldRule))
        try subject.updateEvent(id: id, draft: .init(title: "Clear", start: start, end: start.addingTimeInterval(60), isAllDay: false, calendarID: nil, alarms: .clear, recurrence: .clear), scope: .futureOccurrences)
        XCTAssertEqual(subject.event(id: id)?.alarms, .some(EventAlarmSnapshot.none))
        XCTAssertEqual(subject.event(id: id)?.recurrence, .some(RecurrenceSnapshot.none))
        try subject.updateEvent(id: id, draft: .init(title: "Replace", start: start, end: start.addingTimeInterval(60), isAllDay: false, calendarID: nil, alarms: .replace([-120]), recurrence: .replace(newRule)), scope: .thisOccurrence)
        XCTAssertEqual(subject.event(id: id)?.alarms, .editable([-120]))
        XCTAssertEqual(subject.event(id: id)?.recurrence, .editable(newRule))
    }

    func testDemoRecurringReminderIsOneStoredSnapshotAndClearScheduleIsRejected() async throws {
        let subject = DemoRemindersService(access: .granted)
        let due = Date(timeIntervalSince1970: 30_000)
        let rule = RecurrenceRuleDraft(frequency: .weekly, interval: 1, weekdays: [2], endDate: nil)
        let id = try XCTUnwrap(try subject.createReminder(.init(title: "Weekly", notes: nil, dueDate: due, dueHasTime: true, priority: 1, recurrence: .replace(rule))))
        let original = try XCTUnwrap(subject.reminder(id: id))
        var clear = ReminderDraft(title: "Weekly", notes: nil, dueDate: nil, priority: 1)
        clear.schedule = .clear

        let fetched = try await subject.fetchReminders(listIDs: [])
        XCTAssertEqual(fetched.filter { $0.id == id }, [original])
        XCTAssertThrowsError(try subject.updateReminder(id: id, draft: clear))
        XCTAssertEqual(subject.reminder(id: id), original)
    }

    func testDemoReminderClearAndReplaceAlarmAndRecurrenceRoundTrip() throws {
        let subject = DemoRemindersService(access: .granted)
        let due = Date(timeIntervalSince1970: 70_000)
        let oldRule = RecurrenceRuleDraft(frequency: .daily, interval: 1, weekdays: [], endDate: nil)
        let newRule = RecurrenceRuleDraft(frequency: .weekly, interval: 1, weekdays: [2], endDate: nil)
        let id = try XCTUnwrap(try subject.createReminder(.init(title: "Task", notes: nil, dueDate: due, dueHasTime: true, priority: 1, alarm: .replace(Date(timeIntervalSince1970: 69_000)), recurrence: .replace(oldRule))))

        try subject.updateReminder(id: id, draft: .init(title: "Replace", notes: nil, dueDate: due, dueHasTime: true, priority: 1, alarm: .replace(Date(timeIntervalSince1970: 68_000)), recurrence: .replace(newRule)))
        XCTAssertEqual(subject.reminder(id: id)?.alarm, .editable(Date(timeIntervalSince1970: 68_000)))
        XCTAssertEqual(subject.reminder(id: id)?.recurrence, .editable(newRule))
        var clear = ReminderDraft(title: "Clear", notes: nil, dueDate: nil, priority: 1, alarm: .clear, recurrence: .clear)
        clear.schedule = .preserve(current: .init(date: due, hasTime: true))
        try subject.updateReminder(id: id, draft: clear)
        XCTAssertEqual(subject.reminder(id: id)?.alarm, .some(ReminderAlarmSnapshot.none))
        XCTAssertEqual(subject.reminder(id: id)?.recurrence, .some(RecurrenceSnapshot.none))
    }

    func testDemoEnvironmentRoutesEventUpdateAndDeleteFailOnceArguments() throws {
        let updateEnvironment = AppEnvironment.demo(container: makeContainer(), arguments: ["-event-update-fails-once"])
        let original = try XCTUnwrap(updateEnvironment.calendar.event(id: "demo-event"))
        let mutationID = try XCTUnwrap(original.mutationID)
        let draft = EventDraft(title: "Updated", start: original.start, end: original.end.addingTimeInterval(60), isAllDay: original.isAllDay, calendarID: nil)
        XCTAssertThrowsError(try updateEnvironment.calendar.updateEvent(id: mutationID, draft: draft, scope: .thisOccurrence))
        try updateEnvironment.calendar.updateEvent(id: mutationID, draft: draft, scope: .thisOccurrence)
        XCTAssertEqual(updateEnvironment.calendar.event(id: mutationID)?.title, "Updated")

        let deleteEnvironment = AppEnvironment.demo(container: makeContainer(), arguments: ["-event-delete-fails-once"])
        let deleteItem = try XCTUnwrap(deleteEnvironment.calendar.event(id: "demo-event"))
        let deleteID = try XCTUnwrap(deleteItem.mutationID)
        XCTAssertThrowsError(try deleteEnvironment.calendar.deleteEvent(id: deleteID, scope: .thisOccurrence))
        try deleteEnvironment.calendar.deleteEvent(id: deleteID, scope: .thisOccurrence)
        XCTAssertNil(deleteEnvironment.calendar.event(id: deleteID))
    }

    func testDemoEnvironmentRoutesReminderUpdateAndDeleteFailOnceArguments() throws {
        let updateEnvironment = AppEnvironment.demo(container: makeContainer(), arguments: ["-task-update-fails-once"])
        let original = try XCTUnwrap(updateEnvironment.reminders.reminder(id: "demo-task"))
        let draft = ReminderDraft(title: "Updated", notes: original.notes, dueDate: original.dueDate, dueHasTime: original.dueHasTime, priority: original.priority)
        XCTAssertThrowsError(try updateEnvironment.reminders.updateReminder(id: original.id, draft: draft))
        try updateEnvironment.reminders.updateReminder(id: original.id, draft: draft)
        XCTAssertEqual(updateEnvironment.reminders.reminder(id: original.id)?.title, "Updated")

        let deleteEnvironment = AppEnvironment.demo(container: makeContainer(), arguments: ["-task-delete-fails-once"])
        XCTAssertNotNil(deleteEnvironment.reminders.reminder(id: "demo-task"))
        XCTAssertThrowsError(try deleteEnvironment.reminders.deleteReminder(id: "demo-task"))
        try deleteEnvironment.reminders.deleteReminder(id: "demo-task")
        XCTAssertNil(deleteEnvironment.reminders.reminder(id: "demo-task"))
    }

    func testDemoRoutineMutationsPersist() throws {
        let subject = DemoRoutineRepository()
        let id = try subject.create(.init(title: "Stretch", weekdays: [1], window: .morning, reminderHour: 8, reminderMinute: 0))
        let day = LocalDay(year: 2026, month: 8, day: 24)
        try subject.setPaused(id: id, paused: true)
        try subject.setCompleted(routineID: id, day: day, completed: true)

        XCTAssertEqual(try subject.list(includeArchived: false).first(where: { $0.id == id })?.isPaused, true)
        XCTAssertTrue(try subject.isCompleted(routineID: id, day: day))
    }

    private func makeContainer() -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try! ModelContainer(for: RoutineRecord.self, RoutineCompletionRecord.self, configurations: configuration)
    }
}
