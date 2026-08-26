import XCTest
@testable import PersonalCalendar

final class TaskTimeBlockPlannerTests: XCTestCase {
    func testSuggestionsPreferNearestDistinctGapsBeforeTimedDue() throws {
        let calendar = singaporeCalendar()
        let now = date(2026, 8, 24, 9, 0, calendar: calendar)
        let task = reminder(due: date(2026, 8, 24, 13, 0, calendar: calendar))
        let events = [
            event("Lecture", 10, 0, 11, 0, calendar: calendar),
            event("Lunch", 12, 0, 12, 30, calendar: calendar)
        ]

        let result = TaskTimeBlockPlanner(calendar: calendar).suggestions(
            task: task,
            durationMinutes: 30,
            events: events,
            now: now
        )

        XCTAssertEqual(result.map(\.interval), [
            DateInterval(
                start: date(2026, 8, 24, 12, 30, calendar: calendar),
                end: date(2026, 8, 24, 13, 0, calendar: calendar)
            ),
            DateInterval(
                start: date(2026, 8, 24, 11, 30, calendar: calendar),
                end: date(2026, 8, 24, 12, 0, calendar: calendar)
            ),
            DateInterval(
                start: date(2026, 8, 24, 9, 30, calendar: calendar),
                end: date(2026, 8, 24, 10, 0, calendar: calendar)
            )
        ])
        XCTAssertTrue(result.allSatisfy { $0.conflicts.isEmpty })
    }

    func testSupportedDurationsProduceExactCalendarMinuteIntervalsAndInvalidDurationReturnsNone() throws {
        let calendar = singaporeCalendar()
        let now = date(2026, 8, 24, 8, 0, calendar: calendar)
        let task = reminder(due: date(2026, 8, 24, 12, 0, calendar: calendar))
        let planner = TaskTimeBlockPlanner(calendar: calendar)

        for duration in [30, 60, 90] {
            let suggestion = try XCTUnwrap(planner.suggestions(
                task: task,
                durationMinutes: duration,
                events: [],
                now: now
            ).first)
            XCTAssertEqual(
                calendar.dateComponents(
                    [.minute],
                    from: suggestion.interval.start,
                    to: suggestion.interval.end
                ).minute,
                duration
            )
        }
        XCTAssertTrue(planner.suggestions(
            task: task,
            durationMinutes: 45,
            events: [],
            now: now
        ).isEmpty)
    }

    func testPastDueTaskFallsBackToEarliestAvailableTimeTodayAndNeverReturnsPastTime() throws {
        let calendar = singaporeCalendar()
        let now = date(2026, 8, 24, 10, 17, calendar: calendar)
        let task = reminder(due: date(2026, 8, 23, 9, 0, calendar: calendar))

        let suggestion = try XCTUnwrap(TaskTimeBlockPlanner(calendar: calendar)
            .suggestions(task: task, durationMinutes: 60, events: [], now: now)
            .first)

        XCTAssertEqual(suggestion.interval.start, now)
        XCTAssertEqual(
            suggestion.interval.end,
            date(2026, 8, 24, 11, 17, calendar: calendar)
        )
    }

    func testBusyIntervalsMergeAndBackToBackBoundariesRemainAvailable() {
        let calendar = singaporeCalendar()
        let now = date(2026, 8, 24, 8, 0, calendar: calendar)
        let task = reminder(due: date(2026, 8, 24, 13, 0, calendar: calendar))
        let events = [
            event("A", 9, 0, 10, 0, calendar: calendar),
            event("B", 9, 30, 11, 0, calendar: calendar),
            event("C", 11, 0, 12, 0, calendar: calendar)
        ]

        let result = TaskTimeBlockPlanner(calendar: calendar).suggestions(
            task: task,
            durationMinutes: 60,
            events: events,
            now: now
        )

        XCTAssertEqual(result.map(\.interval), [
            DateInterval(
                start: date(2026, 8, 24, 12, 0, calendar: calendar),
                end: date(2026, 8, 24, 13, 0, calendar: calendar)
            ),
            DateInterval(
                start: date(2026, 8, 24, 8, 0, calendar: calendar),
                end: date(2026, 8, 24, 9, 0, calendar: calendar)
            ),
            DateInterval(
                start: date(2026, 8, 24, 13, 0, calendar: calendar),
                end: date(2026, 8, 24, 14, 0, calendar: calendar)
            )
        ])
    }

