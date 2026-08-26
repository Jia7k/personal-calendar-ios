import XCTest
@testable import PersonalCalendar

@MainActor
final class ProfileSelectionControllerTests: XCTestCase {
    private static let personalID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private static let schoolID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    private static let workID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
    private static let missingID = UUID(uuidString: "99999999-9999-9999-9999-999999999999")!

    func testReloadRestoresValidPersistedSelectionAndPersistsMissingFallback() throws {
        let valid = try makeFixture(active: .saved(Self.personalID))

        XCTAssertEqual(valid.subject.profiles, valid.repository.snapshots)
        XCTAssertEqual(valid.subject.activeIdentity, .saved(Self.personalID))
        XCTAssertEqual(valid.subject.scopeRevision, 0)

        let missing = try makeFixture(active: .saved(Self.missingID))

        XCTAssertEqual(missing.subject.activeIdentity, .everything)
        XCTAssertEqual(missing.settings.activeProfileIdentity, .everything)
        XCTAssertEqual(
            AppSettingsStore(defaults: missing.defaults).activeProfileIdentity,
            .everything
        )
    }

    func testSelectingMissingSavedProfileThrowsTypedErrorWithoutChangingState() throws {
        let fixture = try makeFixture(active: .saved(Self.personalID))
        let initialProfiles = fixture.subject.profiles
        let initialIdentity = fixture.subject.activeIdentity
        let initialRevision = fixture.subject.scopeRevision

        XCTAssertThrowsError(try fixture.subject.select(.saved(Self.missingID))) { error in
            XCTAssertEqual(
                error as? ProfileSelectionError,
                .savedProfileNotFound(Self.missingID)
            )
        }

        XCTAssertEqual(fixture.subject.profiles, initialProfiles)
        XCTAssertEqual(fixture.subject.activeIdentity, initialIdentity)
        XCTAssertEqual(fixture.subject.scopeRevision, initialRevision)
        XCTAssertEqual(fixture.settings.activeProfileIdentity, initialIdentity)
        XCTAssertEqual(
            AppSettingsStore(defaults: fixture.defaults).activeProfileIdentity,
            initialIdentity
        )
    }

    func testSelectingDifferentIdentityIncrementsScopeRevisionOnceAndSelectingItAgainIsNoOp() throws {
        let fixture = try makeFixture(active: .everything)
        let initialRevision = fixture.subject.scopeRevision

        try fixture.subject.select(.saved(Self.personalID))

        XCTAssertEqual(fixture.subject.activeIdentity, .saved(Self.personalID))
        XCTAssertEqual(fixture.subject.scopeRevision, initialRevision + 1)
        XCTAssertEqual(fixture.settings.activeProfileIdentity, .saved(Self.personalID))

        try fixture.subject.select(.saved(Self.personalID))

        XCTAssertEqual(fixture.subject.activeIdentity, .saved(Self.personalID))
        XCTAssertEqual(fixture.subject.scopeRevision, initialRevision + 1)
    }

    func testProfileChangesInvalidateOnlyVisibleMembershipScopesAndIgnoreMetadata() throws {
        let fixture = try makeFixture(active: .saved(Self.personalID))
        let initialRevision = fixture.subject.scopeRevision

        try fixture.subject.profileDidChange(id: Self.schoolID, visibilityChanged: true)
        XCTAssertEqual(fixture.subject.scopeRevision, initialRevision)

        try fixture.subject.profileDidChange(id: Self.personalID, visibilityChanged: true)
        XCTAssertEqual(fixture.subject.scopeRevision, initialRevision + 1)

        try fixture.subject.profileDidChange(id: Self.personalID, visibilityChanged: false)
        XCTAssertEqual(fixture.subject.scopeRevision, initialRevision + 1)

        try fixture.subject.select(.everything)
        let everythingRevision = fixture.subject.scopeRevision

        try fixture.subject.profileDidChange(id: Self.schoolID, visibilityChanged: true)
        XCTAssertEqual(fixture.subject.scopeRevision, everythingRevision + 1)

        try fixture.subject.profileDidChange(id: Self.schoolID, visibilityChanged: false)
        XCTAssertEqual(fixture.subject.scopeRevision, everythingRevision + 1)
    }

