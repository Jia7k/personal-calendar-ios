import XCTest
@testable import PersonalCalendar

final class LocalDayTests: XCTestCase {
    func testRoundTripUsesInjectedCalendarAndTimeZone() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Singapore"))
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 24, hour: 23)))

        let day = LocalDay(date: date, calendar: calendar)

        XCTAssertEqual(day, LocalDay(year: 2026, month: 8, day: 24))
        XCTAssertEqual(day.startDate(in: calendar), calendar.startOfDay(for: date))
    }

    func testRoutineWindowAnchorsAreDeterministic() {
        XCTAssertEqual(RoutineWindow.morning.anchorHour, 9)
        XCTAssertEqual(RoutineWindow.afternoon.anchorHour, 13)
        XCTAssertEqual(RoutineWindow.evening.anchorHour, 18)
        XCTAssertNil(RoutineWindow.anytime.anchorHour)
    }

    func testNextLocalDayUsesCalendarAcrossDaylightSavingChange() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let day = LocalDay(year: 2026, month: 3, day: 8)
        let next = calendar.date(byAdding: .day, value: 1, to: day.startDate(in: calendar))!

        XCTAssertEqual(LocalDay(date: next, calendar: calendar), LocalDay(year: 2026, month: 3, day: 9))
        XCTAssertEqual(next.timeIntervalSince(day.startDate(in: calendar)), 23 * 60 * 60)
    }

    func testMonthBoundaryKeepsCalendarComponents() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let next = calendar.date(byAdding: .day, value: 1, to: LocalDay(year: 2026, month: 8, day: 31).startDate(in: calendar))!
        XCTAssertEqual(LocalDay(date: next, calendar: calendar), LocalDay(year: 2026, month: 9, day: 1))
    }
}
