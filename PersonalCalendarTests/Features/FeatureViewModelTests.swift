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

    func testDeniedTaskLoadInvalidatesSuspendedGrantedFetch() async {
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 24, hour: 9))!; let service = FakeRemindersService(access: .granted, reminders: [reminder(id: "task", title: "Task", due: now, hasTime: true)]); let subject = TasksViewModel(service: service, settings: AppSettingsStore(defaults: .ephemeral), calendar: calendar, now: { now })
        service.suspendNextFetch = true; let old = Task { await subject.load() }; for _ in 0..<30 where !service.isFetchSuspended { await Task.yield() }
        service.accessState = .denied; await subject.load(); XCTAssertTrue(subject.today.isEmpty); XCTAssertNotNil(subject.accessExplanation); service.resumeSuspendedFetch(); await old.value
        XCTAssertTrue(subject.today.isEmpty); XCTAssertNil(subject.refreshErrorMessage)
    }

    func testTaskCreateAndMutationErrorsRemainIndependent() async {
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 24, hour: 9))!; let item = ReminderSnapshot(id: "opaque", title: "Task", notes: nil, dueDate: now, dueHasTime: true, priority: 1, listID: "list", listTitle: "List", isCompleted: false, allowsModification: true, hasRecurrence: false)
        let service = FakeRemindersService(access: .granted, reminders: [item], descriptors: [.init(id: "list", title: "List", colorHex: "#000", allowsContentModifications: true)]); let subject = TasksViewModel(service: service, settings: AppSettingsStore(defaults: .ephemeral), calendar: calendar, now: { now }); service.createError = TestError.failed
        let createResult = await subject.create(.init(title: "  Draft  ", notes: nil, dueDate: nil, dueHasTime: false, priority: 0, listID: "list")); XCTAssertFalse(createResult); let createError = subject.createErrorMessage; await subject.load(); XCTAssertEqual(subject.createErrorMessage, createError); XCTAssertEqual(subject.draftOnFailure?.title, "Draft")
        service.completionError = TestError.failed; await subject.setCompleted(id: "opaque", completed: true); XCTAssertNotNil(subject.mutationErrorMessage); XCTAssertEqual(subject.failedMutationOperation, .init(id: "opaque", completed: true)); XCTAssertNotNil(subject.createErrorMessage)
        service.completionError = nil; await subject.retryFailedMutation(); XCTAssertNil(subject.mutationErrorMessage); XCTAssertNil(subject.failedMutationOperation); XCTAssertNotNil(subject.createErrorMessage)
    }

    func testConfirmedTaskCreateRefreshFailureHasOnlyRefreshErrorAndNeverDuplicates() async {
        let service = FakeRemindersService(access: .granted, descriptors: [.init(id: "list", title: "List", colorHex: "#000", allowsContentModifications: true)]); let subject = TasksViewModel(service: service, settings: AppSettingsStore(defaults: .ephemeral)); service.fetchErrorAfterCreate = TestError.failed
        let saved = await subject.create(.init(title: "Saved", notes: nil, dueDate: nil, dueHasTime: false, priority: 0, listID: "list")); XCTAssertTrue(saved); XCTAssertEqual(service.createdDrafts.count, 1); XCTAssertNil(subject.createErrorMessage); XCTAssertNil(subject.draftOnFailure); XCTAssertNotNil(subject.refreshErrorMessage)
        service.fetchErrorAfterCreate = nil; await subject.load(); XCTAssertNil(subject.refreshErrorMessage); XCTAssertEqual(service.createdDrafts.count, 1)
    }

    func testRoutineSecondHistoryFailureKeepsPriorRowsAndCompletedCacheAtomic() async {
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 24, hour: 9))!; let day = LocalDay(date: now, calendar: calendar); let weekday = calendar.component(.weekday, from: now)
        let first = RoutineSnapshot(id: UUID(), title: "First", weekdays: [weekday], window: .anytime, reminderHour: nil, reminderMinute: nil, isPaused: false, isArchived: false)
        let second = RoutineSnapshot(id: UUID(), title: "Second", weekdays: [weekday], window: .anytime, reminderHour: nil, reminderMinute: nil, isPaused: false, isArchived: false)
        let repository = FakeRoutineRepository(routines: [first, second]); try? repository.setCompleted(routineID: first.id, day: day, completed: true)
        let subject = RoutinesViewModel(repository: repository, calendar: calendar, now: { now }); subject.reload(); XCTAssertTrue(subject.active.first(where: { $0.id == first.id })!.isCompletedToday)
        repository.completedDaysErrors[second.id] = TestError.failed; subject.reload()
        XCTAssertEqual(subject.active.map(\.id), [first.id, second.id]); await subject.setCompleted(id: first.id, completed: false)
        XCTAssertEqual(repository.completionCalls.last, .init(id: first.id, day: day, completed: false)); XCTAssertFalse(subject.active.first(where: { $0.id == first.id })!.isCompletedToday)
    }

    func testRoutineValidationRejectsInvalidDraftsAndNormalizesValidDrafts() {
        let repository = FakeRoutineRepository(); let subject = RoutinesViewModel(repository: repository, calendar: calendar)
        let invalid = [
            RoutineDraft(title: " ", weekdays: [1], window: .anytime, reminderHour: nil, reminderMinute: nil), RoutineDraft(title: "Empty", weekdays: [], window: .anytime, reminderHour: nil, reminderMinute: nil), RoutineDraft(title: "Day", weekdays: [0], window: .anytime, reminderHour: nil, reminderMinute: nil), RoutineDraft(title: "Day", weekdays: [8], window: .anytime, reminderHour: nil, reminderMinute: nil), RoutineDraft(title: "Hour", weekdays: [1], window: .anytime, reminderHour: 9, reminderMinute: nil), RoutineDraft(title: "Minute", weekdays: [1], window: .anytime, reminderHour: nil, reminderMinute: 9), RoutineDraft(title: "Hour", weekdays: [1], window: .anytime, reminderHour: 24, reminderMinute: 0), RoutineDraft(title: "Minute", weekdays: [1], window: .anytime, reminderHour: 0, reminderMinute: 60)
        ]
        for draft in invalid { XCTAssertFalse(subject.create(draft)) }; XCTAssertTrue(repository.createdDrafts.isEmpty)
        XCTAssertTrue(subject.create(.init(title: "  Read  ", weekdays: [1], window: .anytime, reminderHour: nil, reminderMinute: nil))); XCTAssertTrue(subject.create(.init(title: "Clock", weekdays: [1], window: .anytime, reminderHour: 23, reminderMinute: 59)))
        XCTAssertEqual(repository.createdDrafts.map(\.title), ["Read", "Clock"]); XCTAssertEqual(repository.createdDrafts.last?.reminderHour, 23); XCTAssertEqual(repository.createdDrafts.last?.reminderMinute, 59)
    }

    func testRoutineCompletionGatingAllowsCompletedRowsToUndo() async {
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 24, hour: 9))!; let day = LocalDay(date: now, calendar: calendar); let wrong = calendar.component(.weekday, from: now) == 1 ? 2 : 1
        let paused = RoutineSnapshot(id: UUID(), title: "Paused", weekdays: [wrong], window: .anytime, reminderHour: nil, reminderMinute: nil, isPaused: true, isArchived: false); let archived = RoutineSnapshot(id: UUID(), title: "Archived", weekdays: [wrong], window: .anytime, reminderHour: nil, reminderMinute: nil, isPaused: false, isArchived: true); let unscheduled = RoutineSnapshot(id: UUID(), title: "Wrong", weekdays: [wrong], window: .anytime, reminderHour: nil, reminderMinute: nil, isPaused: false, isArchived: false)
        let repository = FakeRoutineRepository(routines: [paused, archived, unscheduled]); let subject = RoutinesViewModel(repository: repository, calendar: calendar, now: { now }); subject.reload()
        for id in [paused.id, archived.id, unscheduled.id] { await subject.setCompleted(id: id, completed: true) }
        XCTAssertTrue(repository.completionCalls.isEmpty)
        try? repository.setCompleted(routineID: paused.id, day: day, completed: true); try? repository.setCompleted(routineID: archived.id, day: day, completed: true); try? repository.setCompleted(routineID: unscheduled.id, day: day, completed: true); subject.reload()
        await subject.setCompleted(id: paused.id, completed: false); await subject.setCompleted(id: archived.id, completed: false); await subject.setCompleted(id: unscheduled.id, completed: false)
        XCTAssertEqual(repository.completionCalls.suffix(3).map(\.completed), [false, false, false])
    }

    func testRoutineReloadUsesOneListOneHistoryPerRoutineAndBuildsConsecutiveHistory() {
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 24, hour: 9))!; let weekday = calendar.component(.weekday, from: now)
        let first = RoutineSnapshot(id: UUID(), title: "Daily", weekdays: [1, 2, 3, 4, 5, 6, 7], window: .anytime, reminderHour: nil, reminderMinute: nil, isPaused: false, isArchived: false); let second = RoutineSnapshot(id: UUID(), title: "Weekly", weekdays: [weekday], window: .anytime, reminderHour: nil, reminderMinute: nil, isPaused: false, isArchived: false)
        let repository = FakeRoutineRepository(routines: [first, second]); let today = LocalDay(date: now, calendar: calendar); let yesterday = LocalDay(date: calendar.date(byAdding: .day, value: -1, to: now)!, calendar: calendar); try? repository.setCompleted(routineID: first.id, day: today, completed: true); try? repository.setCompleted(routineID: first.id, day: yesterday, completed: true)
        repository.listCallCount = 0; repository.completedDaysCallCount = 0; repository.completedDaysCallCounts = [:]
        let subject = RoutinesViewModel(repository: repository, calendar: calendar, now: { now }); subject.reload()
        XCTAssertEqual(repository.listCallCount, 1); XCTAssertEqual(repository.completedDaysCallCounts, [first.id: 1, second.id: 1])
        let row = subject.active.first { $0.id == first.id }!; XCTAssertEqual(row.history.count, 14); XCTAssertEqual(row.history.last?.day, today); XCTAssertEqual(row.history.first?.day, LocalDay(date: calendar.date(byAdding: .day, value: -13, to: now)!, calendar: calendar)); XCTAssertTrue(row.isCompletedToday); XCTAssertEqual(row.streak, RoutineStreakCalculator().currentStreak(routine: first, completedDays: [today, yesterday], through: today, calendar: calendar))
    }

    func testRoutineCreateAndUpdateRetainConfirmedRowsWhenRefreshFails() {
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 24, hour: 9))!; let old = RoutineSnapshot(id: UUID(), title: "Old", weekdays: [1], window: .anytime, reminderHour: nil, reminderMinute: nil, isPaused: false, isArchived: false)
        let repository = FakeRoutineRepository(routines: [old]); let subject = RoutinesViewModel(repository: repository, calendar: calendar, now: { now }); subject.reload(); repository.listError = TestError.failed
        let created = RoutineDraft(title: "  New  ", weekdays: [2], window: .morning, reminderHour: 8, reminderMinute: 30); XCTAssertTrue(subject.create(created)); XCTAssertEqual(repository.createdDrafts, [.init(title: "New", weekdays: [2], window: .morning, reminderHour: 8, reminderMinute: 30)]); XCTAssertTrue(subject.active.contains { $0.routine.title == "New" }); XCTAssertNil(subject.failedEditorOperation); XCTAssertTrue(subject.errorMessage?.contains("saved") == true)
        let changed = RoutineDraft(title: "Changed", weekdays: [3], window: .evening, reminderHour: 23, reminderMinute: 59); XCTAssertTrue(subject.update(id: old.id, draft: changed)); XCTAssertEqual(repository.updateCalls.last, .init(id: old.id, draft: changed)); XCTAssertEqual(subject.active.first(where: { $0.id == old.id })?.routine.reminderMinute, 59)
        repository.listError = nil; subject.reload(); XCTAssertNil(subject.errorMessage); XCTAssertEqual(repository.createdDrafts.count, 1); XCTAssertEqual(repository.updateCalls.count, 1)
    }

    func testRoutineReminderTimeRoundTripsInInjectedTimezone() {
        var tokyo = Calendar(identifier: .gregorian); tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let now = tokyo.date(from: DateComponents(year: 2026, month: 8, day: 24, hour: 9))!; let subject = RoutinesViewModel(repository: FakeRoutineRepository(), calendar: tokyo, now: { now })
        let date = subject.reminderDate(hour: 23, minute: 59); let parts = subject.reminderComponents(for: date)
        XCTAssertEqual(parts.hour, 23); XCTAssertEqual(parts.minute, 59)
    }

    func testRoutineReminderTimeRoundTripsAcrossLosAngelesDSTDates() {
        var losAngeles = Calendar(identifier: .gregorian); losAngeles.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let springNow = losAngeles.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 9))!; let subject = RoutinesViewModel(repository: FakeRoutineRepository(), calendar: losAngeles, now: { springNow })
        for pair in [(2, 30), (1, 30), (23, 59)] { let parts = subject.reminderComponents(for: subject.reminderDate(hour: pair.0, minute: pair.1)); XCTAssertEqual(parts.hour, pair.0); XCTAssertEqual(parts.minute, pair.1) }
    }

    func testRoutineHistoryAccessibilityUsesLocalizedDatesAndStates() {
        let subject = RoutinesViewModel(repository: FakeRoutineRepository(), calendar: calendar)
        let history = [RoutineHistoryDay(day: .init(year: 2026, month: 8, day: 24), isScheduled: true, isCompleted: true), RoutineHistoryDay(day: .init(year: 2026, month: 8, day: 25), isScheduled: false, isCompleted: false)]
        let text = subject.historyAccessibilityValue(history)
        XCTAssertFalse(text.contains("2026-8-24")); XCTAssertTrue(text.contains("scheduled")); XCTAssertTrue(text.contains("completed")); XCTAssertEqual(subject.windowName(.anytime), "Anytime")
    }

    func testRoutinePauseAndArchiveRetainExactStateAcrossRefreshFailure() async {
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 24, hour: 9))!; let day = LocalDay(date: now, calendar: calendar); let routine = RoutineSnapshot(id: UUID(), title: "Read", weekdays: [calendar.component(.weekday, from: now)], window: .anytime, reminderHour: nil, reminderMinute: nil, isPaused: false, isArchived: false)
        let repository = FakeRoutineRepository(routines: [routine]); try? repository.setCompleted(routineID: routine.id, day: day, completed: true); let subject = RoutinesViewModel(repository: repository, calendar: calendar, now: { now }); subject.reload(); repository.listError = TestError.failed
        subject.setPaused(id: routine.id, paused: true); XCTAssertEqual(repository.pauseCalls, [.init(id: routine.id, value: true)]); XCTAssertTrue(subject.active[0].routine.isPaused); XCTAssertTrue(subject.active[0].isCompletedToday)
        subject.setArchived(id: routine.id, archived: true); XCTAssertEqual(repository.archiveCalls, [.init(id: routine.id, value: true)]); XCTAssertTrue(subject.archived[0].routine.isArchived); XCTAssertTrue(subject.archived[0].isCompletedToday)
        await subject.setCompleted(id: routine.id, completed: false); XCTAssertEqual(repository.completionCalls.last, .init(id: routine.id, day: day, completed: false))
        repository.listError = nil; subject.reload(); XCTAssertNil(subject.errorMessage); XCTAssertEqual(repository.pauseCalls.count, 1); XCTAssertEqual(repository.archiveCalls.count, 1)
    }

    func testRoutinePauseFailureCapturesExactActionAndRetriesOnce() {
        let routine = RoutineSnapshot(id: UUID(), title: "Read", weekdays: [1], window: .anytime, reminderHour: nil, reminderMinute: nil, isPaused: false, isArchived: false); let repository = FakeRoutineRepository(routines: [routine]); let subject = RoutinesViewModel(repository: repository, calendar: calendar)
        subject.reload(); repository.pauseError = TestError.failed; subject.setPaused(id: routine.id, paused: true)
        XCTAssertFalse(subject.active[0].routine.isPaused); XCTAssertEqual(subject.failedActionOperation, .pause(routine.id, true)); XCTAssertTrue(repository.pauseCalls.isEmpty)
        repository.pauseError = nil; subject.retryFailedAction(); XCTAssertEqual(repository.pauseCalls, [.init(id: routine.id, value: true)]); XCTAssertTrue(subject.active[0].routine.isPaused); XCTAssertNil(subject.failedActionOperation)
        subject.retryFailedAction(); XCTAssertEqual(repository.pauseCalls.count, 1)
    }

    func testRoutineCompletionFailureRetryUsesOriginallyCapturedDay() async {
        var now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 24, hour: 9))!; let original = LocalDay(date: now, calendar: calendar); let routine = RoutineSnapshot(id: UUID(), title: "Read", weekdays: [calendar.component(.weekday, from: now)], window: .anytime, reminderHour: nil, reminderMinute: nil, isPaused: false, isArchived: false)
        let repository = FakeRoutineRepository(routines: [routine]); let subject = RoutinesViewModel(repository: repository, calendar: calendar, now: { now }); subject.reload(); repository.completionError = TestError.failed
        await subject.setCompleted(id: routine.id, completed: true); XCTAssertEqual(subject.failedActionOperation, .completion(routine.id, original, true)); XCTAssertFalse(subject.active[0].isCompletedToday)
        now = calendar.date(byAdding: .day, value: 1, to: now)!; repository.completionError = nil; subject.retryFailedAction()
        XCTAssertEqual(repository.completionCalls.last, .init(id: routine.id, day: original, completed: true)); XCTAssertNil(subject.failedActionOperation); XCTAssertTrue(subject.active[0].history.contains { $0.day == original && $0.isCompleted })
        let calls = repository.completionCalls.count; subject.retryFailedAction(); XCTAssertEqual(repository.completionCalls.count, calls)
    }

    func testRoutineDeleteFailureRetainsExactOperationThenRetriesOnce() {
        let routine = RoutineSnapshot(id: UUID(), title: "Read", weekdays: [1], window: .anytime, reminderHour: nil, reminderMinute: nil, isPaused: false, isArchived: false); let repository = FakeRoutineRepository(routines: [routine]); let subject = RoutinesViewModel(repository: repository, calendar: calendar); subject.reload()
        repository.deleteError = TestError.failed; XCTAssertFalse(subject.delete(id: routine.id)); XCTAssertTrue(subject.active.contains { $0.id == routine.id }); XCTAssertEqual(subject.failedActionOperation, .delete(routine.id)); XCTAssertTrue(repository.deleteCalls.isEmpty)
        repository.deleteError = nil; subject.retryFailedAction(); XCTAssertEqual(repository.deleteCalls, [routine.id]); XCTAssertFalse(subject.active.contains { $0.id == routine.id }); XCTAssertNil(subject.failedActionOperation)
    }

    func testRoutineArchiveFailureRetriesExactOperation() {
        let routine = RoutineSnapshot(id: UUID(), title: "Read", weekdays: [1], window: .anytime, reminderHour: nil, reminderMinute: nil, isPaused: false, isArchived: false); let repository = FakeRoutineRepository(routines: [routine]); let subject = RoutinesViewModel(repository: repository, calendar: calendar); subject.reload()
        repository.archiveError = TestError.failed; subject.setArchived(id: routine.id, archived: true); XCTAssertTrue(subject.active.contains { $0.id == routine.id }); XCTAssertEqual(subject.failedActionOperation, .archive(routine.id, true)); XCTAssertTrue(repository.archiveCalls.isEmpty)
        repository.archiveError = nil; subject.retryFailedAction(); XCTAssertEqual(repository.archiveCalls, [.init(id: routine.id, value: true)]); XCTAssertTrue(subject.archived.contains { $0.id == routine.id }); XCTAssertNil(subject.failedActionOperation)
    }

    func testConfirmedRoutineDeleteStaysAbsentWhenRefreshFails() {
        let routine = RoutineSnapshot(id: UUID(), title: "Read", weekdays: [1], window: .anytime, reminderHour: nil, reminderMinute: nil, isPaused: false, isArchived: false); let repository = FakeRoutineRepository(routines: [routine]); let subject = RoutinesViewModel(repository: repository, calendar: calendar); subject.reload(); repository.listError = TestError.failed
        XCTAssertTrue(subject.delete(id: routine.id)); XCTAssertFalse(subject.active.contains { $0.id == routine.id }); XCTAssertEqual(repository.deleteCalls, [routine.id]); XCTAssertTrue(subject.errorMessage?.contains("saved") == true)
        repository.listError = nil; subject.reload(); XCTAssertEqual(repository.deleteCalls.count, 1); XCTAssertFalse(subject.active.contains { $0.id == routine.id })
    }

    func testRoutineCreateFailureKeepsNormalizedDraftThenEditedRetryCreatesOnce() {
        let repository = FakeRoutineRepository(); let subject = RoutinesViewModel(repository: repository, calendar: calendar); repository.createError = TestError.failed
        XCTAssertFalse(subject.create(.init(title: "  First  ", weekdays: [1], window: .morning, reminderHour: 8, reminderMinute: 0))); XCTAssertEqual(subject.failedEditorOperation, .create); XCTAssertEqual(subject.draftOnFailure?.title, "First"); XCTAssertTrue(subject.active.isEmpty)
        repository.createError = nil; let edited = RoutineDraft(title: "Edited", weekdays: [2, 3], window: .evening, reminderHour: 23, reminderMinute: 59); XCTAssertTrue(subject.create(edited)); XCTAssertEqual(repository.createdDrafts, [edited]); XCTAssertTrue(subject.active.contains { $0.routine.title == "Edited" }); XCTAssertNil(subject.failedEditorOperation)
    }

    func testRoutineUpdateFailureKeepsRowThenEditedRetryUsesExactIDAndDraft() {
        let routine = RoutineSnapshot(id: UUID(), title: "Old", weekdays: [1], window: .anytime, reminderHour: nil, reminderMinute: nil, isPaused: false, isArchived: false); let repository = FakeRoutineRepository(routines: [routine]); let subject = RoutinesViewModel(repository: repository, calendar: calendar); subject.reload(); repository.updateError = TestError.failed
        XCTAssertFalse(subject.update(id: routine.id, draft: .init(title: "  Failed  ", weekdays: [2], window: .morning, reminderHour: 8, reminderMinute: 0))); XCTAssertEqual(subject.active[0].routine.title, "Old"); XCTAssertEqual(subject.failedEditorOperation, .update(routine.id)); XCTAssertEqual(subject.draftOnFailure?.title, "Failed")
        repository.updateError = nil; let edited = RoutineDraft(title: "Edited", weekdays: [3, 4], window: .evening, reminderHour: 23, reminderMinute: 59); XCTAssertTrue(subject.update(id: routine.id, draft: edited)); XCTAssertEqual(repository.updateCalls, [.init(id: routine.id, draft: edited)]); XCTAssertEqual(subject.active[0].routine.title, "Edited"); XCTAssertNil(subject.failedEditorOperation)
    }

    func testRoutineCompletionAndUndoRetainConfirmedHistoryAcrossRefreshFailures() async {
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 24, hour: 9))!; let day = LocalDay(date: now, calendar: calendar); let yesterday = LocalDay(date: calendar.date(byAdding: .day, value: -1, to: now)!, calendar: calendar); let routine = RoutineSnapshot(id: UUID(), title: "Read", weekdays: [1, 2, 3, 4, 5, 6, 7], window: .anytime, reminderHour: nil, reminderMinute: nil, isPaused: false, isArchived: false)
        let repository = FakeRoutineRepository(routines: [routine]); try? repository.setCompleted(routineID: routine.id, day: yesterday, completed: true); let subject = RoutinesViewModel(repository: repository, calendar: calendar, now: { now }); subject.reload(); repository.listError = TestError.failed
        await subject.setCompleted(id: routine.id, completed: true); XCTAssertEqual(repository.completionCalls.last, .init(id: routine.id, day: day, completed: true)); XCTAssertTrue(subject.active[0].isCompletedToday); XCTAssertGreaterThanOrEqual(subject.active[0].streak, 2); XCTAssertTrue(subject.errorMessage?.contains("saved") == true)
        repository.listError = nil; subject.reload(); let calls = repository.completionCalls.count; XCTAssertNil(subject.errorMessage); XCTAssertEqual(repository.completionCalls.count, calls)
        repository.completedDaysErrors[routine.id] = TestError.failed; await subject.setCompleted(id: routine.id, completed: false); XCTAssertEqual(repository.completionCalls.last, .init(id: routine.id, day: day, completed: false)); XCTAssertFalse(subject.active[0].isCompletedToday); XCTAssertTrue(subject.errorMessage?.contains("saved") == true)
        repository.completedDaysErrors[routine.id] = nil; subject.reload(); XCTAssertEqual(repository.completionCalls.count, calls + 1)
    }

    func testRoutineDeleteAndRefreshErrorsStaySeparateAndRefreshNeverDeletes() {
        let routine = RoutineSnapshot(id: UUID(), title: "Read", weekdays: [1], window: .anytime, reminderHour: nil, reminderMinute: nil, isPaused: false, isArchived: false); let repository = FakeRoutineRepository(routines: [routine]); let subject = RoutinesViewModel(repository: repository, calendar: calendar); subject.reload(); repository.deleteError = TestError.failed
        XCTAssertFalse(subject.delete(id: routine.id)); XCTAssertEqual(subject.failedActionOperation, .delete(routine.id)); XCTAssertNotNil(subject.actionErrorMessage); XCTAssertEqual(subject.deleteRetryTarget?.id, routine.id)
        subject.reload(); repository.listError = TestError.failed; subject.reload(); XCTAssertNotNil(subject.refreshErrorMessage); XCTAssertEqual(repository.deleteCalls.count, 0)
        subject.reload(); XCTAssertEqual(repository.deleteCalls.count, 0); repository.deleteError = nil; XCTAssertTrue(subject.delete(id: routine.id)); XCTAssertEqual(repository.deleteCalls, [routine.id])
    }

    func testRoutineStaleRepresentedDayCannotWriteUntilReload() async {
        var now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 24, hour: 9))!; let day1 = LocalDay(date: now, calendar: calendar); let weekday1 = calendar.component(.weekday, from: now)
        let routine = RoutineSnapshot(id: UUID(), title: "Read", weekdays: [weekday1, weekday1 == 7 ? 1 : weekday1 + 1], window: .anytime, reminderHour: nil, reminderMinute: nil, isPaused: false, isArchived: false); let repository = FakeRoutineRepository(routines: [routine]); try? repository.setCompleted(routineID: routine.id, day: day1, completed: true); let subject = RoutinesViewModel(repository: repository, calendar: calendar, now: { now }); subject.reload(); XCTAssertEqual(subject.active[0].representedDay, day1)
        now = calendar.date(byAdding: .day, value: 1, to: now)!; let calls = repository.completionCalls.count; await subject.setCompleted(id: routine.id, completed: false); XCTAssertEqual(repository.completionCalls.count, calls); XCTAssertEqual(subject.active[0].representedDay, day1); XCTAssertNotNil(subject.refreshErrorMessage)
        subject.reload(); let day2 = LocalDay(date: now, calendar: calendar); XCTAssertEqual(subject.active[0].representedDay, day2); XCTAssertFalse(subject.active[0].isCompletedToday); await subject.setCompleted(id: routine.id, completed: true); XCTAssertEqual(repository.completionCalls.last, .init(id: routine.id, day: day2, completed: true)); XCTAssertEqual(subject.active[0].representedDay, day2)
    }

    func testRoutineEditorErrorSurvivesSuccessfulReloadIndependently() {
        let repository = FakeRoutineRepository(); let subject = RoutinesViewModel(repository: repository, calendar: calendar); repository.createError = TestError.failed
        XCTAssertFalse(subject.create(.init(title: "Read", weekdays: [1], window: .anytime, reminderHour: nil, reminderMinute: nil))); let editor = subject.editorErrorMessage; subject.reload()
        XCTAssertEqual(subject.editorErrorMessage, editor); XCTAssertEqual(subject.failedEditorOperation, .create); XCTAssertNil(subject.refreshErrorMessage); XCTAssertNil(subject.failedActionOperation)
    }

    private func reminder(id: String, title: String, due: Date?, hasTime: Bool) -> ReminderSnapshot {
        .init(id: id, title: title, notes: nil, dueDate: due, dueHasTime: hasTime, priority: 5, listID: "list", listTitle: "List", isCompleted: false, allowsModification: true, hasRecurrence: false)
    }
}

private enum TestError: Error { case failed }
