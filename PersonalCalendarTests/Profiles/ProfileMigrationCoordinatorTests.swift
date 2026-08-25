import SwiftData
import XCTest
@testable import PersonalCalendar

@MainActor
final class ProfileMigrationCoordinatorTests: XCTestCase {
    func testDeniedProviderStaysPendingThenMigratesExactlyOnceAfterGrant() throws {
        let routine = makeRoutine(id: UUID(uuidString: "AAAAAAAA-0000-4000-8000-000000000001")!)
        let fixture = try makeFixture(
            legacy: legacy(
                calendarIDs: ["school", "birthdays"],
                reminderListIDs: ["assignments"],
                calendarExplicit: false,
                reminderExplicit: true
            ),
            calendarAccess: .denied,
            reminderAccess: .granted,
            lists: [list("assignments", writable: true)],
            routines: [routine]
        )

        try fixture.subject.run()

        var personal = try fixture.repository.profile(id: SeedProfile.personalID)
        XCTAssertEqual(personal.calendarIDs, [])
        XCTAssertEqual(personal.reminderListIDs, ["assignments"])
        XCTAssertEqual(personal.routineIDs, [routine.id])
        XCTAssertFalse(fixture.settings.didMigrateProfilePart(.calendar))
        XCTAssertTrue(fixture.settings.didMigrateProfilePart(.reminders))
        XCTAssertTrue(fixture.settings.didMigrateProfilePart(.routines))

        fixture.calendar.accessState = .granted
        fixture.calendar.descriptors = [
            calendar("school", writable: true),
            calendar("birthdays", writable: false)
        ]
        try fixture.subject.run()
        try fixture.subject.run()

        personal = try fixture.repository.profile(id: SeedProfile.personalID)
        XCTAssertEqual(personal.calendarIDs, ["birthdays", "school"])
        XCTAssertEqual(try fixture.repository.list().map(\.id), [
            SeedProfile.personalID,
            SeedProfile.schoolID,
            SeedProfile.workID
        ])
        XCTAssertTrue(fixture.settings.didMigrateProfilePart(.calendar))
    }

    func testImplicitSelectionsUseEveryCurrentDescriptorAndOnlyWritableMemberDefaults() throws {
        let fixture = try makeFixture(
            legacy: legacy(
                defaultCalendarID: "work",
                defaultReminderListID: "locked",
                calendarExplicit: false,
                reminderExplicit: false
            ),
            calendarAccess: .granted,
            reminderAccess: .granted,
            calendars: [
                calendar("birthdays", writable: false),
                calendar("work", writable: true)
            ],
            lists: [
                list("home", writable: true),
                list("locked", writable: false)
            ]
        )

        try fixture.subject.run()

        let personal = try fixture.repository.profile(id: SeedProfile.personalID)
        XCTAssertEqual(personal.calendarIDs, ["birthdays", "work"])
        XCTAssertEqual(personal.reminderListIDs, ["home", "locked"])
        XCTAssertEqual(personal.defaultCalendarID, "work")
        XCTAssertNil(personal.defaultReminderListID)
    }

    func testExplicitStoredCalendarSelectionMigratesWhileEveryUnavailableStateIsPendingForImplicitSelection() throws {
        for access in [AccessState.notDetermined, .denied, .restricted] {
            let explicitFixture = try makeFixture(
                legacy: legacy(
                    calendarIDs: ["missing-school"],
                    defaultCalendarID: "missing-school",
                    calendarExplicit: true,
                    reminderExplicit: true
                ),
                calendarAccess: access,
                reminderAccess: .granted
            )

            try explicitFixture.subject.run()

            let explicitPersonal = try explicitFixture.repository.profile(id: SeedProfile.personalID)
            XCTAssertEqual(explicitPersonal.calendarIDs, ["missing-school"])
            XCTAssertNil(explicitPersonal.defaultCalendarID)
            XCTAssertTrue(explicitFixture.settings.didMigrateProfilePart(.calendar))

            let implicitFixture = try makeFixture(
                legacy: legacy(calendarExplicit: false, reminderExplicit: true),
                calendarAccess: access,
                reminderAccess: .granted
            )

            try implicitFixture.subject.run()

            XCTAssertEqual(
                try implicitFixture.repository.profile(id: SeedProfile.personalID).calendarIDs,
                []
            )
            XCTAssertFalse(implicitFixture.settings.didMigrateProfilePart(.calendar))
        }
    }

    func testRoutineMigrationUsesOnlyNonarchivedRoutinesAndNeverOverwritesCompletedMigration() throws {
        let active = makeRoutine(id: UUID(uuidString: "BBBBBBBB-0000-4000-8000-000000000001")!)
        let archived = makeRoutine(
            id: UUID(uuidString: "BBBBBBBB-0000-4000-8000-000000000002")!,
            archived: true
        )
        let fixture = try makeFixture(
            legacy: legacy(calendarExplicit: true, reminderExplicit: true),
            calendarAccess: .denied,
            reminderAccess: .denied,
            routines: [active, archived]
        )

        try fixture.subject.run()

        var personal = try fixture.repository.profile(id: SeedProfile.personalID)
        XCTAssertEqual(personal.routineIDs, [active.id])
        XCTAssertEqual(fixture.settings.activeProfileIdentity, .saved(SeedProfile.personalID))

        var edited = draft(from: personal)
        edited.routineIDs = [archived.id]
        try fixture.repository.update(id: SeedProfile.personalID, draft: edited)
        fixture.settings.setActiveProfile(.saved(SeedProfile.workID))

        try fixture.subject.run()

        personal = try fixture.repository.profile(id: SeedProfile.personalID)
        XCTAssertEqual(personal.routineIDs, [archived.id])
        XCTAssertEqual(fixture.settings.activeProfileIdentity, .saved(SeedProfile.workID))
    }

