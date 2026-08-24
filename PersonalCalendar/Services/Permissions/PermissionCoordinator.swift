import Foundation
import Observation

@MainActor
protocol NotificationAuthorizing: AnyObject {
    var accessState: AccessState { get async }

    func requestAccess() async -> AccessState
}

@MainActor
@Observable
final class PermissionCoordinator {
    private(set) var calendarAccess: AccessState
    private(set) var remindersAccess: AccessState
    private(set) var notificationAccess: AccessState
    private(set) var isRefreshing = true
    private(set) var pendingSources: Set<String> = []
    private var sourceGenerations: [String: Int] = [:]
    private var refreshGeneration = 0
    private var activeRefreshGeneration: Int?

    func isPending(_ source: String) -> Bool { pendingSources.contains(source) }

    private let calendar: any CalendarServicing
    private let reminders: any RemindersServicing
    private let notifications: any NotificationAuthorizing

    init(
        calendar: any CalendarServicing,
        reminders: any RemindersServicing,
        notifications: any NotificationAuthorizing
    ) {
        self.calendar = calendar
        self.reminders = reminders
        self.notifications = notifications
        calendarAccess = calendar.accessState
        remindersAccess = reminders.accessState
        notificationAccess = .notDetermined
    }

    func refresh() async {
        let calendarGeneration = nextGeneration(for: "calendar")
        let remindersGeneration = nextGeneration(for: "reminders")
        let notificationsGeneration = nextGeneration(for: "notifications")
        refreshGeneration += 1
        let currentRefreshGeneration = refreshGeneration
        activeRefreshGeneration = currentRefreshGeneration
        isRefreshing = true
        let calendarState = calendar.accessState
        let reminderState = reminders.accessState
        let notificationState = await notifications.accessState
        defer {
            if activeRefreshGeneration == currentRefreshGeneration {
                activeRefreshGeneration = nil
                isRefreshing = false
            }
        }
        guard
            activeRefreshGeneration == currentRefreshGeneration,
            sourceGenerations["calendar"] == calendarGeneration,
            sourceGenerations["reminders"] == remindersGeneration,
            sourceGenerations["notifications"] == notificationsGeneration
        else { return }
        calendarAccess = calendarState
        remindersAccess = reminderState
        notificationAccess = notificationState
    }

    func requestCalendar() async {
        guard calendarAccess == .notDetermined, !pendingSources.contains("calendar") else { return }
        let generation = nextGeneration(for: "calendar")
        pendingSources.insert("calendar"); defer { pendingSources.remove("calendar") }
        let state = await calendar.requestFullAccess()
        guard sourceGenerations["calendar"] == generation else { return }
        calendarAccess = state
    }

    func requestReminders() async {
        guard remindersAccess == .notDetermined, !pendingSources.contains("reminders") else { return }
        let generation = nextGeneration(for: "reminders")
        pendingSources.insert("reminders"); defer { pendingSources.remove("reminders") }
        let state = await reminders.requestFullAccess()
        guard sourceGenerations["reminders"] == generation else { return }
        remindersAccess = state
    }

    func requestNotifications() async {
        guard notificationAccess == .notDetermined, !pendingSources.contains("notifications") else { return }
        let generation = nextGeneration(for: "notifications")
        pendingSources.insert("notifications"); defer { pendingSources.remove("notifications") }
        let state = await notifications.requestAccess()
        guard sourceGenerations["notifications"] == generation else { return }
        notificationAccess = state
    }

    private func nextGeneration(for source: String) -> Int {
        let next = sourceGenerations[source, default: 0] + 1
        sourceGenerations[source] = next
        return next
    }
}
