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
}

private enum TestError: Error { case failed }
