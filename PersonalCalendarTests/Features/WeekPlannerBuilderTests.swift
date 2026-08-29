import XCTest
@testable import PersonalCalendar

final class WeekPlannerBuilderTests: XCTestCase {
    private let monday = LocalDay(year: 2026, month: 8, day: 31)

    func testBuildPlacesAllDayEventsAndDateOnlyTasksInTopStrip() {
        let calendar = makeCalendar()
        let days = weekDays(calendar: calendar)
        let event = makeEvent(
            id: "all-day",
            title: "Orientation",
            start: date(2026, 8, 31, calendar: calendar),
            end: date(2026, 9, 1, calendar: calendar),
            isAllDay: true
        )
        let reminder = makeReminder(
            id: "assignment",
            title: "Assignment 1",
            due: date(2026, 9, 4, calendar: calendar),
            dueHasTime: false
        )
        let overdue = makeReminder(
            id: "overdue",
            title: "Old task",
            due: date(2026, 8, 30, calendar: calendar),
            dueHasTime: false
        )
        let friday = LocalDay(year: 2026, month: 9, day: 4)
        let agendas: [LocalDay: DayAgenda] = [
            monday: agenda(allDay: [AgendaItem(event: event)]),
            friday: agenda(priority: [AgendaItem(reminder: reminder)]),
            LocalDay(year: 2026, month: 9, day: 2): agenda(priority: [AgendaItem(reminder: overdue)])
        ]

        let result = WeekPlannerBuilder(calendar: calendar).build(
            days: days,
            agendas: agendas,
            events: [event],
            reminders: [reminder, overdue],
            selectedDay: monday
        )

        XCTAssertEqual(result.allDayItems.map(\.day), [monday, friday])
        XCTAssertEqual(result.allDayItems.map(\.item.origin), [
            .event(id: "all-day"),
            .reminder(id: "assignment")
        ])
        XCTAssertFalse(result.allDayItems.contains(where: { $0.item.origin == .reminder(id: "overdue") }))
    }

    func testBuildClipsMultiDayEventToEachIntersectedDay() {
        let calendar = makeCalendar()
        let tuesday = LocalDay(year: 2026, month: 9, day: 1)
        let event = makeEvent(
            id: "overnight",
            title: "Hackathon",
            start: date(2026, 8, 31, 23, calendar: calendar),
            end: date(2026, 9, 1, 2, calendar: calendar)
        )
        let item = AgendaItem(event: event)

        let result = WeekPlannerBuilder(calendar: calendar).build(
            days: [monday, tuesday],
            agendas: [monday: agenda(scheduled: [item]), tuesday: agenda(scheduled: [item])],
            events: [event],
            reminders: [],
            selectedDay: monday
        )

        XCTAssertEqual(result.timedItems.count, 2)
        XCTAssertEqual(result.timedItems[0].day, monday)
        XCTAssertEqual(result.timedItems[0].start, date(2026, 8, 31, 23, calendar: calendar))
        XCTAssertEqual(result.timedItems[0].end, date(2026, 9, 1, calendar: calendar))
        XCTAssertEqual(result.timedItems[1].day, tuesday)
        XCTAssertEqual(result.timedItems[1].start, date(2026, 9, 1, calendar: calendar))
        XCTAssertEqual(result.timedItems[1].end, date(2026, 9, 1, 2, calendar: calendar))
    }

