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
        XCTAssertTrue(dates.contains(fixture.monday0840.addingTimeInterval(6 * 60 * 60)))
        XCTAssertEqual(dates, Array(Set(dates)).sorted())
    }

    func testFreshnessBecomesStaleAtExactlySixHours() {
        let fixture = TimetableTestFixture()
        let generatedAt = fixture.monday0840
        let boundary = generatedAt.addingTimeInterval(6 * 60 * 60)

        XCTAssertEqual(
            TimetableFreshness.generatedAt(
                generatedAt,
                now: boundary.addingTimeInterval(-0.001)
            ),
            .fresh
        )
        XCTAssertEqual(
            TimetableFreshness.generatedAt(generatedAt, now: boundary),
            .stale
        )
        XCTAssertEqual(
            TimetableFreshness.generatedAt(
                generatedAt,
                now: boundary.addingTimeInterval(0.001)
            ),
            .stale
        )
    }

    func testTimelineIncludesOnlyFutureFreshnessBoundary() {
        let fixture = TimetableTestFixture()
        let subject = TimetableTimelineBuilder(calendar: fixture.calendar)
        let snapshot = TimetableSnapshotBuilder(calendar: fixture.calendar)
            .makeSnapshot(access: .granted, events: [], now: fixture.monday0840)
        let boundary = fixture.monday0840.addingTimeInterval(6 * 60 * 60)

        XCTAssertTrue(subject.refreshDates(
            snapshot: snapshot,
            now: boundary.addingTimeInterval(-1)
        ).contains(boundary))
        XCTAssertEqual(
            subject.refreshDates(snapshot: snapshot, now: boundary)
                .filter { $0 == boundary }
                .count,
            1
        )
    }
}
