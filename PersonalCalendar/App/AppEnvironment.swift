import EventKit
import SwiftData

@MainActor
struct AppEnvironment {
    let calendar: any CalendarServicing
    let reminders: any RemindersServicing
    let routines: any RoutineRepository
    let notificationAuthorization: any NotificationAuthorizing
    let permissions: PermissionCoordinator
    let agendaComposer: AgendaComposer
    let settings: AppSettingsStore

    static func live(container: ModelContainer) -> AppEnvironment {
        let store = EKEventStore()
        let calendar = EventKitCalendarService(store: store)
        let reminders = EventKitRemindersService(store: store)
        let notifications = SystemNotificationAuthorizer()
        let permissions = PermissionCoordinator(
            calendar: calendar,
            reminders: reminders,
            notifications: notifications
        )
        return .init(
            calendar: calendar,
            reminders: reminders,
            routines: SwiftDataRoutineRepository(context: container.mainContext),
            notificationAuthorization: notifications,
            permissions: permissions,
            agendaComposer: AgendaComposer(),
            settings: AppSettingsStore()
        )
    }

    static func demo(container: ModelContainer, arguments: [String]) -> AppEnvironment {
        let calendarAccess: AccessState = arguments.contains("-calendar-denied") ? .denied : .granted
        let calendar = DemoCalendarService(access: calendarAccess, failFirstCreate: arguments.contains("-event-save-fails-once"))
        let reminders = DemoRemindersService(access: .granted, failFirstCreate: arguments.contains("-task-save-fails-once"))
        let notifications = DemoNotificationAuthorizer(access: .granted)
        let permissions = PermissionCoordinator(
            calendar: calendar,
            reminders: reminders,
            notifications: notifications
        )
        return .init(
            calendar: calendar,
            reminders: reminders,
            routines: DemoRoutineRepository(),
            notificationAuthorization: notifications,
            permissions: permissions,
            agendaComposer: AgendaComposer(),
            settings: AppSettingsStore(defaults: .ephemeral)
        )
    }
}
