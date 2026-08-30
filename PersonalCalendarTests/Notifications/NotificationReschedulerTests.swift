import XCTest
@testable import PersonalCalendar

@MainActor
final class NotificationReschedulerTests: XCTestCase {
    func testLatestAuthoritativeFailuresClearEveryOwnedRequestAndPersistPausedHealth() async {
        for failure in AuthoritativeFailure.allCases {
            let fixture = makeFixture()
            fixture.scheduler.pending = staleRequests()
            failure.inject(into: fixture)

            let outcome = await fixture.subject.reschedule()

            XCTAssertEqual(outcome, .failure, failure.description)
            XCTAssertEqual(fixture.scheduler.replacements, [[]], failure.description)
            XCTAssertTrue(fixture.scheduler.pending.isEmpty, failure.description)
            XCTAssertTrue(
                fixture.settings.notificationsPausedForStaleInput,
                failure.description
            )
            XCTAssertNil(
                fixture.settings.lastSuccessfulNotificationRefresh,
                failure.description
            )
            let reloaded = AppSettingsStore(defaults: fixture.defaults)
            XCTAssertTrue(
                reloaded.notificationsPausedForStaleInput,
                failure.description
            )
            XCTAssertNil(
                reloaded.lastSuccessfulNotificationRefresh,
                failure.description
            )
        }
    }

    func testCancelledLatestDeniedAuthorizationReadStillFailsClosed() async {
        let fixture = makeFixture()
        fixture.scheduler.pending = staleRequests()
        fixture.authorization.suspendNextRead = true

        let refresh = Task { @MainActor in
            await fixture.subject.reschedule()
        }
        while !fixture.authorization.isReadSuspended {
            await Task.yield()
        }

        fixture.authorization.setAccessState(.denied)
        refresh.cancel()
        fixture.authorization.resumeRead()
        let outcome = await refresh.value

        XCTAssertEqual(outcome, .failure)
        XCTAssertEqual(fixture.scheduler.replacements, [[]])
        XCTAssertTrue(fixture.scheduler.pending.isEmpty)
        XCTAssertTrue(fixture.settings.notificationsPausedForStaleInput)
        XCTAssertNil(fixture.settings.lastSuccessfulNotificationRefresh)
    }

    func testOlderFailedGenerationCannotClearNewerSuccessfulReplacement() async {
        let fixture = makeFixture()
        fixture.scheduler.pending = staleRequests()
        fixture.reminders.fetchError = ReschedulerTestError.authoritativeInput
        fixture.reminders.suspendNextFetch = true

        let olderRefresh = Task { @MainActor in
            await fixture.subject.reschedule()
        }
        while !fixture.reminders.isFetchSuspended {
            await Task.yield()
        }

        fixture.reminders.fetchError = nil
        let newerOutcome = await fixture.subject.reschedule()
        let newerRequests = fixture.scheduler.pending
        fixture.reminders.resumeSuspendedFetch()
        let olderOutcome = await olderRefresh.value

        XCTAssertEqual(newerOutcome, .success)
        XCTAssertEqual(olderOutcome, .superseded)
        XCTAssertEqual(fixture.scheduler.replacements.count, 1)
        XCTAssertEqual(fixture.scheduler.pending, newerRequests)
        XCTAssertFalse(fixture.settings.notificationsPausedForStaleInput)
        XCTAssertEqual(
            fixture.settings.lastSuccessfulNotificationRefresh,
            fixture.now
        )
    }

    func testLaterCompleteSuccessClearsPausedHealthAndPersistsRefreshDate() async {
        let fixture = makeFixture()
        fixture.reminders.fetchError = ReschedulerTestError.authoritativeInput

        let failureOutcome = await fixture.subject.reschedule()
        XCTAssertEqual(failureOutcome, .failure)
        XCTAssertTrue(fixture.settings.notificationsPausedForStaleInput)

        fixture.reminders.fetchError = nil
        let outcome = await fixture.subject.reschedule()

        XCTAssertEqual(outcome, .success)
        XCTAssertFalse(fixture.settings.notificationsPausedForStaleInput)
        XCTAssertEqual(
            fixture.settings.lastSuccessfulNotificationRefresh,
            fixture.now
        )
        XCTAssertFalse(fixture.scheduler.pending.isEmpty)
        let reloaded = AppSettingsStore(defaults: fixture.defaults)
        XCTAssertFalse(reloaded.notificationsPausedForStaleInput)
        XCTAssertEqual(reloaded.lastSuccessfulNotificationRefresh, fixture.now)
    }

