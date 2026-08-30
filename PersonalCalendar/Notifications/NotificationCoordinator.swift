import Foundation
import Observation

private enum NotificationCoordinatorOperationError: Error {
    case superseded
}

@MainActor
@Observable
final class NotificationCoordinator {
    private static let maximumSystemRequests = 64
    private let scheduler: any NotificationScheduling
    private let maximumRoutineRequests: Int
    private let horizonDays: Int
    private var operationGeneration = 0
    private(set) var errorMessage: String?
    private(set) var deferredRoutineRequestCount = 0

    init(scheduler: any NotificationScheduling, maximumRoutineRequests: Int = 48, horizonDays: Int = 14) {
        self.scheduler = scheduler
        self.maximumRoutineRequests = maximumRoutineRequests
        self.horizonDays = horizonDays
    }

    @discardableResult
    func reschedule(
        summary: MorningSummaryInput?,
        routines: [RoutineSnapshot],
        completedDays: [UUID: Set<LocalDay>],
        routineProfiles: [UUID: ProfileIdentity] = [:],
        classAlerts: [LocalNotificationRequest] = [],
        now: Date,
        calendar: Calendar
    ) async -> Bool {
        operationGeneration &+= 1
        let generation = operationGeneration
        let sortedClassAlerts = classAlerts.sorted {
            $0.fireDate == $1.fireDate
                ? $0.identifier < $1.identifier
                : $0.fireDate < $1.fireDate
        }
        let summaryRequest: LocalNotificationRequest?
        if let summary,
           summary.enabled,
           (0...23).contains(summary.hour),
           (0...59).contains(summary.minute),
           let fireDate = calendar.date(bySettingHour: summary.hour, minute: summary.minute, second: 0, of: summary.day.startDate(in: calendar)),
           fireDate > now {
            summaryRequest = .init(
                identifier: "morning-summary",
                title: "Your day",
                body: summaryBody(for: summary),
                fireDate: fireDate,
                categoryIdentifier: NotificationCategoryIdentifier.morningSummary,
                userInfo: routePayload(for: .today)
            )
        } else {
            summaryRequest = nil
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
                    fireDate: fireDate,
                    categoryIdentifier: NotificationCategoryIdentifier.routineReminder,
                    userInfo: routinePayload(
                        routineID: routine.id,
                        day: day,
                        profile: routineProfiles[routine.id] ?? .everything
                    )
                ))
            }
        }

        let sortedRoutineRequests = routineRequests.sorted {
            $0.fireDate == $1.fireDate ? $0.identifier < $1.identifier : $0.fireDate < $1.fireDate
        }
        guard generation == operationGeneration else { return false }
        do {
            try await scheduler.mutateAppRequests { [self] pendingRequests in
                guard generation == operationGeneration else {
                    throw NotificationCoordinatorOperationError.superseded
                }
                var requests = Array(actionableSnoozes(
                    from: pendingRequests,
                    routines: routines,
                    completedDays: completedDays,
                    now: now,
                    calendar: calendar
                )
                    .sorted {
                        $0.fireDate == $1.fireDate
                            ? $0.identifier < $1.identifier
                            : $0.fireDate < $1.fireDate
                    }
                    .prefix(Self.maximumSystemRequests))
                requests.append(contentsOf: sortedClassAlerts.prefix(
                    max(0, Self.maximumSystemRequests - requests.count)
                ))
                if let summaryRequest,
                   requests.count < Self.maximumSystemRequests {
                    requests.append(summaryRequest)
                }
                let routineRequestLimit = min(
                    maximumRoutineRequests,
                    max(0, Self.maximumSystemRequests - requests.count)
                )
                deferredRoutineRequestCount = max(
                    0,
                    sortedRoutineRequests.count - routineRequestLimit
                )
                requests.append(contentsOf: sortedRoutineRequests.prefix(
                    routineRequestLimit
                ))
                return requests
            }
            guard generation == operationGeneration else { return false }
            errorMessage = nil
            return true
        } catch {
            guard generation == operationGeneration else { return false }
            errorMessage = "Notifications could not be updated. Open Settings and try again."
            return false
        }
    }

    @discardableResult
    func clear() async -> Bool {
        await removeAllRequests()
    }

    @discardableResult
    func removeRequestsForStaleInput() async -> Bool {
        await removeAllRequests()
    }

    private func removeAllRequests() async -> Bool {
        operationGeneration &+= 1
        let generation = operationGeneration
        deferredRoutineRequestCount = 0
        do {
            try await scheduler.replaceAppRequests(with: [])
            guard generation == operationGeneration else { return false }
            errorMessage = nil
            return true
        } catch {
            guard generation == operationGeneration else { return false }
            errorMessage = "Notifications could not be updated. Open Settings and try again."
            return false
        }
    }

    private func actionableSnoozes(
        from pending: [LocalNotificationRequest],
        routines: [RoutineSnapshot],
        completedDays: [UUID: Set<LocalDay>],
        now: Date,
        calendar: Calendar
    ) -> [LocalNotificationRequest] {
        let routinesByID = Dictionary(uniqueKeysWithValues: routines.map {
            ($0.id, $0)
        })
        let today = LocalDay(date: now, calendar: calendar)
        return pending.filter { request in
            guard request.identifier.hasPrefix("snooze|"),
                  request.fireDate > now,
                  let (routineID, day) = snoozeIdentity(
                      from: request.identifier,
                      calendar: calendar
                  ),
                  day == today,
                  let routine = routinesByID[routineID],
                  !routine.isPaused,
                  !routine.isArchived,
                  routine.reminderHour != nil,
                  routine.reminderMinute != nil,
                  routine.weekdays.contains(
                      calendar.component(
                          .weekday,
                          from: day.startDate(in: calendar)
                      )
                  ),
                  !completedDays[routineID, default: []].contains(day)
            else { return false }
            return true
        }
    }

    private func snoozeIdentity(
        from identifier: String,
        calendar: Calendar
    ) -> (UUID, LocalDay)? {
        let components = identifier.split(
            separator: "|",
            omittingEmptySubsequences: false
        )
        guard components.count >= 3,
              components[0] == "snooze",
              let routineID = UUID(uuidString: String(components[1])),
              let day = localDay(
                  from: String(components[2]),
                  calendar: calendar
              ) else { return nil }
        return (routineID, day)
    }

    private func localDay(from value: String, calendar: Calendar) -> LocalDay? {
        let pieces = value.split(separator: "-", omittingEmptySubsequences: false)
        guard pieces.count == 3,
              pieces[0].count == 4,
              pieces[1].count == 2,
              pieces[2].count == 2,
              let year = Int(pieces[0]),
              let month = Int(pieces[1]),
              let day = Int(pieces[2]) else { return nil }
        let candidate = LocalDay(year: year, month: month, day: day)
        let date = candidate.startDate(in: calendar)
        return LocalDay(date: date, calendar: calendar) == candidate
            ? candidate
            : nil
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

    private func routinePayload(
        routineID: UUID,
        day: LocalDay,
        profile: ProfileIdentity
    ) -> [String: String] {
        var payload = routePayload(for: .routine(
            id: routineID,
            profile: profile
        ))
        payload[NotificationPayloadKey.routineID] = routineID.uuidString
        payload[NotificationPayloadKey.localDay] = String(
            format: "%04d-%02d-%02d",
            day.year,
            day.month,
            day.day
        )
        return payload
    }

    private func routePayload(for route: AppRoute) -> [String: String] {
        guard let url = try? AppRouteCodec().url(for: route) else { return [:] }
        return [NotificationPayloadKey.route: url.absoluteString]
    }
}
