import Foundation
import Observation

enum TrayState: Equatable {
    case resting
    case expanded
}

enum CalendarDisplayMode: String, CaseIterable, Equatable, Sendable {
    case month
    case week
}

enum CalendarEditorRefreshOperation: Equatable {
    case eventSaved, eventDeleted, taskSaved, taskDeleted

    var failureMessage: String {
        switch self {
        case .eventSaved: "Your event was saved, but your schedule could not be refreshed. Pull to try again."
        case .eventDeleted: "Your event was deleted, but your schedule could not be refreshed. Pull to try again."
        case .taskSaved: "Your task was saved, but your schedule could not be refreshed. Pull to try again."
        case .taskDeleted: "Your task was deleted, but your schedule could not be refreshed. Pull to try again."
        }
    }
}

private enum CalendarRefreshFailureSource: Hashable {
    case event, task, routine
}

struct SourceAccessNotice: Equatable, Identifiable, Sendable {
    enum Source: Hashable, Sendable {
        case calendar
        case reminders

        var displayName: String {
            switch self {
            case .calendar: "Calendar"
            case .reminders: "Reminders"
            }
        }

        var settingsActionIdentifier: String {
            switch self {
            case .calendar: "calendar-permission-settings"
            case .reminders: "reminders-permission-settings"
            }
        }
    }

    enum Action: Equatable, Sendable {
        case openSettings
    }

    let source: Source
    let accessState: AccessState

    var id: Source { source }

    var message: String {
        switch (source, accessState) {
        case (.calendar, .restricted):
            "Calendar access is restricted. Calendar events are hidden because this access is controlled by your device or account."
        case (.reminders, .restricted):
            "Reminders access is restricted. Tasks are hidden because this access is controlled by your device or account."
        case (.calendar, .granted):
            "Calendar access is available."
        case (.reminders, .granted):
            "Reminders access is available."
        case (.calendar, .denied), (.calendar, .notDetermined):
            "Calendar access is unavailable. Calendar events are hidden."
        case (.reminders, .denied), (.reminders, .notDetermined):
            "Reminders access is unavailable. Tasks are hidden."
        }
    }

    var action: Action? {
        switch accessState {
        case .denied, .notDetermined: .openSettings
        case .granted, .restricted: nil
        }
    }

    var canOpenSettings: Bool { action == .openSettings }
    var settingsActionIdentifier: String { source.settingsActionIdentifier }
}

@MainActor
@Observable
final class CalendarViewModel {
    var displayedMonth: LocalDay
    var selectedDay: LocalDay
    var trayState: TrayState = .resting
    private(set) var displayMode: CalendarDisplayMode = .month
    private(set) var agenda = DayAgenda(allDay: [], scheduled: [], priority: [])
    private(set) var visibleAgendas: [LocalDay: DayAgenda] = [:]
    private(set) var weekPlanner: WeekPlannerSnapshot = .empty
    private(set) var errorMessage: String?
    private(set) var isLoading = false
    private(set) var sourceAccessNotices: [SourceAccessNotice] = []
    private(set) var mutatingItemIDs: Set<String> = []
    private(set) var isProfileEmpty = false

    private var cachedEvents: [CalendarEventSnapshot] = []
    private var cachedReminders: [ReminderSnapshot] = []
    private var cachedRoutines: [RoutineSnapshot] = []
    private var cachedRoutineCompletions: [UUID: Set<LocalDay>] = [:]
    private var cachedScopeIdentity: ProfileIdentity?
    private var cachedScope: ProfileScope?

    var routeEvents: [CalendarEventSnapshot] { cachedEvents }
    private let today: LocalDay
    private let calendarService: any CalendarServicing
    private let remindersService: any RemindersServicing
    private let routines: any RoutineRepository
    private let composer: AgendaComposer
    private let settings: AppSettingsStore
    private let currentScope: @MainActor () throws -> ProfileScope
    private let usesLegacyScope: Bool
    private let systemCalendar: Calendar
    private var loadGeneration = 0
    private var latestRefreshFailures: Set<CalendarRefreshFailureSource> = []

    var visibleDays: [LocalDay] {
        let builder = MonthGridBuilder(calendar: systemCalendar)
        switch displayMode {
        case .month:
            return builder.days(containing: displayedMonth).map(\.day)
        case .week:
            return builder.week(
                containing: selectedDay,
                displayedMonth: displayedMonth
            ).map(\.day)
        }
    }

