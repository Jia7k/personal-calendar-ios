import EventKit
import SwiftData

@MainActor
struct AppEnvironment {
    let calendar: any CalendarServicing
    let reminders: any RemindersServicing
    let routines: any RoutineRepository
    let categories: any CategoryRepository
    let notificationAuthorization: any NotificationAuthorizing
    let permissions: PermissionCoordinator
    let agendaComposer: AgendaComposer
    let settings: AppSettingsStore
    let reduceMotionOverride: Bool
    let quickEntryContext: @MainActor @Sendable () -> QuickEntryParseContext

    static func live(container: ModelContainer) -> AppEnvironment {
        let store = EKEventStore()
        let mutations = SystemEventKitMutationBacking(store: store)
        let calendar = EventKitCalendarService(store: store, mutations: mutations)
        let reminders = EventKitRemindersService(store: store, mutations: mutations)
        let notifications = SystemNotificationAuthorizer()
        let settings = AppSettingsStore()
        let categories = SwiftDataCategoryRepository(context: container.mainContext)
        try! categories.seedDefaultsIfNeeded(settings: settings)
        let permissions = PermissionCoordinator(
            calendar: calendar,
            reminders: reminders,
            notifications: notifications
        )
        return .init(
            calendar: calendar,
            reminders: reminders,
            routines: SwiftDataRoutineRepository(context: container.mainContext),
            categories: categories,
            notificationAuthorization: notifications,
            permissions: permissions,
            agendaComposer: AgendaComposer(),
            settings: settings,
            reduceMotionOverride: false,
            quickEntryContext: { currentQuickEntryContext() }
        )
    }

    static func demo(container: ModelContainer, arguments: [String]) -> AppEnvironment {
        let calendarAccess: AccessState = arguments.contains("-calendar-not-determined") ? .notDetermined : arguments.contains("-calendar-restricted") ? .restricted : arguments.contains("-calendar-denied") ? .denied : .granted
        let calendar = DemoCalendarService(
            access: calendarAccess,
            failFirstCreate: arguments.contains("-event-save-fails-once"),
            failFirstUpdate: arguments.contains("-event-update-fails-once"),
            failFirstDelete: arguments.contains("-event-delete-fails-once"),
            multipleSources: arguments.contains("-demo-multiple-sources"),
            includeReadOnlySource: arguments.contains("-demo-editor-read-only"),
            includeRecurringItems: arguments.contains("-demo-editor-recurring"),
            includeUnsupportedItems: arguments.contains("-demo-editor-unsupported")
        )
        let reminderAccess: AccessState = arguments.contains("-reminders-not-determined") ? .notDetermined : arguments.contains("-reminders-restricted") ? .restricted : arguments.contains("-reminders-denied") ? .denied : .granted
        let reminders = DemoRemindersService(
            access: reminderAccess,
            failFirstCreate: arguments.contains("-task-save-fails-once"),
            failFirstUpdate: arguments.contains("-task-update-fails-once"),
            failFirstDelete: arguments.contains("-task-delete-fails-once"),
            multipleSources: arguments.contains("-demo-multiple-sources"),
            includeReadOnlySource: arguments.contains("-demo-editor-read-only"),
            includeRecurringItems: arguments.contains("-demo-editor-recurring"),
            includeUnsupportedItems: arguments.contains("-demo-editor-unsupported")
        )
        let notificationAccess: AccessState = arguments.contains("-notifications-not-determined") ? .notDetermined : arguments.contains("-notifications-restricted") ? .restricted : arguments.contains("-notifications-denied") ? .denied : .granted
        let notifications = DemoNotificationAuthorizer(access: notificationAccess)
        let settings = AppSettingsStore(defaults: .ephemeral)
        settings.didCompleteOnboarding = !arguments.contains("-show-onboarding")
        let categories = SwiftDataCategoryRepository(context: container.mainContext)
        try! categories.seedDefaultsIfNeeded(settings: settings)
        let quickEntryContext: @MainActor @Sendable () -> QuickEntryParseContext
        if arguments.contains("-quick-entry-fixed-context") {
            quickEntryContext = { fixedQuickEntryContext() }
        } else {
            quickEntryContext = { currentQuickEntryContext() }
        }
        let permissions = PermissionCoordinator(
            calendar: calendar,
            reminders: reminders,
            notifications: notifications
        )
        return .init(
            calendar: calendar,
            reminders: reminders,
            routines: DemoRoutineRepository(failFirstDelete: arguments.contains("-routine-delete-fails-once"), failFirstCreate: arguments.contains("-routine-create-fails-once"), failFirstUpdate: arguments.contains("-routine-update-fails-once"), longTitle: arguments.contains("-routine-long-title")),
            categories: categories,
            notificationAuthorization: notifications,
            permissions: permissions,
            agendaComposer: AgendaComposer(),
            settings: settings,
            reduceMotionOverride: arguments.contains("-reduce-motion"),
            quickEntryContext: quickEntryContext
        )
    }

    private static func currentQuickEntryContext() -> QuickEntryParseContext {
        let timeZone = TimeZone.current
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        let locale = Locale.current
        return .init(now: Date(), calendar: calendar, locale: locale, timeZone: timeZone)
    }

    private static func fixedQuickEntryContext() -> QuickEntryParseContext {
        let timeZone = TimeZone(identifier: "Asia/Singapore")!
        let locale = Locale(identifier: "en_SG")
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        calendar.timeZone = timeZone
        let now = calendar.date(
            from: DateComponents(
                timeZone: timeZone,
                year: 2026,
                month: 8,
                day: 25,
                hour: 12,
                minute: 0
            )
        )!
        return .init(now: now, calendar: calendar, locale: locale, timeZone: timeZone)
    }
}
