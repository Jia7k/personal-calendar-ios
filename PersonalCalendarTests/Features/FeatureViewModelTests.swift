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

    func testUndoStaysPendingUntilSuspendedRefreshFinishes() async {
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 24, hour: 9))!
        let service = FakeRemindersService(access: .granted, reminders: [reminder(id: "raw", title: "Task", due: now, hasTime: true)])
        let subject = TodayViewModel(calendar: FakeCalendarService(access: .granted), reminders: service, routines: FakeRoutineRepository(), composer: AgendaComposer(), settings: AppSettingsStore(defaults: .ephemeral), calendarProvider: { self.calendar }, now: { now })
        await subject.load(); await subject.setTaskCompleted(subject.agenda.scheduled[0], completed: true)
        service.suspendFetchAfterUndo = true
        let work = Task { await subject.undoLastTaskCompletion() }
        for _ in 0..<20 where !service.isFetchSuspended { await Task.yield() }
        XCTAssertTrue(service.isFetchSuspended); XCTAssertTrue(subject.latestTaskUndo?.isPending == true)
        await subject.undoLastTaskCompletion()
        XCTAssertEqual(service.completedCalls.filter { !$0.completed }.count, 1)
        service.resumeSuspendedFetch(); await work.value
        XCTAssertNil(subject.latestTaskUndo)
    }

    func testUndoRestoresCapturedTaskWhenPostUndoRefreshFails() async {
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 24, hour: 9))!
        let service = FakeRemindersService(access: .granted, reminders: [reminder(id: "opaque|raw", title: "Task", due: now, hasTime: true)])
        let subject = TodayViewModel(calendar: FakeCalendarService(access: .granted), reminders: service, routines: FakeRoutineRepository(), composer: AgendaComposer(), settings: AppSettingsStore(defaults: .ephemeral), calendarProvider: { self.calendar }, now: { now })
        await subject.load(); await subject.setTaskCompleted(subject.agenda.scheduled[0], completed: true)
        service.reminders = []; await subject.load(); service.allowMissingCompletion = true; service.fetchErrorAfterCompletion = TestError.failed
        await subject.undoLastTaskCompletion()
        XCTAssertEqual(subject.agenda.scheduled.map(\.title), ["Task"])
        XCTAssertNil(subject.latestTaskUndo); XCTAssertEqual(service.completedCalls.last, .init(id: "opaque|raw", completed: false)); XCTAssertNotNil(subject.remindersError)
    }

    func testOlderUndoRefreshDoesNotClearNewCompletionUndo() async {
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 24, hour: 9))!
        let service = FakeRemindersService(access: .granted, reminders: [reminder(id: "raw", title: "Task", due: now, hasTime: true)])
        let subject = TodayViewModel(calendar: FakeCalendarService(access: .granted), reminders: service, routines: FakeRoutineRepository(), composer: AgendaComposer(), settings: AppSettingsStore(defaults: .ephemeral), calendarProvider: { self.calendar }, now: { now })
        await subject.load(); await subject.setTaskCompleted(subject.agenda.scheduled[0], completed: true)
        service.suspendFetchAfterUndo = true
        let oldUndo = Task { await subject.undoLastTaskCompletion() }
        for _ in 0..<20 where !service.isFetchSuspended { await Task.yield() }
        let restored = subject.agenda.scheduled[0]
        await subject.setTaskCompleted(restored, completed: true)
        let newGeneration = subject.latestTaskUndo?.generation
        service.resumeSuspendedFetch(); await oldUndo.value
        XCTAssertEqual(subject.latestTaskUndo?.generation, newGeneration)
        XCTAssertTrue(subject.agenda.scheduled.isEmpty)
    }

    func testTasksGroupsOverdueTodayTomorrowUndatedAndCompletedInInjectedTimezone() async {
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 24, hour: 9))!
        let overdue = reminder(id: "overdue", title: "Overdue", due: calendar.date(byAdding: .day, value: -1, to: now)!, hasTime: false)
        let today = reminder(id: "today", title: "Today", due: now, hasTime: true)
        let tomorrow = reminder(id: "tomorrow", title: "Tomorrow", due: calendar.date(byAdding: .day, value: 1, to: now)!, hasTime: false)
        let undated = reminder(id: "undated", title: "Inbox", due: nil, hasTime: false)
        let done = ReminderSnapshot(id: "done", title: "Done", notes: nil, dueDate: nil, dueHasTime: false, priority: 1, listID: "list", listTitle: "List", isCompleted: true, allowsModification: true, hasRecurrence: false)
        let subject = TasksViewModel(service: FakeRemindersService(access: .granted, reminders: [undated, tomorrow, done, today, overdue]), settings: AppSettingsStore(defaults: .ephemeral), calendar: calendar, now: { now })

        await subject.load()

        XCTAssertEqual(subject.today.map(\.id), ["overdue", "today"])
        XCTAssertEqual(subject.upcoming.map(\.id), ["tomorrow", "undated"])
        XCTAssertEqual(subject.completed.map(\.id), ["done"])
    }

    func testRoutinesBuildFourteenDayHistoryWithOneQueryPerRoutine() {
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 24, hour: 9))!
        let routine = RoutineSnapshot(id: UUID(), title: "Read", weekdays: [1, 2, 3, 4, 5, 6, 7], window: .evening, reminderHour: nil, reminderMinute: nil, isPaused: false, isArchived: false)
        let repository = FakeRoutineRepository(routines: [routine])
        let subject = RoutinesViewModel(repository: repository, calendar: calendar, now: { now })

        subject.reload()

        XCTAssertEqual(subject.active.count, 1)
        XCTAssertEqual(subject.active[0].history.count, 14)
        XCTAssertEqual(subject.active[0].history.first?.day, LocalDay(year: 2026, month: 8, day: 11))
        XCTAssertEqual(subject.active[0].history.last?.day, LocalDay(year: 2026, month: 8, day: 24))
        XCTAssertEqual(repository.completedDaysCallCount, 1)
    }

    func testTasksHonorsSelectionAndDoesNotRevealDeselectedStaleCacheAfterFailure() async {
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 24, hour: 9))!
        let shown = ReminderSnapshot(id: "shown", title: "Shown", notes: nil, dueDate: now, dueHasTime: true, priority: 1, listID: "shown", listTitle: "Shown", isCompleted: false, allowsModification: true, hasRecurrence: false)
        let hidden = ReminderSnapshot(id: "hidden", title: "Hidden", notes: nil, dueDate: now, dueHasTime: true, priority: 1, listID: "hidden", listTitle: "Hidden", isCompleted: false, allowsModification: true, hasRecurrence: false)
        let settings = AppSettingsStore(defaults: .ephemeral); settings.selectedReminderListIDs = ["shown", "hidden"]
        let service = FakeRemindersService(access: .granted, reminders: [shown, hidden])
        let subject = TasksViewModel(service: service, settings: settings, calendar: calendar, now: { now })
        await subject.load(); settings.selectedReminderListIDs = ["shown"]; service.fetchError = TestError.failed; await subject.load()
        XCTAssertEqual(subject.today.map(\.id), ["shown"])
        XCTAssertEqual(service.fetchListIDs.last, ["shown"])
        service.fetchError = nil; await subject.load()
        XCTAssertNil(subject.errorMessage)
    }

    func testTasksDeniedAndRecurringSnapshotRemainEmptyOrOneRow() async {
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 24, hour: 9))!
        let recurring = ReminderSnapshot(id: "opaque", title: "One supplied occurrence", notes: nil, dueDate: now, dueHasTime: true, priority: 1, listID: "list", listTitle: "List", isCompleted: false, allowsModification: true, hasRecurrence: true)
        let denied = TasksViewModel(service: FakeRemindersService(access: .denied, reminders: [recurring]), settings: AppSettingsStore(defaults: .ephemeral), calendar: calendar, now: { now })
        await denied.load(); XCTAssertTrue(denied.today.isEmpty); XCTAssertNotNil(denied.accessExplanation)
        let allowed = TasksViewModel(service: FakeRemindersService(access: .granted, reminders: [recurring]), settings: AppSettingsStore(defaults: .ephemeral), calendar: calendar, now: { now })
        await allowed.load(); XCTAssertEqual(allowed.today.map(\.id), ["opaque"])
    }

    func testTaskCreateUsesWritableFallbackRetainsEditedRetryAndDoesNotDuplicateAfterRefreshFailure() async {
        let writable = ReminderListDescriptor(id: "write", title: "Writable", colorHex: "#000000", allowsContentModifications: true)
        let readonly = ReminderListDescriptor(id: "read", title: "Read", colorHex: "#000000", allowsContentModifications: false)
        let settings = AppSettingsStore(defaults: .ephemeral); settings.defaultReminderListID = "read"
        let service = FakeRemindersService(access: .granted, descriptors: [readonly, writable]); service.createError = TestError.failed
        let subject = TasksViewModel(service: service, settings: settings, calendar: calendar)
        let explicitReadOnly = ReminderDraft(title: "Explicit", notes: nil, dueDate: nil, dueHasTime: false, priority: 5, listID: "read")
        let rejected = await subject.create(explicitReadOnly); XCTAssertFalse(rejected); XCTAssertTrue(service.createdDrafts.isEmpty)
        let first = ReminderDraft(title: "  First  ", notes: nil, dueDate: nil, dueHasTime: false, priority: 5, listID: nil)
        let failed = await subject.create(first); XCTAssertFalse(failed); XCTAssertEqual(subject.draftOnFailure?.title, "First")
        service.createError = nil
        let edited = ReminderDraft(title: "Edited", notes: nil, dueDate: nil, dueHasTime: false, priority: 5, listID: nil)
        service.fetchErrorAfterCreate = TestError.failed
        let saved = await subject.create(edited); XCTAssertTrue(saved); XCTAssertEqual(service.createdDrafts.map(\.title), ["Edited"]); XCTAssertEqual(service.createdDrafts.first?.listID, "write")
        XCTAssertEqual(service.createdDrafts.count, 1); XCTAssertNotNil(subject.errorMessage)
    }

    func testTaskCreateRejectsMissingListAndNoWritableDestination() async {
        let readOnly = ReminderListDescriptor(id: "read", title: "Read", colorHex: "#000", allowsContentModifications: false)
        let service = FakeRemindersService(access: .granted, descriptors: [readOnly]); let subject = TasksViewModel(service: service, settings: AppSettingsStore(defaults: .ephemeral))
        let missing = await subject.create(.init(title: "Task", notes: nil, dueDate: nil, dueHasTime: false, priority: 5, listID: "missing")); XCTAssertFalse(missing)
        let none = await subject.create(.init(title: "Task", notes: nil, dueDate: nil, dueHasTime: false, priority: 5, listID: nil)); XCTAssertFalse(none); XCTAssertTrue(service.createdDrafts.isEmpty)
    }

    func testTaskCompletionUsesOpaqueIDAndPreservesConfirmedChangeAcrossRefreshFailure() async {
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 24, hour: 9))!
        let item = ReminderSnapshot(id: "opaque|raw|id", title: "Task", notes: nil, dueDate: now, dueHasTime: true, priority: 1, listID: "list", listTitle: "List", isCompleted: false, allowsModification: true, hasRecurrence: false)
        let service = FakeRemindersService(access: .granted, reminders: [item]); let subject = TasksViewModel(service: service, settings: AppSettingsStore(defaults: .ephemeral), calendar: calendar, now: { now })
        await subject.load(); service.fetchErrorAfterCompletion = TestError.failed; await subject.setCompleted(id: item.id, completed: true)
        XCTAssertEqual(service.completedCalls, [.init(id: "opaque|raw|id", completed: true)]); XCTAssertTrue(subject.today.isEmpty)
        service.fetchErrorAfterCompletion = nil; await subject.setCompleted(id: item.id, completed: false)
        XCTAssertEqual(subject.today.map(\.id), [item.id])
    }

    func testTaskReadOnlyAndFailedCompletionPreserveRows() async {
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 24, hour: 9))!
        let immutable = ReminderSnapshot(id: "immutable", title: "Immutable", notes: nil, dueDate: now, dueHasTime: true, priority: 1, listID: "list", listTitle: "List", isCompleted: false, allowsModification: false, hasRecurrence: false)
        let service = FakeRemindersService(access: .granted, reminders: [immutable]); let subject = TasksViewModel(service: service, settings: AppSettingsStore(defaults: .ephemeral), calendar: calendar, now: { now })
        await subject.load(); await subject.setCompleted(id: immutable.id, completed: true); XCTAssertTrue(service.completedCalls.isEmpty)
        let mutable = ReminderSnapshot(id: "mutable", title: "Mutable", notes: nil, dueDate: now, dueHasTime: true, priority: 1, listID: "list", listTitle: "List", isCompleted: false, allowsModification: true, hasRecurrence: false)
        service.reminders = [mutable]; await subject.load(); service.completionError = TestError.failed; await subject.setCompleted(id: mutable.id, completed: true)
        XCTAssertEqual(subject.today.map(\.id), ["mutable"]); XCTAssertTrue(service.completedCalls.isEmpty)
    }

    func testRoutineCompletionGatesNewCompletionsButAllowsUndo() async {
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 24, hour: 9))!; let weekday = calendar.component(.weekday, from: now)
        let paused = RoutineSnapshot(id: UUID(), title: "Paused", weekdays: [weekday], window: .anytime, reminderHour: nil, reminderMinute: nil, isPaused: true, isArchived: false)
        let unscheduled = RoutineSnapshot(id: UUID(), title: "Unscheduled", weekdays: [weekday == 1 ? 2 : 1], window: .anytime, reminderHour: nil, reminderMinute: nil, isPaused: false, isArchived: false)
        let repository = FakeRoutineRepository(routines: [paused, unscheduled]); let subject = RoutinesViewModel(repository: repository, calendar: calendar, now: { now })
        subject.reload(); await subject.setCompleted(id: paused.id, completed: true); await subject.setCompleted(id: unscheduled.id, completed: true); XCTAssertTrue(repository.completionCalls.isEmpty)
        try? repository.setCompleted(routineID: paused.id, day: LocalDay(date: now, calendar: calendar), completed: true); subject.reload(); await subject.setCompleted(id: paused.id, completed: false)
        XCTAssertEqual(repository.completionCalls.last?.completed, false)
    }

    func testRoutineMutationsUpdateConfirmedRowsBeforeARefreshFailure() async {
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 24, hour: 9))!
        let routine = RoutineSnapshot(id: UUID(), title: "Read", weekdays: [calendar.component(.weekday, from: now)], window: .anytime, reminderHour: nil, reminderMinute: nil, isPaused: false, isArchived: false)
        let repository = FakeRoutineRepository(routines: [routine]); let subject = RoutinesViewModel(repository: repository, calendar: calendar, now: { now })
        subject.reload(); repository.completedDaysError = TestError.failed
        subject.setPaused(id: routine.id, paused: true)
        XCTAssertTrue(subject.active[0].routine.isPaused)
        subject.setArchived(id: routine.id, archived: true)
        XCTAssertTrue(subject.archived[0].routine.isArchived)
    }

    func testOlderSuspendedTaskLoadCannotOverwriteNewerSuccessfulLoad() async {
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 24, hour: 9))!
        let first = reminder(id: "first", title: "First", due: now, hasTime: true)
        let service = FakeRemindersService(access: .granted, reminders: [first]); let subject = TasksViewModel(service: service, settings: AppSettingsStore(defaults: .ephemeral), calendar: calendar, now: { now })
        service.suspendNextFetch = true; let older = Task { await subject.load() }
        for _ in 0..<30 where !service.isFetchSuspended { await Task.yield() }
        service.reminders = [self.reminder(id: "new", title: "New", due: now, hasTime: true)]; await subject.load(); service.resumeSuspendedFetch(); await older.value
        XCTAssertEqual(subject.today.map(\.id), ["new"]); XCTAssertNil(subject.errorMessage)
    }

    func testOlderSuspendedTaskLoadFailureCannotSetErrorAfterNewerSuccess() async {
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 24, hour: 9))!
        let service = FakeRemindersService(access: .granted, reminders: [reminder(id: "old", title: "Old", due: now, hasTime: true)]); let subject = TasksViewModel(service: service, settings: AppSettingsStore(defaults: .ephemeral), calendar: calendar, now: { now })
        service.suspendNextFetch = true; let older = Task { await subject.load() }
        for _ in 0..<30 where !service.isFetchSuspended { await Task.yield() }
        service.reminders = [reminder(id: "fresh", title: "Fresh", due: now, hasTime: true)]; await subject.load(); service.fetchError = TestError.failed; service.resumeSuspendedFetch(); await older.value
        XCTAssertEqual(subject.today.map(\.id), ["fresh"]); XCTAssertNil(subject.errorMessage)
    }

    func testSuspendedTaskCreatePreventsSecondCreateAndShowsSaving() async {
        let service = FakeRemindersService(access: .granted, descriptors: [.init(id: "list", title: "List", colorHex: "#000", allowsContentModifications: true)]); let subject = TasksViewModel(service: service, settings: AppSettingsStore(defaults: .ephemeral))
        let draft = ReminderDraft(title: "One", notes: nil, dueDate: nil, dueHasTime: false, priority: 5, listID: "list")
        service.suspendNextFetch = true; let first = Task { await subject.create(draft) }
        for _ in 0..<30 where !service.isFetchSuspended { await Task.yield() }
        XCTAssertTrue(subject.isSaving); let second = await subject.create(draft); XCTAssertFalse(second); XCTAssertEqual(service.createdDrafts.count, 1)
        service.resumeSuspendedFetch(); let firstResult = await first.value; XCTAssertTrue(firstResult)
    }

    func testSuspendedTaskCompletionPreventsDuplicateMutation() async {
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 24, hour: 9))!; let item = reminder(id: "same", title: "Same", due: now, hasTime: true)
        let service = FakeRemindersService(access: .granted, reminders: [item]); let subject = TasksViewModel(service: service, settings: AppSettingsStore(defaults: .ephemeral), calendar: calendar, now: { now })
        await subject.load(); service.suspendNextFetch = true; let first = Task { await subject.setCompleted(id: "same", completed: true) }
        for _ in 0..<30 where !service.isFetchSuspended { await Task.yield() }
        XCTAssertTrue(subject.mutatingIDs.contains("same")); await subject.setCompleted(id: "same", completed: true); XCTAssertEqual(service.completedCalls.count, 1)
        service.resumeSuspendedFetch(); await first.value
    }

    func testTaskValidationRejectsInvalidDraftsWithoutCreating() async {
        let list = ReminderListDescriptor(id: "list", title: "List", colorHex: "#000", allowsContentModifications: true)
        let service = FakeRemindersService(access: .granted, descriptors: [list]); let subject = TasksViewModel(service: service, settings: AppSettingsStore(defaults: .ephemeral))
        let invalid = [
            ReminderDraft(title: " ", notes: nil, dueDate: nil, dueHasTime: false, priority: 0, listID: "list"),
            ReminderDraft(title: "Bad priority", notes: nil, dueDate: nil, dueHasTime: false, priority: -1, listID: "list"),
            ReminderDraft(title: "Bad priority", notes: nil, dueDate: nil, dueHasTime: false, priority: 10, listID: "list"),
            ReminderDraft(title: "Bad time", notes: nil, dueDate: nil, dueHasTime: true, priority: 0, listID: "list")
        ]
        for draft in invalid { let result = await subject.create(draft); XCTAssertFalse(result) }
        XCTAssertTrue(service.createdDrafts.isEmpty)
    }

    func testTaskExplicitWritableDestinationWinsAndSavedWritableDefaultWins() async {
        let a = ReminderListDescriptor(id: "a", title: "A", colorHex: "#000", allowsContentModifications: true); let b = ReminderListDescriptor(id: "b", title: "B", colorHex: "#000", allowsContentModifications: true)
        let settings = AppSettingsStore(defaults: .ephemeral); settings.defaultReminderListID = "b"; let service = FakeRemindersService(access: .granted, descriptors: [b, a]); let subject = TasksViewModel(service: service, settings: settings)
        let explicit = await subject.create(.init(title: "Explicit", notes: nil, dueDate: nil, dueHasTime: false, priority: 0, listID: "a")); let fallback = await subject.create(.init(title: "Default", notes: nil, dueDate: nil, dueHasTime: false, priority: 0, listID: nil))
        XCTAssertTrue(explicit); XCTAssertTrue(fallback); XCTAssertEqual(service.createdDrafts.map(\.listID), ["a", "b"])
    }

    private func reminder(id: String, title: String, due: Date?, hasTime: Bool) -> ReminderSnapshot {
        .init(id: id, title: title, notes: nil, dueDate: due, dueHasTime: hasTime, priority: 5, listID: "list", listTitle: "List", isCompleted: false, allowsModification: true, hasRecurrence: false)
    }
}

private enum TestError: Error { case failed }
