import XCTest
@testable import PersonalCalendar

@MainActor
final class DailyActivitySnapshotCoordinatorTests: XCTestCase {
    private let profileID = UUID(uuidString: "B7E7D18E-6A86-4C5F-8BF8-1AE1C20EA6C2")!

    func testEmptyConfiguredMembershipNeverFetchesAllProviderData() async throws {
        let fixture = makeFixture(profile: profile(calendarIDs: [], reminderListIDs: []))

        let snapshot = try await fixture.subject.snapshot(
            for: .saved(profileID),
            now: fixture.now
        )

        XCTAssertTrue(fixture.calendar.fetchCalendarIDs.isEmpty)
        XCTAssertTrue(fixture.reminders.fetchListIDs.isEmpty)
        XCTAssertTrue(snapshot.items.isEmpty)
        XCTAssertFalse(snapshot.calendarUnavailable)
        XCTAssertFalse(snapshot.tasksUnavailable)
    }

    func testEverythingFetchesOnlyUnionMembershipAndExcludesUnassignedProviderItems() async throws {
        let school = profile(
            name: "School",
            calendarIDs: ["school-calendar"],
            reminderListIDs: ["school-list"]
        )
        let personal = profile(
            id: UUID(uuidString: "42D1465D-491C-47D0-A142-C7D2A271FEA6")!,
            name: "Home",
            calendarIDs: ["home-calendar"],
            reminderListIDs: []
        )
        let fixture = makeFixture(
            profiles: [school, personal],
            calendarDescriptors: [
                calendarDescriptor("school-calendar"),
                calendarDescriptor("home-calendar"),
                calendarDescriptor("private-calendar")
            ],
            reminderDescriptors: [
                reminderDescriptor("school-list"),
                reminderDescriptor("private-list")
            ],
            events: [
                event(id: "school", calendarID: "school-calendar"),
                event(id: "home", calendarID: "home-calendar"),
                event(id: "private", calendarID: "private-calendar")
            ],
            reminderValues: [
                reminder(id: "school", listID: "school-list"),
                reminder(id: "private", listID: "private-list")
            ]
        )

        let snapshot = try await fixture.subject.snapshot(for: .everything, now: fixture.now)

        XCTAssertEqual(fixture.calendar.fetchCalendarIDs, [["school-calendar", "home-calendar"]])
        XCTAssertEqual(fixture.reminders.fetchListIDs, [["school-list"]])
        XCTAssertEqual(snapshot.profile.id, .everything)
        XCTAssertEqual(snapshot.profile.name, "Everything")
        XCTAssertEqual(snapshot.items.filter { $0.kind == .event }.count, 2)
        XCTAssertEqual(snapshot.items.filter { $0.kind == .task }.count, 1)
        XCTAssertFalse(snapshot.items.contains { $0.title == "private" })
    }

    func testConfiguredButMissingSourceIsReportedWithoutFetchingIt() async throws {
        let fixture = makeFixture(
            profile: profile(
                calendarIDs: ["missing-calendar"],
                reminderListIDs: ["available-list"]
            ),
            calendarDescriptors: [],
            reminderDescriptors: [reminderDescriptor("available-list")],
            reminderValues: [reminder(id: "task", listID: "available-list")]
        )

        let snapshot = try await fixture.subject.snapshot(
            for: .saved(profileID),
            now: fixture.now
        )

        XCTAssertTrue(fixture.calendar.fetchCalendarIDs.isEmpty)
        XCTAssertEqual(fixture.reminders.fetchListIDs, [["available-list"]])
        XCTAssertTrue(snapshot.calendarUnavailable)
        XCTAssertFalse(snapshot.tasksUnavailable)
        XCTAssertEqual(snapshot.items.map(\.kind), [.task])
    }

    func testTaskOnlyProfileDoesNotTreatDeniedUnconfiguredCalendarAsUnavailable() async throws {
        let fixture = makeFixture(
            profile: profile(calendarIDs: [], reminderListIDs: ["tasks"]),
            calendarAccess: .denied,
            reminderDescriptors: [reminderDescriptor("tasks")],
            reminderValues: [reminder(id: "report", listID: "tasks")]
        )

        let snapshot = try await fixture.subject.snapshot(
            for: .saved(profileID),
            now: fixture.now
        )

        XCTAssertFalse(snapshot.calendarUnavailable)
        XCTAssertFalse(snapshot.tasksUnavailable)
        XCTAssertEqual(snapshot.items.count, 1)
        XCTAssertEqual(snapshot.items.first?.kind, .task)
    }

