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
        let notificationActionHandler = AppNotificationActionHandler(
            routines: routines,
            scheduler: notificationScheduler,
            calendar: localCalendar,
            isRoutineInNotificationScope: { routineID in
                (try? profileScopes.resolve(.everything).routineIDs.contains(routineID)) == true
            }
        )
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
        let rescheduleNotifications = makeNotificationRescheduler(calendar: calendar, reminders: reminders, routines: routines, profiles: profiles, composer: AgendaComposer(categories: categories), settings: settings, profileScopes: profileScopes, authorization: notifications, coordinator: notificationCoordinator)
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
        let notificationAccess: AccessState = arguments.contains("-notifications-not-determined") ? .notDetermined : arguments.contains("-notifications-restricted") ? .restricted : arguments.contains("-notifications-denied") ? .denied : .granted
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
        let notificationActionHandler = AppNotificationActionHandler(
            routines: routines,
            scheduler: notificationScheduler,
            calendar: localCalendar,
            isRoutineInNotificationScope: { routineID in
                (try? profileScopes.resolve(.everything).routineIDs.contains(routineID)) == true
            }
        )
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
        let rescheduleNotifications = makeNotificationRescheduler(calendar: calendar, reminders: reminders, routines: routines, profiles: profiles, composer: AgendaComposer(categories: categories), settings: settings, profileScopes: profileScopes, authorization: notifications, coordinator: notificationCoordinator)
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
        profiles: any ProfileRepository,
        composer: AgendaComposer,
        settings: AppSettingsStore,
        profileScopes: ProfileScopeResolver,
        authorization: any NotificationAuthorizing,
        coordinator: NotificationCoordinator
    ) -> @MainActor @Sendable () async -> Void {
        let generationState = NotificationRescheduleGeneration()
        return {
            let generation = generationState.begin()
            guard await authorization.accessState == .granted else {
                guard generationState.isLatest(generation) else { return }
                await coordinator.clear()
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

            let everythingScope: ProfileScope
            do {
                everythingScope = try profileScopes.resolve(.everything)
            } catch {
                return
            }

            let routineSnapshots: [RoutineSnapshot]
            var completedDays: [UUID: Set<LocalDay>] = [:]
            do {
                routineSnapshots = try routines.list(includeArchived: false).filter {
                    everythingScope.routineIDs.contains($0.id)
                }
                for routine in routineSnapshots {
                    completedDays[routine.id] = try routines.completedDays(
                        routineID: routine.id
                    )
                }
            } catch {
                return
            }

            let alertStart = localCalendar.startOfDay(for: now)
            let alertEnd = localCalendar.date(byAdding: .day, value: 15, to: alertStart)!
            let eventInterval = DateInterval(start: alertStart, end: alertEnd)
            let events: [CalendarEventSnapshot]
            if !everythingScope.calendarIDs.isEmpty {
                do {
                    events = try calendar.fetchEvents(
                        in: eventInterval,
                        calendarIDs: everythingScope.calendarIDs
                    )
                } catch {
                    return
                }
            } else {
                events = []
            }
            let taskSnapshots: [ReminderSnapshot]
            if !everythingScope.reminderListIDs.isEmpty {
                do {
                    taskSnapshots = try await reminders.fetchReminders(
                        listIDs: everythingScope.reminderListIDs
                    )
                } catch {
                    return
                }
            } else {
                taskSnapshots = []
            }
            let completedRoutineIDs = Set(routineSnapshots.filter { completedDays[$0.id]?.contains(summaryDay) == true }.map(\.id))
            let agenda = composer.compose(day: summaryDay, events: events, reminders: taskSnapshots, routines: routineSnapshots, completedRoutineIDs: completedRoutineIDs, includeOverdueTasks: false, calendar: localCalendar)
            let profileSnapshots: [ProfileSnapshot]
            do {
                profileSnapshots = try profiles.list()
                settings.reconcileClassAlertPreferences(
                    validProfileIDs: Set(profileSnapshots.map(\.id))
                )
            } catch {
                return
            }
            let classAlerts = ClassAlertCoordinator(calendar: localCalendar).requests(
                profiles: profileSnapshots,
                preferences: settings.classAlertPreferences,
                events: events,
                now: now
            )
            var routineProfiles: [UUID: ProfileIdentity] = [:]
            for profile in profileSnapshots.sorted(by: {
                $0.sortOrder == $1.sortOrder
                    ? $0.id.uuidString < $1.id.uuidString
                    : $0.sortOrder < $1.sortOrder
            }) {
                for routineID in profile.routineIDs where routineProfiles[routineID] == nil {
                    routineProfiles[routineID] = .saved(profile.id)
                }
            }
            guard generationState.isLatest(generation) else { return }
            await coordinator.reschedule(
                summary: .init(enabled: settings.morningSummaryEnabled, hour: settings.morningSummaryHour, minute: settings.morningSummaryMinute, day: summaryDay, agenda: agenda, showsNextTitle: settings.showNextItemOnLockScreen),
                routines: routineSnapshots,
                completedDays: completedDays,
                routineProfiles: routineProfiles,
                classAlerts: classAlerts,
                now: now,
                calendar: localCalendar
            )
        }
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
