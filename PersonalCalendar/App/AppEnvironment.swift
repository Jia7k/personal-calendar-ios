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
    let backup: BackupService
    let notificationCoordinator: NotificationCoordinator
    let rescheduleNotifications: @MainActor @Sendable () async -> Void
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
        let routines = SwiftDataRoutineRepository(context: container.mainContext)
        let notificationCoordinator = NotificationCoordinator(scheduler: SystemNotificationScheduler())
        let backup = BackupService(context: container.mainContext, settings: settings)
        try! categories.seedDefaultsIfNeeded(settings: settings)
        let permissions = PermissionCoordinator(
            calendar: calendar,
            reminders: reminders,
            notifications: notifications
        )
        return .init(
            calendar: calendar,
            reminders: reminders,
            routines: routines,
            categories: categories,
            notificationAuthorization: notifications,
            permissions: permissions,
            agendaComposer: AgendaComposer(categories: categories),
            settings: settings,
            backup: backup,
            notificationCoordinator: notificationCoordinator,
            rescheduleNotifications: makeNotificationRescheduler(calendar: calendar, reminders: reminders, routines: routines, composer: AgendaComposer(categories: categories), settings: settings, authorization: notifications, coordinator: notificationCoordinator),
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
        let routines = DemoRoutineRepository(failFirstDelete: arguments.contains("-routine-delete-fails-once"), failFirstCreate: arguments.contains("-routine-create-fails-once"), failFirstUpdate: arguments.contains("-routine-update-fails-once"), longTitle: arguments.contains("-routine-long-title"))
        let notificationCoordinator = NotificationCoordinator(scheduler: SystemNotificationScheduler())
        let backup = BackupService(context: container.mainContext, settings: settings)
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
            routines: routines,
            categories: categories,
            notificationAuthorization: notifications,
            permissions: permissions,
            agendaComposer: AgendaComposer(categories: categories),
            settings: settings,
            backup: backup,
            notificationCoordinator: notificationCoordinator,
            rescheduleNotifications: makeNotificationRescheduler(calendar: calendar, reminders: reminders, routines: routines, composer: AgendaComposer(categories: categories), settings: settings, authorization: notifications, coordinator: notificationCoordinator),
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

    private static func makeNotificationRescheduler(
        calendar: any CalendarServicing,
        reminders: any RemindersServicing,
        routines: any RoutineRepository,
        composer: AgendaComposer,
        settings: AppSettingsStore,
        authorization: any NotificationAuthorizing,
        coordinator: NotificationCoordinator
    ) -> @MainActor @Sendable () async -> Void {
        let generationState = NotificationRescheduleGeneration()
        return {
            let generation = generationState.begin()
            guard await authorization.accessState == .granted else {
                guard generationState.isLatest(generation) else { return }
                await coordinator.reschedule(summary: nil, routines: [], completedDays: [:], now: .now, calendar: .current)
                return
            }

            var localCalendar = Calendar.current
            localCalendar.timeZone = .current
            let now = Date()
            let today = LocalDay(date: now, calendar: localCalendar)
            let todaySummaryTime = localCalendar.date(
                bySettingHour: settings.morningSummaryHour,
                minute: settings.morningSummaryMinute,
                second: 0,
                of: today.startDate(in: localCalendar)
            )
            let summaryDay: LocalDay
            if let todaySummaryTime, todaySummaryTime > now {
                summaryDay = today
            } else {
                summaryDay = LocalDay(date: localCalendar.date(byAdding: .day, value: 1, to: today.startDate(in: localCalendar))!, calendar: localCalendar)
            }

            let routineSnapshots = (try? routines.list(includeArchived: false)) ?? []
            var completedDays: [UUID: Set<LocalDay>] = [:]
            for routine in routineSnapshots {
                completedDays[routine.id] = (try? routines.completedDays(routineID: routine.id)) ?? []
            }

            let start = summaryDay.startDate(in: localCalendar)
            let interval = DateInterval(start: start, end: localCalendar.date(byAdding: .day, value: 1, to: start)!)
            let events: [CalendarEventSnapshot]
            if calendar.accessState == .granted {
                let availableIDs = Set(calendar.calendars().map(\.id))
                let selectedIDs = availableIDs.isEmpty ? settings.selectedCalendarIDs : settings.visibleCalendarIDs(availableIDs: availableIDs)
                events = settings.calendarSelectionIsExplicit && selectedIDs.isEmpty ? [] : (try? calendar.fetchEvents(in: interval, calendarIDs: selectedIDs)) ?? []
            } else {
                events = []
            }
            let taskSnapshots: [ReminderSnapshot]
            if reminders.accessState == .granted {
                let availableIDs = Set(reminders.lists().map(\.id))
                let selectedIDs = availableIDs.isEmpty ? settings.selectedReminderListIDs : settings.visibleReminderListIDs(availableIDs: availableIDs)
                taskSnapshots = settings.reminderSelectionIsExplicit && selectedIDs.isEmpty ? [] : (try? await reminders.fetchReminders(listIDs: selectedIDs)) ?? []
            } else {
                taskSnapshots = []
            }
            let completedRoutineIDs = Set(routineSnapshots.filter { completedDays[$0.id]?.contains(summaryDay) == true }.map(\.id))
            let agenda = composer.compose(day: summaryDay, events: events, reminders: taskSnapshots, routines: routineSnapshots, completedRoutineIDs: completedRoutineIDs, includeOverdueTasks: false, calendar: localCalendar)
            guard generationState.isLatest(generation) else { return }
            await coordinator.reschedule(
                summary: .init(enabled: settings.morningSummaryEnabled, hour: settings.morningSummaryHour, minute: settings.morningSummaryMinute, day: summaryDay, agenda: agenda, showsNextTitle: settings.showNextItemOnLockScreen),
                routines: routineSnapshots,
                completedDays: completedDays,
                now: now,
                calendar: localCalendar
            )
        }
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

@MainActor
private final class NotificationRescheduleGeneration {
    private var latest = 0

    func begin() -> Int {
        latest &+= 1
        return latest
    }

    func isLatest(_ generation: Int) -> Bool {
        generation == latest
    }
}
