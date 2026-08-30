import Foundation

enum NotificationRescheduleOutcome: Equatable, Sendable {
    case success
    case failure
    case superseded
}

@MainActor
final class NotificationRescheduler {
    private let calendarService: any CalendarServicing
    private let reminders: any RemindersServicing
    private let routines: any RoutineRepository
    private let profiles: any ProfileRepository
    private let composer: AgendaComposer
    private let settings: AppSettingsStore
    private let profileScopes: ProfileScopeResolver
    private let authorization: any NotificationAuthorizing
    private let coordinator: NotificationCoordinator
    private let calendarProvider: @MainActor @Sendable () -> Calendar
    private let now: @MainActor @Sendable () -> Date
    private var latestGeneration = 0

    init(
        calendarService: any CalendarServicing,
        reminders: any RemindersServicing,
        routines: any RoutineRepository,
        profiles: any ProfileRepository,
        composer: AgendaComposer,
        settings: AppSettingsStore,
        profileScopes: ProfileScopeResolver,
        authorization: any NotificationAuthorizing,
        coordinator: NotificationCoordinator,
        calendarProvider: @escaping @MainActor @Sendable () -> Calendar = {
            var calendar = Calendar.current
            calendar.timeZone = .current
            return calendar
        },
        now: @escaping @MainActor @Sendable () -> Date = Date.init
    ) {
        self.calendarService = calendarService
        self.reminders = reminders
        self.routines = routines
        self.profiles = profiles
        self.composer = composer
        self.settings = settings
        self.profileScopes = profileScopes
        self.authorization = authorization
        self.coordinator = coordinator
        self.calendarProvider = calendarProvider
        self.now = now
    }

    func reschedule() async -> NotificationRescheduleOutcome {
        latestGeneration &+= 1
        let generation = latestGeneration

        let authorizationState = await authorization.accessState
        guard isLatest(generation) else { return .superseded }
        guard !Task.isCancelled else { return .failure }
        guard authorizationState == .granted else {
            return await failClosed(generation: generation)
        }

        let localCalendar = calendarProvider()
        let refreshDate = now()
        let today = LocalDay(date: refreshDate, calendar: localCalendar)
        let todaySummaryTime = localCalendar.date(
            bySettingHour: settings.morningSummaryHour,
            minute: settings.morningSummaryMinute,
            second: 0,
            of: today.startDate(in: localCalendar)
        )
        let summaryDay: LocalDay
        if let todaySummaryTime, todaySummaryTime > refreshDate {
            summaryDay = today
        } else if let tomorrow = localCalendar.date(
            byAdding: .day,
            value: 1,
            to: today.startDate(in: localCalendar)
        ) {
            summaryDay = LocalDay(date: tomorrow, calendar: localCalendar)
        } else {
            return await failClosed(generation: generation)
        }

        let everythingScope: ProfileScope
        do {
            everythingScope = try profileScopes.resolve(.everything)
        } catch {
            return await failClosed(generation: generation)
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
            return await failClosed(generation: generation)
        }

        let alertStart = localCalendar.startOfDay(for: refreshDate)
        guard let alertEnd = localCalendar.date(
            byAdding: .day,
            value: 15,
            to: alertStart
        ) else {
            return await failClosed(generation: generation)
        }
        let eventInterval = DateInterval(start: alertStart, end: alertEnd)
        let events: [CalendarEventSnapshot]
        if everythingScope.calendarIDs.isEmpty {
            events = []
        } else {
            do {
                events = try calendarService.fetchEvents(
                    in: eventInterval,
                    calendarIDs: everythingScope.calendarIDs
                )
            } catch {
                return await failClosed(generation: generation)
            }
        }

        let taskSnapshots: [ReminderSnapshot]
        if everythingScope.reminderListIDs.isEmpty {
            taskSnapshots = []
        } else {
            do {
                taskSnapshots = try await reminders.fetchReminders(
                    listIDs: everythingScope.reminderListIDs
                )
            } catch {
                return await failClosed(generation: generation)
            }
        }
        guard isLatest(generation) else { return .superseded }
        guard !Task.isCancelled else { return .failure }

        let completedRoutineIDs = Set(routineSnapshots.compactMap { routine in
            completedDays[routine.id]?.contains(summaryDay) == true
                ? routine.id
                : nil
        })
        let agenda = composer.compose(
            day: summaryDay,
            events: events,
            reminders: taskSnapshots,
            routines: routineSnapshots,
            completedRoutineIDs: completedRoutineIDs,
            includeOverdueTasks: false,
            calendar: localCalendar
        )

        let profileSnapshots: [ProfileSnapshot]
        do {
            profileSnapshots = try profiles.list()
        } catch {
            return await failClosed(generation: generation)
        }
        guard isLatest(generation) else { return .superseded }
        guard !Task.isCancelled else { return .failure }

        settings.reconcileClassAlertPreferences(
            validProfileIDs: Set(profileSnapshots.map(\.id))
        )
        let classAlerts = ClassAlertCoordinator(
            calendar: localCalendar
        ).requests(
            profiles: profileSnapshots,
            preferences: settings.classAlertPreferences,
            events: events,
            now: refreshDate
        )
        var routineProfiles: [UUID: ProfileIdentity] = [:]
        for profile in profileSnapshots.sorted(by: {
            $0.sortOrder == $1.sortOrder
                ? $0.id.uuidString < $1.id.uuidString
                : $0.sortOrder < $1.sortOrder
        }) {
            for routineID in profile.routineIDs
            where routineProfiles[routineID] == nil {
                routineProfiles[routineID] = .saved(profile.id)
            }
        }

        let replacementSucceeded = await coordinator.reschedule(
            summary: .init(
                enabled: settings.morningSummaryEnabled,
                hour: settings.morningSummaryHour,
                minute: settings.morningSummaryMinute,
                day: summaryDay,
                agenda: agenda,
                showsNextTitle: settings.showNextItemOnLockScreen
            ),
            routines: routineSnapshots,
            completedDays: completedDays,
            routineProfiles: routineProfiles,
            classAlerts: classAlerts,
            now: refreshDate,
            calendar: localCalendar
        )
        guard isLatest(generation) else { return .superseded }
        guard replacementSucceeded else { return .failure }
        settings.markNotificationRefreshSuccessful(at: refreshDate)
        return .success
    }

    private func failClosed(
        generation: Int
    ) async -> NotificationRescheduleOutcome {
        guard isLatest(generation) else { return .superseded }
        settings.markNotificationsPausedForStaleInput()
        await coordinator.removeRequestsForStaleInput()
        guard isLatest(generation) else { return .superseded }
        return .failure
    }

    private func isLatest(_ generation: Int) -> Bool {
        generation == latestGeneration
    }
}