    func testSnapshotCachesWithinGenerationAndInvalidateForcesFreshFetch() async throws {
        let fixture = makeFixture(
            profile: profile(calendarIDs: ["calendar"], reminderListIDs: ["tasks"]),
            calendarDescriptors: [calendarDescriptor("calendar")],
            reminderDescriptors: [reminderDescriptor("tasks")],
            events: [event(id: "class", calendarID: "calendar")],
            reminderValues: [reminder(id: "report", listID: "tasks")]
        )

        let first = try await fixture.subject.snapshot(for: .saved(profileID), now: fixture.now)
        let second = try await fixture.subject.snapshot(for: .saved(profileID), now: fixture.now)

        XCTAssertEqual(first, second)
        XCTAssertEqual(fixture.calendar.fetchCalendarIDs.count, 1)
        XCTAssertEqual(fixture.reminders.fetchListIDs.count, 1)
        XCTAssertEqual(fixture.subject.revision, 0)

        fixture.subject.invalidate()
        _ = try await fixture.subject.snapshot(for: .saved(profileID), now: fixture.now)

        XCTAssertEqual(fixture.subject.revision, 1)
        XCTAssertEqual(fixture.calendar.fetchCalendarIDs.count, 2)
        XCTAssertEqual(fixture.reminders.fetchListIDs.count, 2)
    }

    func testInvalidateWhileReminderFetchIsSuspendedRejectsStaleResult() async throws {
        let fixture = makeFixture(
            profile: profile(calendarIDs: [], reminderListIDs: ["tasks"]),
            reminderDescriptors: [reminderDescriptor("tasks")],
            reminderValues: [reminder(id: "report", listID: "tasks")]
        )
        fixture.reminders.suspendNextFetch = true
        let request = Task {
            try await fixture.subject.snapshot(for: .saved(self.profileID), now: fixture.now)
        }
        await waitUntil { fixture.reminders.isFetchSuspended }

        fixture.subject.invalidate()
        fixture.reminders.resumeSuspendedFetch()

        do {
            _ = try await request.value
            XCTFail("A pre-invalidation fetch must not publish a stale snapshot.")
        } catch {
            XCTAssertEqual(
                error as? DailyActivitySnapshotCoordinatorError,
                .superseded
            )
        }
        XCTAssertEqual(fixture.subject.revision, 1)
    }

    func testEquivalentConcurrentConsumersBothReceiveSnapshots() async throws {
        let fixture = makeFixture(
            profile: profile(calendarIDs: [], reminderListIDs: ["tasks"]),
            reminderDescriptors: [reminderDescriptor("tasks")],
            reminderValues: [reminder(id: "report", listID: "tasks")]
        )
        fixture.reminders.suspendNextFetch = true
        let activityRequest = Task {
            try await fixture.subject.snapshot(for: .saved(self.profileID), now: fixture.now)
        }
        await waitUntil { fixture.reminders.isFetchSuspended }

        let preview = try await fixture.subject.snapshot(
            for: .saved(profileID),
            now: fixture.now
        )
        fixture.reminders.resumeSuspendedFetch()
        let activity = try await activityRequest.value

        XCTAssertEqual(activity, preview)
        XCTAssertEqual(activity.items.map(\.kind), [.task])
        XCTAssertEqual(fixture.subject.revision, 0)
        XCTAssertEqual(fixture.reminders.fetchListIDs.count, 2)
    }