    func testBuildIndexesFullEventDetailsByDisplayIDWithoutClippingMetadata() {
        let calendar = makeCalendar()
        let tuesday = LocalDay(year: 2026, month: 9, day: 1)
        let originalStart = date(2026, 8, 31, 23, calendar: calendar)
        let originalEnd = date(2026, 9, 1, 2, calendar: calendar)
        let event = CalendarEventSnapshot(
            id: "overnight",
            mutationID: "mutation-overnight",
            title: "Hackathon",
            start: originalStart,
            end: originalEnd,
            isAllDay: false,
            calendarID: "university",
            calendarTitle: "University",
            allowsModification: true,
            hasRecurrence: false,
            notes: "Bring a charger",
            location: "Lab 4"
        )
        let item = AgendaItem(event: event)

        let result = WeekPlannerBuilder(calendar: calendar).build(
            days: [monday, tuesday],
            agendas: [monday: agenda(scheduled: [item]), tuesday: agenda(scheduled: [item])],
            events: [event],
            reminders: [],
            selectedDay: monday
        )

        let details = result.eventDetailsByOccurrence[
            WeekPlannerEventOccurrenceKey(displayID: "overnight", start: originalStart)
        ]
        XCTAssertEqual(details?.title, "Hackathon")
        XCTAssertEqual(details?.start, originalStart)
        XCTAssertEqual(details?.end, originalEnd)
        XCTAssertEqual(details?.calendarTitle, "University")
        XCTAssertEqual(details?.location, "Lab 4")
        XCTAssertEqual(details?.notes, "Bring a charger")
    }

    func testBuildKeepsSameIdentityAndDisplayedStartOccurrencesDistinctByOriginalDate() {
        let calendar = makeCalendar()
        let sharedStart = date(2026, 8, 31, 9, calendar: calendar)
        let firstOccurrenceDate = date(2026, 8, 24, 9, calendar: calendar)
        let secondOccurrenceDate = date(2026, 8, 25, 9, calendar: calendar)
        let morning = CalendarEventSnapshot(
            id: "recurring-class",
            mutationID: "recurring-class",
            title: "Morning lecture",
            start: sharedStart,
            end: date(2026, 8, 31, 10, calendar: calendar),
            isAllDay: false,
            calendarID: "university",
            calendarTitle: "University",
            allowsModification: true,
            hasRecurrence: true,
            notes: "Chapter one",
            location: "Room A",
            occurrenceDate: firstOccurrenceDate
        )
        let afternoon = CalendarEventSnapshot(
            id: "recurring-class",
            mutationID: "recurring-class",
            title: "Afternoon lecture",
            start: sharedStart,
            end: date(2026, 8, 31, 11, calendar: calendar),
            isAllDay: false,
            calendarID: "university",
            calendarTitle: "University",
            allowsModification: true,
            hasRecurrence: true,
            notes: "Chapter two",
            location: "Room B",
            occurrenceDate: secondOccurrenceDate
        )

        let result = WeekPlannerBuilder(calendar: calendar).build(
            days: [monday],
            agendas: [monday: agenda(scheduled: [
                AgendaItem(event: morning),
                AgendaItem(event: afternoon)
            ])],
            events: [morning, afternoon],
            reminders: [],
            selectedDay: monday
        )

        XCTAssertEqual(result.timedItems.map(\.start), [sharedStart, sharedStart])
        XCTAssertEqual(Set(result.timedItems.map(\.id)).count, 2)
        XCTAssertEqual(
            result.eventDetailsByOccurrence[
                WeekPlannerEventOccurrenceKey(
                    displayID: morning.id,
                    start: sharedStart,
                    occurrenceDate: firstOccurrenceDate
                )
            ]?.location,
            "Room A"
        )
        XCTAssertEqual(
            result.eventDetailsByOccurrence[
                WeekPlannerEventOccurrenceKey(
                    displayID: afternoon.id,
                    start: sharedStart,
                    occurrenceDate: secondOccurrenceDate
                )
            ]?.location,
            "Room B"
        )
    }

