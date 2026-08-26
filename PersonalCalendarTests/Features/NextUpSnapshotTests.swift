import XCTest
@testable import PersonalCalendar

@MainActor
final class NextUpSnapshotTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    func testCurrentTimedEventWinsOverTheNextEventAndKeepsTypedDetails() throws {
        let now = date(hour: 10, minute: 30)
        let current = event(
            id: "current",
            title: "Design studio",
            start: date(hour: 10),
            end: date(hour: 11),
            location: "  Room E2-07  "
        )
        let next = event(
            id: "next",
            title: "Seminar",
            start: date(hour: 10, minute: 45),
            end: date(hour: 12),
            location: "Auditorium"
        )
        let agenda = DayAgenda(
            allDay: [],
            scheduled: [AgendaItem(event: next), AgendaItem(event: current)],
            priority: []
        )

        let snapshot = try XCTUnwrap(NextUpBuilder().build(
            agenda: agenda,
            events: [next, current],
            reminders: [],
            now: now
        ))

        XCTAssertEqual(snapshot.event?.title, "Design studio")
        XCTAssertEqual(snapshot.event?.origin, .event(id: "current"))
        XCTAssertEqual(snapshot.event?.start, current.start)
        XCTAssertEqual(snapshot.event?.end, current.end)
        XCTAssertEqual(snapshot.event?.phase, .current)
        XCTAssertEqual(snapshot.event?.location, "Room E2-07")
    }

    func testNextTimedEventIsUsedWhenNothingIsInProgress() throws {
        let now = date(hour: 9)
        let ended = event(
            id: "ended",
            title: "Ended",
            start: date(hour: 7),
            end: date(hour: 8)
        )
        let allDay = event(
            id: "all-day",
            title: "Holiday",
            start: date(hour: 0),
            end: date(day: 25, hour: 0),
            isAllDay: true
        )
        let later = event(
            id: "later",
            title: "Later",
            start: date(hour: 14),
            end: date(hour: 15)
        )
        let next = event(
            id: "next",
            title: "Next lecture",
            start: date(hour: 11),
            end: date(hour: 12)
        )
        let agenda = DayAgenda(
            allDay: [AgendaItem(event: allDay)],
            scheduled: [
                AgendaItem(event: ended),
                AgendaItem(event: later),
                AgendaItem(event: next)
            ],
            priority: []
        )

        let snapshot = try XCTUnwrap(NextUpBuilder().build(
            agenda: agenda,
            events: [later, allDay, ended, next],
            reminders: [],
            now: now
        ))

        XCTAssertEqual(snapshot.event?.title, "Next lecture")
        XCTAssertEqual(snapshot.event?.origin, .event(id: "next"))
        XCTAssertEqual(snapshot.event?.phase, .upcoming)
    }

    func testNearestIncompleteFutureDeadlineWinsAndKeepsReminderOrigin() throws {
        let now = date(hour: 9)
        let nearest = reminder(
            id: "nearest",
            title: "Submit lab",
            due: date(hour: 12),
            dueHasTime: true
        )
        let later = reminder(
            id: "later",
            title: "Read chapter",
            due: date(day: 25, hour: 0),
            dueHasTime: false
        )
        let completed = reminder(
            id: "completed",
            title: "Already done",
            due: date(hour: 10),
            dueHasTime: true,
            isCompleted: true
        )
        let overdue = reminder(
            id: "overdue",
            title: "Too late",
            due: date(hour: 8),
            dueHasTime: true
        )
        let undated = reminder(
            id: "undated",
            title: "Someday",
            due: nil,
            dueHasTime: false
        )

        let snapshot = try XCTUnwrap(NextUpBuilder().build(
            agenda: .init(allDay: [], scheduled: [], priority: []),
            events: [],
            reminders: [later, completed, undated, overdue, nearest],
            now: now
        ))

        XCTAssertEqual(snapshot.deadline?.title, "Submit lab")
        XCTAssertEqual(snapshot.deadline?.origin, .reminder(id: "nearest"))
        XCTAssertEqual(snapshot.deadline?.dueDate, nearest.dueDate)
        XCTAssertEqual(snapshot.deadline?.dueHasTime, true)
    }

    func testDateOnlyTaskDueTodayRemainsAnEligibleDeadlineAfterMidnight() throws {
        let today = reminder(
            id: "today",
            title: "Submit reflection",
            due: date(hour: 0),
            dueHasTime: false
        )

        let snapshot = try XCTUnwrap(NextUpBuilder().build(
            agenda: .init(allDay: [], scheduled: [], priority: []),
            events: [],
            reminders: [today],
            now: date(hour: 16),
            calendar: calendar
        ))

        XCTAssertEqual(snapshot.deadline?.origin, .reminder(id: "today"))
        XCTAssertEqual(snapshot.deadline?.dueHasTime, false)
    }

    func testBlankEventLocationIsRemovedSoMapsIsUnavailable() throws {
        let now = date(hour: 9)
        let next = event(
            id: "next",
            title: "Online lecture",
            start: date(hour: 10),
            end: date(hour: 11),
            location: " \n\t "
        )

        let snapshot = try XCTUnwrap(NextUpBuilder().build(
            agenda: .init(
                allDay: [],
                scheduled: [AgendaItem(event: next)],
                priority: []
            ),
            events: [next],
            reminders: [],
            now: now
        ))

        XCTAssertNil(snapshot.event?.location)
    }

    func testNoEligibleEventOrDeadlineReturnsNil() {
        let ended = event(
            id: "ended",
            title: "Ended",
            start: date(hour: 7),
            end: date(hour: 8)
        )
        let completed = reminder(
            id: "completed",
            title: "Done",
            due: date(hour: 12),
            dueHasTime: true,
            isCompleted: true
        )

        XCTAssertNil(NextUpBuilder().build(
            agenda: .init(
                allDay: [],
                scheduled: [AgendaItem(event: ended)],
                priority: []
            ),
            events: [ended],
            reminders: [completed],
            now: date(hour: 9)
        ))
    }

    func testTodayDerivesNextUpFromTheSingleConfirmedLoadWithoutExtraFetch() async {
        let now = date(hour: 9)
        let next = event(
            id: "lecture",
            title: "Lecture",
            start: date(hour: 10),
            end: date(hour: 11),
            location: "Room 4"
        )
        let deadline = reminder(
            id: "assignment",
            title: "Assignment",
            due: date(hour: 14),
            dueHasTime: true
        )
        let calendars = FakeCalendarService(access: .granted, events: [next])
        let reminders = FakeRemindersService(access: .granted, reminders: [deadline])
        let routines = FakeRoutineRepository()
        let subject = TodayViewModel(
            calendar: calendars,
            reminders: reminders,
            routines: routines,
            composer: AgendaComposer(),
            settings: AppSettingsStore(defaults: .ephemeral),
            calendarProvider: { self.calendar },
            now: { now }
        )

        await subject.load()
        let providerCallCounts = (
            calendars.fetchCalendarIDs.count,
            reminders.fetchListIDs.count,
            routines.listCallCount
        )

        XCTAssertEqual(subject.nextUp?.event?.origin, .event(id: "lecture"))
        XCTAssertEqual(subject.nextUp?.deadline?.origin, .reminder(id: "assignment"))
        XCTAssertEqual(calendars.fetchCalendarIDs.count, providerCallCounts.0)
        XCTAssertEqual(reminders.fetchListIDs.count, providerCallCounts.1)
        XCTAssertEqual(routines.listCallCount, providerCallCounts.2)
    }

    func testTodayRefreshesNextUpFromCachedContentWithoutProviderFetches() async {
        var referenceNow = date(hour: 9, minute: 30)
        let current = event(
            id: "current",
            title: "Current lecture",
            start: date(hour: 9),
            end: date(hour: 10)
        )
        let next = event(
            id: "next",
            title: "Next lecture",
            start: date(hour: 11),
            end: date(hour: 12)
        )
        let calendars = FakeCalendarService(
            access: .granted,
            events: [current, next]
        )
        let reminders = FakeRemindersService(access: .granted)
        let routines = FakeRoutineRepository()
        let subject = TodayViewModel(
            calendar: calendars,
            reminders: reminders,
            routines: routines,
            composer: AgendaComposer(),
            settings: AppSettingsStore(defaults: .ephemeral),
            calendarProvider: { self.calendar },
            now: { referenceNow }
        )

        await subject.load()
        let providerCallCounts = (
            calendars.fetchCalendarIDs.count,
            reminders.fetchListIDs.count,
            routines.listCallCount
        )
        XCTAssertEqual(subject.nextUp?.event?.origin, .event(id: "current"))

        referenceNow = date(hour: 10, minute: 30)
        subject.refreshNextUp()

        XCTAssertEqual(subject.nextUp?.event?.origin, .event(id: "next"))
        XCTAssertEqual(calendars.fetchCalendarIDs.count, providerCallCounts.0)
        XCTAssertEqual(reminders.fetchListIDs.count, providerCallCounts.1)
        XCTAssertEqual(routines.listCallCount, providerCallCounts.2)
    }

    func testRoutineAgendaItemKeepsTypedOriginForTodayOpenAction() {
        let routineID = UUID()
        let day = LocalDay(year: 2026, month: 8, day: 24)
        let routine = RoutineSnapshot(
            id: routineID,
            title: "Read",
            weekdays: [2],
            window: .anytime,
            reminderHour: nil,
            reminderMinute: nil,
            isPaused: false,
            isArchived: false
        )

        let item = AgendaItem(
            routine: routine,
            completed: false,
            day: day,
            calendar: calendar
        )

        XCTAssertEqual(item.origin, .routine(id: routineID, day: day))
    }

    private func date(day: Int = 24, hour: Int, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: day,
            hour: hour,
            minute: minute
        ))!
    }

    private func event(
        id: String,
        title: String,
        start: Date,
        end: Date,
        isAllDay: Bool = false,
        location: String? = nil
    ) -> CalendarEventSnapshot {
        CalendarEventSnapshot(
            id: id,
            title: title,
            start: start,
            end: end,
            isAllDay: isAllDay,
            calendarID: "school",
            calendarTitle: "School",
            allowsModification: true,
            hasRecurrence: false,
            location: location
        )
    }

    private func reminder(
        id: String,
        title: String,
        due: Date?,
        dueHasTime: Bool,
        isCompleted: Bool = false
    ) -> ReminderSnapshot {
        ReminderSnapshot(
            id: id,
            title: title,
            notes: nil,
            dueDate: due,
            dueHasTime: dueHasTime,
            priority: 0,
            listID: "school-tasks",
            listTitle: "School Tasks",
            isCompleted: isCompleted,
            allowsModification: true,
            hasRecurrence: false
        )
    }
}