    func testReplacementFailureDoesNotClearExistingPausedHealth() async {
        let fixture = makeFixture()
        fixture.reminders.fetchError = ReschedulerTestError.authoritativeInput
        let staleOutcome = await fixture.subject.reschedule()
        XCTAssertEqual(staleOutcome, .failure)

        fixture.reminders.fetchError = nil
        fixture.scheduler.replacementError =
            ReschedulerTestError.notificationReplacement
        let replacementOutcome = await fixture.subject.reschedule()

        XCTAssertEqual(replacementOutcome, .failure)
        XCTAssertTrue(fixture.settings.notificationsPausedForStaleInput)
        XCTAssertNil(fixture.settings.lastSuccessfulNotificationRefresh)
    }

    private func makeFixture() -> ReschedulerFixture {
        var localCalendar = Calendar(identifier: .gregorian)
        localCalendar.timeZone = TimeZone(identifier: "Asia/Singapore")!
        let now = localCalendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 24,
            hour: 7
        ))!
        let routineID = UUID(
            uuidString: "ABCDEFAB-CDEF-4ABC-8DEF-ABCDEFABCDEF"
        )!
        let profile = ProfileSnapshot(
            id: UUID(uuidString: "C0A10000-0000-4000-8000-000000000002")!,
            name: "School",
            colorHex: "#4868A8",
            symbolName: "graduationcap.fill",
            sortOrder: 0,
            calendarIDs: ["school-calendar"],
            reminderListIDs: ["school-reminders"],
            routineIDs: [routineID],
            defaultCalendarID: nil,
            defaultReminderListID: nil
        )
        let calendarService = FakeCalendarService(
            access: .granted,
            descriptors: [.init(
                id: "school-calendar",
                title: "School",
                colorHex: "#4868A8",
                allowsContentModifications: true
            )]
        )
        let reminders = FakeRemindersService(
            access: .granted,
            descriptors: [.init(
                id: "school-reminders",
                title: "School",
                colorHex: "#4868A8",
                allowsContentModifications: true
            )]
        )
        let routines = FakeRoutineRepository(routines: [.init(
            id: routineID,
            title: "Read",
            weekdays: [1, 2, 3, 4, 5, 6, 7],
            window: .morning,
            reminderHour: 9,
            reminderMinute: 0,
            isPaused: false,
            isArchived: false
        )])
        let profiles = ReschedulerProfileRepository(profiles: [profile])
        let authorization = FakeNotificationAuthorizer(access: .granted)
        let defaults = makeDefaults()
        let settings = AppSettingsStore(defaults: defaults)
        let scheduler = ReschedulerNotificationScheduler()
        let coordinator = NotificationCoordinator(scheduler: scheduler)
        let subject = NotificationRescheduler(
            calendarService: calendarService,
            reminders: reminders,
            routines: routines,
            profiles: profiles,
            composer: AgendaComposer(),
            settings: settings,
            profileScopes: ProfileScopeResolver(
                profiles: profiles,
                calendar: calendarService,
                reminders: reminders
            ),
            authorization: authorization,
            coordinator: coordinator,
            calendarProvider: { localCalendar },
            now: { now }
        )
        return .init(
            subject: subject,
            scheduler: scheduler,
            authorization: authorization,
            calendar: calendarService,
            reminders: reminders,
            routines: routines,
            profiles: profiles,
            settings: settings,
            defaults: defaults,
            now: now
        )
    }

    private func staleRequests() -> [LocalNotificationRequest] {
        [
            .init(
                identifier: "morning-summary",
                title: "Your day",
                body: "Old summary",
                fireDate: .distantFuture
            ),
            .init(
                identifier: "class|school|event",
                title: "Class",
                body: "Old class alert",
                fireDate: .distantFuture
            ),
            .init(
                identifier:
                    "routine|ABCDEFAB-CDEF-4ABC-8DEF-ABCDEFABCDEF|2026-08-24",
                title: "Read",
                body: "Old routine alert",
                fireDate: .distantFuture
            ),
            .init(
                identifier:
                    "snooze|ABCDEFAB-CDEF-4ABC-8DEF-ABCDEFABCDEF|2026-08-24|1",
                title: "Read",
                body: "Old snooze",
                fireDate: .distantFuture
            )
        ]
    }

    private func makeDefaults() -> UserDefaults {
        let suite = "NotificationReschedulerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }
}