    func testBuildRepresentsTimedTaskAsPointMarker() {
        let calendar = makeCalendar()
        let wednesday = LocalDay(year: 2026, month: 9, day: 2)
        let reminder = makeReminder(
            id: "timed-task",
            title: "Submit lab",
            due: date(2026, 9, 2, 15, 30, calendar: calendar),
            dueHasTime: true
        )

        let result = WeekPlannerBuilder(calendar: calendar).build(
            days: [wednesday],
            agendas: [wednesday: agenda(scheduled: [AgendaItem(reminder: reminder)])],
            events: [],
            reminders: [reminder],
            selectedDay: wednesday
        )

        XCTAssertEqual(result.timedItems.count, 1)
        XCTAssertEqual(result.timedItems[0].kind, .taskDue)
        XCTAssertEqual(result.timedItems[0].start, reminder.dueDate)
        XCTAssertNil(result.timedItems[0].end)
        XCTAssertEqual(result.timedItems[0].item.origin, .reminder(id: "timed-task"))
    }

    func testBuildShowsOnlySelectedDayAnchoredRoutinesInLaterStrip() {
        let calendar = makeCalendar()
        let wednesday = LocalDay(year: 2026, month: 9, day: 2)
        let thursday = LocalDay(year: 2026, month: 9, day: 3)
        let routine = RoutineSnapshot(
            id: UUID(uuidString: "A0000000-0000-4000-8000-000000000001")!,
            title: "Review lecture notes",
            weekdays: [4, 5],
            window: .evening,
            reminderHour: 21,
            reminderMinute: 0,
            isPaused: false,
            isArchived: false
        )
        let wednesdayItem = AgendaItem(routine: routine, completed: false, day: wednesday, calendar: calendar)
        let thursdayItem = AgendaItem(routine: routine, completed: false, day: thursday, calendar: calendar)

        let result = WeekPlannerBuilder(calendar: calendar).build(
            days: [wednesday, thursday],
            agendas: [
                wednesday: agenda(scheduled: [wednesdayItem]),
                thursday: agenda(scheduled: [thursdayItem])
            ],
            events: [],
            reminders: [],
            selectedDay: wednesday
        )

        XCTAssertEqual(result.laterItems, [wednesdayItem])
    }

    func testBuildExpandsDefaultHoursForEarlyAndLateItemsWithoutDroppingThem() {
        let calendar = makeCalendar()
        let early = makeEvent(
            id: "early",
            title: "Early lab",
            start: date(2026, 8, 31, 5, 30, calendar: calendar),
            end: date(2026, 8, 31, 6, 30, calendar: calendar)
        )
        let late = makeEvent(
            id: "late",
            title: "Night class",
            start: date(2026, 8, 31, 22, 30, calendar: calendar),
            end: date(2026, 8, 31, 23, 15, calendar: calendar)
        )

        let result = WeekPlannerBuilder(calendar: calendar).build(
            days: [monday],
            agendas: [monday: agenda(scheduled: [AgendaItem(event: early), AgendaItem(event: late)])],
            events: [early, late],
            reminders: [],
            selectedDay: monday
        )

        XCTAssertEqual(result.startHour, 5)
        XCTAssertEqual(result.endHour, 24)
        XCTAssertEqual(result.timedItems.map(\.item.origin), [.event(id: "early"), .event(id: "late")])
    }

    func testBuildAssignsStableColumnsToOverlappingEvents() {
        let calendar = makeCalendar()
        let first = makeEvent(
            id: "a",
            title: "A",
            start: date(2026, 8, 31, 9, calendar: calendar),
            end: date(2026, 8, 31, 11, calendar: calendar)
        )
        let second = makeEvent(
            id: "b",
            title: "B",
            start: date(2026, 8, 31, 9, 30, calendar: calendar),
            end: date(2026, 8, 31, 10, 30, calendar: calendar)
        )
        let third = makeEvent(
            id: "c",
            title: "C",
            start: date(2026, 8, 31, 10, 30, calendar: calendar),
            end: date(2026, 8, 31, 12, calendar: calendar)
        )

        let result = WeekPlannerBuilder(calendar: calendar).build(
            days: [monday],
            agendas: [monday: agenda(scheduled: [
                AgendaItem(event: third), AgendaItem(event: second), AgendaItem(event: first)
            ])],
            events: [third, second, first],
            reminders: [],
            selectedDay: monday
        )

        XCTAssertEqual(result.timedItems.map(\.item.title), ["A", "B", "C"])
        XCTAssertEqual(result.timedItems.map(\.overlapColumn), [0, 1, 1])
        XCTAssertEqual(result.timedItems.map(\.overlapColumnCount), [2, 2, 2])
    }