    func testNewerSuccessfulEquivalentRequestWinsWhenTimestampsAreEqual() async throws {
        let fixture = makeFixture(
            profile: profile(calendarIDs: [], reminderListIDs: ["tasks"]),
            reminderDescriptors: [reminderDescriptor("tasks")],
            reminderValues: [reminder(id: "older", listID: "tasks")]
        )
        fixture.reminders.suspendNextFetch = true
        let activityRequest = Task {
            try await fixture.subject.snapshot(for: .saved(self.profileID), now: fixture.now)
        }
        await waitUntil { fixture.reminders.isFetchSuspended }
        fixture.reminders.reminders = [reminder(id: "newer", listID: "tasks")]

        let preview = try await fixture.subject.snapshot(
            for: .saved(profileID),
            now: fixture.now
        )
        fixture.reminders.resumeSuspendedFetch()
        let activity = try await activityRequest.value
        let cached = try await fixture.subject.snapshot(
            for: .saved(profileID),
            now: fixture.now
        )

        XCTAssertEqual(preview.items.map(\.title), ["newer"])
        XCTAssertEqual(activity, preview)
        XCTAssertEqual(cached, preview)
    }

    func testCachedSnapshotDoesNotSurviveProfileDeletion() async throws {
        let fixture = makeFixture(
            profile: profile(calendarIDs: [], reminderListIDs: ["tasks"]),
            reminderDescriptors: [reminderDescriptor("tasks")],
            reminderValues: [reminder(id: "report", listID: "tasks")]
        )
        _ = try await fixture.subject.snapshot(for: .saved(profileID), now: fixture.now)
        fixture.profiles.values = []

        do {
            _ = try await fixture.subject.snapshot(for: .saved(profileID), now: fixture.now)
            XCTFail("A deleted profile must not return its cached private content.")
        } catch {
            XCTAssertEqual(error as? ProfileRepositoryError, .profileNotFound)
        }
    }

    func testCachedSnapshotReevaluatesIntentionalMembershipRemoval() async throws {
        let fixture = makeFixture(
            profile: profile(calendarIDs: [], reminderListIDs: ["tasks"]),
            reminderDescriptors: [reminderDescriptor("tasks")],
            reminderValues: [reminder(id: "report", listID: "tasks")]
        )
        let first = try await fixture.subject.snapshot(for: .saved(profileID), now: fixture.now)
        fixture.profiles.values = [profile(calendarIDs: [], reminderListIDs: [])]

        let second = try await fixture.subject.snapshot(for: .saved(profileID), now: fixture.now)

        XCTAssertEqual(first.items.map(\.kind), [.task])
        XCTAssertTrue(second.items.isEmpty)
        XCTAssertFalse(second.tasksUnavailable)
        XCTAssertEqual(fixture.reminders.fetchListIDs.count, 1)
    }

    func testCachedSnapshotRemovesTasksAfterReminderPermissionIsRevoked() async throws {
        let fixture = makeFixture(
            profile: profile(calendarIDs: [], reminderListIDs: ["tasks"]),
            reminderDescriptors: [reminderDescriptor("tasks")],
            reminderValues: [reminder(id: "report", listID: "tasks")]
        )
        _ = try await fixture.subject.snapshot(for: .saved(profileID), now: fixture.now)
        fixture.reminders.accessState = .denied

        let snapshot = try await fixture.subject.snapshot(
            for: .saved(profileID),
            now: fixture.now
        )

        XCTAssertTrue(snapshot.items.isEmpty)
        XCTAssertTrue(snapshot.tasksUnavailable)
        XCTAssertEqual(fixture.reminders.fetchListIDs.count, 1)
    }

    func testCachedSnapshotRemovesTasksAfterConfiguredListDisappears() async throws {
        let fixture = makeFixture(
            profile: profile(calendarIDs: [], reminderListIDs: ["tasks"]),
            reminderDescriptors: [reminderDescriptor("tasks")],
            reminderValues: [reminder(id: "report", listID: "tasks")]
        )
        _ = try await fixture.subject.snapshot(for: .saved(profileID), now: fixture.now)
        fixture.reminders.descriptors = []

        let snapshot = try await fixture.subject.snapshot(
            for: .saved(profileID),
            now: fixture.now
        )

        XCTAssertTrue(snapshot.items.isEmpty)
        XCTAssertTrue(snapshot.tasksUnavailable)
        XCTAssertEqual(fixture.reminders.fetchListIDs.count, 1)
    }

