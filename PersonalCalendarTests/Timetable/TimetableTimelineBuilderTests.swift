import XCTest
@testable import PersonalCalendar

final class TimetableTimelineBuilderTests: XCTestCase {
    func testRefreshDatesContainUpcomingClassBoundariesAndNextMidnight() {
        let fixture = TimetableTestFixture()
        let snapshot = TimetableSnapshotBuilder(calendar: fixture.calendar)
            .makeSnapshot(access: .granted, events: fixture.weekEvents, now: fixture.monday0840)
        let dates = TimetableTimelineBuilder(calendar: fixture.calendar)
            .refreshDates(snapshot: snapshot, now: fixture.monday0840)

        XCTAssertEqual(dates.first, fixture.monday0840)
        XCTAssertTrue(dates.contains(fixture.monday0900))
        XCTAssertTrue(dates.contains(fixture.monday1100))
        XCTAssertTrue(dates.contains(fixture.tuesdayStart))
        XCTAssertEqual(dates, Array(Set(dates)).sorted())
    }
}
