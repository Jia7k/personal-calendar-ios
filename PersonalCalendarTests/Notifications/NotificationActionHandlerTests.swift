import XCTest
@testable import PersonalCalendar

@MainActor
final class NotificationActionHandlerTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Singapore")!
        return calendar
    }

    private var now: Date {
        calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 24,
            hour: 9,
            minute: 30
        ))!
    }

    func testCompleteWritesCurrentScheduledDayOnceWhenResponseIsRepeated() async {
        let day = LocalDay(date: now, calendar: calendar)
        let routine = makeRoutine()
        let routines = FakeRoutineRepository(routines: [routine])
        let scheduler = NotificationActionSchedulerSpy()
        var refreshCount = 0
        let subject = makeSubject(
            routines: routines,
            scheduler: scheduler,
            onRoutineCompletionCommitted: { refreshCount += 1 }
        )
        let userInfo = payload(routineID: routine.id, day: day)

        await subject.handle(
            actionIdentifier: NotificationActionIdentifier.routineComplete,
            userInfo: userInfo
        )
        await subject.handle(
            actionIdentifier: NotificationActionIdentifier.routineComplete,
            userInfo: userInfo
        )

        XCTAssertEqual(
            routines.completionCalls,
            [.init(id: routine.id, day: day, completed: true)]
        )
        XCTAssertTrue(scheduler.scheduled.isEmpty)
        XCTAssertTrue(scheduler.replacements.isEmpty)
        XCTAssertEqual(refreshCount, 1)
    }

    func testCompleteAwaitsRefreshHookAfterSuccessfulWrite() async {
        let day = LocalDay(date: now, calendar: calendar)
        let routine = makeRoutine()
        let routines = FakeRoutineRepository(routines: [routine])
        let gate = NotificationActionHookGate()
        let hookStarted = expectation(description: "completion refresh hook started")
        var didReturn = false
        let subject = makeSubject(
            routines: routines,
            scheduler: NotificationActionSchedulerSpy(),
            onRoutineCompletionCommitted: {
                XCTAssertEqual(
                    routines.completionCalls,
                    [.init(id: routine.id, day: day, completed: true)]
                )
                hookStarted.fulfill()
                await gate.wait()
            }
        )

        let handling = Task { @MainActor in
            await subject.handle(
                actionIdentifier: NotificationActionIdentifier.routineComplete,
                userInfo: payload(routineID: routine.id, day: day)
            )
            didReturn = true
        }
        await fulfillment(of: [hookStarted], timeout: 1)

        XCTAssertFalse(didReturn)
        await gate.open()
        await handling.value
        XCTAssertTrue(didReturn)
    }

    func testHookGateRemembersAnOpenThatArrivesBeforeWait() async {
        let gate = NotificationActionHookGate()
        await gate.open()
        let waitReturned = expectation(description: "early-open gate returned")
        let waiter = Task {
            await gate.wait()
            waitReturned.fulfill()
        }

        await fulfillment(of: [waitReturned], timeout: 0.5)

        await gate.open()
        await waiter.value
    }

    func testFailedCompletionWriteDoesNotRunRefreshHook() async {
        let routine = makeRoutine()
        let routines = FakeRoutineRepository(routines: [routine])
        routines.completionError = NotificationActionTestError.failed
        var refreshCount = 0
        let subject = makeSubject(
            routines: routines,
            scheduler: NotificationActionSchedulerSpy(),
            onRoutineCompletionCommitted: { refreshCount += 1 }
        )

        await subject.handle(
            actionIdentifier: NotificationActionIdentifier.routineComplete,
            userInfo: payload(
                routineID: routine.id,
                day: LocalDay(date: now, calendar: calendar)
            )
        )

        XCTAssertTrue(routines.completionCalls.isEmpty)
        XCTAssertEqual(refreshCount, 0)
    }

    func testRefreshFailureAfterCompletionDoesNotRepeatCompletionWrite() async {
        let day = LocalDay(date: now, calendar: calendar)
        let routine = makeRoutine()
        let routines = FakeRoutineRepository(routines: [routine])
        let model = RoutinesViewModel(repository: routines, calendar: calendar, now: { self.now })
        model.reload()
        var refreshCount = 0
        let subject = makeSubject(
            routines: routines,
            scheduler: NotificationActionSchedulerSpy(),
            onRoutineCompletionCommitted: {
                refreshCount += 1
                routines.listError = NotificationActionTestError.failed
                await model.refreshForExternalChange()
            }
        )
        let userInfo = payload(routineID: routine.id, day: day)

        await subject.handle(
            actionIdentifier: NotificationActionIdentifier.routineComplete,
            userInfo: userInfo
        )
        routines.listError = nil
        await subject.handle(
            actionIdentifier: NotificationActionIdentifier.routineComplete,
            userInfo: userInfo
        )

        XCTAssertEqual(
            routines.completionCalls,
            [.init(id: routine.id, day: day, completed: true)]
        )
        XCTAssertEqual(refreshCount, 1)
        XCTAssertNotNil(model.refreshErrorMessage)
    }

    func testStaleRoutineDayDoesNotCompleteSnoozeOrRunRefreshHook() async {
        let routine = makeRoutine()
        let routines = FakeRoutineRepository(routines: [routine])
        let scheduler = NotificationActionSchedulerSpy()
        var refreshCount = 0
        let subject = makeSubject(
            routines: routines,
            scheduler: scheduler,
            onRoutineCompletionCommitted: { refreshCount += 1 }
        )
        let staleDay = LocalDay(year: 2026, month: 8, day: 23)
        let userInfo = payload(routineID: routine.id, day: staleDay)

        await subject.handle(
            actionIdentifier: NotificationActionIdentifier.routineComplete,
            userInfo: userInfo
        )
        await subject.handle(
            actionIdentifier: NotificationActionIdentifier.routineSnooze15,
            userInfo: userInfo
        )

        XCTAssertTrue(routines.completionCalls.isEmpty)
        XCTAssertTrue(scheduler.scheduled.isEmpty)
        XCTAssertTrue(scheduler.replacements.isEmpty)
        XCTAssertEqual(refreshCount, 0)
    }

    func testMalformedPayloadAndUnsupportedActionDoNotRunRefreshHook() async {
        let routine = makeRoutine()
        let routines = FakeRoutineRepository(routines: [routine])
        let scheduler = NotificationActionSchedulerSpy()
        var refreshCount = 0
        let subject = makeSubject(
            routines: routines,
            scheduler: scheduler,
            onRoutineCompletionCommitted: { refreshCount += 1 }
        )

        await subject.handle(
            actionIdentifier: NotificationActionIdentifier.routineComplete,
            userInfo: [NotificationPayloadKey.routineID: "not-a-uuid"]
        )
        await subject.handle(
            actionIdentifier: "unsupported-action",
            userInfo: payload(
                routineID: routine.id,
                day: LocalDay(date: now, calendar: calendar)
            )
        )

        XCTAssertEqual(refreshCount, 0)
        XCTAssertTrue(routines.completionCalls.isEmpty)
        XCTAssertTrue(scheduler.scheduled.isEmpty)
    }

    func testSnoozeSchedulesOneActionableRequestFifteenMinutesAfterResponseWithoutReplacingPendingRequests() async {
        let day = LocalDay(date: now, calendar: calendar)
        let routine = makeRoutine(title: "Morning review")
        let routines = FakeRoutineRepository(routines: [routine])
        let scheduler = NotificationActionSchedulerSpy()
        var refreshCount = 0
        let subject = makeSubject(
            routines: routines,
            scheduler: scheduler,
            onRoutineCompletionCommitted: { refreshCount += 1 }
        )
        let userInfo = payload(routineID: routine.id, day: day)

        await subject.handle(
            actionIdentifier: NotificationActionIdentifier.routineSnooze15,
            userInfo: userInfo
        )

        XCTAssertEqual(scheduler.scheduled.count, 1)
        let request = try! XCTUnwrap(scheduler.scheduled.first)
        XCTAssertTrue(request.identifier.hasPrefix("snooze|\(routine.id.uuidString)|"))
        XCTAssertEqual(request.title, routine.title)
        XCTAssertEqual(request.body, "A gentle reminder for your routine.")
        XCTAssertEqual(request.fireDate, calendar.date(byAdding: .minute, value: 15, to: now))
        XCTAssertEqual(request.categoryIdentifier, NotificationCategoryIdentifier.routineReminder)
        XCTAssertEqual(request.userInfo, userInfo)
        XCTAssertTrue(scheduler.replacements.isEmpty)
        XCTAssertTrue(routines.completionCalls.isEmpty)
        XCTAssertEqual(refreshCount, 0)
    }

    func testSnoozeRejectsRoutineAlreadyCompletedForPayloadDay() async throws {
        let day = LocalDay(date: now, calendar: calendar)
        let routine = makeRoutine()
        let routines = FakeRoutineRepository(routines: [routine])
        try routines.setCompleted(routineID: routine.id, day: day, completed: true)
        let scheduler = NotificationActionSchedulerSpy()
        var refreshCount = 0
        let subject = makeSubject(
            routines: routines,
            scheduler: scheduler,
            onRoutineCompletionCommitted: { refreshCount += 1 }
        )

        await subject.handle(
            actionIdentifier: NotificationActionIdentifier.routineSnooze15,
            userInfo: payload(routineID: routine.id, day: day)
        )

        XCTAssertTrue(scheduler.scheduled.isEmpty)
        XCTAssertEqual(refreshCount, 0)
    }

    func testMissingPausedArchivedAndWrongWeekdayRoutinesRejectEveryActionWithoutWrites() async {
        let day = LocalDay(date: now, calendar: calendar)
        let missingID = UUID()
        let scenarios: [(UUID, [RoutineSnapshot])] = [
            (missingID, []),
            {
                let routine = makeRoutine(isPaused: true)
                return (routine.id, [routine])
            }(),
            {
                let routine = makeRoutine(isArchived: true)
                return (routine.id, [routine])
            }(),
            {
                let routine = makeRoutine(weekdays: [3])
                return (routine.id, [routine])
            }()
        ]

        for (routineID, snapshots) in scenarios {
            let routines = FakeRoutineRepository(routines: snapshots)
            let scheduler = NotificationActionSchedulerSpy()
            var refreshCount = 0
            let subject = makeSubject(
                routines: routines,
                scheduler: scheduler,
                onRoutineCompletionCommitted: { refreshCount += 1 }
            )
            let userInfo = payload(routineID: routineID, day: day)

            await subject.handle(
                actionIdentifier: NotificationActionIdentifier.routineComplete,
                userInfo: userInfo
            )
            await subject.handle(
                actionIdentifier: NotificationActionIdentifier.routineSnooze15,
                userInfo: userInfo
            )

            XCTAssertTrue(routines.completionCalls.isEmpty)
            XCTAssertTrue(scheduler.scheduled.isEmpty)
            XCTAssertTrue(scheduler.replacements.isEmpty)
            XCTAssertEqual(refreshCount, 0)
        }
    }

    func testAppEnvironmentCompletionHookRefreshesRegistryBeforeRescheduling() async {
        let registry = AgendaRefreshRegistry()
        let registrationID = UUID()
        var operations: [String] = []
        registry.register(id: registrationID) {
            operations.append("routines")
        }
        let hook = AppEnvironment.makeRoutineCompletionCommittedHook(
            agendaRefreshRegistry: registry,
            rescheduleNotifications: {
                operations.append("notifications")
            }
        )

        await hook()

        XCTAssertEqual(operations, ["routines", "notifications"])
    }

    func testRoutineRemovedFromEveryProfileRejectsCompletionAndSnooze() async {
        let day = LocalDay(date: now, calendar: calendar)
        let routine = makeRoutine()
        let routines = FakeRoutineRepository(routines: [routine])
        let scheduler = NotificationActionSchedulerSpy()
        var refreshCount = 0
        let subject = makeSubject(
            routines: routines,
            scheduler: scheduler,
            isRoutineInNotificationScope: { _ in false },
            onRoutineCompletionCommitted: { refreshCount += 1 }
        )
        let userInfo = payload(routineID: routine.id, day: day)

        await subject.handle(
            actionIdentifier: NotificationActionIdentifier.routineComplete,
            userInfo: userInfo
        )
        await subject.handle(
            actionIdentifier: NotificationActionIdentifier.routineSnooze15,
            userInfo: userInfo
        )

        XCTAssertTrue(routines.completionCalls.isEmpty)
        XCTAssertTrue(scheduler.scheduled.isEmpty)
        XCTAssertEqual(refreshCount, 0)
    }

    private func makeSubject(
        routines: FakeRoutineRepository,
        scheduler: NotificationActionSchedulerSpy,
        isRoutineInNotificationScope: @escaping @MainActor (UUID) -> Bool = { _ in true },
        onRoutineCompletionCommitted: @escaping @MainActor @Sendable () async -> Void = {}
    ) -> AppNotificationActionHandler {
        AppNotificationActionHandler(
            routines: routines,
            scheduler: scheduler,
            calendar: calendar,
            now: { self.now },
            isRoutineInNotificationScope: isRoutineInNotificationScope,
            onRoutineCompletionCommitted: onRoutineCompletionCommitted
        )
    }

    private func makeRoutine(
        title: String = "Read",
        weekdays: Set<Int> = [2],
        isPaused: Bool = false,
        isArchived: Bool = false
    ) -> RoutineSnapshot {
        RoutineSnapshot(
            id: UUID(),
            title: title,
            weekdays: weekdays,
            window: .morning,
            reminderHour: 9,
            reminderMinute: 0,
            isPaused: isPaused,
            isArchived: isArchived
        )
    }

    private func payload(routineID: UUID, day: LocalDay) -> [String: String] {
        [
            NotificationPayloadKey.routineID: routineID.uuidString,
            NotificationPayloadKey.localDay: String(
                format: "%04d-%02d-%02d",
                day.year,
                day.month,
                day.day
            )
        ]
    }
}

private enum NotificationActionTestError: Error {
    case failed
}

private actor NotificationActionHookGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var isOpen = false

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { pending in
            if isOpen {
                pending.resume()
            } else {
                continuation = pending
            }
        }
    }

    func open() {
        isOpen = true
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
private final class NotificationActionSchedulerSpy: NotificationScheduling {
    private(set) var scheduled: [LocalNotificationRequest] = []
    private(set) var replacements: [[LocalNotificationRequest]] = []

    func pendingRequests() async -> [LocalNotificationRequest] {
        scheduled
    }

    func replaceAppRequests(with requests: [LocalNotificationRequest]) async throws {
        replacements.append(requests)
    }

    func schedule(_ request: LocalNotificationRequest) async throws {
        scheduled.append(request)
    }
}
