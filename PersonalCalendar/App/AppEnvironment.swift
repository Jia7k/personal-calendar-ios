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
    let reduceMotionOverride: Bool

    static func live(container: ModelContainer) -> AppEnvironment {
        let store = EKEventStore()
        let mutations = SystemEventKitMutationBacking(store: store)
        let calendar = EventKitCalendarService(store: store, mutations: mutations)
        let reminders = EventKitRemindersService(store: store, mutations: mutations)
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
            settings: AppSettingsStore(),
            reduceMotionOverride: false
        )
    }

    static func demo(container: ModelContainer, arguments: [String]) -> AppEnvironment {
        let calendarAccess: AccessState = arguments.contains("-calendar-not-determined") ? .notDetermined : arguments.contains("-calendar-restricted") ? .restricted : arguments.contains("-calendar-denied") ? .denied : .granted
        let calendar = DemoCalendarService(
            access: calendarAccess,
            failFirstCreate: arguments.contains("-event-save-fails-once"),
            failFirstUpdate: arguments.contains("-event-update-fails-once"),
            failFirstDelete: arguments.contains("-event-delete-fails-once"),
            multipleSources: arguments.contains("-demo-multiple-sources")
        )
        let reminderAccess: AccessState = arguments.contains("-reminders-not-determined") ? .notDetermined : arguments.contains("-reminders-restricted") ? .restricted : arguments.contains("-reminders-denied") ? .denied : .granted
        let reminders = DemoRemindersService(
            access: reminderAccess,
            failFirstCreate: arguments.contains("-task-save-fails-once"),
            failFirstUpdate: arguments.contains("-task-update-fails-once"),
            failFirstDelete: arguments.contains("-task-delete-fails-once"),
            multipleSources: arguments.contains("-demo-multiple-sources")
        )
        let notificationAccess: AccessState = arguments.contains("-notifications-not-determined") ? .notDetermined : arguments.contains("-notifications-restricted") ? .restricted : arguments.contains("-notifications-denied") ? .denied : .granted
        let notifications = DemoNotificationAuthorizer(access: notificationAccess)
        let permissions = PermissionCoordinator(
            calendar: calendar,
            reminders: reminders,
            notifications: notifications
        )
        return .init(
            calendar: calendar,
            reminders: reminders,
            routines: DemoRoutineRepository(failFirstDelete: arguments.contains("-routine-delete-fails-once"), failFirstCreate: arguments.contains("-routine-create-fails-once"), failFirstUpdate: arguments.contains("-routine-update-fails-once"), longTitle: arguments.contains("-routine-long-title")),
            notificationAuthorization: notifications,
            permissions: permissions,
            agendaComposer: AgendaComposer(),
            settings: { let settings = AppSettingsStore(defaults: .ephemeral); settings.didCompleteOnboarding = !arguments.contains("-show-onboarding"); return settings }(),
            reduceMotionOverride: arguments.contains("-reduce-motion")
        )
    }
}