@MainActor
private struct ReschedulerFixture {
    let subject: NotificationRescheduler
    let scheduler: ReschedulerNotificationScheduler
    let authorization: FakeNotificationAuthorizer
    let calendar: FakeCalendarService
    let reminders: FakeRemindersService
    let routines: FakeRoutineRepository
    let profiles: ReschedulerProfileRepository
    let settings: AppSettingsStore
    let defaults: UserDefaults
    let now: Date
}

private enum AuthoritativeFailure: String, CaseIterable, CustomStringConvertible {
    case authorization
    case scope
    case routineListing
    case routineCompletions
    case events
    case reminders
    case profiles

    var description: String { rawValue }

    @MainActor
    func inject(into fixture: ReschedulerFixture) {
        switch self {
        case .authorization:
            fixture.authorization.setAccessState(.denied)
        case .scope:
            fixture.profiles.unionError = ReschedulerTestError.authoritativeInput
        case .routineListing:
            fixture.routines.listError = ReschedulerTestError.authoritativeInput
        case .routineCompletions:
            fixture.routines.completedDaysError =
                ReschedulerTestError.authoritativeInput
        case .events:
            fixture.calendar.fetchError = ReschedulerTestError.authoritativeInput
        case .reminders:
            fixture.reminders.fetchError = ReschedulerTestError.authoritativeInput
        case .profiles:
            fixture.profiles.listError = ReschedulerTestError.authoritativeInput
        }
    }
}

private enum ReschedulerTestError: Error {
    case authoritativeInput
    case notificationReplacement
    case unexpectedMutation
}

@MainActor
private final class ReschedulerNotificationScheduler: NotificationScheduling {
    var pending: [LocalNotificationRequest] = []
    var replacementError: Error?
    private(set) var replacements: [[LocalNotificationRequest]] = []

    func pendingRequests() async -> [LocalNotificationRequest] {
        pending
    }

    func replaceAppRequests(
        with requests: [LocalNotificationRequest]
    ) async throws {
        if let replacementError { throw replacementError }
        replacements.append(requests)
        pending = requests
    }

    func schedule(_ request: LocalNotificationRequest) async throws {
        pending.append(request)
    }
}

@MainActor
private final class ReschedulerProfileRepository: ProfileRepository {
    var profiles: [ProfileSnapshot]
    var listError: Error?
    var unionError: Error?

    init(profiles: [ProfileSnapshot]) {
        self.profiles = profiles
    }

    func list() throws -> [ProfileSnapshot] {
        if let listError { throw listError }
        return profiles
    }

    func profile(id: UUID) throws -> ProfileSnapshot {
        guard let profile = profiles.first(where: { $0.id == id }) else {
            throw ProfileRepositoryError.profileNotFound
        }
        return profile
    }

    func create(_ draft: ProfileDraft, id: UUID?) throws -> UUID {
        throw ReschedulerTestError.unexpectedMutation
    }

    func update(id: UUID, draft: ProfileDraft) throws {
        throw ReschedulerTestError.unexpectedMutation
    }

    func reorder(_ ids: [UUID]) throws {
        throw ReschedulerTestError.unexpectedMutation
    }

    func delete(id: UUID) throws {
        throw ReschedulerTestError.unexpectedMutation
    }

    func removeRoutineID(_ id: UUID) throws {
        throw ReschedulerTestError.unexpectedMutation
    }

    func unionMembership() throws -> ProfileMembership {
        if let unionError { throw unionError }
        return ProfileMembership(
            calendarIDs: profiles.reduce(into: Set<String>()) {
                $0.formUnion($1.calendarIDs)
            },
            reminderListIDs: profiles.reduce(into: Set<String>()) {
                $0.formUnion($1.reminderListIDs)
            },
            routineIDs: profiles.reduce(into: Set<UUID>()) {
                $0.formUnion($1.routineIDs)
            }
        )
    }
}
