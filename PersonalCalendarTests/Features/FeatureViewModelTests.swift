import XCTest
@testable import PersonalCalendar

@MainActor
final class FeatureViewModelTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return value
    }

    func testTodayKeepsDatedTaskAndRoutineWhenCalendarIsDenied() async {
        let due = calendar.date(from: DateComponents(year: 2026, month: 8, day: 24, hour: 9))!
        let reminder = ReminderSnapshot(id: "opaque|task", title: "Pay rent", notes: nil, dueDate: due, dueHasTime: true, priority: 9, listID: "tasks", listTitle: "Tasks", isCompleted: false, allowsModification: true, hasRecurrence: false)
        let subject = TodayViewModel(calendar: FakeCalendarService(access: .denied), reminders: FakeRemindersService(access: .granted, reminders: [reminder]), routines: FakeRoutineRepository(routines: [.sampleRoutine]), composer: AgendaComposer(), settings: AppSettingsStore(defaults: .ephemeral), calendarProvider: { self.calendar }, now: { due })

        await subject.load()

        XCTAssertEqual(subject.agenda.scheduled.map(\.title), ["Pay rent", "Read"])
        XCTAssertTrue(subject.showsCalendarPermissionCard)
    }

    func testTodayExcludesUndatedReminderAndCompletesOpaqueRawIdentifier() async {
        let due = calendar.date(from: DateComponents(year: 2026, month: 8, day: 24, hour: 9))!
        let opaque = ReminderSnapshot(id: "list|opaque|id", title: "Due", notes: nil, dueDate: due, dueHasTime: true, priority: 1, listID: "one", listTitle: "One", isCompleted: false, allowsModification: true, hasRecurrence: false)
        let undated = ReminderSnapshot(id: "undated", title: "Inbox", notes: nil, dueDate: nil, dueHasTime: false, priority: 9, listID: "one", listTitle: "One", isCompleted: false, allowsModification: true, hasRecurrence: false)
        let reminders = FakeRemindersService(access: .granted, reminders: [opaque, undated])
        let subject = TodayViewModel(calendar: FakeCalendarService(access: .granted), reminders: reminders, routines: FakeRoutineRepository(), composer: AgendaComposer(), settings: AppSettingsStore(defaults: .ephemeral), calendarProvider: { self.calendar }, now: { due })
        await subject.load()
        XCTAssertEqual(subject.agenda.scheduled.map(\.title), ["Due"])
        await subject.setTaskCompleted(subject.agenda.scheduled[0], completed: true)
        XCTAssertEqual(reminders.completedCalls, [.init(id: "list|opaque|id", completed: true)])
    }

    func testTodayFiltersSelectionsIndependentlyAndRetainsEventOnReminderFailure() async {
        let due = calendar.date(from: DateComponents(year: 2026, month: 8, day: 24, hour: 9))!
        let event = CalendarEventSnapshot(id: "event", title: "Chosen event", start: due, end: due.addingTimeInterval(60), isAllDay: false, calendarID: "chosen", calendarTitle: "Chosen", allowsModification: true, hasRecurrence: false)
        let hidden = CalendarEventSnapshot(id: "hidden", title: "Hidden event", start: due, end: due.addingTimeInterval(60), isAllDay: false, calendarID: "hidden", calendarTitle: "Hidden", allowsModification: true, hasRecurrence: false)
        let task = ReminderSnapshot(id: "task", title: "Chosen task", notes: nil, dueDate: due, dueHasTime: true, priority: 1, listID: "chosen-list", listTitle: "Chosen", isCompleted: false, allowsModification: true, hasRecurrence: false)
        let settings = AppSettingsStore(defaults: .ephemeral); settings.selectedCalendarIDs = ["chosen"]; settings.selectedReminderListIDs = ["chosen-list"]
        let reminders = FakeRemindersService(access: .granted, reminders: [task])
        let subject = TodayViewModel(calendar: FakeCalendarService(access: .granted, events: [event, hidden]), reminders: reminders, routines: FakeRoutineRepository(), composer: AgendaComposer(), settings: settings, calendarProvider: { self.calendar }, now: { due })
        await subject.load()
        reminders.fetchError = TestError.failed
        await subject.load()
        XCTAssertEqual(subject.agenda.scheduled.map(\.title), ["Chosen event", "Chosen task"])
        XCTAssertNotNil(subject.remindersError)
    }

    func testTodayComposesFixedTimezoneItemsInSectionsAndExcludesUndatedReminder() async {
        let day = LocalDay(year: 2026, month: 8, day: 24)
        let start = day.startDate(in: calendar)
        let timed = calendar.date(byAdding: .hour, value: 10, to: start)!
        let yesterday = calendar.date(byAdding: .day, value: -1, to: start)!
        let allDay = CalendarEventSnapshot(id: "all-day", title: "Holiday", start: start, end: calendar.date(byAdding: .day, value: 1, to: start)!, isAllDay: true, calendarID: "cal", calendarTitle: "Calendar", allowsModification: true, hasRecurrence: false)
        let meeting = CalendarEventSnapshot(id: "meeting", title: "Meeting", start: timed, end: timed.addingTimeInterval(3600), isAllDay: false, calendarID: "cal", calendarTitle: "Calendar", allowsModification: true, hasRecurrence: false)
        let timedTask = reminder(id: "timed", title: "Timed task", due: calendar.date(byAdding: .hour, value: 11, to: start)!, hasTime: true)
        let overdue = reminder(id: "overdue", title: "Overdue", due: yesterday, hasTime: false)
        let undated = reminder(id: "inbox", title: "Inbox", due: nil, hasTime: false)
        let routine = RoutineSnapshot(id: UUID(), title: "Morning routine", weekdays: [calendar.component(.weekday, from: start)], window: .morning, reminderHour: nil, reminderMinute: nil, isPaused: false, isArchived: false)
        let subject = TodayViewModel(calendar: FakeCalendarService(access: .granted, events: [meeting, allDay]), reminders: FakeRemindersService(access: .granted, reminders: [timedTask, overdue, undated]), routines: FakeRoutineRepository(routines: [routine]), composer: AgendaComposer(), settings: AppSettingsStore(defaults: .ephemeral), calendarProvider: { self.calendar }, now: { start })
        await subject.load()
        XCTAssertEqual(subject.agenda.allDay.map(\.title), ["Holiday"])
        XCTAssertEqual(subject.agenda.scheduled.map(\.title), ["Morning routine", "Meeting", "Timed task"])
        XCTAssertEqual(subject.agenda.priority.map(\.title), ["Overdue"])
    }

    func testTodayKeepsConfirmedMutationWhenPostSaveRefreshFails() async {
        let due = calendar.date(from: DateComponents(year: 2026, month: 8, day: 24, hour: 9))!
        let task = reminder(id: "task", title: "Task", due: due, hasTime: true)
        let reminders = FakeRemindersService(access: .granted, reminders: [task])
        let subject = TodayViewModel(calendar: FakeCalendarService(access: .granted), reminders: reminders, routines: FakeRoutineRepository(), composer: AgendaComposer(), settings: AppSettingsStore(defaults: .ephemeral), calendarProvider: { self.calendar }, now: { due })
        await subject.load()
        reminders.fetchErrorAfterCompletion = TestError.failed
        await subject.setTaskCompleted(subject.agenda.scheduled[0], completed: true)
        XCTAssertTrue(subject.agenda.scheduled.isEmpty)
        XCTAssertEqual(subject.remindersError, "Task changes were saved, but tasks could not be refreshed. Pull to try again.")
    }

    func testTodayKeepsEventAndRoutineWhenRemindersAreDenied() async {
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 24, hour: 9))!
        let event = CalendarEventSnapshot(id: "event", title: "Meeting", start: now, end: now.addingTimeInterval(60), isAllDay: false, calendarID: "calendar", calendarTitle: "Calendar", allowsModification: true, hasRecurrence: false)
        let subject = TodayViewModel(calendar: FakeCalendarService(access: .granted, events: [event]), reminders: FakeRemindersService(access: .denied), routines: FakeRoutineRepository(routines: [.sampleRoutine]), composer: AgendaComposer(), settings: AppSettingsStore(defaults: .ephemeral), calendarProvider: { self.calendar }, now: { now })
        await subject.load()
        XCTAssertTrue(subject.showsRemindersPermissionCard)
        XCTAssertEqual(subject.agenda.scheduled.map(\.title), ["Meeting", "Read"])
    }

    func testRoutineCompletionAndUndoUseExactIdentityAndFailureKeepsState() async {
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 24, hour: 9))!
        let routine = RoutineSnapshot(id: UUID(), title: "Routine", weekdays: [calendar.component(.weekday, from: now)], window: .morning, reminderHour: nil, reminderMinute: nil, isPaused: false, isArchived: false)
        let repository = FakeRoutineRepository(routines: [routine])
        let subject = TodayViewModel(calendar: FakeCalendarService(access: .granted), reminders: FakeRemindersService(access: .granted), routines: repository, composer: AgendaComposer(), settings: AppSettingsStore(defaults: .ephemeral), calendarProvider: { self.calendar }, now: { now })
        await subject.load()
        let item = subject.agenda.scheduled[0]
        await subject.setRoutineCompleted(item, completed: true)
        XCTAssertEqual(repository.completionCalls.last, .init(id: routine.id, day: LocalDay(date: now, calendar: calendar), completed: true))
        XCTAssertTrue(subject.agenda.scheduled[0].isCompleted)
        await subject.setRoutineCompleted(subject.agenda.scheduled[0], completed: false)
        XCTAssertFalse(subject.agenda.scheduled[0].isCompleted)
        repository.completionError = TestError.failed
        await subject.setRoutineCompleted(subject.agenda.scheduled[0], completed: true)
        XCTAssertFalse(subject.agenda.scheduled[0].isCompleted)
        XCTAssertNotNil(subject.routinesError)
    }

    func testDeselectedCachedSourceDoesNotReturnWhenRefreshFails() async {
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 24, hour: 9))!
        let kept = CalendarEventSnapshot(id: "kept", title: "Kept", start: now, end: now.addingTimeInterval(60), isAllDay: false, calendarID: "kept", calendarTitle: "Kept", allowsModification: true, hasRecurrence: false)
        let removed = CalendarEventSnapshot(id: "removed", title: "Removed", start: now, end: now.addingTimeInterval(60), isAllDay: false, calendarID: "removed", calendarTitle: "Removed", allowsModification: true, hasRecurrence: false)
        let taskKept = ReminderSnapshot(id: "task-kept", title: "Task kept", notes: nil, dueDate: now, dueHasTime: true, priority: 1, listID: "list-kept", listTitle: "Kept", isCompleted: false, allowsModification: true, hasRecurrence: false)
        let taskRemoved = ReminderSnapshot(id: "task-removed", title: "Task removed", notes: nil, dueDate: now, dueHasTime: true, priority: 1, listID: "list-removed", listTitle: "Removed", isCompleted: false, allowsModification: true, hasRecurrence: false)
        let settings = AppSettingsStore(defaults: .ephemeral); settings.selectedCalendarIDs = ["kept", "removed"]; settings.selectedReminderListIDs = ["list-kept", "list-removed"]
        let calendars = FakeCalendarService(access: .granted, events: [kept, removed]); let reminders = FakeRemindersService(access: .granted, reminders: [taskKept, taskRemoved])
        let subject = TodayViewModel(calendar: calendars, reminders: reminders, routines: FakeRoutineRepository(), composer: AgendaComposer(), settings: settings, calendarProvider: { self.calendar }, now: { now })
        await subject.load()
        settings.selectedCalendarIDs = ["kept"]; settings.selectedReminderListIDs = ["list-kept"]; calendars.fetchError = TestError.failed; reminders.fetchError = TestError.failed
        await subject.load()
        XCTAssertEqual(Set(subject.agenda.scheduled.map(\.title)), ["Kept", "Task kept"])
    }

    func testCalendarFailureRetainsEventWhileReminderAndRoutineRefreshThenRecovers() async {
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 24, hour: 9))!
        let event = CalendarEventSnapshot(id: "event", title: "Confirmed event", start: now, end: now.addingTimeInterval(60), isAllDay: false, calendarID: "cal", calendarTitle: "Cal", allowsModification: true, hasRecurrence: false)
        let calendarService = FakeCalendarService(access: .granted, events: [event]); let reminders = FakeRemindersService(access: .granted, reminders: [])
        let routines = FakeRoutineRepository(); let subject = TodayViewModel(calendar: calendarService, reminders: reminders, routines: routines, composer: AgendaComposer(), settings: AppSettingsStore(defaults: .ephemeral), calendarProvider: { self.calendar }, now: { now })
        await subject.load(); calendarService.fetchError = TestError.failed
        reminders.reminders = [reminder(id: "fresh", title: "Fresh task", due: now, hasTime: true)]
        routines.routines = [RoutineSnapshot(id: UUID(), title: "Fresh routine", weekdays: [calendar.component(.weekday, from: now)], window: .morning, reminderHour: nil, reminderMinute: nil, isPaused: false, isArchived: false)]
        await subject.load()
        XCTAssertEqual(Set(subject.agenda.scheduled.map(\.title)), ["Confirmed event", "Fresh task", "Fresh routine"])
        XCTAssertNotNil(subject.calendarError)
        calendarService.fetchError = nil; calendarService.events = [CalendarEventSnapshot(id: "new", title: "New event", start: now, end: now.addingTimeInterval(60), isAllDay: false, calendarID: "cal", calendarTitle: "Cal", allowsModification: true, hasRecurrence: false)]
        await subject.load(); XCTAssertNil(subject.calendarError); XCTAssertTrue(subject.agenda.scheduled.contains(where: { $0.title == "New event" }))
    }

    func testReminderFailureRetainsTaskWhileCalendarAndRoutineRefresh() async {
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 24, hour: 9))!
        let reminders = FakeRemindersService(access: .granted, reminders: [reminder(id: "task", title: "Confirmed task", due: now, hasTime: true)])
        let calendars = FakeCalendarService(access: .granted); let routines = FakeRoutineRepository()
        let subject = TodayViewModel(calendar: calendars, reminders: reminders, routines: routines, composer: AgendaComposer(), settings: AppSettingsStore(defaults: .ephemeral), calendarProvider: { self.calendar }, now: { now })
        await subject.load(); reminders.fetchError = TestError.failed
        calendars.events = [CalendarEventSnapshot(id: "fresh", title: "Fresh event", start: now, end: now.addingTimeInterval(60), isAllDay: false, calendarID: "cal", calendarTitle: "Cal", allowsModification: true, hasRecurrence: false)]
        routines.routines = [RoutineSnapshot(id: UUID(), title: "Fresh routine", weekdays: [calendar.component(.weekday, from: now)], window: .morning, reminderHour: nil, reminderMinute: nil, isPaused: false, isArchived: false)]
        await subject.load()
        XCTAssertEqual(Set(subject.agenda.scheduled.map(\.title)), ["Confirmed task", "Fresh event", "Fresh routine"])
    }

    func testTaskCompletionFailurePreservesAgendaAndDoesNotRecordSuccessfulCall() async {
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 24, hour: 9))!
        let service = FakeRemindersService(access: .granted, reminders: [reminder(id: "raw|id", title: "Task", due: now, hasTime: true)])
        let subject = TodayViewModel(calendar: FakeCalendarService(access: .granted), reminders: service, routines: FakeRoutineRepository(), composer: AgendaComposer(), settings: AppSettingsStore(defaults: .ephemeral), calendarProvider: { self.calendar }, now: { now })
        await subject.load(); service.completionError = TestError.failed
        await subject.setTaskCompleted(subject.agenda.scheduled[0], completed: true)
        XCTAssertEqual(subject.agenda.scheduled.map(\.title), ["Task"]); XCTAssertFalse(subject.agenda.scheduled[0].isCompleted)
        XCTAssertTrue(service.completedCalls.isEmpty); XCTAssertNotNil(subject.remindersError)
    }

    func testTaskCompletionUndoUsesOpaqueIdentifierAndRestoresAgenda() async {
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 24, hour: 9))!
        let service = FakeRemindersService(access: .granted, reminders: [reminder(id: "opaque|raw", title: "Task", due: now, hasTime: true)])
        let subject = TodayViewModel(calendar: FakeCalendarService(access: .granted), reminders: service, routines: FakeRoutineRepository(), composer: AgendaComposer(), settings: AppSettingsStore(defaults: .ephemeral), calendarProvider: { self.calendar }, now: { now })
        await subject.load()
        await subject.setTaskCompleted(subject.agenda.scheduled[0], completed: true)
        XCTAssertTrue(subject.agenda.scheduled.isEmpty)
        XCTAssertEqual(subject.latestTaskUndo?.rawID, "opaque|raw")
        await subject.undoLastTaskCompletion()
        XCTAssertEqual(service.completedCalls, [.init(id: "opaque|raw", completed: true), .init(id: "opaque|raw", completed: false)])
        XCTAssertEqual(subject.agenda.scheduled.map(\.title), ["Task"])
        XCTAssertNil(subject.latestTaskUndo)
    }

    func testRoutinePostSaveRefreshFailurePreservesConfirmedCompletion() async {
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 24, hour: 9))!
        let routine = RoutineSnapshot(id: UUID(), title: "Routine", weekdays: [calendar.component(.weekday, from: now)], window: .morning, reminderHour: nil, reminderMinute: nil, isPaused: false, isArchived: false)
        let repository = FakeRoutineRepository(routines: [routine])
        let subject = TodayViewModel(calendar: FakeCalendarService(access: .granted), reminders: FakeRemindersService(access: .granted), routines: repository, composer: AgendaComposer(), settings: AppSettingsStore(defaults: .ephemeral), calendarProvider: { self.calendar }, now: { now })
        await subject.load()
        repository.completedDaysError = TestError.failed
        await subject.setRoutineCompleted(subject.agenda.scheduled[0], completed: true)
        XCTAssertTrue(subject.agenda.scheduled[0].isCompleted)
        XCTAssertEqual(subject.routinesError, "Routine changes were saved, but routines could not be refreshed. Pull to try again.")
    }

    func testUndoWriteFailureKeepsUndoAndCompletedTaskAbsent() async {
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 24, hour: 9))!
        let service = FakeRemindersService(access: .granted, reminders: [reminder(id: "raw", title: "Task", due: now, hasTime: true)])
        let subject = TodayViewModel(calendar: FakeCalendarService(access: .granted), reminders: service, routines: FakeRoutineRepository(), composer: AgendaComposer(), settings: AppSettingsStore(defaults: .ephemeral), calendarProvider: { self.calendar }, now: { now })
        await subject.load(); await subject.setTaskCompleted(subject.agenda.scheduled[0], completed: true)
        service.completionError = TestError.failed
        await subject.undoLastTaskCompletion()
        XCTAssertNotNil(subject.latestTaskUndo)
        XCTAssertTrue(subject.agenda.scheduled.isEmpty)
        XCTAssertNotNil(subject.remindersError)
    }

    private func reminder(id: String, title: String, due: Date?, hasTime: Bool) -> ReminderSnapshot {
        .init(id: id, title: title, notes: nil, dueDate: due, dueHasTime: hasTime, priority: 5, listID: "list", listTitle: "List", isCompleted: false, allowsModification: true, hasRecurrence: false)
    }
}

private enum TestError: Error { case failed }
