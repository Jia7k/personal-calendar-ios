import Foundation
import SwiftData
import XCTest
@testable import PersonalCalendar

@MainActor
final class ProfileScopeResolverTests: XCTestCase {
    private static let personalID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    private static let schoolID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
    private static let invalidDefaultsID = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!
    private static let emptyID = UUID(uuidString: "44444444-4444-4444-8444-444444444444")!
    private static let week = DateInterval(
        start: Date(timeIntervalSince1970: 1_700_000_000),
        duration: 7 * 24 * 60 * 60
    )

    func testEverythingIsOnlyTheDeduplicatedAssignedUnionAndHasNoDefaults() throws {
        let fixture = try makeRepository()
        let sharedRoutine = UUID(uuidString: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA")!
        try createProfile(
            in: fixture.repository,
            id: Self.personalID,
            name: "Personal",
            calendarIDs: ["home", "shared"],
            reminderListIDs: ["personal", "shared-tasks"],
            routineIDs: [sharedRoutine],
            defaultCalendarID: "home",
            defaultReminderListID: "personal"
        )
        try createProfile(
            in: fixture.repository,
            id: Self.schoolID,
            name: "School",
            calendarIDs: ["school", "shared"],
            reminderListIDs: ["assignments", "shared-tasks"],
            routineIDs: [sharedRoutine],
            defaultCalendarID: "school",
            defaultReminderListID: "assignments"
        )
        let calendar = RecordingCalendarService(
            accessState: .granted,
            descriptors: [
                calendarDescriptor("home"),
                calendarDescriptor("school"),
                calendarDescriptor("shared"),
                calendarDescriptor("birthdays", writable: false)
            ]
        )
        let reminders = RecordingRemindersService(
            accessState: .granted,
            descriptors: [
                reminderDescriptor("personal"),
                reminderDescriptor("assignments"),
                reminderDescriptor("shared-tasks"),
                reminderDescriptor("inbox")
            ]
        )

        let scope = try ProfileScopeResolver(
            profiles: fixture.repository,
            calendar: calendar,
            reminders: reminders
        ).resolve(.everything)

        XCTAssertEqual(scope.identity, .everything)
        XCTAssertEqual(scope.calendarIDs, ["home", "school", "shared"])
        XCTAssertFalse(scope.calendarIDs.contains("birthdays"))
        XCTAssertEqual(scope.reminderListIDs, ["assignments", "personal", "shared-tasks"])
        XCTAssertFalse(scope.reminderListIDs.contains("inbox"))
        XCTAssertEqual(scope.routineIDs, [sharedRoutine])
        XCTAssertNil(scope.defaultCalendarID)
        XCTAssertNil(scope.defaultReminderListID)
    }

    func testSavedScopeIntersectsCurrentDescriptorsWithoutDeletingMissingRepositoryMembership() throws {
        let fixture = try makeRepository()
        let routineID = UUID(uuidString: "BBBBBBBB-BBBB-4BBB-8BBB-BBBBBBBBBBBB")!
        try createProfile(
            in: fixture.repository,
            id: Self.personalID,
            name: "Reconnect",
            calendarIDs: ["home", "missing-calendar"],
            reminderListIDs: ["tasks", "missing-list"],
            routineIDs: [routineID],
            defaultCalendarID: "missing-calendar",
            defaultReminderListID: "missing-list"
        )
        let calendar = RecordingCalendarService(
            accessState: .granted,
            descriptors: [calendarDescriptor("home"), calendarDescriptor("unassigned")]
        )
        let reminders = RecordingRemindersService(
            accessState: .granted,
            descriptors: [reminderDescriptor("tasks"), reminderDescriptor("inbox")]
        )

        let scope = try ProfileScopeResolver(
            profiles: fixture.repository,
            calendar: calendar,
            reminders: reminders
        ).resolve(.saved(Self.personalID))

        XCTAssertEqual(scope.calendarIDs, ["home"])
        XCTAssertEqual(scope.reminderListIDs, ["tasks"])
        XCTAssertEqual(scope.routineIDs, [routineID])
        XCTAssertNil(scope.defaultCalendarID)
        XCTAssertNil(scope.defaultReminderListID)

        let stored = try fixture.repository.profile(id: Self.personalID)
        XCTAssertEqual(stored.calendarIDs, ["home", "missing-calendar"])
        XCTAssertEqual(stored.reminderListIDs, ["tasks", "missing-list"])
        XCTAssertEqual(stored.defaultCalendarID, "missing-calendar")
        XCTAssertEqual(stored.defaultReminderListID, "missing-list")
    }

    func testSavedDefaultsRequireStoredMembershipAndCurrentWritableDescriptors() throws {
        let valid = profileSnapshot(
            id: Self.personalID,
            name: "Valid",
            calendarIDs: ["valid-calendar"],
            reminderListIDs: ["valid-list"],
            defaultCalendarID: "valid-calendar",
            defaultReminderListID: "valid-list"
        )
        let invalid = profileSnapshot(
            id: Self.invalidDefaultsID,
            name: "Invalid",
            calendarIDs: ["member-calendar"],
            reminderListIDs: ["read-only-list"],
            defaultCalendarID: "outside-membership",
            defaultReminderListID: "read-only-list"
        )
        let profiles = SnapshotProfileRepository(profiles: [valid, invalid])
        let calendar = RecordingCalendarService(
            accessState: .granted,
            descriptors: [
                calendarDescriptor("valid-calendar"),
                calendarDescriptor("member-calendar"),
                calendarDescriptor("outside-membership")
            ]
        )
        let reminders = RecordingRemindersService(
            accessState: .granted,
            descriptors: [
                reminderDescriptor("valid-list"),
                reminderDescriptor("read-only-list", writable: false)
            ]
        )
        let subject = ProfileScopeResolver(
            profiles: profiles,
            calendar: calendar,
            reminders: reminders
        )

        let validScope = try subject.resolve(.saved(Self.personalID))
        XCTAssertEqual(validScope.defaultCalendarID, "valid-calendar")
        XCTAssertEqual(validScope.defaultReminderListID, "valid-list")

        let invalidScope = try subject.resolve(.saved(Self.invalidDefaultsID))
        XCTAssertNil(invalidScope.defaultCalendarID)
        XCTAssertNil(invalidScope.defaultReminderListID)
    }

    func testUnavailableProviderAccessClearsExternalScopeButPreservesRoutineIDs() throws {
        let fixture = try makeRepository()
        let routineID = UUID(uuidString: "CCCCCCCC-CCCC-4CCC-8CCC-CCCCCCCCCCCC")!
        try createProfile(
            in: fixture.repository,
            id: Self.personalID,
            name: "Personal",
            calendarIDs: ["home"],
            reminderListIDs: ["tasks"],
            routineIDs: [routineID],
            defaultCalendarID: "home",
            defaultReminderListID: "tasks"
        )

        for access in [AccessState.denied, .restricted, .notDetermined] {
            let calendar = RecordingCalendarService(
                accessState: access,
                descriptors: [calendarDescriptor("home")]
            )
            let reminders = RecordingRemindersService(
                accessState: access,
                descriptors: [reminderDescriptor("tasks")]
            )

            let scope = try ProfileScopeResolver(
                profiles: fixture.repository,
                calendar: calendar,
                reminders: reminders
            ).resolve(.saved(Self.personalID))

            XCTAssertEqual(scope.calendarIDs, [], "Calendar access \(access) must fail closed")
            XCTAssertEqual(scope.reminderListIDs, [], "Reminders access \(access) must fail closed")
            XCTAssertEqual(scope.routineIDs, [routineID])
            XCTAssertNil(scope.defaultCalendarID)
            XCTAssertNil(scope.defaultReminderListID)
        }
    }

    func testEmptySavedScopeDoesNotCallProviders() async throws {
        let calendar = RecordingCalendarService(
            accessState: .granted,
            descriptors: [calendarDescriptor("unassigned")]
        )
        let reminders = RecordingRemindersService(
            accessState: .granted,
            descriptors: [reminderDescriptor("unassigned")]
        )
        let scope = ProfileScope(
            identity: .saved(Self.emptyID),
            calendarIDs: [],
            reminderListIDs: [],
            routineIDs: [],
            defaultCalendarID: nil,
            defaultReminderListID: nil
        )

        let result = try await ProfileSourceFetcher(calendar: calendar, reminders: reminders)
            .fetch(scope: scope, interval: Self.week)

        XCTAssertEqual(result.events, [])
        XCTAssertEqual(result.reminders, [])
        XCTAssertEqual(calendar.fetchCalls, 0)
        XCTAssertEqual(reminders.fetchCalls, 0)
    }

    private func makeRepository() throws -> ProfileRepositoryFixture {
        let container = try ModelContainer(
            for: ProfileRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ProfileRepositoryFixture(
            container: container,
            repository: SwiftDataProfileRepository(context: container.mainContext)
        )
    }

    private func createProfile(
        in repository: any ProfileRepository,
        id: UUID,
        name: String,
        calendarIDs: Set<String>,
        reminderListIDs: Set<String>,
        routineIDs: Set<UUID>,
        defaultCalendarID: String?,
        defaultReminderListID: String?
    ) throws {
        _ = try repository.create(
            ProfileDraft(
                name: name,
                colorHex: "#4868A8",
                symbolName: "person.fill",
                calendarIDs: calendarIDs,
                reminderListIDs: reminderListIDs,
                routineIDs: routineIDs,
                defaultCalendarID: defaultCalendarID,
                defaultReminderListID: defaultReminderListID
            ),
            id: id
        )
    }

    private func profileSnapshot(
        id: UUID,
        name: String,
        calendarIDs: Set<String>,
        reminderListIDs: Set<String>,
        defaultCalendarID: String?,
        defaultReminderListID: String?
    ) -> ProfileSnapshot {
        ProfileSnapshot(
            id: id,
            name: name,
            colorHex: "#4868A8",
            symbolName: "person.fill",
            sortOrder: 0,
            calendarIDs: calendarIDs,
            reminderListIDs: reminderListIDs,
            routineIDs: [],
            defaultCalendarID: defaultCalendarID,
            defaultReminderListID: defaultReminderListID
        )
    }

    private func calendarDescriptor(_ id: String, writable: Bool = true) -> CalendarDescriptor {
        CalendarDescriptor(
            id: id,
            title: id,
            colorHex: "#4868A8",
            allowsContentModifications: writable
        )
    }

    private func reminderDescriptor(_ id: String, writable: Bool = true) -> ReminderListDescriptor {
        ReminderListDescriptor(
            id: id,
            title: id,
            colorHex: "#4868A8",
            allowsContentModifications: writable
        )
    }
}

@MainActor
private struct ProfileRepositoryFixture {
    // Retaining the container keeps its in-memory store alive for the test.
    let container: ModelContainer
    let repository: SwiftDataProfileRepository
}

@MainActor
private final class SnapshotProfileRepository: ProfileRepository {
    private let profiles: [ProfileSnapshot]

    init(profiles: [ProfileSnapshot]) {
        self.profiles = profiles
    }

    func list() throws -> [ProfileSnapshot] {
        profiles.sorted { $0.sortOrder < $1.sortOrder }
    }

    func profile(id: UUID) throws -> ProfileSnapshot {
        guard let profile = profiles.first(where: { $0.id == id }) else {
            throw ProfileRepositoryError.profileNotFound
        }
        return profile
    }

    func create(_ draft: ProfileDraft, id: UUID?) throws -> UUID {
        fatalError("Mutation is not used by resolver tests")
    }

    func update(id: UUID, draft: ProfileDraft) throws {
        fatalError("Mutation is not used by resolver tests")
    }

    func reorder(_ ids: [UUID]) throws {
        fatalError("Mutation is not used by resolver tests")
    }

    func delete(id: UUID) throws {
        fatalError("Mutation is not used by resolver tests")
    }

    func removeRoutineID(_ id: UUID) throws {
        fatalError("Mutation is not used by resolver tests")
    }

    func unionMembership() throws -> ProfileMembership {
        ProfileMembership(
            calendarIDs: profiles.reduce(into: Set<String>()) { $0.formUnion($1.calendarIDs) },
            reminderListIDs: profiles.reduce(into: Set<String>()) { $0.formUnion($1.reminderListIDs) },
            routineIDs: profiles.reduce(into: Set<UUID>()) { $0.formUnion($1.routineIDs) }
        )
    }
}

@MainActor
private final class RecordingCalendarService: CalendarServicing {
    let accessState: AccessState
    let descriptors: [CalendarDescriptor]
    private(set) var fetchCalls = 0

    init(accessState: AccessState, descriptors: [CalendarDescriptor]) {
        self.accessState = accessState
        self.descriptors = descriptors
    }

    func requestFullAccess() async -> AccessState { accessState }
    func calendars() -> [CalendarDescriptor] { descriptors }

    func fetchEvents(
        in interval: DateInterval,
        calendarIDs: Set<String>
    ) throws -> [CalendarEventSnapshot] {
        fetchCalls += 1
        return []
    }

    func createEvent(_ draft: EventDraft) throws -> String? {
        fatalError("Mutation is not used by resolver tests")
    }

    func event(id: String) -> CalendarEventSnapshot? { nil }

    func updateEvent(id: String, draft: EventDraft, scope: RecurrenceEditScope) throws {
        fatalError("Mutation is not used by resolver tests")
    }

    func deleteEvent(id: String, scope: RecurrenceEditScope) throws {
        fatalError("Mutation is not used by resolver tests")
    }
}

@MainActor
private final class RecordingRemindersService: RemindersServicing {
    let accessState: AccessState
    let descriptors: [ReminderListDescriptor]
    private(set) var fetchCalls = 0

    init(accessState: AccessState, descriptors: [ReminderListDescriptor]) {
        self.accessState = accessState
        self.descriptors = descriptors
    }

    func requestFullAccess() async -> AccessState { accessState }
    func lists() -> [ReminderListDescriptor] { descriptors }

    func fetchReminders(listIDs: Set<String>) async throws -> [ReminderSnapshot] {
        fetchCalls += 1
        return []
    }

    func createReminder(_ draft: ReminderDraft) throws -> String? {
        fatalError("Mutation is not used by resolver tests")
    }

    func setCompleted(id: String, completed: Bool) throws {
        fatalError("Mutation is not used by resolver tests")
    }

    func reminder(id: String) -> ReminderSnapshot? { nil }

    func updateReminder(id: String, draft: ReminderDraft) throws {
        fatalError("Mutation is not used by resolver tests")
    }

    func deleteReminder(id: String) throws {
        fatalError("Mutation is not used by resolver tests")
    }
}
