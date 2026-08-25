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
}

@MainActor
private final class FakeNotificationScheduler: NotificationScheduling {
    var pending: [LocalNotificationRequest] = []

    func pendingRequests() async -> [LocalNotificationRequest] { pending }

    func replaceAppRequests(with requests: [LocalNotificationRequest]) async throws {
        pending = requests
    }
}