    func testBuildGroupsOverlappingEventsIntoOneDisplayStack() {
        let calendar = makeCalendar()
        let first = makeEvent(
            id: "first",
            title: "Algorithms",
            start: date(2026, 8, 31, 9, calendar: calendar),
            end: date(2026, 8, 31, 11, calendar: calendar)
        )
        let second = makeEvent(
            id: "second",
            title: "Database Lab",
            start: date(2026, 8, 31, 9, 30, calendar: calendar),
            end: date(2026, 8, 31, 10, 30, calendar: calendar)
        )

        let result = WeekPlannerBuilder(calendar: calendar).build(
            days: [monday],
            agendas: [monday: agenda(scheduled: [AgendaItem(event: second), AgendaItem(event: first)])],
            events: [second, first],
            reminders: [],
            selectedDay: monday
        )

        XCTAssertEqual(result.eventStacks.count, 1)
        XCTAssertEqual(result.eventStacks[0].events.map(\.item.title), ["Algorithms", "Database Lab"])
        XCTAssertEqual(result.eventStacks[0].start, first.start)
        XCTAssertEqual(result.eventStacks[0].end, first.end)
    }

    func testBuildGroupsBackToBackShortEventsWhenMinimumTapTargetsWouldOverlap() {
        let calendar = makeCalendar()
        let first = makeEvent(
            id: "first-short",
            title: "Quiz",
            start: date(2026, 8, 31, 9, calendar: calendar),
            end: date(2026, 8, 31, 9, 15, calendar: calendar)
        )
        let second = makeEvent(
            id: "second-short",
            title: "Stand-up",
            start: date(2026, 8, 31, 9, 15, calendar: calendar),
            end: date(2026, 8, 31, 9, 30, calendar: calendar)
        )

        let result = WeekPlannerBuilder(calendar: calendar).build(
            days: [monday],
            agendas: [monday: agenda(scheduled: [AgendaItem(event: first), AgendaItem(event: second)])],
            events: [first, second],
            reminders: [],
            selectedDay: monday
        )

        XCTAssertEqual(result.eventStacks.count, 1)
        XCTAssertEqual(result.eventStacks[0].events.map(\.item.title), ["Quiz", "Stand-up"])
    }

    func testBuildGroupsEventAndTaskWhenMinimumTapTargetsWouldOverlap() {
        let calendar = makeCalendar()
        let event = makeEvent(
            id: "short-class",
            title: "Quiz",
            start: date(2026, 8, 31, 9, calendar: calendar),
            end: date(2026, 8, 31, 9, 15, calendar: calendar)
        )
        let reminder = makeReminder(
            id: "due-after-class",
            title: "Submit quiz",
            due: date(2026, 8, 31, 9, 15, calendar: calendar),
            dueHasTime: true
        )

        let result = WeekPlannerBuilder(calendar: calendar).build(
            days: [monday],
            agendas: [monday: agenda(scheduled: [AgendaItem(event: event), AgendaItem(reminder: reminder)])],
            events: [event],
            reminders: [reminder],
            selectedDay: monday
        )

        XCTAssertEqual(result.collisionStacks.count, 1)
        XCTAssertEqual(
            result.collisionStacks[0].items.map(\.item.origin),
            [.event(id: "short-class"), .reminder(id: "due-after-class")]
        )
    }

