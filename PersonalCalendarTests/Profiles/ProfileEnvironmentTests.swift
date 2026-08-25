import SwiftData
import XCTest
@testable import PersonalCalendar

@MainActor
final class ProfileEnvironmentTests: XCTestCase {
    func testRefreshMigratesBeforeLegacyReconciliationAndPublishesOneScopeRevision() async {
        var operations: [String] = []
        var scopeRevision = 0
        let subject = AppRefreshCoordinator(actions: RefreshActions(
            refreshPermissions: { operations.append("permissions") },
            migrateProfiles: { operations.append("profiles") },
            refreshSources: { operations.append("legacy") },
            reloadProfiles: {
                operations.append("catalog")
                scopeRevision += 1
            },
            refreshAgenda: { operations.append("agenda") },
            cleanCategoryLinks: { operations.append("cleanup") },
            refreshTimetable: { operations.append("timetable") },
            rescheduleNotifications: { operations.append("notifications") }
        ))

        await subject.refreshNow(reason: .foreground)

        XCTAssertEqual(operations, [
            "permissions",
            "profiles",
            "legacy",
            "catalog",
            "agenda",
            "cleanup",
            "timetable",
            "notifications"
        ])
        XCTAssertEqual(scopeRevision, 1)
        XCTAssertNotEqual(
            AppContentRevision(lifecycle: 1, profileScope: 0),
            AppContentRevision(lifecycle: 0, profileScope: 1)
        )
    }

    func testDemoEnvironmentExposesSeededProfilesAndMigratedPersonalScopeExactlyOnce() async throws {
        let container = try makeContainer()
        let environment = AppEnvironment.demo(container: container, arguments: [])

        XCTAssertEqual(try environment.profiles.list().map(\.id), [
            SeedProfile.personalID,
            SeedProfile.schoolID,
            SeedProfile.workID
        ])
        XCTAssertEqual(try environment.profiles.list().map(\.name), [
            "Personal",
            "School",
            "Work"
        ])
        XCTAssertEqual(environment.profileSelection.activeIdentity, .saved(SeedProfile.personalID))

        let personal = try environment.profileScopes.resolve(.saved(SeedProfile.personalID))
        XCTAssertEqual(personal.calendarIDs, ["demo-calendar"])
        XCTAssertEqual(personal.reminderListIDs, ["demo-list"])
        XCTAssertEqual(personal.routineIDs, [
            UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        ])

        let initialRevision = environment.profileSelection.scopeRevision
        await environment.refreshCoordinator.refreshNow(reason: .foreground)

        XCTAssertEqual(try environment.profiles.list().count, 3)
        XCTAssertEqual(environment.profileSelection.profiles.count, 3)
        XCTAssertEqual(environment.profileSelection.scopeRevision, initialRevision + 1)
    }

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: RoutineRecord.self,
            RoutineCompletionRecord.self,
            CategoryRecord.self,
            ExternalCategoryLinkRecord.self,
            ProfileRecord.self,
            configurations: ModelConfiguration(
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
        )
    }
}
