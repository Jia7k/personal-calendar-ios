import EventKit
import Foundation
import SwiftData

@MainActor
struct AppEnvironment {
    let calendar: any CalendarServicing
    let reminders: any RemindersServicing
    let routines: any RoutineRepository
    let routineProfileMutations: any RoutineProfileMutating
    let categories: any CategoryRepository
    let profiles: any ProfileRepository
    let profileScopes: ProfileScopeResolver
    let profileSelection: ProfileSelectionController
    let profileMigration: ProfileMigrationCoordinator
    let notificationAuthorization: any NotificationAuthorizing
    let permissions: PermissionCoordinator
    let agendaComposer: AgendaComposer
    let eventLocationMapsOpener: any EventLocationMapsOpening
    let settings: AppSettingsStore
    let backup: BackupService
    let notificationCoordinator: NotificationCoordinator
    let notificationActionHandler: AppNotificationActionHandler
    let notificationRescheduler: NotificationRescheduler
    let notificationRenewalScheduler: NotificationRenewalScheduler
    let rescheduleNotifications: @MainActor @Sendable () async -> Void
    let refreshCoordinator: AppRefreshCoordinator
    let agendaRefreshRegistry: AgendaRefreshRegistry
    let timetableSnapshotCoordinator: TimetableSnapshotCoordinator
    let timetableLiveActivityCoordinator: TimetableLiveActivityCoordinator
    private let refreshRuntime: EventStoreRefreshRuntime
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
        let profiles = SwiftDataProfileRepository(context: container.mainContext)
        let routineProfileMutations = RoutineProfileMutationCoordinator(
            context: container.mainContext,
            routines: routines
        )
        let profileMigration = ProfileMigrationCoordinator(
            profiles: profiles,
            calendar: calendar,
            reminders: reminders,
            routines: routines,
            settings: settings
        )
        try! profileMigration.run()
        let profileSelection = ProfileSelectionController(repository: profiles, settings: settings)
        try! profileSelection.reloadProfiles()
        let profileScopes = ProfileScopeResolver(
            profiles: profiles,
            calendar: calendar,
            reminders: reminders
        )
        var localCalendar = Calendar.current
        localCalendar.timeZone = .current
        let notificationScheduler = SystemNotificationScheduler()
        let notificationCoordinator = NotificationCoordinator(scheduler: notificationScheduler)
        try! categories.seedDefaultsIfNeeded(settings: settings)
        let permissions = PermissionCoordinator(
            calendar: calendar,
            reminders: reminders,
            notifications: notifications
        )
        let agendaRefreshRegistry = AgendaRefreshRegistry()
        let timetableWriter: any TimetableWidgetCatalogWriting
        do {
            timetableWriter = try TimetableWidgetCatalogStore.appGroup()
        } catch {
            timetableWriter = UnavailableTimetableCatalogWriter()
        }
        let timetableLiveActivityCoordinator = TimetableLiveActivityCoordinator(
            driver: SystemTimetableActivityDriver(),
            calendar: localCalendar
        )
        let timetableSnapshotCoordinator = TimetableSnapshotCoordinator(
            calendar: calendar,
            profiles: profiles,
            builder: TimetableSnapshotBuilder(calendar: localCalendar),
            writer: timetableWriter,
            reloader: SystemTimetableWidgetReloader(),
            onFailClosed: {
                Task { await timetableLiveActivityCoordinator.stop() }
            }
        )
        let backup = BackupService(
            context: container.mainContext,
            settings: settings,
            profileMigration: profileMigration,
            onRestored: {
                let restoredIdentity = settings.activeProfileIdentity
                try? profileSelection.reloadProfiles()
                try? profileSelection.select(restoredIdentity)
                if (try? timetableSnapshotCoordinator.refresh(failClosed: true)) != nil,
                   let catalog = timetableSnapshotCoordinator.latestCatalog {
                    Task {
                        if settings.automaticallyStartsLiveActivityOnForeground {
                            await timetableLiveActivityCoordinator
                                .applyForegroundPreference(
                                    isEnabled: true,
                                    preferredProfileIdentity:
                                        settings.preferredLiveActivityProfile,
                                    catalog: catalog
                                )
                        } else {
                            await timetableLiveActivityCoordinator.stop()
                        }
                    }
                }
            }
        )
        let notificationRescheduler = NotificationRescheduler(
            calendarService: calendar,
            reminders: reminders,
            routines: routines,
            profiles: profiles,
            composer: AgendaComposer(categories: categories),
            settings: settings,
            profileScopes: profileScopes,
            authorization: notifications,
            coordinator: notificationCoordinator
        )
        let notificationRenewalScheduler = NotificationRenewalScheduler(
            driver: SystemNotificationRenewalDriver(),
            reschedule: { await notificationRescheduler.reschedule() }
        )
        let rescheduleNotifications: @MainActor @Sendable () async -> Void = {
            _ = await notificationRenewalScheduler.rescheduleNotifications()
        }
        let notificationActionHandler = AppNotificationActionHandler(
            routines: routines,
            scheduler: notificationScheduler,
            calendar: localCalendar,
            isRoutineInNotificationScope: { routineID in
                (try? profileScopes.resolve(.everything).routineIDs.contains(routineID)) == true
            },
            onRoutineCompletionCommitted: makeRoutineCompletionCommittedHook(
                agendaRefreshRegistry: agendaRefreshRegistry,
                rescheduleNotifications: rescheduleNotifications
            )
        )
        let refreshCoordinator = AppRefreshCoordinator(actions: .init(
            refreshPermissions: { await permissions.refresh() },
            migrateProfiles: { try? profileMigration.run() },
            refreshSources: {
                settings.reconcileSources(
                    calendarAccess: calendar.accessState,
                    calendars: calendar.calendars(),
                    remindersAccess: reminders.accessState,
                    lists: reminders.lists()
                )
            },
            reloadProfiles: { try? profileSelection.refreshScope() },
            refreshAgenda: { await agendaRefreshRegistry.refreshAll() },
            // EventKit currently exposes no authoritative all-item inventory. Never prune links from visible-range snapshots.
            cleanCategoryLinks: {},
            refreshTimetable: {
                guard (try? timetableSnapshotCoordinator.refresh()) != nil,
                      let catalog = timetableSnapshotCoordinator.latestCatalog else { return }
                await timetableLiveActivityCoordinator.reconcile(catalog: catalog)
            },
            rescheduleNotifications: rescheduleNotifications
        ))
        return .init(
            calendar: calendar,
            reminders: reminders,
            routines: routines,
            routineProfileMutations: routineProfileMutations,
            categories: categories,
            profiles: profiles,
            profileScopes: profileScopes,
            profileSelection: profileSelection,
            profileMigration: profileMigration,
            notificationAuthorization: notifications,
            permissions: permissions,
            agendaComposer: AgendaComposer(categories: categories),
            eventLocationMapsOpener: SystemEventLocationMapsOpener(),
            settings: settings,
            backup: backup,
            notificationCoordinator: notificationCoordinator,
            notificationActionHandler: notificationActionHandler,
            notificationRescheduler: notificationRescheduler,
            notificationRenewalScheduler: notificationRenewalScheduler,
            rescheduleNotifications: rescheduleNotifications,
            refreshCoordinator: refreshCoordinator,
            agendaRefreshRegistry: agendaRefreshRegistry,
            timetableSnapshotCoordinator: timetableSnapshotCoordinator,
            timetableLiveActivityCoordinator: timetableLiveActivityCoordinator,
            refreshRuntime: EventStoreRefreshRuntime(coordinator: refreshCoordinator, monitor: EventStoreChangeMonitor(store: store)),
            reduceMotionOverride: false,
            quickEntryContext: { currentQuickEntryContext() }
        )
    }

    static func demo(container: ModelContainer, arguments: [String]) -> AppEnvironment {
        let usesProfileFixtures = arguments.contains("-demo-profiles")
        let usesDailyTaskRescueFixtures = arguments.contains("-demo-daily-task-rescue")
        let calendarAccess: AccessState = arguments.contains("-calendar-not-determined") ? .notDetermined : arguments.contains("-calendar-restricted") ? .restricted : arguments.contains("-calendar-denied") ? .denied : .granted
        let calendar = DemoCalendarService(
            access: calendarAccess,
            failFirstCreate: arguments.contains("-event-save-fails-once"),
            failFirstUpdate: arguments.contains("-event-update-fails-once"),
            failFirstDelete: arguments.contains("-event-delete-fails-once"),
            multipleSources: arguments.contains("-demo-multiple-sources"),
            includeReadOnlySource: arguments.contains("-demo-editor-read-only"),
            replacePrimaryEventWithReadOnly: arguments.contains("-read-only-event"),
            includeRecurringItems: arguments.contains("-demo-editor-recurring"),
            includeUnsupportedItems: arguments.contains("-demo-editor-unsupported"),
            profileFixtures: usesProfileFixtures,
            dailyQOLFixtures: arguments.contains("-demo-daily-qol"),
            denseWeekFixtures: arguments.contains("-demo-week-overlaps")
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
            includeUnsupportedItems: arguments.contains("-demo-editor-unsupported"),
            includeOverdueTask: arguments.contains("-demo-overdue-task"),
            profileFixtures: usesProfileFixtures,
            dailyQOLFixtures: arguments.contains("-demo-daily-qol"),
            dailyTaskRescueFixtures: usesDailyTaskRescueFixtures,
            denseWeekFixtures: arguments.contains("-demo-week-overlaps")
        )
        let notificationAccess: AccessState = arguments.contains("-notifications-not-determined") ? .notDetermined : arguments.contains("-notifications-restricted") ? .restricted : arguments.contains("-notifications-denied") || arguments.contains("-demo-notification-scheduling-paused") ? .denied : .granted
        let notifications = DemoNotificationAuthorizer(access: notificationAccess)
        let settings = AppSettingsStore(defaults: .ephemeral)
        if !usesProfileFixtures {
            settings.resetProfileMigration(legacy: LegacyProfileSelectionSnapshot(
                calendarIDs: [],
                reminderListIDs: [],
                defaultCalendarID: "demo-calendar",
                defaultReminderListID: "demo-list",
                calendarSelectionWasExplicit: false,
                reminderSelectionWasExplicit: false
            ))
        }
        let routines = DemoRoutineRepository(failFirstDelete: arguments.contains("-routine-delete-fails-once"), failFirstCreate: arguments.contains("-routine-create-fails-once"), failFirstUpdate: arguments.contains("-routine-update-fails-once"), longTitle: arguments.contains("-routine-long-title"), profileFixtures: usesProfileFixtures)
        if arguments.contains("-demo-routine-notification-completion") {
            try? routines.update(
                id: DemoProfileFixture.personalRoutineID,
                draft: .init(
                    title: "Read",
                    weekdays: [1, 2, 3, 4, 5, 6, 7],
                    window: .evening,
                    reminderHour: 18,
                    reminderMinute: 0
                )
            )
        }
        let profiles = SwiftDataProfileRepository(context: container.mainContext)
        let routineProfileMutations = DemoRoutineProfileMutationAdapter(
            routines: routines,
            profiles: profiles
        )
        let profileMigration = ProfileMigrationCoordinator(
            profiles: profiles,
            calendar: calendar,
            reminders: reminders,
            routines: routines,
            settings: settings
        )
        try! profileMigration.run()
        if usesProfileFixtures {
            try! DemoProfileFixture.configure(profiles: profiles)
        }
        let profileSelection = ProfileSelectionController(repository: profiles, settings: settings)
        try! profileSelection.reloadProfiles()
        let profileScopes = ProfileScopeResolver(
            profiles: profiles,
            calendar: calendar,
            reminders: reminders
        )
        settings.didCompleteOnboarding = !arguments.contains("-show-onboarding")
        let categories = SwiftDataCategoryRepository(context: container.mainContext)
        try! categories.seedDefaultsIfNeeded(settings: settings)
        let quickEntryContext: @MainActor @Sendable () -> QuickEntryParseContext
        if arguments.contains("-quick-entry-fixed-context") {
            let context = fixedQuickEntryContext(referenceDate: Date())
            quickEntryContext = { context }
        } else {
            quickEntryContext = { currentQuickEntryContext() }
        }
        var localCalendar = Calendar.current
        localCalendar.timeZone = .current
        let notificationScheduler = SystemNotificationScheduler()
        let notificationCoordinator = NotificationCoordinator(scheduler: notificationScheduler)
        let permissions = PermissionCoordinator(
            calendar: calendar,
            reminders: reminders,
            notifications: notifications
        )
        let agendaRefreshRegistry = AgendaRefreshRegistry()
        let timetableLiveActivityCoordinator = TimetableLiveActivityCoordinator(
            driver: NoopTimetableActivityDriver(),
            calendar: localCalendar
        )
        let timetableSnapshotCoordinator = TimetableSnapshotCoordinator(
            calendar: calendar,
            profiles: profiles,
            builder: TimetableSnapshotBuilder(calendar: localCalendar),
            writer: TimetableWidgetCatalogStore(
                fileURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent("demo-timetable-catalog-\(UUID().uuidString).json")
            ),
            reloader: NoopTimetableWidgetReloader(),
            onFailClosed: {
                Task { await timetableLiveActivityCoordinator.stop() }
            }
        )
        let backup = BackupService(
            context: container.mainContext,
            settings: settings,
            profileMigration: profileMigration,
            onRestored: {
                let restoredIdentity = settings.activeProfileIdentity
                try? profileSelection.reloadProfiles()
                try? profileSelection.select(restoredIdentity)
                if (try? timetableSnapshotCoordinator.refresh(failClosed: true)) != nil,
                   let catalog = timetableSnapshotCoordinator.latestCatalog {
                    Task {
                        if settings.automaticallyStartsLiveActivityOnForeground {
                            await timetableLiveActivityCoordinator
                                .applyForegroundPreference(
                                    isEnabled: true,
                                    preferredProfileIdentity:
                                        settings.preferredLiveActivityProfile,
                                    catalog: catalog
                                )
                        } else {
                            await timetableLiveActivityCoordinator.stop()
                        }
                    }
                }
            }
        )
        let notificationRescheduler = NotificationRescheduler(
            calendarService: calendar,
            reminders: reminders,
            routines: routines,
            profiles: profiles,
            composer: AgendaComposer(categories: categories),
            settings: settings,
            profileScopes: profileScopes,
            authorization: notifications,
            coordinator: notificationCoordinator
        )
        let notificationRenewalScheduler = NotificationRenewalScheduler(
            driver: NoopNotificationRenewalDriver(),
            reschedule: { await notificationRescheduler.reschedule() }
        )
        let rescheduleNotifications: @MainActor @Sendable () async -> Void = {
            _ = await notificationRenewalScheduler.rescheduleNotifications()
        }
        let notificationActionHandler = AppNotificationActionHandler(
            routines: routines,
            scheduler: notificationScheduler,
            calendar: localCalendar,
            isRoutineInNotificationScope: { routineID in
                (try? profileScopes.resolve(.everything).routineIDs.contains(routineID)) == true
            },
            onRoutineCompletionCommitted: makeRoutineCompletionCommittedHook(
                agendaRefreshRegistry: agendaRefreshRegistry,
                rescheduleNotifications: rescheduleNotifications
            )
        )
        let refreshCoordinator = AppRefreshCoordinator(actions: .init(
            refreshPermissions: { await permissions.refresh() },
            migrateProfiles: { try? profileMigration.run() },
            refreshSources: {
                settings.reconcileSources(
                    calendarAccess: calendar.accessState,
                    calendars: calendar.calendars(),
                    remindersAccess: reminders.accessState,
                    lists: reminders.lists()
                )
            },
            reloadProfiles: { try? profileSelection.refreshScope() },
            refreshAgenda: { await agendaRefreshRegistry.refreshAll() },
            cleanCategoryLinks: {},
            refreshTimetable: {
                guard (try? timetableSnapshotCoordinator.refresh()) != nil,
                      let catalog = timetableSnapshotCoordinator.latestCatalog else { return }
                await timetableLiveActivityCoordinator.reconcile(catalog: catalog)
            },
            rescheduleNotifications: rescheduleNotifications
        ))
        return .init(
            calendar: calendar,
            reminders: reminders,
            routines: routines,
            routineProfileMutations: routineProfileMutations,
            categories: categories,
            profiles: profiles,
            profileScopes: profileScopes,
            profileSelection: profileSelection,
            profileMigration: profileMigration,
            notificationAuthorization: notifications,
            permissions: permissions,
            agendaComposer: AgendaComposer(categories: categories),
            eventLocationMapsOpener: NoopEventLocationMapsOpener(),
            settings: settings,
            backup: backup,
            notificationCoordinator: notificationCoordinator,
            notificationActionHandler: notificationActionHandler,
            notificationRescheduler: notificationRescheduler,
            notificationRenewalScheduler: notificationRenewalScheduler,
            rescheduleNotifications: rescheduleNotifications,
            refreshCoordinator: refreshCoordinator,
            agendaRefreshRegistry: agendaRefreshRegistry,
            timetableSnapshotCoordinator: timetableSnapshotCoordinator,
            timetableLiveActivityCoordinator: timetableLiveActivityCoordinator,
            refreshRuntime: EventStoreRefreshRuntime(coordinator: refreshCoordinator, monitor: nil),
            reduceMotionOverride: arguments.contains("-reduce-motion"),
            quickEntryContext: quickEntryContext
        )
    }

    func startRefreshMonitoring() {
        refreshRuntime.start()
    }

    func stopRefreshMonitoring() {
        refreshRuntime.stop()
    }

    static func makeRoutineCompletionCommittedHook(
        agendaRefreshRegistry: AgendaRefreshRegistry,
        rescheduleNotifications: @escaping @MainActor @Sendable () async -> Void
    ) -> @MainActor @Sendable () async -> Void {
        {
            await agendaRefreshRegistry.refreshAll()
            await rescheduleNotifications()
        }
    }

    private static func currentQuickEntryContext() -> QuickEntryParseContext {
        let timeZone = TimeZone.current
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        let locale = Locale.current
        return .init(now: Date(), calendar: calendar, locale: locale, timeZone: timeZone)
    }

    private static func fixedQuickEntryContext(referenceDate: Date) -> QuickEntryParseContext {
        let timeZone = TimeZone(identifier: "Asia/Singapore")!
        let locale = Locale(identifier: "en_SG")
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        calendar.timeZone = timeZone
        let now = calendar.date(
            bySettingHour: 12,
            minute: 0,
            second: 0,
            of: referenceDate
        )!
        return .init(now: now, calendar: calendar, locale: locale, timeZone: timeZone)
    }
}

private struct UnavailableTimetableCatalogWriter: TimetableWidgetCatalogWriting {
    func write(_ value: TimetableWidgetCatalogV1) throws {
        throw TimetableSnapshotStoreError.containerUnavailable
    }

    func delete() throws {}
}

@MainActor
private final class NoopTimetableWidgetReloader: TimetableWidgetReloading {
    func reloadTimetableWidgets() {}
}
