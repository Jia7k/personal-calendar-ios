import SwiftData
import XCTest
@testable import PersonalCalendar

@MainActor
final class RoutineProfileMutationCoordinatorTests: XCTestCase {
    private static let personalID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private static let schoolID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

    func testCreateInsertsNormalizedRoutineAndAssignsOnlyChosenProfile() throws {
        let fixture = try makeFixture()

        let routineID = try fixture.subject.create(
            draft: Self.routineDraft,
            profileID: Self.schoolID
        )

        let routine = try XCTUnwrap(
            fixture.routines.list(includeArchived: true).first { $0.id == routineID }
        )
        XCTAssertEqual(routine.title, "Read every night")
        XCTAssertEqual(routine.weekdays, [2, 4, 6])
        XCTAssertEqual(try fixture.profiles.profile(id: Self.schoolID).routineIDs, [routineID])
        XCTAssertEqual(try fixture.profiles.profile(id: Self.personalID).routineIDs, [])
    }

    func testDeleteRemovesRoutineCompletionsAndMembershipFromEveryProfile() throws {
        let fixture = try makeFixture()
        let routineID = try fixture.subject.create(
            draft: Self.routineDraft,
            profileID: Self.schoolID
        )
        try add(routineID: routineID, to: Self.personalID, profiles: fixture.profiles)
        try fixture.routines.setCompleted(
            routineID: routineID,
            day: LocalDay(year: 2026, month: 8, day: 24),
            completed: true
        )
        try fixture.routines.setCompleted(
            routineID: routineID,
            day: LocalDay(year: 2026, month: 8, day: 26),
            completed: true
        )

        try fixture.subject.delete(id: routineID)

        XCTAssertFalse(try fixture.routines.list(includeArchived: true).contains { $0.id == routineID })
        XCTAssertTrue(try fixture.context.fetch(FetchDescriptor<RoutineCompletionRecord>()).allSatisfy {
            $0.routineID != routineID
        })
        XCTAssertTrue(try fixture.profiles.list().allSatisfy {
            !$0.routineIDs.contains(routineID)
        })
    }

    func testCreateSaveFailureRollsBackRoutineAndProfileMembership() throws {
        let fixture = try makeFixture()
        let profilesBefore = try fixture.profiles.list()
        let subject = RoutineProfileMutationCoordinator(
            context: fixture.context,
            transaction: { changes in
                try changes()
                throw InjectedSaveError.failed
            }
        )

        XCTAssertThrowsError(
            try subject.create(draft: Self.routineDraft, profileID: Self.schoolID)
        ) { error in
            XCTAssertEqual(error as? InjectedSaveError, .failed)
        }

        XCTAssertTrue(try fixture.routines.list(includeArchived: true).isEmpty)
        XCTAssertEqual(try fixture.profiles.list(), profilesBefore)
    }

    func testDeleteSaveFailureRollsBackRoutineCompletionsAndProfileMembership() throws {
        let fixture = try makeFixture()
        let routineID = try fixture.subject.create(
            draft: Self.routineDraft,
            profileID: Self.schoolID
        )
        try add(routineID: routineID, to: Self.personalID, profiles: fixture.profiles)
        try fixture.routines.setCompleted(
            routineID: routineID,
            day: LocalDay(year: 2026, month: 8, day: 24),
            completed: true
        )
        let routinesBefore = try fixture.routines.list(includeArchived: true)
        let completionsBefore = try fixture.routines.completedDays(routineID: routineID)
        let profilesBefore = try fixture.profiles.list()
        let subject = RoutineProfileMutationCoordinator(
            context: fixture.context,
            transaction: { changes in
                try changes()
                throw InjectedSaveError.failed
            }
        )

        XCTAssertThrowsError(try subject.delete(id: routineID)) { error in
            XCTAssertEqual(error as? InjectedSaveError, .failed)
        }

        XCTAssertEqual(try fixture.routines.list(includeArchived: true), routinesBefore)
        XCTAssertEqual(try fixture.routines.completedDays(routineID: routineID), completionsBefore)
        XCTAssertEqual(try fixture.profiles.list(), profilesBefore)
    }

    func testRoutinesViewModelRoutesCreateAndDeleteThroughProfileMutator() throws {
        let fixture = try makeFixture()
        var membershipChanges = 0
        let model = RoutinesViewModel(
            repository: fixture.routines,
            routineProfileMutations: fixture.subject,
            selectedProfileID: { Self.schoolID },
            onProfileMembershipChanged: { membershipChanges += 1 }
        )

        XCTAssertTrue(model.create(Self.routineDraft))
        let routineID = try XCTUnwrap(
            fixture.profiles.profile(id: Self.schoolID).routineIDs.first
        )
        XCTAssertTrue(model.delete(id: routineID))

        XCTAssertTrue(try fixture.routines.list(includeArchived: true).isEmpty)
        XCTAssertTrue(try fixture.profiles.profile(id: Self.schoolID).routineIDs.isEmpty)
        XCTAssertEqual(membershipChanges, 2)
    }

    private static let routineDraft = RoutineDraft(
        title: "  Read every night  ",
        weekdays: [2, 4, 6],
        window: .evening,
        reminderHour: 21,
        reminderMinute: 0
    )

    private func makeFixture() throws -> RoutineProfileMutationFixture {
        let container = try ModelContainer(
            for: RoutineRecord.self,
            RoutineCompletionRecord.self,
            ProfileRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let profiles = SwiftDataProfileRepository(context: context)
        _ = try profiles.create(profileDraft(name: "Personal"), id: Self.personalID)
        _ = try profiles.create(profileDraft(name: "School"), id: Self.schoolID)
        return RoutineProfileMutationFixture(
            container: container,
            context: context,
            profiles: profiles,
            routines: SwiftDataRoutineRepository(context: context),
            subject: RoutineProfileMutationCoordinator(context: context)
        )
    }

    private func profileDraft(name: String) -> ProfileDraft {
        ProfileDraft(
            name: name,
            colorHex: "#4868A8",
            symbolName: "person.fill",
            calendarIDs: [],
            reminderListIDs: [],
            routineIDs: [],
            defaultCalendarID: nil,
            defaultReminderListID: nil
        )
    }

    private func add(
        routineID: UUID,
        to profileID: UUID,
        profiles: SwiftDataProfileRepository
    ) throws {
        let profile = try profiles.profile(id: profileID)
        try profiles.update(
            id: profileID,
            draft: ProfileDraft(
                name: profile.name,
                colorHex: profile.colorHex,
                symbolName: profile.symbolName,
                calendarIDs: profile.calendarIDs,
                reminderListIDs: profile.reminderListIDs,
                routineIDs: profile.routineIDs.union([routineID]),
                defaultCalendarID: profile.defaultCalendarID,
                defaultReminderListID: profile.defaultReminderListID
            )
        )
    }
}

@MainActor
private struct RoutineProfileMutationFixture {
    let container: ModelContainer
    let context: ModelContext
    let profiles: SwiftDataProfileRepository
    let routines: SwiftDataRoutineRepository
    let subject: RoutineProfileMutationCoordinator
}

private enum InjectedSaveError: Error, Equatable {
    case failed
}