    func testDeletionFallsBackOnlyWhenTheActiveSavedProfileIsDeleted() throws {
        let inactive = try makeFixture(active: .saved(Self.personalID))
        let inactiveRevision = inactive.subject.scopeRevision
        inactive.repository.snapshots.removeAll { $0.id == Self.schoolID }

        try inactive.subject.profileWasDeleted(id: Self.schoolID)

        XCTAssertEqual(inactive.subject.profiles.map(\.id), [Self.personalID])
        XCTAssertEqual(inactive.subject.activeIdentity, .saved(Self.personalID))
        XCTAssertEqual(inactive.subject.scopeRevision, inactiveRevision)
        XCTAssertEqual(inactive.settings.activeProfileIdentity, .saved(Self.personalID))

        let active = try makeFixture(active: .saved(Self.personalID))
        let activeRevision = active.subject.scopeRevision
        active.repository.snapshots.removeAll { $0.id == Self.personalID }

        try active.subject.profileWasDeleted(id: Self.personalID)

        XCTAssertEqual(active.subject.profiles.map(\.id), [Self.schoolID])
        XCTAssertEqual(active.subject.activeIdentity, .everything)
        XCTAssertEqual(active.subject.scopeRevision, activeRevision + 1)
        XCTAssertEqual(active.settings.activeProfileIdentity, .everything)
        XCTAssertEqual(
            AppSettingsStore(defaults: active.defaults).activeProfileIdentity,
            .everything
        )

        let everything = try makeFixture(active: .everything)
        let everythingRevision = everything.subject.scopeRevision
        everything.repository.snapshots.removeAll { $0.id == Self.schoolID }

        try everything.subject.profileWasDeleted(id: Self.schoolID)

        XCTAssertEqual(everything.subject.profiles.map(\.id), [Self.personalID])
        XCTAssertEqual(everything.subject.activeIdentity, .everything)
        XCTAssertEqual(everything.subject.scopeRevision, everythingRevision + 1)
    }

    func testReloadUpdatesCatalogWithoutChangingRevisionUntilActiveProfileDisappears() throws {
        let fixture = try makeFixture(active: .saved(Self.personalID))
        let initialRevision = fixture.subject.scopeRevision
        let updatedPersonal = profile(
            id: Self.personalID,
            name: "Personal renamed",
            sortOrder: 1,
            calendarIDs: ["home", "shared"]
        )
        fixture.repository.snapshots = [
            profile(id: Self.schoolID, name: "School", sortOrder: 0),
            updatedPersonal,
            profile(id: Self.workID, name: "Work", sortOrder: 2)
        ]

        try fixture.subject.reloadProfiles()

        XCTAssertEqual(
            fixture.subject.profiles.map(\.id),
            [Self.schoolID, Self.personalID, Self.workID]
        )
        XCTAssertEqual(fixture.subject.profiles[1], updatedPersonal)
        XCTAssertEqual(fixture.subject.activeIdentity, .saved(Self.personalID))
        XCTAssertEqual(fixture.subject.scopeRevision, initialRevision)

        fixture.repository.snapshots.removeAll { $0.id == Self.personalID }
        try fixture.subject.reloadProfiles()

        XCTAssertEqual(fixture.subject.profiles.map(\.id), [Self.schoolID, Self.workID])
        XCTAssertEqual(fixture.subject.activeIdentity, .everything)
        XCTAssertEqual(fixture.subject.scopeRevision, initialRevision + 1)
        XCTAssertEqual(fixture.settings.activeProfileIdentity, .everything)

        try fixture.subject.reloadProfiles()

        XCTAssertEqual(fixture.subject.scopeRevision, initialRevision + 1)
    }