    func testBuildGroupsNearbyTasksIntoOneSelectableCollisionStack() {
        let calendar = makeCalendar()
        let first = makeReminder(
            id: "first-task",
            title: "First",
            due: date(2026, 8, 31, 9, calendar: calendar),
            dueHasTime: true
        )
        let second = makeReminder(
            id: "second-task",
            title: "Second",
            due: date(2026, 8, 31, 9, 15, calendar: calendar),
            dueHasTime: true
        )

        let result = WeekPlannerBuilder(calendar: calendar).build(
            days: [monday],
            agendas: [monday: agenda(scheduled: [AgendaItem(reminder: second), AgendaItem(reminder: first)])],
            events: [],
            reminders: [first, second],
            selectedDay: monday
        )

        XCTAssertEqual(result.collisionStacks.count, 1)
        XCTAssertEqual(
            result.collisionStacks[0].items.map(\.item.origin),
            [.reminder(id: "first-task"), .reminder(id: "second-task")]
        )
    }

    func testBuildKeepsGroupedTaskStackAndFollowingEventAsSeparateNonOverlappingTargets() {
        let calendar = makeCalendar()
        let due = date(2026, 8, 31, 9, calendar: calendar)
        let first = makeReminder(id: "first-task", title: "First", due: due, dueHasTime: true)
        let second = makeReminder(id: "second-task", title: "Second", due: due, dueHasTime: true)
        let event = makeEvent(
            id: "following-class",
            title: "Lecture",
            start: date(2026, 8, 31, 9, 30, calendar: calendar),
            end: date(2026, 8, 31, 10, 30, calendar: calendar)
        )

        let result = WeekPlannerBuilder(calendar: calendar).build(
            days: [monday],
            agendas: [
                monday: agenda(scheduled: [
                    AgendaItem(reminder: first),
                    AgendaItem(reminder: second),
                    AgendaItem(event: event)
                ])
            ],
            events: [event],
            reminders: [first, second],
            selectedDay: monday
        )

        XCTAssertEqual(result.collisionStacks.count, 2)
        XCTAssertEqual(result.collisionStacks[0].items.count, 2)
        XCTAssertEqual(result.collisionStacks[1].items.map(\.item.origin), [.event(id: "following-class")])
        XCTAssertLessThanOrEqual(
            result.collisionStacks[0].renderedEnd,
            result.collisionStacks[1].renderedStart
        )
    }

    func testBuildGroupsStartHourTaskWithEventInsideItsClampedRenderedTarget() {
        let calendar = makeCalendar()
        let reminder = makeReminder(
            id: "start-task",
            title: "Morning checklist",
            due: date(2026, 8, 31, 8, calendar: calendar),
            dueHasTime: true
        )
        let event = makeEvent(
            id: "early-class",
            title: "Seminar",
            start: date(2026, 8, 31, 8, 30, calendar: calendar),
            end: date(2026, 8, 31, 9, 30, calendar: calendar)
        )

        let result = WeekPlannerBuilder(calendar: calendar).build(
            days: [monday],
            agendas: [monday: agenda(scheduled: [AgendaItem(reminder: reminder), AgendaItem(event: event)])],
            events: [event],
            reminders: [reminder],
            selectedDay: monday
        )

        XCTAssertEqual(result.startHour, 8)
        XCTAssertEqual(result.collisionStacks.count, 1)
        XCTAssertEqual(result.collisionStacks[0].items.count, 2)
    }

    func testTimelineMetricsKeepDenseEventAndTaskControlsAtLeastFortyFourPoints() {
        let dayWidth = WeekPlannerTimelineMetrics.dayWidth(
            availableWidth: 375,
            timeGutterWidth: 40,
            dayCount: 7,
            maximumOverlapCount: 3
        )

        XCTAssertGreaterThanOrEqual(
            WeekPlannerTimelineMetrics.eventWidth(dayWidth: dayWidth, overlapCount: 3),
            44
        )
        XCTAssertGreaterThanOrEqual(
            WeekPlannerTimelineMetrics.taskWidth(dayWidth: dayWidth),
            44
        )
        XCTAssertGreaterThanOrEqual(
            WeekPlannerTimelineMetrics.stackedEventWidth(dayWidth: dayWidth),
            44
        )
    }

