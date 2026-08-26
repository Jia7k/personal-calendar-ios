import XCTest
@testable import PersonalCalendar

@MainActor
final class NotificationCoordinatorTests: XCTestCase {
    func testSchedulesMorningSummaryAndBoundsRoutineRequests() async {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Singapore")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 24, hour: 7, minute: 0))!
        let day = LocalDay(date: now, calendar: calendar)
        let scheduler = FakeNotificationScheduler()
        let subject = NotificationCoordinator(scheduler: scheduler, maximumRoutineRequests: 48, horizonDays: 14)
        let agenda = DayAgenda(
            allDay: [AgendaItem(id: "event-1", title: "All-day event", source: .event, placement: .allDay, sortDate: nil, priority: 0, isCompleted: false, allowsModification: true)],
            scheduled: [
                AgendaItem(id: "event-2", title: "Planning", source: .event, placement: .timed(now), sortDate: now, priority: 0, isCompleted: false, allowsModification: true),
                AgendaItem(id: "routine-1", title: "Read", source: .routine, placement: .window(.morning), sortDate: now, priority: 0, isCompleted: false, allowsModification: true)
            ],
            priority: [AgendaItem(id: "task-1", title: "Email", source: .task, placement: .unscheduled, sortDate: nil, priority: 0, isCompleted: false, allowsModification: true)]
        )
        let routines = (0..<10).map { index in
            RoutineSnapshot(id: UUID(), title: "Routine \(index)", weekdays: [1, 2, 3, 4, 5, 6, 7], window: .morning, reminderHour: 9, reminderMinute: index, isPaused: false, isArchived: false)
        }

        await subject.reschedule(
            summary: .init(enabled: true, hour: 8, minute: 0, day: day, agenda: agenda, showsNextTitle: false),
            routines: routines,
            completedDays: [:],
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(scheduler.pending.first { $0.identifier == "morning-summary" }?.body, "2 events, 1 task, and 1 routine today.")
        let routineRequests = scheduler.pending.filter { $0.identifier.hasPrefix("routine|") }
        XCTAssertEqual(routineRequests.count, 48)
        XCTAssertTrue(routineRequests.allSatisfy { $0.fireDate < calendar.date(byAdding: .day, value: 14, to: calendar.startOfDay(for: now))! })
        XCTAssertEqual(subject.deferredRoutineRequestCount, 92)
    }

    func testMorningSummaryCarriesTodayRoutePayloadAndCategory() async throws {
        let calendar = singaporeCalendar()
        let now = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 24,
            hour: 7
        )))
        let scheduler = FakeNotificationScheduler()
        let subject = NotificationCoordinator(scheduler: scheduler)

        await subject.reschedule(
            summary: .init(
                enabled: true,
                hour: 8,
                minute: 0,
                day: .init(year: 2026, month: 8, day: 24),
                agenda: .init(allDay: [], scheduled: [], priority: []),
                showsNextTitle: false
            ),
            routines: [],
            completedDays: [:],
            now: now,
            calendar: calendar
        )

        let request = try XCTUnwrap(scheduler.pending.first { $0.identifier == "morning-summary" })
        XCTAssertEqual(request.categoryIdentifier, "morning-summary")
        XCTAssertEqual(request.userInfo, [
            "route": "personalcalendar://v1/today"
        ])
    }

    func testRoutineRequestCarriesRouteAndExactScheduledLocalDayPayload() async throws {
        let calendar = singaporeCalendar()
        let now = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 24,
            hour: 7
        )))
        let routineID = try XCTUnwrap(UUID(uuidString: "ABCDEFAB-CDEF-4ABC-8DEF-ABCDEFABCDEF"))
        let profileID = try XCTUnwrap(UUID(uuidString: "C0A10000-0000-4000-8000-000000000002"))
        let scheduler = FakeNotificationScheduler()
        let subject = NotificationCoordinator(scheduler: scheduler, horizonDays: 1)
        let routine = RoutineSnapshot(
            id: routineID,
            title: "Read",
            weekdays: [2],
            window: .morning,
            reminderHour: 9,
            reminderMinute: 30,
            isPaused: false,
            isArchived: false
        )

        await subject.reschedule(
            summary: nil,
            routines: [routine],
            completedDays: [:],
            routineProfiles: [routineID: .saved(profileID)],
            now: now,
            calendar: calendar
        )

        let request = try XCTUnwrap(scheduler.pending.first { $0.identifier.hasPrefix("routine|") })
        XCTAssertEqual(request.categoryIdentifier, "routine-reminder")
        XCTAssertEqual(request.userInfo["localDay"], "2026-08-24")
        XCTAssertEqual(request.userInfo["routineID"], routineID.uuidString)
        let routeString = try XCTUnwrap(request.userInfo["route"])
        let routeURL = try XCTUnwrap(URL(string: routeString))
        XCTAssertEqual(
            try AppRouteCodec().route(from: routeURL),
            .routine(id: routineID, profile: .saved(profileID))
        )
    }

    func testNormalReplacementPreservesPendingSnoozeRequest() async throws {
        let calendar = singaporeCalendar()
        let now = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 24,
            hour: 7
        )))
        let routineID = try XCTUnwrap(UUID(
            uuidString: "ABCDEFAB-CDEF-4ABC-8DEF-ABCDEFABCDEF"
        ))
        let routine = RoutineSnapshot(
            id: routineID,
            title: "Read",
            weekdays: [2],
            window: .morning,
            reminderHour: 9,
            reminderMinute: 0,
            isPaused: false,
            isArchived: false
        )
        let snooze = LocalNotificationRequest(
            identifier: "snooze|\(routineID.uuidString)|2026-08-24",
            title: "Read",
            body: "A gentle reminder for your routine.",
            fireDate: try XCTUnwrap(calendar.date(byAdding: .minute, value: 15, to: now))
        )
        let scheduler = FakeNotificationScheduler()
        scheduler.pending = [snooze]
        let subject = NotificationCoordinator(scheduler: scheduler)

        await subject.reschedule(
            summary: nil,
            routines: [routine],
            completedDays: [:],
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(
            scheduler.pending.filter { $0.identifier.hasPrefix("snooze|") },
            [snooze]
        )
        XCTAssertEqual(
            scheduler.pending.filter { $0.identifier.hasPrefix("routine|") }.count,
            2
        )
    }

    func testRescheduleDropsSnoozeWhenRoutineIsNoLongerInNotificationScope() async throws {
        let calendar = singaporeCalendar()
        let now = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 24,
            hour: 7
        )))
        let scheduler = FakeNotificationScheduler()
        scheduler.pending = [LocalNotificationRequest(
            identifier: "snooze|ABCDEFAB-CDEF-4ABC-8DEF-ABCDEFABCDEF|2026-08-24",
            title: "Read",
            body: "A gentle reminder for your routine.",
            fireDate: try XCTUnwrap(calendar.date(byAdding: .minute, value: 15, to: now))
        )]
        let subject = NotificationCoordinator(scheduler: scheduler)

        await subject.reschedule(
            summary: nil,
            routines: [],
            completedDays: [:],
            now: now,
            calendar: calendar
        )

        XCTAssertTrue(scheduler.pending.isEmpty)
    }

    func testNewerClearWinsWhileOlderRescheduleIsSuspendedReadingPendingRequests() async {
        let calendar = singaporeCalendar()
        let now = calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 24,
            hour: 7
        ))!
        let scheduler = FakeNotificationScheduler()
        scheduler.suspendsNextPendingRead = true
        let subject = NotificationCoordinator(scheduler: scheduler)

        let staleReschedule = Task { @MainActor in
            await subject.reschedule(
                summary: .init(
                    enabled: true,
                    hour: 8,
                    minute: 0,
                    day: .init(year: 2026, month: 8, day: 24),
                    agenda: .init(allDay: [], scheduled: [], priority: []),
                    showsNextTitle: false
                ),
                routines: [],
                completedDays: [:],
                now: now,
                calendar: calendar
            )
        }
        await scheduler.waitUntilPendingReadSuspends()

        await subject.clear()
        scheduler.resumePendingRead()
        await staleReschedule.value

        XCTAssertTrue(scheduler.pending.isEmpty)
        XCTAssertEqual(scheduler.replacementCount, 1)
    }

    func testSnoozeScheduledDuringAtomicRescheduleIsPreserved() async throws {
        let calendar = singaporeCalendar()
        let now = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 24,
            hour: 7
        )))
        let routineID = try XCTUnwrap(UUID(
            uuidString: "ABCDEFAB-CDEF-4ABC-8DEF-ABCDEFABCDEF"
        ))
        let routine = RoutineSnapshot(
            id: routineID,
            title: "Read",
            weekdays: [2],
            window: .morning,
            reminderHour: 9,
            reminderMinute: 0,
            isPaused: false,
            isArchived: false
        )
        let snooze = LocalNotificationRequest(
            identifier: "snooze|\(routineID.uuidString)|2026-08-24",
            title: routine.title,
            body: "A gentle reminder for your routine.",
            fireDate: try XCTUnwrap(calendar.date(
                byAdding: .minute,
                value: 15,
                to: now
            ))
        )
        let scheduler = FakeNotificationScheduler()
        scheduler.suspendsNextPendingRead = true
        let subject = NotificationCoordinator(scheduler: scheduler)
        let reschedule = Task { @MainActor in
            await subject.reschedule(
                summary: nil,
                routines: [routine],
                completedDays: [:],
                now: now,
                calendar: calendar
            )
        }
        await scheduler.waitUntilPendingReadSuspends()

        try await scheduler.schedule(snooze)
        scheduler.resumePendingRead()
        await reschedule.value

        XCTAssertEqual(
            scheduler.pending.filter { $0.identifier.hasPrefix("snooze|") },
            [snooze]
        )
    }

    func testClearRemovesPendingSnoozeRequestForPermissionLoss() async throws {
        let calendar = singaporeCalendar()
        let now = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 24,
            hour: 7
        )))
        let snooze = LocalNotificationRequest(
            identifier: "snooze|ABCDEFAB-CDEF-4ABC-8DEF-ABCDEFABCDEF|2026-08-24|1",
            title: "Read",
            body: "A gentle reminder for your routine.",
            fireDate: try XCTUnwrap(calendar.date(byAdding: .minute, value: 15, to: now))
        )
        let scheduler = FakeNotificationScheduler()
        scheduler.pending = [snooze]
        let subject = NotificationCoordinator(scheduler: scheduler)

        await subject.clear()

        XCTAssertTrue(scheduler.pending.isEmpty)
    }

    func testRescheduleIncludesPreparedClassAlertsWithoutReplacingTheirRoutePayload() async throws {
        let calendar = singaporeCalendar()
        let now = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 24,
            hour: 7
        )))
        let classAlert = LocalNotificationRequest(
            identifier: "class|school|entry",
            title: "INF 2003",
            body: "Starts in 10 minutes · E2-08-01",
            fireDate: try XCTUnwrap(calendar.date(byAdding: .hour, value: 2, to: now)),
            categoryIdentifier: NotificationCategoryIdentifier.classAlert,
            userInfo: [
                NotificationPayloadKey.route: "personalcalendar://v1/calendar?profile=saved%3Aschool&entry=entry"
            ]
        )
        let scheduler = FakeNotificationScheduler()
        let subject = NotificationCoordinator(scheduler: scheduler)

        await subject.reschedule(
            summary: nil,
            routines: [],
            completedDays: [:],
            classAlerts: [classAlert],
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(scheduler.pending, [classAlert])
    }

    func testRescheduleKeepsAllAppOwnedRequestsWithinTheSystemBudget() async throws {
        let calendar = singaporeCalendar()
        let now = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 24,
            hour: 7
        )))
        let classAlerts = (0..<12).map { index in
            LocalNotificationRequest(
                identifier: "class|school|\(index)",
                title: "Class \(index)",
                body: "Starts soon",
                fireDate: now.addingTimeInterval(Double(index + 1) * 120),
                categoryIdentifier: NotificationCategoryIdentifier.classAlert
            )
        }
        let routines = (0..<10).map { index in
            RoutineSnapshot(
                id: UUID(),
                title: "Routine \(index)",
                weekdays: [1, 2, 3, 4, 5, 6, 7],
                window: .morning,
                reminderHour: 9,
                reminderMinute: index,
                isPaused: false,
                isArchived: false
            )
        }
        let scheduler = FakeNotificationScheduler()
        scheduler.pending = routines.prefix(4).enumerated().map { index, routine in
            LocalNotificationRequest(
                identifier: "snooze|\(routine.id.uuidString)|2026-08-24",
                title: routine.title,
                body: "Reminder",
                fireDate: now.addingTimeInterval(Double(index + 1) * 60)
            )
        }
        let subject = NotificationCoordinator(scheduler: scheduler)

        await subject.reschedule(
            summary: .init(
                enabled: true,
                hour: 8,
                minute: 0,
                day: .init(year: 2026, month: 8, day: 24),
                agenda: .init(allDay: [], scheduled: [], priority: []),
                showsNextTitle: false
            ),
            routines: routines,
            completedDays: [:],
            classAlerts: classAlerts,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(scheduler.pending.count, 64)
        XCTAssertEqual(
            scheduler.pending.filter { $0.identifier.hasPrefix("routine|") }.count,
            47
        )
        XCTAssertEqual(subject.deferredRoutineRequestCount, 93)
    }

    private func singaporeCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Singapore")!
        return calendar
    }
}

@MainActor
private final class FakeNotificationScheduler: NotificationScheduling {
    var pending: [LocalNotificationRequest] = []
    var suspendsNextPendingRead = false
    private var pendingReadContinuation: CheckedContinuation<Void, Never>?
    private(set) var replacementCount = 0

    func pendingRequests() async -> [LocalNotificationRequest] {
        if suspendsNextPendingRead {
            suspendsNextPendingRead = false
            await withCheckedContinuation { continuation in
                pendingReadContinuation = continuation
            }
        }
        return pending
    }

    func replaceAppRequests(with requests: [LocalNotificationRequest]) async throws {
        replacementCount += 1
        pending = requests
    }

    func schedule(_ request: LocalNotificationRequest) async throws {
        pending.append(request)
    }

    func waitUntilPendingReadSuspends() async {
        while pendingReadContinuation == nil {
            await Task.yield()
        }
    }

    func resumePendingRead() {
        pendingReadContinuation?.resume()
        pendingReadContinuation = nil
    }
}
