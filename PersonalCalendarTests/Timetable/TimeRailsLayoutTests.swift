import XCTest
@testable import PersonalCalendar

final class TimeRailsLayoutTests: XCTestCase {
    func testGeometryPreservesDurationsAndMondayGap() throws {
        let fixture = TimetableTestFixture()
        let snapshot = TimetableSnapshotBuilder(calendar: fixture.calendar)
            .makeSnapshot(access: .granted, events: fixture.weekEvents, now: fixture.tuesday0941)
        let placements = TimeRailsLayout(calendar: fixture.calendar, startHour: 9, endHour: 18)
            .placements(snapshot: snapshot)

        let friday = try XCTUnwrap(placements.first { $0.entry.shortTitle == "U22" })
        let tuesday = try XCTUnwrap(placements.first {
            $0.entry.shortTitle == "I03" && $0.weekdayIndex == 1
        })
        let mondayLate = try XCTUnwrap(placements.first {
            $0.entry.shortTitle == "B05" && $0.weekdayIndex == 0
        })

        XCTAssertEqual(friday.heightFraction, 3.0 / 9.0, accuracy: 0.001)
        XCTAssertEqual(tuesday.heightFraction, 2.0 / 9.0, accuracy: 0.001)
        XCTAssertEqual(mondayLate.startFraction, 7.0 / 9.0, accuracy: 0.001)
    }
}
