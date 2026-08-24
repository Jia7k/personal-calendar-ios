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
}
