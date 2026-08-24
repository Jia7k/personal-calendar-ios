import XCTest
@testable import PersonalCalendar

final class AgendaComposerTests: XCTestCase {
    // Break caught: merging sources without sectioning or chronological ordering would make a day unreadable.
    func testPlacesAllDayItemsBeforeChronologicalScheduledItemsAndPriorityItems() throws {
        let result = compose(
            events: [
                event(id: "all-day", title: "Birthday", startHour: 0, endHour: 24, isAllDay: true),
                event(id: "meeting", title: "Meeting", startHour: 8, endHour: 9)
            ],
            reminders: [reminder(id: "timed", title: "Call", dueHour: 10, priority: 1)],
            routines: [routine(id: "00000000-0000-0000-0000-000000000001", title: "Plan", window: .morning), routine(id: "00000000-0000-0000-0000-000000000002", title: "Reflect", window: .anytime)]
        )

        XCTAssertEqual(result.allDay.map(\.title), ["Birthday"])
        XCTAssertEqual(result.scheduled.map(\.title), ["Meeting", "Plan", "Call"])
        XCTAssertEqual(result.priority.map(\.title), ["Reflect"])
    }

    // Break caught: undated inbox tasks would leak from Tasks into Calendar and Today agendas.
    func testExcludesUndatedReminders() throws {
        let result = compose(reminders: [reminder(id: "inbox", title: "Someday", dueHour: nil, priority: 9)])

        XCTAssertTrue(result.allDay.isEmpty)
        XCTAssertTrue(result.scheduled.isEmpty)
        XCTAssertTrue(result.priority.isEmpty)
    }

    // Break caught: date-only tasks could receive an invented clock time and appear in the schedule.
    func testPlacesDateOnlyReminderDueOnSelectedDayInPriority() throws {
        let result = compose(reminders: [reminder(id: "date-only", title: "Pay rent", dueHour: nil, priority: 5, dueDate: date(hour: 0))])

        XCTAssertEqual(result.scheduled.map(\.title), [])
        XCTAssertEqual(result.priority.map(\.title), ["Pay rent"])
        XCTAssertNil(result.priority.first?.sortDate)
    }

    // Break caught: past-due tasks could appear in a selected-day Calendar agenda when overdue visibility is disabled.
    func testIncludesOverdueTimedReminderOnlyWhenRequested() throws {
        let overdue = reminder(id: "overdue", title: "File taxes", dueHour: 16, priority: 2, dueDate: date(dayOffset: -1, hour: 16))

        XCTAssertTrue(compose(reminders: [overdue], includeOverdue: false).scheduled.isEmpty)
        XCTAssertEqual(compose(reminders: [overdue], includeOverdue: true).scheduled.map(\.title), ["File taxes"])
    }

    // Break caught: a task due at the following local midnight would be displayed on the preceding day.
    func testIncludesStartOfDayTimedReminderAndExcludesFollowingMidnight() throws {
        let startOfDay = reminder(id: "start", title: "Start", dueHour: 0, priority: 1)
        let followingMidnight = reminder(id: "next", title: "Next", dueHour: 0, priority: 1, dueDate: date(dayOffset: 1, hour: 0))

        let result = compose(reminders: [startOfDay, followingMidnight])

        XCTAssertEqual(result.scheduled.map(\.title), ["Start"])
    }

    // Break caught: completed tasks would remain visible alongside actionable agenda items.
    func testExcludesCompletedReminders() throws {
        let completed = reminder(id: "done", title: "Finished", dueHour: 11, priority: 1, isCompleted: true)

        let result = compose(reminders: [completed])

        XCTAssertTrue(result.scheduled.isEmpty)
        XCTAssertTrue(result.priority.isEmpty)
    }

    // Break caught: paused, archived, or unscheduled routines would appear on a day where they are not actionable.
    func testIncludesOnlyActiveRoutinesScheduledForSelectedWeekday() throws {
        let result = compose(
            routines: [
                routine(id: "00000000-0000-0000-0000-000000000010", title: "Active", window: .afternoon),
                routine(id: "00000000-0000-0000-0000-000000000011", title: "Paused", window: .morning, isPaused: true),
                routine(id: "00000000-0000-0000-0000-000000000012", title: "Archived", window: .evening, isArchived: true),
                routine(id: "00000000-0000-0000-0000-000000000013", title: "Other day", window: .morning, weekdays: [3])
            ]
        )

        XCTAssertEqual(result.scheduled.map(\.title), ["Active"])
    }

    // Break caught: routine completion records would not be reflected in their day-agenda item.
    func testMarksCompletedRoutineFromCompletedRoutineIDs() throws {
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000014")!
        let result = compose(
            routines: [routine(id: id.uuidString, title: "Complete", window: .morning)],
            completedRoutineIDs: [id]
        )

        XCTAssertTrue(result.scheduled.first?.isCompleted == true)
    }

