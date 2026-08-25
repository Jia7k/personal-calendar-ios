import SwiftData
import XCTest
@testable import PersonalCalendar

@MainActor
final class ProfileRepositoryTests: XCTestCase {
    func testManyToManyMembershipAndEverythingUnionRemainExact() throws {
        let subject = try makeSubject()
        let sharedRoutine = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!

        let personalID = try subject.create(
            ProfileDraft(
                name: "  Personal  ",
                colorHex: "#4868a8",
                symbolName: "person.fill",
                calendarIDs: ["home", "shared", "missing-calendar"],
                reminderListIDs: ["personal"],
                routineIDs: [sharedRoutine],
                defaultCalendarID: "home",
                defaultReminderListID: "personal"
            ),
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")
        )
        let schoolID = try subject.create(
            ProfileDraft(
                name: "School",
                colorHex: "#3A8D7C",
                symbolName: "graduationcap.fill",
                calendarIDs: ["school", "shared"],
                reminderListIDs: ["assignments"],
                routineIDs: [sharedRoutine],
                defaultCalendarID: "school",
                defaultReminderListID: "assignments"
            ),
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")
        )

        let personal = try subject.profile(id: personalID)
        XCTAssertEqual(personal.name, "Personal")
        XCTAssertEqual(personal.colorHex, "#4868A8")
        XCTAssertEqual(personal.calendarIDs, ["home", "shared", "missing-calendar"])
        XCTAssertEqual(try subject.profile(id: schoolID).routineIDs, [sharedRoutine])

        let union = try subject.unionMembership()
        XCTAssertEqual(union.calendarIDs, ["home", "missing-calendar", "school", "shared"])
        XCTAssertEqual(union.reminderListIDs, ["personal", "assignments"])
        XCTAssertEqual(union.routineIDs, [sharedRoutine])
    }

    func testValidationRunsBeforeMutation() throws {
        let subject = try makeSubject()
        _ = try subject.create(validDraft(name: "Personal"), id: nil)

        assertError(.duplicateName) {
            _ = try subject.create(validDraft(name: "  PERSONAL "), id: nil)
        }
        assertError(.invalidName) {
            _ = try subject.create(validDraft(name: " \n "), id: nil)
        }
        assertError(.invalidColor) {
            _ = try subject.create(validDraft(name: "School", colorHex: "#GGGGGG"), id: nil)
        }
        assertError(.invalidSymbol) {
            _ = try subject.create(validDraft(name: "School", symbolName: "externaldrive.badge.xmark"), id: nil)
        }
        assertError(.invalidExternalIdentifier) {
            var draft = validDraft(name: "School")
            draft.calendarIDs = [" "]
            _ = try subject.create(draft, id: nil)
        }
        assertError(.defaultCalendarNotMember) {
            var draft = validDraft(name: "School")
            draft.defaultCalendarID = "not-a-member"
            _ = try subject.create(draft, id: nil)
        }
        assertError(.defaultReminderListNotMember) {
            var draft = validDraft(name: "School")
            draft.defaultReminderListID = "not-a-member"
            _ = try subject.create(draft, id: nil)
        }

        XCTAssertEqual(try subject.list().map(\.name), ["Personal"])
    }

    func testReorderRequiresEveryProfileExactlyOnce() throws {
        let subject = try makeSubject()
        let personal = try subject.create(validDraft(name: "Personal"), id: nil)
        let school = try subject.create(validDraft(name: "School"), id: nil)
        let work = try subject.create(validDraft(name: "Work"), id: nil)

        try subject.reorder([work, personal, school])

        XCTAssertEqual(try subject.list().map(\.id), [work, personal, school])
        XCTAssertEqual(try subject.list().map(\.sortOrder), [0, 1, 2])
        assertError(.invalidReorder) { try subject.reorder([work, personal]) }
        assertError(.invalidReorder) { try subject.reorder([work, personal, personal]) }
        XCTAssertEqual(try subject.list().map(\.id), [work, personal, school])
    }

    func testDeletingAProfileCompactsOrderAndProtectsTheLastSavedProfile() throws {
        let subject = try makeSubject()
        let personal = try subject.create(validDraft(name: "Personal"), id: nil)
        let school = try subject.create(validDraft(name: "School"), id: nil)
        let work = try subject.create(validDraft(name: "Work"), id: nil)

        try subject.delete(id: school)

        XCTAssertEqual(try subject.list().map(\.id), [personal, work])
        XCTAssertEqual(try subject.list().map(\.sortOrder), [0, 1])
        try subject.delete(id: work)
        assertError(.cannotDeleteLastProfile) { try subject.delete(id: personal) }
        XCTAssertEqual(try subject.list().map(\.id), [personal])
    }

    func testRemovingRoutineMembershipUpdatesEveryProfileWithoutChangingOtherMembership() throws {
        let subject = try makeSubject()
        let removed = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        let retained = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
        var personal = validDraft(name: "Personal")
        personal.routineIDs = [removed, retained]
        var school = validDraft(name: "School")
        school.routineIDs = [removed]
        let personalID = try subject.create(personal, id: nil)
        let schoolID = try subject.create(school, id: nil)

        try subject.removeRoutineID(removed)

        XCTAssertEqual(try subject.profile(id: personalID).routineIDs, [retained])
        XCTAssertEqual(try subject.profile(id: schoolID).routineIDs, [])
        XCTAssertEqual(try subject.profile(id: personalID).calendarIDs, personal.calendarIDs)
    }

    private func makeSubject() throws -> SwiftDataProfileRepository {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: ProfileRecord.self, configurations: configuration)
        addTeardownBlock { _ = container }
        return SwiftDataProfileRepository(context: container.mainContext)
    }

    private func validDraft(
        name: String,
        colorHex: String = "#4868A8",
        symbolName: String = "person.fill"
    ) -> ProfileDraft {
        ProfileDraft(
            name: name,
            colorHex: colorHex,
            symbolName: symbolName,
            calendarIDs: ["calendar"],
            reminderListIDs: ["list"],
            routineIDs: [],
            defaultCalendarID: "calendar",
            defaultReminderListID: "list"
        )
    }

    private func assertError(
        _ expected: ProfileRepositoryError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () throws -> Void
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            XCTAssertEqual(error as? ProfileRepositoryError, expected, file: file, line: line)
        }
    }
}
