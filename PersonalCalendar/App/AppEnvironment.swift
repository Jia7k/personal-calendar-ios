import EventKit

@MainActor
struct AppEnvironment {
    let calendar: any CalendarServicing
    let reminders: any RemindersServicing
    let notifications: any NotificationAuthorizing
    let permissionCoordinator: PermissionCoordinator

    static let bootstrap = AppEnvironment()

    init() {
        let store = EKEventStore()
        self.init(
            calendar: EventKitCalendarService(store: store),
            reminders: EventKitRemindersService(store: store),
            notifications: SystemNotificationAuthorizer()
        )
    }

    init(
        calendar: any CalendarServicing,
        reminders: any RemindersServicing,
        notifications: any NotificationAuthorizing
    ) {
        self.calendar = calendar
        self.reminders = reminders
        self.notifications = notifications
        permissionCoordinator = PermissionCoordinator(
            calendar: calendar,
            reminders: reminders,
            notifications: notifications
        )
    }
}