    func testTimeZoneChangeDuringFetchSupersedesCapturedDayContext() async throws {
        let fixture = makeFixture(
            profile: profile(calendarIDs: [], reminderListIDs: ["tasks"]),
            reminderDescriptors: [reminderDescriptor("tasks")],
            reminderValues: [reminder(id: "report", listID: "tasks")],
            usesCalendarProvider: true
        )
        fixture.reminders.suspendNextFetch = true
        let request = Task {
            try await fixture.subject.snapshot(for: .saved(self.profileID), now: fixture.now)
        }
        await waitUntil { fixture.reminders.isFetchSuspended }
        fixture.calendarProvider.calendar.timeZone = TimeZone(identifier: "UTC")!

        fixture.reminders.resumeSuspendedFetch()

        do {
            _ = try await request.value
            XCTFail("A request must not publish into a different local day context.")
        } catch {
            XCTAssertEqual(
                error as? DailyActivitySnapshotCoordinatorError,
                .superseded
            )
        }
    }

    func testMembershipChangeDuringReminderFetchRejectsResultEvenWithoutExplicitInvalidation() async throws {
        let original = profile(calendarIDs: [], reminderListIDs: ["tasks"])
        let fixture = makeFixture(
            profile: original,
            reminderDescriptors: [reminderDescriptor("tasks")],
            reminderValues: [reminder(id: "report", listID: "tasks")]
        )
        fixture.reminders.suspendNextFetch = true
        let request = Task {
            try await fixture.subject.snapshot(for: .saved(self.profileID), now: fixture.now)
        }
        await waitUntil { fixture.reminders.isFetchSuspended }
        fixture.profiles.values = [profile(calendarIDs: [], reminderListIDs: [])]

        fixture.reminders.resumeSuspendedFetch()

        do {
            _ = try await request.value
            XCTFail("A result fetched for obsolete profile membership must be rejected.")
        } catch {
            XCTAssertEqual(
                error as? DailyActivitySnapshotCoordinatorError,
                .superseded
            )
        }
    }

    func testProviderFailureInvalidatesCacheGenerationAndRethrowsError() async {
        let fixture = makeFixture(
            profile: profile(calendarIDs: ["calendar"], reminderListIDs: []),
            calendarDescriptors: [calendarDescriptor("calendar")]
        )
        fixture.calendar.fetchError = DailyActivityProviderTestError.failed

        do {
            _ = try await fixture.subject.snapshot(for: .saved(profileID), now: fixture.now)
            XCTFail("An uncertain provider failure must be thrown.")
        } catch {
            XCTAssertEqual(error as? DailyActivityProviderTestError, .failed)
        }
        XCTAssertEqual(fixture.subject.revision, 1)
    }

    private func makeFixture(
        profile: ProfileSnapshot? = nil,
        profiles: [ProfileSnapshot]? = nil,
        calendarAccess: AccessState = .granted,
        reminderAccess: AccessState = .granted,
        calendarDescriptors: [CalendarDescriptor] = [],
        reminderDescriptors: [ReminderListDescriptor] = [],
        events: [CalendarEventSnapshot] = [],
        reminderValues: [ReminderSnapshot] = [],
        usesCalendarProvider: Bool = false
    ) -> DailyActivityCoordinatorFixture {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Singapore")!
        let now = calendar.date(from: DateComponents(
            year: 2026,
            month: 9,
            day: 16,
            hour: 9,
            minute: 40
        ))!
        let repository = MutableDailyProfileRepository(
            values: profiles ?? [profile ?? self.profile()]
        )
        let calendarService = FakeCalendarService(
            access: calendarAccess,
            events: events,
            descriptors: calendarDescriptors
        )
        let remindersService = FakeRemindersService(
            access: reminderAccess,
            reminders: reminderValues,
            descriptors: reminderDescriptors
        )
        let calendarProvider = MutableDailyCalendarProvider(calendar: calendar)
        let calendarSource: (@MainActor () -> Calendar)?
        if usesCalendarProvider {
            calendarSource = { calendarProvider.calendar }
        } else {
            calendarSource = nil
        }
        let subject = DailyActivitySnapshotCoordinator(
            profiles: repository,
            calendar: calendarService,
            reminders: remindersService,
            localCalendar: calendar,
            calendarProvider: calendarSource
        )
        return .init(
            subject: subject,
            profiles: repository,
            calendar: calendarService,
            reminders: remindersService,
            calendarProvider: calendarProvider,
            now: now
        )
    }

