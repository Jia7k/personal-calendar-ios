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
    private var generation = 0

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
        generation += 1
        let current = generation
        let calendarState = calendar.accessState
        let reminderState = reminders.accessState
        let notificationState = await notifications.accessState
        guard current == generation else { return }
        calendarAccess = calendarState
        remindersAccess = reminderState
        notificationAccess = notificationState
        isRefreshing = false
    }

    func requestCalendar() async {
        guard calendarAccess == .notDetermined, !pendingSources.contains("calendar") else { return }
        pendingSources.insert("calendar"); defer { pendingSources.remove("calendar") }
        calendarAccess = await calendar.requestFullAccess()
    }

    func requestReminders() async {
        guard remindersAccess == .notDetermined, !pendingSources.contains("reminders") else { return }
        pendingSources.insert("reminders"); defer { pendingSources.remove("reminders") }
        remindersAccess = await reminders.requestFullAccess()
    }

    func requestNotifications() async {
        guard notificationAccess == .notDetermined, !pendingSources.contains("notifications") else { return }
        pendingSources.insert("notifications"); defer { pendingSources.remove("notifications") }
        notificationAccess = await notifications.requestAccess()
    }
}