    func testReloadClearsDeletedPreferredLiveActivityProfileWithoutFallingBack() throws {
        let fixture = try makeFixture(active: .everything)
        fixture.settings.setPreferredLiveActivityProfile(
            .saved(Self.schoolID),
            validProfileIDs: [Self.personalID, Self.schoolID]
        )
        fixture.settings.setAutomaticallyStartsLiveActivityOnForeground(true)
        fixture.repository.snapshots.removeAll { $0.id == Self.schoolID }

        try fixture.subject.reloadProfiles()

        XCTAssertNil(fixture.settings.preferredLiveActivityProfile)
        XCTAssertFalse(
            fixture.settings.automaticallyStartsLiveActivityOnForeground
        )
    }

    private func makeFixture(
        active: ProfileIdentity,
        profiles: [ProfileSnapshot]? = nil
    ) throws -> SelectionFixture {
        let suite = "ProfileSelectionControllerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let seededSettings = AppSettingsStore(defaults: defaults)
        seededSettings.setActiveProfile(active)
        let settings = AppSettingsStore(defaults: defaults)
        let repository = InMemoryProfileRepository(
            snapshots: profiles ?? [
                profile(id: Self.personalID, name: "Personal", sortOrder: 0),
                profile(id: Self.schoolID, name: "School", sortOrder: 1)
            ]
        )
        let subject = ProfileSelectionController(repository: repository, settings: settings)
        try subject.reloadProfiles()
        return SelectionFixture(
            defaults: defaults,
            repository: repository,
            settings: settings,
            subject: subject
        )
    }

    private func profile(
        id: UUID,
        name: String,
        sortOrder: Int,
        calendarIDs: Set<String> = []
    ) -> ProfileSnapshot {
        ProfileSnapshot(
            id: id,
            name: name,
            colorHex: "#4868A8",
            symbolName: "person.fill",
            sortOrder: sortOrder,
            calendarIDs: calendarIDs,
            reminderListIDs: [],
            routineIDs: [],
            defaultCalendarID: nil,
            defaultReminderListID: nil
        )
    }
}

@MainActor
private struct SelectionFixture {
    let defaults: UserDefaults
    let repository: InMemoryProfileRepository
    let settings: AppSettingsStore
    let subject: ProfileSelectionController
}

private enum InMemoryProfileRepositoryError: Error {
    case unexpectedMutation
}

@MainActor
private final class InMemoryProfileRepository: ProfileRepository {
    var snapshots: [ProfileSnapshot]

    init(snapshots: [ProfileSnapshot]) {
        self.snapshots = snapshots
    }

    func list() throws -> [ProfileSnapshot] {
        snapshots.sorted {
            ($0.sortOrder, $0.id.uuidString) < ($1.sortOrder, $1.id.uuidString)
        }
    }

    func profile(id: UUID) throws -> ProfileSnapshot {
        guard let snapshot = snapshots.first(where: { $0.id == id }) else {
            throw ProfileRepositoryError.profileNotFound
        }
        return snapshot
    }

    func create(_ draft: ProfileDraft, id: UUID?) throws -> UUID {
        throw InMemoryProfileRepositoryError.unexpectedMutation
    }

    func update(id: UUID, draft: ProfileDraft) throws {
        throw InMemoryProfileRepositoryError.unexpectedMutation
    }

    func reorder(_ ids: [UUID]) throws {
        throw InMemoryProfileRepositoryError.unexpectedMutation
    }

    func delete(id: UUID) throws {
        throw InMemoryProfileRepositoryError.unexpectedMutation
    }

    func removeRoutineID(_ id: UUID) throws {
        throw InMemoryProfileRepositoryError.unexpectedMutation
    }

    func unionMembership() throws -> ProfileMembership {
        ProfileMembership(
            calendarIDs: snapshots.reduce(into: Set<String>()) { $0.formUnion($1.calendarIDs) },
            reminderListIDs: snapshots.reduce(into: Set<String>()) { $0.formUnion($1.reminderListIDs) },
            routineIDs: snapshots.reduce(into: Set<UUID>()) { $0.formUnion($1.routineIDs) }
        )
    }
}
