import EventKit
import XCTest
@testable import PersonalCalendar

final class EventKitServiceMappingTests: XCTestCase {
    func testEventDraftRejectsBlankTitleAndInvertedDates() {
        let date = Date(timeIntervalSince1970: 100)

        XCTAssertThrowsError(
            try EventDraftValidator.validate(
                .init(
                    title: " ",
                    start: date,
                    end: date.addingTimeInterval(60),
                    isAllDay: false,
                    calendarID: nil
                )
            )
        )
        XCTAssertThrowsError(
            try EventDraftValidator.validate(
                .init(
                    title: "Dentist",
                    start: date,
                    end: date.addingTimeInterval(-60),
                    isAllDay: false,
                    calendarID: nil
                )
            )
        )
    }

    func testAuthorizationMappingRequiresFullAccess() {
        XCTAssertEqual(EventKitAccessMapper.map(.fullAccess), .granted)
        XCTAssertEqual(EventKitAccessMapper.map(.denied), .denied)
        XCTAssertEqual(EventKitAccessMapper.map(.writeOnly), .restricted)
    }
}
