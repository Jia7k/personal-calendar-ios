import SwiftData
import XCTest
@testable import PersonalCalendar

@MainActor
final class RoutineRepositoryTests: XCTestCase {
    func testCreateCompleteAndUndoRoundTrip() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: RoutineRecord.self,
            RoutineCompletionRecord.self,
            configurations: configuration
        )
        let subject = SwiftDataRoutineRepository(context: container.mainContext)
        let day = LocalDay(year: 2026, month: 8, day: 24)
        let id = try subject.create(
            .init(
                title: "Read",
                weekdays: [1, 2, 3, 4, 5, 6, 7],
                window: .evening,
                reminderHour: nil,
                reminderMinute: nil
            )
        )

        try subject.setCompleted(routineID: id, day: day, completed: true)
        XCTAssertTrue(try subject.isCompleted(routineID: id, day: day))
        try subject.setCompleted(routineID: id, day: day, completed: true)
        XCTAssertEqual(try subject.completedDays(routineID: id), [day])

        try subject.setCompleted(routineID: id, day: day, completed: false)
        XCTAssertFalse(try subject.isCompleted(routineID: id, day: day))
    }

    func testCurrentStreakCountsScheduledDaysBeforeAndAfterTodaysCompletion() throws {
        let container = try makeContainer()
        let subject = SwiftDataRoutineRepository(context: container.mainContext)
        let routineID = try subject.create(
            .init(
                title: "Run",
                weekdays: [2, 4, 6],
                window: .morning,
                reminderHour: nil,
                reminderMinute: nil
            )
        )
        let wednesday = LocalDay(year: 2026, month: 8, day: 19)
        let friday = LocalDay(year: 2026, month: 8, day: 21)
        let monday = LocalDay(year: 2026, month: 8, day: 24)
        try subject.setCompleted(routineID: routineID, day: wednesday, completed: true)
        try subject.setCompleted(routineID: routineID, day: friday, completed: true)

        let routine = try XCTUnwrap(subject.list(includeArchived: false).first)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        XCTAssertEqual(
            RoutineStreakCalculator().currentStreak(
                routine: routine,
                completedDays: try subject.completedDays(routineID: routineID),
                through: monday,
                calendar: calendar
            ),
            2
        )

        try subject.setCompleted(routineID: routineID, day: monday, completed: true)
        XCTAssertEqual(
            RoutineStreakCalculator().currentStreak(
                routine: routine,
                completedDays: try subject.completedDays(routineID: routineID),
                through: monday,
                calendar: calendar
            ),
            3
        )
    }

    func testDeleteRemovesRoutineAndEveryCompletionRecord() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: RoutineRecord.self,
            RoutineCompletionRecord.self,
            configurations: configuration
        )
        let subject = SwiftDataRoutineRepository(context: container.mainContext)
        let id = try subject.create(
            .init(title: "Read", weekdays: [2], window: .evening, reminderHour: nil, reminderMinute: nil)
        )
        try subject.setCompleted(routineID: id, day: .init(year: 2026, month: 8, day: 17), completed: true)
        try subject.setCompleted(routineID: id, day: .init(year: 2026, month: 8, day: 24), completed: true)

        try subject.delete(id: id)

        XCTAssertTrue(try subject.list(includeArchived: true).isEmpty)
        XCTAssertTrue(try subject.completedDays(routineID: id).isEmpty)
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<RoutineCompletionRecord>()).isEmpty)
    }

    func testCreateAndListRoundTripCategoryID() throws {
        let container = try makeContainer()
        let subject = SwiftDataRoutineRepository(context: container.mainContext)
        let categoryID = UUID(uuidString: "F46D5B2D-F279-4BCB-9307-D4EFCC52B7D6")!

        let id = try subject.create(
            .init(
                title: "Read",
                weekdays: [2],
                window: .evening,
                reminderHour: nil,
                reminderMinute: nil,
                categoryID: categoryID
            )
        )

        let routine = try XCTUnwrap(subject.list(includeArchived: false).first { $0.id == id })
        XCTAssertEqual(routine.categoryID, categoryID)
    }

    func testUpdateChangesCategoryIDAndDefaultCategoryRemainsNil() throws {
        let container = try makeContainer()
        let subject = SwiftDataRoutineRepository(context: container.mainContext)
        let categoryID = UUID(uuidString: "6C8CB9AB-615C-42B2-98A2-55D3BEA324A0")!
        let id = try subject.create(
            .init(title: "Read", weekdays: [2], window: .evening, reminderHour: nil, reminderMinute: nil)
        )

        XCTAssertNil(try XCTUnwrap(subject.list(includeArchived: false).first { $0.id == id }).categoryID)

        try subject.update(
            id: id,
            draft: .init(
                title: "Read",
                weekdays: [2],
                window: .evening,
                reminderHour: nil,
                reminderMinute: nil,
                categoryID: categoryID
            )
        )

        XCTAssertEqual(
            try XCTUnwrap(subject.list(includeArchived: false).first { $0.id == id }).categoryID,
            categoryID
        )
    }

    func testCreateRejectsInvalidDraft() throws {
        let container = try makeContainer()
        let subject = SwiftDataRoutineRepository(context: container.mainContext)
        let invalidDrafts = [
            RoutineDraft(title: "  ", weekdays: [2], window: .anytime, reminderHour: nil, reminderMinute: nil),
            RoutineDraft(title: "Read", weekdays: [], window: .anytime, reminderHour: nil, reminderMinute: nil),
            RoutineDraft(title: "Read", weekdays: [8], window: .anytime, reminderHour: nil, reminderMinute: nil),
            RoutineDraft(title: "Read", weekdays: [2], window: .anytime, reminderHour: 9, reminderMinute: nil),
            RoutineDraft(title: "Read", weekdays: [2], window: .anytime, reminderHour: 24, reminderMinute: 0),
            RoutineDraft(title: "Read", weekdays: [2], window: .anytime, reminderHour: 9, reminderMinute: 60)
        ]

        for draft in invalidDrafts {
            XCTAssertThrowsError(try subject.create(draft)) { error in
                XCTAssertEqual(error as? RoutineRepositoryError, .invalidDraft)
            }
        }
    }

    private func makeContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: RoutineRecord.self,
            RoutineCompletionRecord.self,
            configurations: configuration
        )
    }
}
