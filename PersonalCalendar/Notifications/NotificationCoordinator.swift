import Foundation
import Observation

@MainActor
@Observable
final class NotificationCoordinator {
    private let scheduler: any NotificationScheduling
    private let maximumRoutineRequests: Int
    private let horizonDays: Int
    private(set) var errorMessage: String?
    private(set) var deferredRoutineRequestCount = 0

    init(scheduler: any NotificationScheduling, maximumRoutineRequests: Int = 48, horizonDays: Int = 14) {
        self.scheduler = scheduler
        self.maximumRoutineRequests = maximumRoutineRequests
        self.horizonDays = horizonDays
    }

    func reschedule(
        summary: MorningSummaryInput?,
        routines: [RoutineSnapshot],
        completedDays: [UUID: Set<LocalDay>],
        now: Date,
        calendar: Calendar
    ) async {
        var requests: [LocalNotificationRequest] = []
        if let summary,
           summary.enabled,
           (0...23).contains(summary.hour),
           (0...59).contains(summary.minute),
           let fireDate = calendar.date(bySettingHour: summary.hour, minute: summary.minute, second: 0, of: summary.day.startDate(in: calendar)),
           fireDate > now {
            requests.append(.init(
                identifier: "morning-summary",
                title: "Your day",
                body: summaryBody(for: summary),
                fireDate: fireDate
            ))
        }

        var routineRequests: [LocalNotificationRequest] = []
        for offset in 0..<horizonDays {
            guard let date = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)) else { continue }
            let day = LocalDay(date: date, calendar: calendar)
            let weekday = calendar.component(.weekday, from: date)
            for routine in routines where !routine.isPaused && !routine.isArchived && routine.weekdays.contains(weekday) {
                guard let hour = routine.reminderHour,
                      let minute = routine.reminderMinute,
                      (0...23).contains(hour),
                      (0...59).contains(minute),
                      !completedDays[routine.id, default: []].contains(day),
                      let fireDate = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date),
                      fireDate > now
                else { continue }
                routineRequests.append(.init(
                    identifier: "routine|\(routine.id.uuidString)|\(day.year)-\(day.month)-\(day.day)",
                    title: routine.title,
                    body: "A gentle reminder for your routine.",
                    fireDate: fireDate
                ))
            }
        }

        let sortedRoutineRequests = routineRequests.sorted {
            $0.fireDate == $1.fireDate ? $0.identifier < $1.identifier : $0.fireDate < $1.fireDate
        }
        deferredRoutineRequestCount = max(0, sortedRoutineRequests.count - maximumRoutineRequests)
        requests.append(contentsOf: sortedRoutineRequests.prefix(maximumRoutineRequests))

        do {
            try await scheduler.replaceAppRequests(with: requests)
            errorMessage = nil
        } catch {
            errorMessage = "Notifications could not be updated. Open Settings and try again."
        }
    }

    private func summaryBody(for summary: MorningSummaryInput) -> String {
        let items = summary.agenda.allDay + summary.agenda.scheduled + summary.agenda.priority
        let eventCount = items.filter { $0.source == .event }.count
        let taskCount = items.filter { $0.source == .task }.count
        let routineCount = items.filter { $0.source == .routine }.count
        var body = "\(eventCount) events, \(taskCount) task\(taskCount == 1 ? "" : "s"), and \(routineCount) routine\(routineCount == 1 ? "" : "s") today."
        if summary.showsNextTitle,
           let next = summary.agenda.scheduled.first(where: { if case .timed = $0.placement { true } else { false } }) {
            body += " Next: \(next.title)."
        }
        return body
    }
}
