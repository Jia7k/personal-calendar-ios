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
        calendarAccess = calendar.accessState
        remindersAccess = reminders.accessState
        notificationAccess = await notifications.accessState
    }

    func requestCalendar() async {
        calendarAccess = await calendar.requestFullAccess()
    }

    func requestReminders() async {
        remindersAccess = await reminders.requestFullAccess()
    }

    func requestNotifications() async {
        notificationAccess = await notifications.requestAccess()
    }
}