    private func profile(
        id: UUID? = nil,
        name: String = "School",
        calendarIDs: Set<String> = [],
        reminderListIDs: Set<String> = []
    ) -> ProfileSnapshot {
        .init(
            id: id ?? profileID,
            name: name,
            colorHex: "#4868A8",
            symbolName: "graduationcap.fill",
            sortOrder: 0,
            calendarIDs: calendarIDs,
            reminderListIDs: reminderListIDs,
            routineIDs: [],
            defaultCalendarID: nil,
            defaultReminderListID: nil
        )
    }

    private func calendarDescriptor(_ id: String) -> CalendarDescriptor {
        .init(id: id, title: id, colorHex: "#4868A8", allowsContentModifications: true)
    }

    private func reminderDescriptor(_ id: String) -> ReminderListDescriptor {
        .init(id: id, title: id, colorHex: "#D97745", allowsContentModifications: true)
    }

    private func event(id: String, calendarID: String) -> CalendarEventSnapshot {
        let start = Date(timeIntervalSince1970: 1_789_528_400)
        return .init(
            id: id,
            mutationID: id,
            title: id,
            start: start,
            end: start.addingTimeInterval(3_600),
            isAllDay: false,
            calendarID: calendarID,
            calendarTitle: calendarID,
            allowsModification: true,
            hasRecurrence: false
        )
    }

    private func reminder(id: String, listID: String) -> ReminderSnapshot {
        .init(
            id: id,
            title: id,
            notes: nil,
            dueDate: Date(timeIntervalSince1970: 1_789_530_000),
            dueHasTime: true,
            priority: 0,
            listID: listID,
            listTitle: listID,
            isCompleted: false,
            allowsModification: true,
            hasRecurrence: false
        )
    }

    private func waitUntil(
        _ predicate: @escaping @MainActor () -> Bool
    ) async {
        for _ in 0..<1_000 {
            if predicate() { return }
            await Task.yield()
        }
        XCTFail("Timed out waiting for suspended provider operation.")
    }
}

@MainActor
private struct DailyActivityCoordinatorFixture {
    let subject: DailyActivitySnapshotCoordinator
    let profiles: MutableDailyProfileRepository
    let calendar: FakeCalendarService
    let reminders: FakeRemindersService
    let calendarProvider: MutableDailyCalendarProvider
    let now: Date
}

@MainActor
private final class MutableDailyCalendarProvider {
    var calendar: Calendar

    init(calendar: Calendar) {
        self.calendar = calendar
    }
}

private enum DailyActivityProviderTestError: Error, Equatable {
    case failed
}

@MainActor
private final class MutableDailyProfileRepository: ProfileRepository {
    var values: [ProfileSnapshot]

    init(values: [ProfileSnapshot]) {
        self.values = values
    }

    func list() throws -> [ProfileSnapshot] { values }

    func profile(id: UUID) throws -> ProfileSnapshot {
        guard let value = values.first(where: { $0.id == id }) else {
            throw ProfileRepositoryError.profileNotFound
        }
        return value
    }

    func create(_ draft: ProfileDraft, id: UUID?) throws -> UUID {
        fatalError("Mutation is not used by daily activity provider tests")
    }

    func update(id: UUID, draft: ProfileDraft) throws {
        fatalError("Mutation is not used by daily activity provider tests")
    }

    func reorder(_ ids: [UUID]) throws {
        fatalError("Mutation is not used by daily activity provider tests")
    }

    func delete(id: UUID) throws {
        fatalError("Mutation is not used by daily activity provider tests")
    }

    func removeRoutineID(_ id: UUID) throws {
        fatalError("Mutation is not used by daily activity provider tests")
    }

    func unionMembership() throws -> ProfileMembership {
        .init(
            calendarIDs: values.reduce(into: Set<String>()) {
                $0.formUnion($1.calendarIDs)
            },
            reminderListIDs: values.reduce(into: Set<String>()) {
                $0.formUnion($1.reminderListIDs)
            },
            routineIDs: values.reduce(into: Set<UUID>()) {
                $0.formUnion($1.routineIDs)
            }
        )
    }
}