    func testInterruptedSeedRetriesOnlyMissingDeterministicProfiles() throws {
        let container = try makeContainer()
        let base = SwiftDataProfileRepository(context: container.mainContext)
        let repository = FailSecondCreateProfileRepository(base: base)
        let settings = AppSettingsStore(defaults: .ephemeral)
        settings.resetProfileMigration(legacy: legacy(calendarExplicit: true, reminderExplicit: true))
        let subject = ProfileMigrationCoordinator(
            profiles: repository,
            calendar: FakeCalendarService(access: .denied),
            reminders: FakeRemindersService(access: .denied),
            routines: FakeRoutineRepository(),
            settings: settings
        )

        XCTAssertThrowsError(try subject.run())
        XCTAssertEqual(try repository.list().map(\.id), [SeedProfile.personalID])
        XCTAssertFalse(settings.didMigrateProfilePart(.records))

        try subject.run()

        XCTAssertEqual(try repository.list().map(\.id), [
            SeedProfile.personalID,
            SeedProfile.schoolID,
            SeedProfile.workID
        ])
        XCTAssertTrue(settings.didMigrateProfilePart(.records))
    }

    private func makeFixture(
        legacy: LegacyProfileSelectionSnapshot,
        calendarAccess: AccessState,
        reminderAccess: AccessState,
        calendars: [CalendarDescriptor] = [],
        lists: [ReminderListDescriptor] = [],
        routines: [RoutineSnapshot] = []
    ) throws -> Fixture {
        let container = try makeContainer()
        let repository = SwiftDataProfileRepository(context: container.mainContext)
        let settings = AppSettingsStore(defaults: .ephemeral)
        settings.resetProfileMigration(legacy: legacy)
        let calendar = FakeCalendarService(access: calendarAccess, descriptors: calendars)
        let reminders = FakeRemindersService(access: reminderAccess, descriptors: lists)
        let routineRepository = FakeRoutineRepository(routines: routines)
        let subject = ProfileMigrationCoordinator(
            profiles: repository,
            calendar: calendar,
            reminders: reminders,
            routines: routineRepository,
            settings: settings
        )
        return Fixture(
            container: container,
            repository: repository,
            settings: settings,
            calendar: calendar,
            reminders: reminders,
            routines: routineRepository,
            subject: subject
        )
    }

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: ProfileRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private func legacy(
        calendarIDs: Set<String> = [],
        reminderListIDs: Set<String> = [],
        defaultCalendarID: String? = nil,
        defaultReminderListID: String? = nil,
        calendarExplicit: Bool,
        reminderExplicit: Bool
    ) -> LegacyProfileSelectionSnapshot {
        LegacyProfileSelectionSnapshot(
            calendarIDs: calendarIDs,
            reminderListIDs: reminderListIDs,
            defaultCalendarID: defaultCalendarID,
            defaultReminderListID: defaultReminderListID,
            calendarSelectionWasExplicit: calendarExplicit,
            reminderSelectionWasExplicit: reminderExplicit
        )
    }

    private func calendar(_ id: String, writable: Bool) -> CalendarDescriptor {
        CalendarDescriptor(id: id, title: id, colorHex: "#000000", allowsContentModifications: writable)
    }

    private func list(_ id: String, writable: Bool) -> ReminderListDescriptor {
        ReminderListDescriptor(id: id, title: id, colorHex: "#000000", allowsContentModifications: writable)
    }

    private func makeRoutine(id: UUID, archived: Bool = false) -> RoutineSnapshot {
        RoutineSnapshot(
            id: id,
            title: id.uuidString,
            weekdays: [2],
            window: .morning,
            reminderHour: nil,
            reminderMinute: nil,
            isPaused: false,
            isArchived: archived
        )
    }

    private func draft(from snapshot: ProfileSnapshot) -> ProfileDraft {
        ProfileDraft(
            name: snapshot.name,
            colorHex: snapshot.colorHex,
            symbolName: snapshot.symbolName,
            calendarIDs: snapshot.calendarIDs,
            reminderListIDs: snapshot.reminderListIDs,
            routineIDs: snapshot.routineIDs,
            defaultCalendarID: snapshot.defaultCalendarID,
            defaultReminderListID: snapshot.defaultReminderListID
        )
    }
}

@MainActor
private struct Fixture {
    let container: ModelContainer
    let repository: SwiftDataProfileRepository
    let settings: AppSettingsStore
    let calendar: FakeCalendarService
    let reminders: FakeRemindersService
    let routines: FakeRoutineRepository
    let subject: ProfileMigrationCoordinator
}

private enum ProfileMigrationTestError: Error {
    case interrupted
}

@MainActor
private final class FailSecondCreateProfileRepository: ProfileRepository {
    private let base: SwiftDataProfileRepository
    private var createCallCount = 0

    init(base: SwiftDataProfileRepository) {
        self.base = base
    }

    func list() throws -> [ProfileSnapshot] { try base.list() }
    func profile(id: UUID) throws -> ProfileSnapshot { try base.profile(id: id) }
    func create(_ draft: ProfileDraft, id: UUID?) throws -> UUID {
        createCallCount += 1
        if createCallCount == 2 {
            throw ProfileMigrationTestError.interrupted
        }
        return try base.create(draft, id: id)
    }
    func update(id: UUID, draft: ProfileDraft) throws { try base.update(id: id, draft: draft) }
    func reorder(_ ids: [UUID]) throws { try base.reorder(ids) }
    func delete(id: UUID) throws { try base.delete(id: id) }
    func removeRoutineID(_ id: UUID) throws { try base.removeRoutineID(id) }
    func unionMembership() throws -> ProfileMembership { try base.unionMembership() }
}
