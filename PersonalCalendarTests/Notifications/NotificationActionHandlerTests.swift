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
        let subject = makeSubject(routines: routines, scheduler: scheduler)
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
    }

    func testStaleRoutineDayDoesNotCompleteOrSnooze() async {
        let routine = makeRoutine()
        let routines = FakeRoutineRepository(routines: [routine])
        let scheduler = NotificationActionSchedulerSpy()
        let subject = makeSubject(routines: routines, scheduler: scheduler)
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
    }

    func testSnoozeSchedulesOneActionableRequestFifteenMinutesAfterResponseWithoutReplacingPendingRequests() async {
        let day = LocalDay(date: now, calendar: calendar)
        let routine = makeRoutine(title: "Morning review")
        let routines = FakeRoutineRepository(routines: [routine])
        let scheduler = NotificationActionSchedulerSpy()
        let subject = makeSubject(routines: routines, scheduler: scheduler)
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
            let subject = makeSubject(routines: routines, scheduler: scheduler)
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
        }
    }

    func testRoutineRemovedFromEveryProfileRejectsCompletionAndSnooze() async {
        let day = LocalDay(date: now, calendar: calendar)
        let routine = makeRoutine()
        let routines = FakeRoutineRepository(routines: [routine])
        let scheduler = NotificationActionSchedulerSpy()
        let subject = makeSubject(
            routines: routines,
            scheduler: scheduler,
            isRoutineInNotificationScope: { _ in false }
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
    }

    private func makeSubject(
        routines: FakeRoutineRepository,
        scheduler: NotificationActionSchedulerSpy,
        isRoutineInNotificationScope: @escaping @MainActor (UUID) -> Bool = { _ in true }
    ) -> AppNotificationActionHandler {
        AppNotificationActionHandler(
            routines: routines,
            scheduler: scheduler,
            calendar: calendar,
            now: { self.now },
            isRoutineInNotificationScope: isRoutineInNotificationScope
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
