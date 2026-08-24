import XCTest
@testable import PersonalCalendar

final class TaskRecurrenceEndDateSeedTests: XCTestCase {
    func testSeedPrefersAFutureEffectiveDueDate() {
        let now = Date(timeIntervalSince1970: 1_000)
        let futureDueDate = Date(timeIntervalSince1970: 9_000)

        XCTAssertEqual(
            taskRecurrenceEndDateSeed(effectiveDueDate: futureDueDate, now: now),
            futureDueDate
        )
    }

    func testSeedUsesNowWhenEffectiveDueDateIsMissingOrPast() {
        let now = Date(timeIntervalSince1970: 1_000)

        XCTAssertEqual(taskRecurrenceEndDateSeed(effectiveDueDate: nil, now: now), now)
        XCTAssertEqual(
            taskRecurrenceEndDateSeed(effectiveDueDate: Date(timeIntervalSince1970: 999), now: now),
            now
        )
    }
}