    func testTimelineMetricsKeepSevenDayTimelineWithinAvailableWidthWhenEventsOverlap() {
        let availableWidth: CGFloat = 375
        let timeGutterWidth: CGFloat = 40
        let dayWidth = WeekPlannerTimelineMetrics.dayWidth(
            availableWidth: availableWidth,
            timeGutterWidth: timeGutterWidth,
            dayCount: 7,
            maximumOverlapCount: 3
        )

        XCTAssertEqual(
            timeGutterWidth + dayWidth * 7,
            availableWidth,
            accuracy: 0.001
        )
    }

    func testTimelineContentHeightKeepsLateMinimumTapTargetInsideScrollableCanvas() {
        let baseHeight = CGFloat(16) * WeekPlannerTimelineMetrics.pointsPerHour

        XCTAssertEqual(
            WeekPlannerTimelineMetrics.contentHeight(baseHeight: baseHeight),
            baseHeight + WeekPlannerTimelineMetrics.minimumControlSize,
            accuracy: 0.001
        )
    }

    func testCompactCardPresentationReservesCollisionBadgeInsteadOfCompressingTime() {
        let collision = WeekPlannerCompactCardPresentation.resolve(height: 96, itemCount: 3)
        XCTAssertFalse(collision.showsTime)
        XCTAssertEqual(collision.titleLineLimit, 2)

        let singleEvent = WeekPlannerCompactCardPresentation.resolve(height: 96, itemCount: 1)
        XCTAssertTrue(singleEvent.showsTime)
        XCTAssertEqual(singleEvent.titleLineLimit, 2)

        let shortEvent = WeekPlannerCompactCardPresentation.resolve(height: 44, itemCount: 1)
        XCTAssertFalse(shortEvent.showsTime)
        XCTAssertEqual(shortEvent.titleLineLimit, 1)
    }

    func testTaskTopOffsetKeepsEarlyMinimumTapTargetInsideScrollableCanvas() {
        XCTAssertEqual(
            WeekPlannerTimelineMetrics.taskTopOffset(minuteOffset: 0),
            0,
            accuracy: 0.001
        )
        XCTAssertEqual(
            WeekPlannerTimelineMetrics.taskTopOffset(minuteOffset: 80),
            58,
            accuracy: 0.001
        )
    }

    private func makeCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_SG")
        calendar.timeZone = TimeZone(identifier: "Asia/Singapore")!
        calendar.firstWeekday = 2
        return calendar
    }

    private func weekDays(calendar: Calendar) -> [LocalDay] {
        (0..<7).map { offset in
            LocalDay(
                date: calendar.date(byAdding: .day, value: offset, to: monday.startDate(in: calendar))!,
                calendar: calendar
            )
        }
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int = 0,
        _ minute: Int = 0,
        calendar: Calendar
    ) -> Date {
        calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        ))!
    }

    private func agenda(
        allDay: [AgendaItem] = [],
        scheduled: [AgendaItem] = [],
        priority: [AgendaItem] = []
    ) -> DayAgenda {
        DayAgenda(allDay: allDay, scheduled: scheduled, priority: priority)
    }

    private func makeEvent(
        id: String,
        title: String,
        start: Date,
        end: Date,
        isAllDay: Bool = false
    ) -> CalendarEventSnapshot {
        CalendarEventSnapshot(
            id: id,
            mutationID: "mutation-\(id)",
            title: title,
            start: start,
            end: end,
            isAllDay: isAllDay,
            calendarID: "school",
            calendarTitle: "School",
            allowsModification: true,
            hasRecurrence: false
        )
    }

    private func makeReminder(
        id: String,
        title: String,
        due: Date,
        dueHasTime: Bool
    ) -> ReminderSnapshot {
        ReminderSnapshot(
            id: id,
            title: title,
            notes: nil,
            dueDate: due,
            dueHasTime: dueHasTime,
            priority: 1,
            listID: "assignments",
            listTitle: "Assignments",
            isCompleted: false,
            allowsModification: true,
            hasRecurrence: false
        )
    }
}
