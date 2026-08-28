import XCTest
@testable import PersonalCalendar

final class MonthGridBuilderTests: XCTestCase {
    func testAugust2026BuildsSixCompleteWeeks() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 1
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let month = LocalDay(year: 2026, month: 8, day: 1)

        let result = MonthGridBuilder(calendar: calendar).days(containing: month)

        XCTAssertEqual(result.count, 42)
        XCTAssertEqual(result.first?.day, LocalDay(year: 2026, month: 7, day: 26))
        XCTAssertEqual(result.last?.day, LocalDay(year: 2026, month: 9, day: 5))
    }

    func testWeekContainingMonthBoundarySelectionHasSevenConsecutiveDays() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 1
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let selected = LocalDay(year: 2026, month: 8, day: 1)

        let result = MonthGridBuilder(calendar: calendar).week(containing: selected, displayedMonth: selected)

        XCTAssertEqual(result.count, 7)
        XCTAssertEqual(result.first?.day, LocalDay(year: 2026, month: 7, day: 26))
        XCTAssertEqual(result.last?.day, LocalDay(year: 2026, month: 8, day: 1))
        XCTAssertEqual(result.filter(\.belongsToDisplayedMonth).count, 1)
    }
}

final class MonthGridActivitySummaryTests: XCTestCase {
    func testQuietMarkersCapAtThreeWhileSourceCountsRemainExact() {
        let items = [
            item(id: "event-one", source: .event),
            item(id: "task-one", source: .task),
            item(id: "routine-one", source: .routine),
            item(id: "event-two", source: .event),
            item(id: "event-three", source: .event)
        ]

        let summary = MonthGridActivitySummary(items: items)

        XCTAssertEqual(summary.markerSources, [.event, .task, .routine])
        XCTAssertEqual(summary.totalCount, 5)
        XCTAssertEqual(summary.sourceCountDescription, "3 events, 1 task, 1 routine")
    }

    func testSourceCountDescriptionOmitsAbsentSourcesAndHandlesEmptyDays() {
        let taskOnly = MonthGridActivitySummary(items: [
            item(id: "task-one", source: .task),
            item(id: "task-two", source: .task)
        ])
        let empty = MonthGridActivitySummary(items: [])

        XCTAssertEqual(taskOnly.sourceCountDescription, "2 tasks")
        XCTAssertEqual(empty.sourceCountDescription, "0 items")
        XCTAssertTrue(empty.markerSources.isEmpty)
    }

    private func item(id: String, source: AgendaSource) -> AgendaItem {
        AgendaItem(
            id: id,
            title: id,
            source: source,
            placement: .unscheduled,
            sortDate: nil,
            priority: 0,
            isCompleted: false,
            allowsModification: true
        )
    }
}

final class CalendarHeaderIdentityTextTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        value.locale = Locale(identifier: "en_US_POSIX")
        return value
    }

    func testSelectedDayInDisplayedMonthAvoidsRepeatingMonth() {
        let title = CalendarHeaderIdentityText.selectedDayTitle(
            for: LocalDay(year: 2026, month: 8, day: 28),
            displayedMonth: LocalDay(year: 2026, month: 8, day: 1),
            calendar: calendar
        )

        XCTAssertEqual(title, "FRIDAY 28")
    }

    func testAdjacentMonthSelectionIncludesItsMonth() {
        let title = CalendarHeaderIdentityText.selectedDayTitle(
            for: LocalDay(year: 2026, month: 9, day: 1),
            displayedMonth: LocalDay(year: 2026, month: 8, day: 1),
            calendar: calendar
        )

        XCTAssertTrue(title.contains("SEP"))
        XCTAssertTrue(title.contains("1"))
    }
}
