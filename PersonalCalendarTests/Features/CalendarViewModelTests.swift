import XCTest
@testable import PersonalCalendar

@MainActor
final class CalendarViewModelTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }
    private let today = LocalDay(year: 2026, month: 8, day: 24)

    func testLoadUsesOnlySelectedSources() async {
        let start = today.startDate(in: calendar).addingTimeInterval(3_600)
        let event = CalendarEventSnapshot(id: "included", title: "Included", start: start, end: start.addingTimeInterval(3_600), isAllDay: false, calendarID: "included", calendarTitle: "Included", allowsModification: true, hasRecurrence: false)
        let ignored = CalendarEventSnapshot(id: "ignored", title: "Ignored", start: start, end: start.addingTimeInterval(3_600), isAllDay: false, calendarID: "ignored", calendarTitle: "Ignored", allowsModification: true, hasRecurrence: false)
        let settings = AppSettingsStore(defaults: .ephemeral)
        settings.replaceSelectedCalendarIDs(["included"], availableIDs: ["included"])
        let model = makeModel(calendarService: FakeCalendarService(access: .granted, events: [event, ignored]), settings: settings)

        await model.load()

        XCTAssertEqual(model.agenda.scheduled.map(\.title), ["Included"])
    }

    func testExplicitStaleSourcesShowNoneAndNeverCallEmptyMeansAllServiceBoundary() async {
        let defaults = UserDefaults.ephemeral
        defaults.set(["gone"], forKey: "selectedCalendarIDs")
        defaults.set(true, forKey: "selectedCalendarIDsAreExplicit")
        defaults.set(["gone-list"], forKey: "selectedReminderListIDs")
        defaults.set(true, forKey: "selectedReminderListIDsAreExplicit")
        let settings = AppSettingsStore(defaults: defaults)
        let start = today.startDate(in: calendar).addingTimeInterval(3_600)
        let calendarService = FakeCalendarService(access: .granted, events: [.init(id: "event", title: "Event", start: start, end: start.addingTimeInterval(60), isAllDay: false, calendarID: "current", calendarTitle: "Current", allowsModification: true, hasRecurrence: false)], descriptors: [.init(id: "current", title: "Current", colorHex: "#000", allowsContentModifications: true)])
        let reminders = FakeRemindersService(access: .granted, reminders: [.init(id: "task", title: "Task", notes: nil, dueDate: start, dueHasTime: true, priority: 1, listID: "current-list", listTitle: "Current", isCompleted: false, allowsModification: true, hasRecurrence: false)], descriptors: [.init(id: "current-list", title: "Current", colorHex: "#000", allowsContentModifications: true)])
        let model = makeModel(calendarService: calendarService, reminders: reminders, settings: settings)

        await model.load()

        XCTAssertTrue(model.agenda.scheduled.isEmpty)
        XCTAssertTrue(calendarService.fetchCalendarIDs.isEmpty)
        XCTAssertTrue(reminders.fetchListIDs.isEmpty)
    }

    func testDeniedCalendarKeepsOtherSourcesAndReportsPermission() async {
        let routine = RoutineSnapshot.sampleRoutine
        let model = makeModel(calendarService: FakeCalendarService(access: .denied), routines: FakeRoutineRepository(routines: [routine]))

        await model.load()

        XCTAssertEqual(model.agenda.scheduled.map(\.title), ["Read"])
        let notice = try! XCTUnwrap(model.sourceAccessNotices.first)
        XCTAssertEqual(model.sourceAccessNotices.count, 1)
        XCTAssertEqual(notice.source, .calendar)
        XCTAssertEqual(notice.accessState, .denied)
        XCTAssertEqual(notice.message, "Calendar access is unavailable. Calendar events are hidden.")
        XCTAssertEqual(notice.action, .openSettings)
        XCTAssertTrue(notice.canOpenSettings)
    }

    func testRestrictedCalendarReportsControlledHiddenSourceWithoutHidingRoutine() async {
        let model = makeModel(
            calendarService: FakeCalendarService(access: .restricted),
            routines: FakeRoutineRepository(routines: [.sampleRoutine])
        )

        await model.load()

        XCTAssertEqual(model.agenda.scheduled.map(\.title), ["Read"])
        let notice = try! XCTUnwrap(model.sourceAccessNotices.first)
        XCTAssertEqual(model.sourceAccessNotices.count, 1)
        XCTAssertEqual(notice.source, .calendar)
        XCTAssertEqual(notice.accessState, .restricted)
        XCTAssertEqual(notice.message, "Calendar access is restricted. Calendar events are hidden because this access is controlled by your device or account.")
        XCTAssertNil(notice.action)
        XCTAssertFalse(notice.canOpenSettings)
    }

    func testRestrictedRemindersReportsControlledHiddenSourceWithoutHidingRoutine() async {
        let model = makeModel(
            reminders: FakeRemindersService(access: .restricted),
            routines: FakeRoutineRepository(routines: [.sampleRoutine])
        )

        await model.load()

        XCTAssertEqual(model.agenda.scheduled.map(\.title), ["Read"])
        let notice = try! XCTUnwrap(model.sourceAccessNotices.first)
        XCTAssertEqual(model.sourceAccessNotices.count, 1)
        XCTAssertEqual(notice.source, .reminders)
        XCTAssertEqual(notice.accessState, .restricted)
        XCTAssertEqual(notice.message, "Reminders access is restricted. Tasks are hidden because this access is controlled by your device or account.")
        XCTAssertNil(notice.action)
        XCTAssertFalse(notice.canOpenSettings)
    }

    func testNotDeterminedSourcesRetainInAppSettingsRoute() async {
        let model = makeModel(
            calendarService: FakeCalendarService(access: .notDetermined),
            reminders: FakeRemindersService(access: .notDetermined)
        )

        await model.load()

        XCTAssertEqual(model.sourceAccessNotices.map(\.source), [.calendar, .reminders])
        XCTAssertEqual(model.sourceAccessNotices.map(\.accessState), [.notDetermined, .notDetermined])
        XCTAssertEqual(model.sourceAccessNotices.map(\.action), [.openSettings, .openSettings])
        XCTAssertTrue(model.sourceAccessNotices.allSatisfy(\.canOpenSettings))
    }

    func testSelectingDayRecomposesAgendaForThatDay() async {
        let next = LocalDay(year: 2026, month: 8, day: 25)
        let start = next.startDate(in: calendar).addingTimeInterval(3_600)
        let event = CalendarEventSnapshot(id: "next", title: "Tomorrow", start: start, end: start.addingTimeInterval(3_600), isAllDay: false, calendarID: "calendar", calendarTitle: "Calendar", allowsModification: true, hasRecurrence: false)
        let model = makeModel(calendarService: FakeCalendarService(access: .granted, events: [event]))
        await model.load()

        await model.select(next)

        XCTAssertEqual(model.selectedDay, next)
        XCTAssertEqual(model.agenda.scheduled.map(\.title), ["Tomorrow"])
    }

    func testMovingMonthChangesDisplayedMonth() async {
        let model = makeModel()

        await model.moveMonth(by: 1)

        XCTAssertEqual(model.displayedMonth, LocalDay(year: 2026, month: 9, day: 1))
    }

    func testTrayStateChanges() {
        let model = makeModel()

        model.setTray(.expanded)

        XCTAssertEqual(model.trayState, .expanded)
    }

    func testFailedRefreshRetainsConfirmedAgenda() async {
        let start = today.startDate(in: calendar).addingTimeInterval(3_600)
        let event = CalendarEventSnapshot(id: "confirmed", title: "Confirmed", start: start, end: start.addingTimeInterval(3_600), isAllDay: false, calendarID: "calendar", calendarTitle: "Calendar", allowsModification: true, hasRecurrence: false)
        let service = FakeCalendarService(access: .granted, events: [event])
        let model = makeModel(calendarService: service)
        await model.load()
        service.fetchError = TestError.failed

        await model.load()

        XCTAssertEqual(model.agenda.scheduled.map(\.title), ["Confirmed"])
        XCTAssertNotNil(model.errorMessage)
    }

    func testOlderSuspendedLoadCannotRestoreDeselectedReminder() async {
        let due = today.startDate(in: calendar).addingTimeInterval(3_600)
        let old = ReminderSnapshot(id: "old", title: "Old", notes: nil, dueDate: due, dueHasTime: true, priority: 1, listID: "old", listTitle: "Old", isCompleted: false, allowsModification: true, hasRecurrence: false)
        let fresh = ReminderSnapshot(id: "fresh", title: "Fresh", notes: nil, dueDate: due, dueHasTime: true, priority: 1, listID: "fresh", listTitle: "Fresh", isCompleted: false, allowsModification: true, hasRecurrence: false)
        let settings = AppSettingsStore(defaults: .ephemeral)
        settings.replaceSelectedReminderListIDs(["old", "fresh"], availableIDs: ["old", "fresh"])
        let reminders = FakeRemindersService(access: .granted, reminders: [old, fresh])
        let model = makeModel(reminders: reminders, settings: settings)

        reminders.suspendNextFetch = true
        let older = Task { await model.load() }
        for _ in 0..<30 where !reminders.isFetchSuspended { await Task.yield() }
        settings.replaceSelectedReminderListIDs(["fresh"], availableIDs: ["fresh"])
        await model.load()
        reminders.resumeSuspendedFetch()
        await older.value

        XCTAssertEqual(model.agenda.scheduled.map(\.title), ["Fresh"])
    }

    func testOlderSuspendedFailureCannotReplaceNewerCalendarState() async {
        let due = today.startDate(in: calendar).addingTimeInterval(3_600)
        let old = ReminderSnapshot(id: "old", title: "Old", notes: nil, dueDate: due, dueHasTime: true, priority: 1, listID: "list", listTitle: "List", isCompleted: false, allowsModification: true, hasRecurrence: false)
        let reminders = FakeRemindersService(access: .granted, reminders: [old])
        let model = makeModel(reminders: reminders)

        reminders.suspendNextFetch = true
        let older = Task { await model.load() }
        for _ in 0..<30 where !reminders.isFetchSuspended { await Task.yield() }
        reminders.reminders = []
        await model.load()
        reminders.fetchError = TestError.failed
        reminders.resumeSuspendedFetch()
        await older.value

        XCTAssertTrue(model.agenda.scheduled.isEmpty)
        XCTAssertNil(model.errorMessage)
    }

    func testFailedEventSaveRetainsExactDraftForRetry() async {
        let service = FakeCalendarService(access: .granted, createError: TestError.failed)
        let model = makeModel(calendarService: service)
        let draft = EventDraft(title: "Dentist", start: today.startDate(in: calendar).addingTimeInterval(3_600), end: today.startDate(in: calendar).addingTimeInterval(7_200), isAllDay: false, calendarID: "calendar")

        await model.createEvent(draft)

        XCTAssertEqual(model.eventDraftOnFailure, draft)
        XCTAssertNotNil(model.errorMessage)
    }

    func testVisibleAgendasIncludeNonselectedDaySourceItems() async {
        let other = LocalDay(year: 2026, month: 8, day: 25)
        let start = other.startDate(in: calendar).addingTimeInterval(3_600)
        let event = CalendarEventSnapshot(id: "other", title: "Other day", start: start, end: start.addingTimeInterval(3_600), isAllDay: false, calendarID: "calendar", calendarTitle: "Calendar", allowsModification: true, hasRecurrence: false)
        let model = makeModel(calendarService: FakeCalendarService(access: .granted, events: [event]))
        await model.load()

        XCTAssertEqual(model.visibleAgendas[other]?.scheduled.map(\.source), [.event])
        XCTAssertEqual(model.visibleAgendas[other]?.scheduled.map(\.title), ["Other day"])
    }

    func testThrowingReminderRefreshKeepsConfirmedRemindersWhileOtherSourcesRefresh() async {
        let due = today.startDate(in: calendar)
        let reminder = ReminderSnapshot(id: "old", title: "Old reminder", notes: nil, dueDate: due, priority: 3, listID: "tasks", listTitle: "Tasks", isCompleted: false, allowsModification: true, hasRecurrence: false)
        let reminders = FakeRemindersService(access: .granted, reminders: [reminder])
        let events = FakeCalendarService(access: .granted)
        let routines = FakeRoutineRepository()
        let model = makeModel(calendarService: events, reminders: reminders, routines: routines)
        await model.load()
        events.events = [CalendarEventSnapshot(id: "new", title: "New event", start: due.addingTimeInterval(3_600), end: due.addingTimeInterval(7_200), isAllDay: false, calendarID: "calendar", calendarTitle: "Calendar", allowsModification: true, hasRecurrence: false)]
        reminders.fetchError = TestError.failed

        await model.load()

        XCTAssertTrue(model.agenda.priority.contains { $0.title == "Old reminder" })
        XCTAssertTrue(model.agenda.scheduled.contains { $0.title == "New event" })
    }

    func testRetryAfterFailedEventSaveClearsDraftAfterSuccess() async {
        let service = FakeCalendarService(access: .granted, createError: TestError.failed)
        let model = makeModel(calendarService: service)
        let draft = EventDraft(title: "Dentist", start: today.startDate(in: calendar).addingTimeInterval(3_600), end: today.startDate(in: calendar).addingTimeInterval(7_200), isAllDay: false, calendarID: "calendar")
        await model.createEvent(draft)
        service.createError = nil

        await model.createEvent(model.eventDraftOnFailure!)

        XCTAssertNil(model.eventDraftOnFailure)
        XCTAssertEqual(service.createdDrafts, [draft])
    }

    func testRestingTraySelectorsUseCorrectSourcesAndPriorityAcrossSections() {
        let earlyTask = AgendaItem(id: "task-early", title: "Timed task", source: .task, placement: .timed(Date(timeIntervalSince1970: 1)), sortDate: Date(timeIntervalSince1970: 1), priority: 5, isCompleted: false, allowsModification: true)
        let event = AgendaItem(id: "event", title: "Event", source: .event, placement: .timed(Date(timeIntervalSince1970: 2)), sortDate: Date(timeIntervalSince1970: 2), priority: 0, isCompleted: false, allowsModification: true)
        let highTask = AgendaItem(id: "task-high", title: "High task", source: .task, placement: .unscheduled, sortDate: nil, priority: 1, isCompleted: false, allowsModification: true)
        let routine = AgendaItem(id: "routine", title: "Routine", source: .routine, placement: .window(.anytime), sortDate: nil, priority: 0, isCompleted: false, allowsModification: true)
        let agenda = DayAgenda(allDay: [], scheduled: [earlyTask, event], priority: [highTask, routine])

        XCTAssertEqual(DayTrayView.nextEvent(in: agenda)?.title, "Event")
        XCTAssertEqual(DayTrayView.highestPriorityTask(in: agenda)?.title, "High task")
        XCTAssertEqual(DayTrayView.nextIncompleteRoutine(in: agenda)?.title, "Routine")
    }

    func testRoutineSelectionPrefersScheduledRoutineOverAlphabeticallyEarlierAnytimeRoutine() {
        let anytime = AgendaItem(id: "anytime", title: "A Anytime", source: .routine, placement: .window(.anytime), sortDate: nil, priority: 0, isCompleted: false, allowsModification: true)
        let scheduled = AgendaItem(id: "scheduled", title: "Z Scheduled", source: .routine, placement: .window(.morning), sortDate: Date(timeIntervalSince1970: 10), priority: 0, isCompleted: false, allowsModification: true)
        XCTAssertEqual(DayTrayView.nextIncompleteRoutine(in: .init(allDay: [], scheduled: [scheduled], priority: [anytime]))?.title, "Z Scheduled")
    }

    func testCompletionHistoryLoadsOncePerRoutineAndSelectionDoesNotRefetch() async {
        let routines = FakeRoutineRepository(routines: [.sampleRoutine])
        let model = makeModel(routines: routines)
        await model.load()
        let callsAfterLoad = routines.completedDaysCallCount

        await model.select(LocalDay(year: 2026, month: 8, day: 25))

        XCTAssertEqual(callsAfterLoad, 1)
        XCTAssertEqual(routines.completedDaysCallCount, callsAfterLoad)
    }

    func testFailedRoutineHistoryRefreshPreservesConfirmedRoutinesWhileEventsRefresh() async {
        let routines = FakeRoutineRepository(routines: [.sampleRoutine])
        try! routines.setCompleted(routineID: RoutineSnapshot.sampleRoutine.id, day: today, completed: true)
        let events = FakeCalendarService(access: .granted)
        let model = makeModel(calendarService: events, routines: routines)
        await model.load()
        events.events = [CalendarEventSnapshot(id: "fresh", title: "Fresh", start: today.startDate(in: calendar).addingTimeInterval(3_600), end: today.startDate(in: calendar).addingTimeInterval(7_200), isAllDay: false, calendarID: "calendar", calendarTitle: "Calendar", allowsModification: true, hasRecurrence: false)]
        routines.completedDaysError = TestError.failed
        await model.load()
        XCTAssertTrue(model.agenda.scheduled.contains { $0.title == "Fresh" })
        XCTAssertTrue(model.agenda.scheduled.contains { $0.title == "Read" && $0.isCompleted })
    }

    private func makeModel(calendarService: FakeCalendarService = FakeCalendarService(access: .granted), reminders: FakeRemindersService = FakeRemindersService(access: .granted), routines: FakeRoutineRepository = FakeRoutineRepository(), settings: AppSettingsStore = AppSettingsStore(defaults: .ephemeral)) -> CalendarViewModel {
        CalendarViewModel(today: today, calendarService: calendarService, remindersService: reminders, routines: routines, composer: AgendaComposer(), settings: settings, systemCalendar: calendar)
    }
}

private enum TestError: Error { case failed }