    init(
        today: LocalDay,
        calendarService: any CalendarServicing,
        remindersService: any RemindersServicing,
        routines: any RoutineRepository,
        composer: AgendaComposer,
        settings: AppSettingsStore,
        systemCalendar: Calendar
    ) {
        self.today = today
        self.calendarService = calendarService
        self.remindersService = remindersService
        self.routines = routines
        self.composer = composer
        self.settings = settings
        displayMode = settings.calendarDisplayMode
        currentScope = {
            let calendarDescriptorIDs = Set(calendarService.calendars().map(\.id))
            let reminderDescriptorIDs = Set(remindersService.lists().map(\.id))
            return ProfileScope(
                identity: .everything,
                calendarIDs: calendarDescriptorIDs.isEmpty
                    ? settings.selectedCalendarIDs
                    : settings.visibleCalendarIDs(availableIDs: calendarDescriptorIDs),
                reminderListIDs: reminderDescriptorIDs.isEmpty
                    ? settings.selectedReminderListIDs
                    : settings.visibleReminderListIDs(availableIDs: reminderDescriptorIDs),
                routineIDs: [],
                defaultCalendarID: nil,
                defaultReminderListID: nil
            )
        }
        usesLegacyScope = true
        self.systemCalendar = systemCalendar
        displayedMonth = LocalDay(year: today.year, month: today.month, day: 1)
        selectedDay = today
    }

    init(
        today: LocalDay,
        calendarService: any CalendarServicing,
        remindersService: any RemindersServicing,
        routines: any RoutineRepository,
        composer: AgendaComposer,
        settings: AppSettingsStore,
        currentScope: @escaping @MainActor () throws -> ProfileScope,
        systemCalendar: Calendar
    ) {
        self.today = today
        self.calendarService = calendarService
        self.remindersService = remindersService
        self.routines = routines
        self.composer = composer
        self.settings = settings
        displayMode = settings.calendarDisplayMode
        self.currentScope = currentScope
        usesLegacyScope = false
        self.systemCalendar = systemCalendar
        displayedMonth = LocalDay(year: today.year, month: today.month, day: 1)
        selectedDay = today
    }

    func load() async {
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true
        defer { if generation == loadGeneration { isLoading = false } }

        let scope: ProfileScope
        do {
            scope = try currentScope()
        } catch {
            guard generation == loadGeneration else { return }
            failScopeResolution()
            return
        }
        adopt(scope)

        var nextEvents = cachedEvents
        var nextReminders = cachedReminders
        var nextRoutines = cachedRoutines
        var nextCompletions = cachedRoutineCompletions
        var notices: [SourceAccessNotice] = []
        var encounteredFailure = false
        var refreshFailures: Set<CalendarRefreshFailureSource> = []
        let days = visibleDays
        let interval = DateInterval(
            start: days.first!.startDate(in: systemCalendar),
            end: systemCalendar.date(
                byAdding: .day,
                value: 1,
                to: days.last!.startDate(in: systemCalendar)
            )!
        )

        let calendarAccess = calendarService.accessState
        if calendarAccess == .granted {
            let skipsFetch = scope.calendarIDs.isEmpty
                && (!usesLegacyScope || settings.calendarSelectionIsExplicit)
            if skipsFetch {
                nextEvents = []
            } else {
                do {
                    let fetched = try calendarService.fetchEvents(
                        in: interval,
                        calendarIDs: scope.calendarIDs
                    )
                    nextEvents = shouldFilterLegacyCalendarResults
                        ? fetched.filter { scope.calendarIDs.contains($0.calendarID) }
                        : fetched
                } catch {
                    encounteredFailure = true
                    refreshFailures.insert(.event)
                }
            }
        } else {
            nextEvents = []
            notices.append(SourceAccessNotice(source: .calendar, accessState: calendarAccess))
        }

        let remindersAccess = remindersService.accessState
        if remindersAccess == .granted {
            let skipsFetch = scope.reminderListIDs.isEmpty
                && (!usesLegacyScope || settings.reminderSelectionIsExplicit)
            if skipsFetch {
                nextReminders = []
            } else {
                do {
                    let fetched = try await remindersService.fetchReminders(
                        listIDs: scope.reminderListIDs
                    )
                    nextReminders = shouldFilterLegacyReminderResults
                        ? fetched.filter { scope.reminderListIDs.contains($0.listID) }
                        : fetched
                } catch {
                    encounteredFailure = true
                    refreshFailures.insert(.task)
                }
            }
        } else {
            nextReminders = []
            notices.append(SourceAccessNotice(source: .reminders, accessState: remindersAccess))
        }

        if !usesLegacyScope && scope.routineIDs.isEmpty {
            nextRoutines = []
            nextCompletions = [:]
        } else {
            do {
                let refreshed = try routines.list(includeArchived: false)
                let scoped = usesLegacyScope
                    ? refreshed
                    : refreshed.filter { scope.routineIDs.contains($0.id) }
                let completions = try Dictionary(uniqueKeysWithValues: scoped.map {
                    ($0.id, try routines.completedDays(routineID: $0.id))
                })
                nextRoutines = scoped
                nextCompletions = completions
            } catch {
                encounteredFailure = true
                refreshFailures.insert(.routine)
            }
        }

        guard generation == loadGeneration else { return }
        cachedEvents = nextEvents
        cachedReminders = nextReminders
        cachedRoutines = nextRoutines
        cachedRoutineCompletions = nextCompletions
        sourceAccessNotices = notices
        latestRefreshFailures = refreshFailures
        cachedScope = scope
        rebuildVisibleAgendas(scope: scope)
        errorMessage = encounteredFailure ? "Your schedule could not be refreshed. Try again." : nil
    }