    func testWhenNothingFitsBeforeDueSuggestionsFallBackToEarliestLaterGap() throws {
        let calendar = singaporeCalendar()
        let now = date(2026, 8, 24, 8, 0, calendar: calendar)
        let task = reminder(due: date(2026, 8, 24, 9, 0, calendar: calendar))
        let events = [
            event("Morning class", 8, 0, 10, 0, calendar: calendar)
        ]

        let suggestion = try XCTUnwrap(TaskTimeBlockPlanner(calendar: calendar)
            .suggestions(task: task, durationMinutes: 30, events: events, now: now)
            .first)

        XCTAssertEqual(
            suggestion.interval,
            DateInterval(
                start: date(2026, 8, 24, 10, 0, calendar: calendar),
                end: date(2026, 8, 24, 10, 30, calendar: calendar)
            )
        )
    }

    func testAllDayEventsDoNotBlockSuggestionsAndTimedConflictsUseStrictOverlap() {
        let calendar = singaporeCalendar()
        let planner = TaskTimeBlockPlanner(calendar: calendar)
        let interval = DateInterval(
            start: date(2026, 8, 24, 10, 0, calendar: calendar),
            end: date(2026, 8, 24, 11, 0, calendar: calendar)
        )
        let events = [
            event("Ends at start", 9, 0, 10, 0, calendar: calendar),
            event("Starts at end", 11, 0, 12, 0, calendar: calendar),
            event("Overlap Z", 10, 45, 11, 30, calendar: calendar),
            event("Overlap A", 9, 30, 10, 15, calendar: calendar),
            event("All day", 0, 0, 23, 59, calendar: calendar, isAllDay: true)
        ]

        XCTAssertEqual(
            planner.conflicts(for: interval, events: events),
            ["Overlap A", "Overlap Z"]
        )
    }

    func testWorkingHoursExcludeTooShortFinalGapAndNoSlotReturnsEmpty() {
        let calendar = singaporeCalendar()
        let now = date(2026, 8, 24, 20, 31, calendar: calendar)
        let task = reminder(due: nil)

        XCTAssertTrue(TaskTimeBlockPlanner(calendar: calendar).suggestions(
            task: task,
            durationMinutes: 30,
            events: [],
            now: now
        ).isEmpty)
    }

    func testCandidateDayAndDurationUseCalendarArithmeticAcrossDST() throws {
        let calendar = newYorkCalendar()
        let now = date(2026, 3, 8, 22, 0, calendar: calendar)
        let task = reminder(due: date(2026, 3, 9, 10, 0, calendar: calendar))

        let suggestion = try XCTUnwrap(TaskTimeBlockPlanner(calendar: calendar)
            .suggestions(task: task, durationMinutes: 60, events: [], now: now)
            .first)

        XCTAssertEqual(
            suggestion.interval,
            DateInterval(
                start: date(2026, 3, 9, 9, 0, calendar: calendar),
                end: date(2026, 3, 9, 10, 0, calendar: calendar)
            )
        )
    }

    func testWorkingEndUsesLocalWallClockAcrossSpringForward() {
        let calendar = newYorkCalendar()
        let now = date(2026, 3, 8, 4, 15, calendar: calendar)

        XCTAssertTrue(TaskTimeBlockPlanner(
            calendar: calendar,
            workingStartHour: 0,
            workingEndHour: 4
        ).suggestions(
            task: reminder(due: nil),
            durationMinutes: 30,
            events: [],
            now: now
        ).isEmpty)
    }

    private func reminder(due: Date?) -> ReminderSnapshot {
        .init(
            id: "task-1",
            title: "Assignment",
            notes: nil,
            dueDate: due,
            dueHasTime: due != nil,
            priority: 1,
            listID: "school",
            listTitle: "School",
            isCompleted: false,
            allowsModification: true,
            hasRecurrence: false
        )
    }

    private func event(
        _ title: String,
        _ startHour: Int,
        _ startMinute: Int,
        _ endHour: Int,
        _ endMinute: Int,
        calendar: Calendar,
        isAllDay: Bool = false
    ) -> CalendarEventSnapshot {
        .init(
            id: "\(title)-\(startHour)-\(startMinute)",
            mutationID: "mutation-\(title)",
            title: title,
            start: date(2026, 8, 24, startHour, startMinute, calendar: calendar),
            end: date(2026, 8, 24, endHour, endMinute, calendar: calendar),
            isAllDay: isAllDay,
            calendarID: "calendar",
            calendarTitle: "Calendar",
            allowsModification: true,
            hasRecurrence: false
        )
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

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int,
        _ minute: Int,
        calendar: Calendar
    ) -> Date {
        calendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        ))!
    }
}
