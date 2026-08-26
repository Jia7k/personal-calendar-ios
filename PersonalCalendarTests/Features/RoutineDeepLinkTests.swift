import XCTest
@testable import PersonalCalendar

@MainActor
final class RoutineDeepLinkTests: XCTestCase {
    func testFreshSignalSelectsMatchingScopedRowExactlyOnce() {
        let target = row(title: "Read")
        let other = row(title: "Walk")
        let signal = RoutineDeepLinkSignal(id: UUID(), routineID: target.id)
        var resolver = RoutineDeepLinkResolver()

        XCTAssertEqual(resolver.resolve(signal, rows: [other, target]), target)
        XCTAssertEqual(resolver.lastSignalID, signal.id)
        XCTAssertNil(resolver.resolve(signal, rows: [other, target]))
    }

    func testMissingOrReplayedSignalDoesNotOpenAnEditor() {
        let existing = row(title: "Read")
        let missing = RoutineDeepLinkSignal(id: UUID(), routineID: UUID())
        let replayed = RoutineDeepLinkSignal(id: UUID(), routineID: existing.id)
        var resolver = RoutineDeepLinkResolver()

        XCTAssertNil(resolver.resolve(missing, rows: [existing]))
        XCTAssertEqual(resolver.lastSignalID, missing.id)
        XCTAssertNil(resolver.resolve(missing, rows: [existing]))

        XCTAssertEqual(resolver.resolve(replayed, rows: [existing]), existing)
        XCTAssertNil(resolver.resolve(replayed, rows: [existing]))
        XCTAssertNil(resolver.resolve(nil, rows: [existing]))
    }

    private func row(title: String) -> RoutineRowState {
        let routine = RoutineSnapshot(
            id: UUID(),
            title: title,
            weekdays: [2],
            window: .morning,
            reminderHour: nil,
            reminderMinute: nil,
            isPaused: false,
            isArchived: false
        )
        return RoutineRowState(
            routine: routine,
            isCompletedToday: false,
            streak: 0,
            history: [],
            representedDay: .init(year: 2026, month: 8, day: 24)
        )
    }
}