    func refreshForExternalChange() async {
        await load()
    }

    func select(_ day: LocalDay) async {
        selectedDay = day
        if let scope = cachedScope {
            rebuildVisibleAgendas(scope: scope)
        } else {
            agenda = visibleAgendas[selectedDay] ?? DayAgenda(allDay: [], scheduled: [], priority: [])
        }
    }

    func jump(to routeDay: AppRouteDay) async {
        await jump(to: LocalDay(
            year: routeDay.year,
            month: routeDay.month,
            day: routeDay.day
        ))
    }

    func jump(to day: LocalDay) async {
        selectedDay = day
        displayedMonth = LocalDay(year: day.year, month: day.month, day: 1)
        await load()
    }

    /// Fetches a fresh, profile-scoped event set for an exact deep-link lookup.
    /// Normal calendar refreshes may retain confirmed cache on provider failure;
    /// a route must fail closed instead of opening an event from that stale cache.
    func authoritativeRouteEvents(
        for routeDay: AppRouteDay?
    ) -> [CalendarEventSnapshot]? {
        guard calendarService.accessState == .granted else { return nil }

        let scope: ProfileScope
        do {
            scope = try currentScope()
        } catch {
            return nil
        }

        let skipsFetch = scope.calendarIDs.isEmpty
            && (!usesLegacyScope || settings.calendarSelectionIsExplicit)
        if skipsFetch { return [] }

        let interval: DateInterval
        if let routeDay {
            let day = LocalDay(
                year: routeDay.year,
                month: routeDay.month,
                day: routeDay.day
            )
            let start = day.startDate(in: systemCalendar)
            guard let end = systemCalendar.date(
                byAdding: .day,
                value: 1,
                to: start
            ) else { return nil }
            interval = DateInterval(start: start, end: end)
        } else {
            let days = visibleDays
            guard let first = days.first,
                  let last = days.last,
                  let end = systemCalendar.date(
                      byAdding: .day,
                      value: 1,
                      to: last.startDate(in: systemCalendar)
                  ) else { return nil }
            interval = DateInterval(
                start: first.startDate(in: systemCalendar),
                end: end
            )
        }

        do {
            let fetched = try calendarService.fetchEvents(
                in: interval,
                calendarIDs: scope.calendarIDs
            )
            return shouldFilterLegacyCalendarResults
                ? fetched.filter { scope.calendarIDs.contains($0.calendarID) }
                : fetched
        } catch {
            return nil
        }
    }

    func setTray(_ state: TrayState) { trayState = state }

    func showToday() async {
        selectedDay = today
        displayedMonth = LocalDay(year: today.year, month: today.month, day: 1)
        await load()
    }

    func setDisplayMode(_ mode: CalendarDisplayMode) async {
        guard displayMode != mode else { return }
        displayMode = mode
        settings.calendarDisplayMode = mode
        await load()
    }