    // Break caught: events beginning before midnight would disappear even when they overlap the selected local day.
    func testIncludesEventOverlappingStartOfSelectedDay() throws {
        let result = compose(events: [event(id: "overnight", title: "Flight", startHour: 23, endHour: 2, startDayOffset: -1)])

        XCTAssertEqual(result.scheduled.map(\.title), ["Flight"])
    }

    // Break caught: equal-time items or equal-priority tasks could reorder nondeterministically between refreshes.
    func testUsesDeterministicSourceTitleAndIDTieOrdering() throws {
        let result = compose(
            events: [event(id: "event-b", title: "Same", startHour: 9, endHour: 10), event(id: "event-a", title: "Same", startHour: 9, endHour: 10)],
            reminders: [reminder(id: "task", title: "Same", dueHour: 9, priority: 1), reminder(id: "low", title: "Later alphabetically", dueHour: nil, priority: 9, dueDate: date(hour: 0)), reminder(id: "high", title: "Earlier alphabetically", dueHour: nil, priority: 1, dueDate: date(hour: 0))],
            routines: [routine(id: "00000000-0000-0000-0000-000000000020", title: "Same", window: .morning), routine(id: "00000000-0000-0000-0000-000000000021", title: "Zulu", window: .anytime), routine(id: "00000000-0000-0000-0000-000000000022", title: "Alpha", window: .anytime)]
        )

        XCTAssertEqual(result.scheduled.map(\.id), ["event|event-a", "event|event-b", "routine|00000000-0000-0000-0000-000000000020|2026-8-24", "task|task"])
        XCTAssertEqual(result.priority.map(\.title), ["Earlier alphabetically", "Later alphabetically", "Alpha", "Zulu"])
    }

    func testEventKitPriorityOrderingPlacesHighBeforeMediumLowAndNoneLast() throws {
        let result = compose(reminders: [
            reminder(id: "none", title: "None", dueHour: nil, priority: 0, dueDate: date(hour: 0)),
            reminder(id: "low", title: "Low", dueHour: nil, priority: 9, dueDate: date(hour: 0)),
            reminder(id: "medium", title: "Medium", dueHour: nil, priority: 5, dueDate: date(hour: 0)),
            reminder(id: "high", title: "High", dueHour: nil, priority: 1, dueDate: date(hour: 0))
        ])

        XCTAssertEqual(result.priority.map(\.title), ["High", "Medium", "Low", "None"])
    }

    private let day = LocalDay(year: 2026, month: 8, day: 24)

    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Singapore")!
        return value
    }

    private func compose(
        events: [CalendarEventSnapshot] = [],
        reminders: [ReminderSnapshot] = [],
        routines: [RoutineSnapshot] = [],
        completedRoutineIDs: Set<UUID> = [],
        includeOverdue: Bool = false
    ) -> DayAgenda {
        AgendaComposer().compose(day: day, events: events, reminders: reminders, routines: routines, completedRoutineIDs: completedRoutineIDs, includeOverdueTasks: includeOverdue, calendar: calendar)
    }

    private func date(dayOffset: Int = 0, hour: Int) -> Date {
        calendar.date(byAdding: .day, value: dayOffset, to: calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day.startDate(in: calendar))!)!
    }

    private func event(id: String, title: String, startHour: Int, endHour: Int, isAllDay: Bool = false, startDayOffset: Int = 0) -> CalendarEventSnapshot {
        .init(id: id, title: title, start: date(dayOffset: startDayOffset, hour: startHour), end: date(dayOffset: startDayOffset + (endHour <= startHour || endHour == 24 ? 1 : 0), hour: endHour % 24), isAllDay: isAllDay, calendarID: "calendar", calendarTitle: "Home", allowsModification: true, hasRecurrence: false)
    }

    private func reminder(id: String, title: String, dueHour: Int?, priority: Int, dueDate: Date? = nil, isCompleted: Bool = false) -> ReminderSnapshot {
        .init(id: id, title: title, notes: nil, dueDate: dueDate ?? dueHour.map { date(hour: $0) }, dueHasTime: dueHour != nil, priority: priority, listID: "list", listTitle: "Tasks", isCompleted: isCompleted, allowsModification: true, hasRecurrence: false)
    }

    private func routine(id: String, title: String, window: RoutineWindow, weekdays: Set<Int> = [2], isPaused: Bool = false, isArchived: Bool = false) -> RoutineSnapshot {
        .init(id: UUID(uuidString: id)!, title: title, weekdays: weekdays, window: window, reminderHour: nil, reminderMinute: nil, isPaused: isPaused, isArchived: isArchived)
    }
}
