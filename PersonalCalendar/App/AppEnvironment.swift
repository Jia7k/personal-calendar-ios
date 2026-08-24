@MainActor
struct AppEnvironment {
    let calendar: any CalendarServicing
    let reminders: any RemindersServicing
    let notifications: any NotificationAuthorizing
    let permissionCoordinator: PermissionCoordinator

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