    func movePeriod(by value: Int) async {
        switch displayMode {
        case .month:
            await moveMonth(by: value)
        case .week:
            let moved = systemCalendar.date(
                byAdding: .day,
                value: value * 7,
                to: selectedDay.startDate(in: systemCalendar)
            )!
            selectedDay = LocalDay(date: moved, calendar: systemCalendar)
            displayedMonth = LocalDay(
                year: selectedDay.year,
                month: selectedDay.month,
                day: 1
            )
            await load()
        }
    }

    func moveMonth(by value: Int) async {
        let moved = systemCalendar.date(byAdding: .month, value: value, to: displayedMonth.startDate(in: systemCalendar))!
        displayedMonth = LocalDay(date: moved, calendar: systemCalendar)
        let lastDay = systemCalendar.range(of: .day, in: .month, for: moved)!.count
        selectedDay = LocalDay(
            year: displayedMonth.year,
            month: displayedMonth.month,
            day: min(selectedDay.day, lastDay)
        )
        await load()
    }

    /// Host-owned post-editor refresh.  A successful editor write is never retried here.
    func refreshAfterEditorCommit(_ operation: CalendarEditorRefreshOperation) async {
        await load()
        if errorMessage != nil { errorMessage = operation.failureMessage }
    }

    /// Host-owned post-Quick-Entry reconciliation. The provider write is already terminal.
    func refreshAfterQuickEntry(_ outcome: QuickEntrySaveOutcome) async {
        await load()
        let source: CalendarRefreshFailureSource
        let message: String
        switch outcome {
        case .event:
            source = .event
            message = "Your event was saved, but your schedule could not be refreshed. Pull to try again."
        case .task:
            source = .task
            message = "Your task was saved, but your schedule could not be refreshed. Pull to try again."
        case .routine:
            source = .routine
            message = "Your routine was saved, but your schedule could not be refreshed. Pull to try again."
        }
        if latestRefreshFailures.contains(source) { errorMessage = message }
    }

    func setTaskCompleted(_ item: AgendaItem, completed: Bool) async {
        guard case let .reminder(id) = item.origin,
              item.allowsModification else { return }
        await setTaskCompleted(reminderID: id, completed: completed)
    }

    func setTaskCompleted(reminderID id: String, completed: Bool) async {
        let scope: ProfileScope
        do {
            scope = try currentScope()
        } catch {
            failScopeResolution()
            return
        }
        adopt(scope)

        let mutationID = "task|\(id)"
        guard !mutatingItemIDs.contains(mutationID),
              cachedReminders.contains(where: { $0.id == id }),
              let snapshot = remindersService.reminder(id: id),
              snapshot.allowsModification,
              snapshot.isCompleted != completed,
              usesLegacyScope || scope.reminderListIDs.contains(snapshot.listID)
        else { return }
        mutatingItemIDs.insert(mutationID)
        defer { mutatingItemIDs.remove(mutationID) }
        do {
            try remindersService.setCompleted(id: id, completed: completed)
            cachedReminders = cachedReminders.map { $0.id == id ? $0.withCompletion(completed) : $0 }
            rebuildVisibleAgendas(scope: scope)
            await load()
        } catch {
            errorMessage = "This task could not be updated. Pull to try again."
        }
    }

    func scopedIncompleteReminder(id: String) -> ReminderSnapshot? {
        guard remindersService.accessState == .granted else { return nil }

        let scope: ProfileScope
        do {
            scope = try currentScope()
        } catch {
            return nil
        }

        guard !scope.reminderListIDs.isEmpty,
              cachedScopeIdentity == scope.identity,
              let cached = cachedReminders.first(where: { $0.id == id }),
              scope.reminderListIDs.contains(cached.listID),
              let live = remindersService.reminder(id: id),
              scope.reminderListIDs.contains(live.listID),
              !live.isCompleted else { return nil }
        return live
    }

    private var shouldFilterLegacyCalendarResults: Bool {
        !usesLegacyScope || settings.calendarSelectionIsExplicit
    }

    private var shouldFilterLegacyReminderResults: Bool {
        !usesLegacyScope || settings.reminderSelectionIsExplicit
    }

