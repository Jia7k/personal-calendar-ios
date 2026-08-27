import XCTest
@testable import PersonalCalendar

final class TaskQuickRescheduleTests: XCTestCase {
    func testTodayMakesAnUndatedReminderDateOnlyOnTheCurrentLocalDay() throws {
        let calendar = singaporeCalendar()
        let now = date(2026, 8, 24, 10, 15, calendar: calendar)

        let result = try TaskQuickReschedulePlanner(calendar: calendar).schedule(
            for: reminder(dueDate: nil, dueHasTime: false),
            command: .today,
            now: now
        )

        XCTAssertEqual(
            result,
            .init(date: date(2026, 8, 24, calendar: calendar), hasTime: false)
        )
    }

    func testLaterTodayUsesSixPMWhenItIsStillFuture() throws {
        let calendar = singaporeCalendar()
        let now = date(2026, 8, 24, 10, 0, calendar: calendar)

        let result = try TaskQuickReschedulePlanner(calendar: calendar).schedule(
            for: reminder(dueDate: date(2026, 8, 23, 9, 0, calendar: calendar)),
            command: .laterToday,
            now: now
        )

        XCTAssertEqual(result, .init(date: date(2026, 8, 24, 18, 0, calendar: calendar), hasTime: true))
    }

    func testLaterTodayPreservesAnExistingFutureTimeToday() throws {
        let calendar = singaporeCalendar()
        let now = date(2026, 8, 24, 10, 0, calendar: calendar)

        let result = try TaskQuickReschedulePlanner(calendar: calendar).schedule(
            for: reminder(dueDate: date(2026, 8, 24, 20, 30, calendar: calendar)),
            command: .laterToday,
            now: now
        )

        XCTAssertEqual(result, .init(date: date(2026, 8, 24, 20, 30, calendar: calendar), hasTime: true))
    }

    func testLaterTodayClampsToFifteenMinutesAfterLateNow() throws {
        let calendar = singaporeCalendar()
        let now = date(2026, 8, 24, 17, 55, calendar: calendar)

        let result = try TaskQuickReschedulePlanner(calendar: calendar).schedule(
            for: reminder(dueDate: date(2026, 8, 23, 9, 0, calendar: calendar)),
            command: .laterToday,
            now: now
        )

        XCTAssertEqual(result, .init(date: date(2026, 8, 24, 18, 10, calendar: calendar), hasTime: true))
    }

    func testTomorrowAndNextWeekPreserveTimedLocalComponentsAcrossDST() throws {
        let calendar = newYorkCalendar()
        let now = date(2026, 3, 8, 12, 0, calendar: calendar)
        let item = reminder(dueDate: date(2026, 3, 8, 9, 30, calendar: calendar))
        let planner = TaskQuickReschedulePlanner(calendar: calendar)

        let tomorrow = try planner.schedule(for: item, command: .tomorrow, now: now)
        let nextWeek = try planner.schedule(for: item, command: .nextWeek, now: now)

        XCTAssertEqual(tomorrow, .init(date: date(2026, 3, 9, 9, 30, calendar: calendar), hasTime: true))
        XCTAssertEqual(nextWeek, .init(date: date(2026, 3, 15, 9, 30, calendar: calendar), hasTime: true))
    }

    func testDateOnlyTomorrowAndNextWeekRemainDateOnly() throws {
        let calendar = singaporeCalendar()
        let now = date(2026, 8, 24, 10, 0, calendar: calendar)
        let item = reminder(dueDate: date(2026, 8, 23, calendar: calendar), dueHasTime: false)
        let planner = TaskQuickReschedulePlanner(calendar: calendar)

        XCTAssertEqual(
            try planner.schedule(for: item, command: .tomorrow, now: now),
            .init(date: date(2026, 8, 25, calendar: calendar), hasTime: false)
        )
        XCTAssertEqual(
            try planner.schedule(for: item, command: .nextWeek, now: now),
            .init(date: date(2026, 8, 31, calendar: calendar), hasTime: false)
        )
    }

    func testPickUsesExactDateAndTimeFlag() throws {
        let calendar = singaporeCalendar()
        let chosen = date(2026, 9, 2, 14, 45, calendar: calendar)

        let result = try TaskQuickReschedulePlanner(calendar: calendar).schedule(
            for: reminder(dueDate: date(2026, 8, 23, calendar: calendar)),
            command: .pick(chosen, hasTime: false),
            now: date(2026, 8, 24, 10, 0, calendar: calendar)
        )

        XCTAssertEqual(result, .init(date: chosen, hasTime: false))
    }

    func testRecurringReminderRequiresTheEditor() {
        let calendar = singaporeCalendar()

        XCTAssertThrowsError(
            try TaskQuickReschedulePlanner(calendar: calendar).schedule(
                for: reminder(dueDate: date(2026, 8, 23, calendar: calendar), hasRecurrence: true),
                command: .tomorrow,
                now: date(2026, 8, 24, 10, 0, calendar: calendar)
            )
        ) {
            XCTAssertEqual($0 as? TaskQuickRescheduleError, .recurringTaskRequiresEditor)
        }
    }

    private func reminder(
        dueDate: Date?,
        dueHasTime: Bool = true,
        hasRecurrence: Bool = false
    ) -> ReminderSnapshot {
        .init(id: "task", title: "Task", notes: nil, dueDate: dueDate, dueHasTime: dueHasTime, priority: 1, listID: "list", listTitle: "List", isCompleted: false, allowsModification: true, hasRecurrence: hasRecurrence)
    }

    private func singaporeCalendar() -> Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Singapore")!
        return value
    }

    private func newYorkCalendar() -> Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "America/New_York")!
        return value
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }
}