    private func adopt(_ scope: ProfileScope) {
        let identityChanged = cachedScopeIdentity != scope.identity
        if identityChanged {
            cachedEvents = []
            cachedReminders = []
            cachedRoutines = []
            cachedRoutineCompletions = [:]
            sourceAccessNotices = []
            latestRefreshFailures = []
            errorMessage = nil
        } else if !usesLegacyScope {
            cachedEvents.removeAll { !scope.calendarIDs.contains($0.calendarID) }
            cachedReminders.removeAll { !scope.reminderListIDs.contains($0.listID) }
            cachedRoutines.removeAll { !scope.routineIDs.contains($0.id) }
            cachedRoutineCompletions = cachedRoutineCompletions.filter {
                scope.routineIDs.contains($0.key)
            }
        }

        cachedScopeIdentity = scope.identity
        cachedScope = scope
        isProfileEmpty = profileIsEmpty(scope)
        rebuildVisibleAgendas(scope: scope)
    }

    private func failScopeResolution() {
        cachedEvents = []
        cachedReminders = []
        cachedRoutines = []
        cachedRoutineCompletions = [:]
        cachedScopeIdentity = nil
        cachedScope = nil
        sourceAccessNotices = []
        latestRefreshFailures = []
        isProfileEmpty = false
        publishEmptyAgendas()
        errorMessage = "The selected profile could not be loaded. Try again."
    }

    private func profileIsEmpty(_ scope: ProfileScope) -> Bool {
        guard case .saved = scope.identity else { return false }
        return scope.calendarIDs.isEmpty
            && scope.reminderListIDs.isEmpty
            && scope.routineIDs.isEmpty
    }

    private func rebuildVisibleAgendas(scope: ProfileScope) {
        let visibleEvents: [CalendarEventSnapshot]
        let visibleReminders: [ReminderSnapshot]
        let visibleRoutines: [RoutineSnapshot]
        if usesLegacyScope {
            let descriptorCalendarIDs = Set(calendarService.calendars().map(\.id))
            let descriptorReminderIDs = Set(remindersService.lists().map(\.id))
            let calendarIDs = descriptorCalendarIDs.isEmpty
                ? Set(cachedEvents.map(\.calendarID))
                : descriptorCalendarIDs
            let reminderIDs = descriptorReminderIDs.isEmpty
                ? Set(cachedReminders.map(\.listID))
                : descriptorReminderIDs
            visibleEvents = cachedEvents.filter {
                settings.visibleCalendarIDs(availableIDs: calendarIDs).contains($0.calendarID)
            }
            visibleReminders = cachedReminders.filter {
                settings.visibleReminderListIDs(availableIDs: reminderIDs).contains($0.listID)
            }
            visibleRoutines = cachedRoutines
        } else {
            visibleEvents = cachedEvents.filter { scope.calendarIDs.contains($0.calendarID) }
            visibleReminders = cachedReminders.filter { scope.reminderListIDs.contains($0.listID) }
            visibleRoutines = cachedRoutines.filter { scope.routineIDs.contains($0.id) }
        }

        let days = visibleDays
        visibleAgendas = Dictionary(uniqueKeysWithValues: days.map { day in
            let completed = Set(visibleRoutines.filter {
                cachedRoutineCompletions[$0.id]?.contains(day) == true
            }.map(\.id))
            return (
                day,
                composer.compose(
                    day: day,
                    events: visibleEvents,
                    reminders: visibleReminders,
                    routines: visibleRoutines,
                    completedRoutineIDs: completed,
                    includeOverdueTasks: day == today,
                    calendar: systemCalendar
                )
            )
        })
        agenda = visibleAgendas[selectedDay] ?? DayAgenda(allDay: [], scheduled: [], priority: [])
        if displayMode == .week {
            weekPlanner = WeekPlannerBuilder(calendar: systemCalendar).build(
                days: days,
                agendas: visibleAgendas,
                events: visibleEvents,
                reminders: visibleReminders,
                selectedDay: selectedDay
            )
        } else {
            weekPlanner = .empty
        }
    }

    private func publishEmptyAgendas() {
        let empty = DayAgenda(allDay: [], scheduled: [], priority: [])
        let days = visibleDays
        visibleAgendas = Dictionary(uniqueKeysWithValues: days.map { ($0, empty) })
        agenda = empty
        weekPlanner = displayMode == .week
            ? WeekPlannerSnapshot(
                calendar: systemCalendar,
                days: days,
                allDayItems: [],
                timedItems: [],
                laterItems: [],
                eventDetailsByOccurrence: [:],
                startHour: 8,
                endHour: 18
            )
            : .empty
    }
}
