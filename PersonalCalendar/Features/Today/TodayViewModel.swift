import Foundation
import Observation

struct TaskUndoState: Equatable {
    let generation: UUID
    let title: String
    let rawID: String
    let snapshot: ReminderSnapshot
    var isPending = false
}

@MainActor
@Observable
final class TodayViewModel {
    private struct ReminderContext: Equatable {
        let scopeIdentity: ProfileIdentity
        let access: AccessState
        let descriptorIDs: Set<String>
        let writableDescriptorIDs: Set<String>
        let selectedIDs: Set<String>
        let selectionIsExplicit: Bool

        var shouldFetch: Bool { access == .granted && !(selectionIsExplicit && selectedIDs.isEmpty) }
    }

    private enum ReminderRefreshOutcome: Equatable { case success, failure, stale, unavailable }

    private(set) var agenda = DayAgenda(allDay: [], scheduled: [], priority: [])
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    private(set) var calendarError: String?
    private(set) var remindersError: String?
    private(set) var routinesError: String?
    private(set) var mutatingItemIDs: Set<String> = []
    private(set) var showsCalendarPermissionCard = false
    private(set) var showsRemindersPermissionCard = false
    private(set) var latestTaskUndo: TaskUndoState?
    private(set) var isProfileEmpty = false
    private(set) var nextUp: NextUpSnapshot?
    private(set) var nextUpReferenceDate = Date.distantPast

    private var cachedEvents: [CalendarEventSnapshot] = []
    private var cachedReminders: [ReminderSnapshot] = []
    private var cachedRoutines: [RoutineSnapshot] = []
    private var cachedRoutineDays: [UUID: Set<LocalDay>] = [:]
    private var nextUpEvents: [CalendarEventSnapshot] = []
    private var nextUpReminders: [ReminderSnapshot] = []
    private var cachedScopeIdentity: ProfileIdentity?
    private var cachedScope: ProfileScope?
    private let calendar: any CalendarServicing
    private let reminders: any RemindersServicing
    private let routines: any RoutineRepository
    private let composer: AgendaComposer
    private let settings: AppSettingsStore
    private let currentScope: @MainActor () throws -> ProfileScope
    private let usesLegacyScope: Bool
    private let calendarProvider: () -> Calendar
    private let now: () -> Date
    private let rescheduleNotifications: @MainActor @Sendable () async -> Void
    private var loadGeneration = 0
    private var reminderRefreshGeneration = 0

    func refreshNextUp() {
        let referenceDate = now()
        nextUpReferenceDate = referenceDate
        nextUp = NextUpBuilder().build(
            agenda: agenda,
            events: nextUpEvents,
            reminders: nextUpReminders,
            now: referenceDate,
            calendar: calendarProvider()
        )
    }

    init(
        calendar: any CalendarServicing,
        reminders: any RemindersServicing,
        routines: any RoutineRepository,
        composer: AgendaComposer,
        settings: AppSettingsStore,
        calendarProvider: @escaping () -> Calendar = { .current },
        now: @escaping () -> Date = Date.init,
        rescheduleNotifications: @escaping @MainActor @Sendable () async -> Void = {}
    ) {
        self.calendar = calendar
        self.reminders = reminders
        self.routines = routines
        self.composer = composer
        self.settings = settings
        currentScope = {
            let calendarDescriptorIDs = Set(calendar.calendars().map(\.id))
            let reminderDescriptorIDs = Set(reminders.lists().map(\.id))
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
        self.calendarProvider = calendarProvider
        self.now = now
        self.rescheduleNotifications = rescheduleNotifications
    }

    init(
        calendar: any CalendarServicing,
        reminders: any RemindersServicing,
        routines: any RoutineRepository,
        composer: AgendaComposer,
        settings: AppSettingsStore,
        currentScope: @escaping @MainActor () throws -> ProfileScope,
        calendarProvider: @escaping () -> Calendar = { .current },
        now: @escaping () -> Date = Date.init,
        rescheduleNotifications: @escaping @MainActor @Sendable () async -> Void = {}
    ) {
        self.calendar = calendar
        self.reminders = reminders
        self.routines = routines
        self.composer = composer
        self.settings = settings
        self.currentScope = currentScope
        usesLegacyScope = false
        self.calendarProvider = calendarProvider
        self.now = now
        self.rescheduleNotifications = rescheduleNotifications
    }

    var localDay: LocalDay { LocalDay(date: now(), calendar: calendarProvider()) }
    var calendarAccessState: AccessState { calendar.accessState }
    var remindersAccessState: AccessState { reminders.accessState }
    var isGenuinelyEmpty: Bool {
        hasLoaded && calendarError == nil && remindersError == nil && routinesError == nil
            && !showsCalendarPermissionCard && !showsRemindersPermissionCard
            && agenda.allDay.isEmpty && agenda.scheduled.isEmpty && agenda.priority.isEmpty
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
        var nextRoutines = cachedRoutines
        var nextDays = cachedRoutineDays
        var nextCalendarError: String?
        var nextRoutinesError: String?
        let systemCalendar = calendarProvider()
        let day = LocalDay(date: now(), calendar: systemCalendar)
        let start = day.startDate(in: systemCalendar)
        let end = systemCalendar.date(byAdding: .day, value: 1, to: start)!
        let nextCalendarCard = calendar.accessState != .granted
        if calendar.accessState == .granted {
            let skipsFetch = scope.calendarIDs.isEmpty
                && (!usesLegacyScope || settings.calendarSelectionIsExplicit)
            if skipsFetch {
                nextEvents = []
            } else {
                do {
                    let fetched = try calendar.fetchEvents(
                        in: DateInterval(start: start, end: end),
                        calendarIDs: scope.calendarIDs
                    )
                    nextEvents = shouldFilterLegacyCalendarResults
                        ? fetched.filter { scope.calendarIDs.contains($0.calendarID) }
                        : fetched
                } catch {
                    nextCalendarError = "Calendar events could not be refreshed. Pull to try again."
                }
            }
        } else {
            nextEvents = []
        }
        _ = await refreshReminders(
            scope: scope,
            failureMessage: "Tasks could not be refreshed. Pull to try again."
        )
        if !usesLegacyScope && scope.routineIDs.isEmpty {
            nextRoutines = []
            nextDays = [:]
        } else {
            do {
                let values = try routines.list(includeArchived: false)
                let scoped = usesLegacyScope
                    ? values
                    : values.filter { scope.routineIDs.contains($0.id) }
                let days = try Dictionary(uniqueKeysWithValues: scoped.map {
                    ($0.id, try routines.completedDays(routineID: $0.id))
                })
                nextRoutines = scoped
                nextDays = days
            } catch {
                nextRoutinesError = "Routines could not be refreshed. Pull to try again."
            }
        }
        guard generation == loadGeneration else { return }
        cachedEvents = nextEvents
        cachedRoutines = nextRoutines
        cachedRoutineDays = nextDays
        cachedScope = scope
        calendarError = nextCalendarError
        routinesError = nextRoutinesError
        showsCalendarPermissionCard = nextCalendarCard
        reconcileReminderState(scope: scope)
        compose(day: day, calendar: systemCalendar, scope: scope)
        hasLoaded = true
    }

    func refreshForExternalChange() async {
        await load()
    }

    /// Host-owned post-editor refresh. A failed refresh never asks the editor to repeat its write.
    func refreshAfterEventEditorCommit(_ commit: EventEditorCommit) async {
        await load()
        guard calendarError != nil else { return }
        calendarError = switch commit {
        case .deleted: "Your event was deleted, but calendar events could not be refreshed. Pull to try again."
        case .created, .updated: "Your event was saved, but calendar events could not be refreshed. Pull to try again."
        }
    }

    /// Host-owned post-editor refresh. A failed refresh never asks the editor to repeat its write.
    func refreshAfterTaskEditorCommit(_ commit: TaskEditorCommit) async {
        await load()
        guard remindersError != nil else { return }
        remindersError = switch commit {
        case .deleted: "Your task was deleted, but tasks could not be refreshed. Pull to try again."
        case .created, .updated: "Your task was saved, but tasks could not be refreshed. Pull to try again."
        }
    }

    /// Host-owned post-Quick-Entry reconciliation. It never repeats the provider write.
    func refreshAfterQuickEntry(_ outcome: QuickEntrySaveOutcome) async {
        await load()
        switch outcome {
        case .event where calendarError != nil:
            calendarError = "Your event was saved, but calendar events could not be refreshed. Pull to try again."
        case .task where remindersError != nil:
            remindersError = "Your task was saved, but tasks could not be refreshed. Pull to try again."
        case .routine where routinesError != nil:
            routinesError = "Your routine was saved, but routines could not be refreshed. Pull to try again."
        case .event, .task, .routine:
            break
        }
    }

    func setTaskCompleted(_ item: AgendaItem, completed: Bool) async {
        let scope: ProfileScope
        do {
            scope = try currentScope()
        } catch {
            failScopeResolution()
            return
        }
        adopt(scope)
        reconcileReminderState(scope: scope)
        guard case let .reminder(id) = item.origin,
              item.allowsModification,
              !mutatingItemIDs.contains(item.id),
              let snapshot = writableSelectedReminder(id: id, scope: scope)
        else { return }
        invalidateOlderReminderWork()
        mutatingItemIDs.insert(item.id)
        defer { mutatingItemIDs.remove(item.id) }
        do {
            try reminders.setCompleted(id: id, completed: completed)
            cachedReminders = cachedReminders.map { value in
                guard value.id == id else { return value }
                return value.withCompletion(completed)
            }
            if completed {
                latestTaskUndo = TaskUndoState(generation: UUID(), title: snapshot.title, rawID: id, snapshot: snapshot)
            } else if latestTaskUndo?.rawID == id {
                latestTaskUndo = nil
            }
            compose(day: localDay, calendar: calendarProvider(), scope: scope)
            _ = await refreshReminders(
                scope: scope,
                failureMessage: "Task changes were saved, but tasks could not be refreshed. Pull to try again."
            )
        } catch {
            remindersError = "This task could not be updated. Pull to try again."
            reconcileReminderState(scope: scope)
        }
    }

    func undoLastTaskCompletion() async {
        let scope: ProfileScope
        do {
            scope = try currentScope()
        } catch {
            failScopeResolution()
            return
        }
        adopt(scope)
        reconcileReminderState(scope: scope)
        let context = reminderContext(scope: scope)
        guard var undo = latestTaskUndo,
              !undo.isPending,
              capturedUndoIsEligible(undo, context: context)
        else { return }
        let undoGeneration = undo.generation
        invalidateOlderReminderWork()
        undo.isPending = true
        if latestTaskUndo?.generation == undoGeneration { latestTaskUndo = undo }
        do {
            try reminders.setCompleted(id: undo.rawID, completed: false)
            let restored = undo.snapshot
            let restoredSnapshot = restored.withCompletion(false)
            cachedReminders = cachedReminders.map { value in
                guard value.id == undo.rawID else { return value }
                return restoredSnapshot
            }
            if !cachedReminders.contains(where: { $0.id == undo.rawID }) { cachedReminders.append(restoredSnapshot) }
            compose(day: localDay, calendar: calendarProvider(), scope: scope)
            _ = await refreshReminders(
                scope: scope,
                failureMessage: "Task changes were saved, but tasks could not be refreshed. Pull to try again."
            )
            if latestTaskUndo?.generation == undoGeneration { latestTaskUndo = nil }
        } catch {
            undo.isPending = false
            if latestTaskUndo?.generation == undoGeneration { latestTaskUndo = undo }
            remindersError = "This task could not be updated. Pull to try again."
            reconcileReminderState(scope: scope)
        }
    }

    func setRoutineCompleted(_ item: AgendaItem, completed: Bool) async {
        let scope: ProfileScope
        do {
            scope = try currentScope()
        } catch {
            failScopeResolution()
            return
        }
        adopt(scope)
        guard case let .routine(id, day) = item.origin,
              cachedRoutines.contains(where: { $0.id == id }),
              usesLegacyScope || scope.routineIDs.contains(id)
        else { return }
        invalidateOlderReminderWork()
        mutatingItemIDs.insert(item.id)
        defer { mutatingItemIDs.remove(item.id) }
        do {
            try routines.setCompleted(routineID: id, day: day, completed: completed)
            if completed {
                cachedRoutineDays[id, default: []].insert(day)
            } else {
                cachedRoutineDays[id]?.remove(day)
            }
            compose(day: localDay, calendar: calendarProvider(), scope: scope)
            do {
                let values = try routines.list(includeArchived: false)
                let scoped = usesLegacyScope
                    ? values
                    : values.filter { scope.routineIDs.contains($0.id) }
                let days = try Dictionary(uniqueKeysWithValues: scoped.map {
                    ($0.id, try routines.completedDays(routineID: $0.id))
                })
                cachedRoutines = scoped
                cachedRoutineDays = days
                routinesError = nil
            } catch {
                routinesError = "Routine changes were saved, but routines could not be refreshed. Pull to try again."
            }
            compose(day: localDay, calendar: calendarProvider(), scope: scope)
            await rescheduleNotifications()
        } catch {
            routinesError = "This routine could not be updated. Pull to try again."
        }
    }

    private var shouldFilterLegacyCalendarResults: Bool {
        !usesLegacyScope || settings.calendarSelectionIsExplicit
    }

    private func compose(day: LocalDay, calendar: Calendar, scope: ProfileScope) {
        let events: [CalendarEventSnapshot]
        let reminderSnapshots: [ReminderSnapshot]
        let routineSnapshots: [RoutineSnapshot]
        if usesLegacyScope {
            let descriptorCalendarIDs = Set(self.calendar.calendars().map(\.id))
            let descriptorReminderIDs = Set(self.reminders.lists().map(\.id))
            let calendarIDs = descriptorCalendarIDs.isEmpty
                ? Set(cachedEvents.map(\.calendarID))
                : descriptorCalendarIDs
            let reminderIDs = descriptorReminderIDs.isEmpty
                ? Set(cachedReminders.map(\.listID))
                : descriptorReminderIDs
            events = cachedEvents.filter {
                settings.visibleCalendarIDs(availableIDs: calendarIDs).contains($0.calendarID)
            }
            reminderSnapshots = cachedReminders.filter {
                settings.visibleReminderListIDs(availableIDs: reminderIDs).contains($0.listID)
            }
            routineSnapshots = cachedRoutines
        } else {
            events = cachedEvents.filter { scope.calendarIDs.contains($0.calendarID) }
            reminderSnapshots = cachedReminders.filter {
                scope.reminderListIDs.contains($0.listID)
            }
            routineSnapshots = cachedRoutines.filter { scope.routineIDs.contains($0.id) }
        }
        let completed = Set(routineSnapshots.filter {
            cachedRoutineDays[$0.id]?.contains(day) == true
        }.map(\.id))
        agenda = composer.compose(
            day: day,
            events: events,
            reminders: reminderSnapshots,
            routines: routineSnapshots,
            completedRoutineIDs: completed,
            includeOverdueTasks: true,
            calendar: calendar
        )
        nextUpEvents = events
        nextUpReminders = reminderSnapshots
        refreshNextUp()
    }

    private func refreshReminders(
        scope: ProfileScope,
        failureMessage: String
    ) async -> ReminderRefreshOutcome {
        reminderRefreshGeneration += 1
        let generation = reminderRefreshGeneration
        let context = reminderContext(scope: scope)
        reconcileReminderState(scope: scope)
        guard context.access == .granted else {
            remindersError = nil
            return .unavailable
        }
        guard context.shouldFetch else {
            cachedReminders = []
            remindersError = nil
            reconcileReminderState(scope: scope)
            return .success
        }
        do {
            let refreshed = try await reminders.fetchReminders(listIDs: context.selectedIDs)
            guard generation == reminderRefreshGeneration,
                  context == reminderContext(scope: scope) else {
                reconcileCachedReminderState()
                return .stale
            }
            cachedReminders = shouldFilterReminderResults(context: context)
                ? refreshed.filter { context.selectedIDs.contains($0.listID) }
                : refreshed
            remindersError = nil
            reconcileReminderState(scope: scope)
            return .success
        } catch {
            guard generation == reminderRefreshGeneration,
                  context == reminderContext(scope: scope) else {
                reconcileCachedReminderState()
                return .stale
            }
            remindersError = failureMessage
            reconcileReminderState(scope: scope)
            return .failure
        }
    }

    private func reminderContext(scope: ProfileScope) -> ReminderContext {
        let descriptors = reminders.lists()
        let descriptorIDs = Set(descriptors.map(\.id))
        let selectedIDs: Set<String>
        let selectionIsExplicit: Bool
        if usesLegacyScope {
            selectedIDs = descriptorIDs.isEmpty
                ? settings.selectedReminderListIDs
                : settings.visibleReminderListIDs(availableIDs: descriptorIDs)
            selectionIsExplicit = settings.reminderSelectionIsExplicit
        } else {
            selectedIDs = scope.reminderListIDs
            selectionIsExplicit = true
        }
        return ReminderContext(
            scopeIdentity: scope.identity,
            access: reminders.accessState,
            descriptorIDs: descriptorIDs,
            writableDescriptorIDs: Set(descriptors.filter(\.allowsContentModifications).map(\.id)),
            selectedIDs: selectedIDs,
            selectionIsExplicit: selectionIsExplicit
        )
    }

    private func reconcileReminderState(scope: ProfileScope) {
        let context = reminderContext(scope: scope)
        showsRemindersPermissionCard = context.access != .granted
        guard context.access == .granted else {
            cachedReminders = []
            remindersError = nil
            latestTaskUndo = nil
            compose(day: localDay, calendar: calendarProvider(), scope: scope)
            return
        }
        let availableIDs = context.descriptorIDs.isEmpty
            ? Set(cachedReminders.map(\.listID))
            : context.descriptorIDs
        let selectedIDs: Set<String>
        if usesLegacyScope {
            selectedIDs = context.descriptorIDs.isEmpty && !context.selectionIsExplicit
                ? availableIDs
                : settings.visibleReminderListIDs(availableIDs: availableIDs)
        } else {
            selectedIDs = scope.reminderListIDs
        }
        cachedReminders = cachedReminders.filter { selectedIDs.contains($0.listID) }
        if let undo = latestTaskUndo, !capturedUndoIsEligible(undo, context: context) {
            latestTaskUndo = nil
        }
        compose(day: localDay, calendar: calendarProvider(), scope: scope)
    }

    private func reconcileCachedReminderState() {
        guard let cachedScope else { return }
        reconcileReminderState(scope: cachedScope)
    }

    private func shouldFilterReminderResults(context: ReminderContext) -> Bool {
        !usesLegacyScope || context.selectionIsExplicit || !context.selectedIDs.isEmpty
    }

    private func writableSelectedReminder(
        id: String,
        scope: ProfileScope
    ) -> ReminderSnapshot? {
        guard reminders.accessState == .granted,
              let value = cachedReminders.first(where: { $0.id == id }),
              value.allowsModification
        else {
            if latestTaskUndo?.rawID == id { latestTaskUndo = nil }
            return nil
        }
        let context = reminderContext(scope: scope)
        let availableIDs = context.descriptorIDs.isEmpty
            ? Set(cachedReminders.map(\.listID))
            : context.descriptorIDs
        let selectedIDs: Set<String>
        if usesLegacyScope {
            selectedIDs = context.descriptorIDs.isEmpty && !context.selectionIsExplicit
                ? availableIDs
                : settings.visibleReminderListIDs(availableIDs: availableIDs)
        } else {
            selectedIDs = scope.reminderListIDs
        }
        guard availableIDs.contains(value.listID),
              (context.writableDescriptorIDs.contains(value.listID)
                  || (usesLegacyScope && context.descriptorIDs.isEmpty)),
              selectedIDs.contains(value.listID) else {
            if latestTaskUndo?.rawID == id { latestTaskUndo = nil }
            return nil
        }
        return value
    }

    private func capturedUndoIsEligible(
        _ undo: TaskUndoState,
        context: ReminderContext
    ) -> Bool {
        guard context.access == .granted,
              undo.snapshot.allowsModification,
              context.descriptorIDs.contains(undo.snapshot.listID),
              context.writableDescriptorIDs.contains(undo.snapshot.listID),
              context.selectedIDs.contains(undo.snapshot.listID)
        else { return false }
        guard let authoritative = cachedReminders.first(where: { $0.id == undo.rawID }) else {
            return true
        }
        return authoritative.listID == undo.snapshot.listID
            && authoritative.allowsModification
            && (authoritative.isCompleted || undo.isPending)
    }

    private func adopt(_ scope: ProfileScope) {
        let identityChanged = cachedScopeIdentity != scope.identity
        if identityChanged {
            cachedEvents = []
            cachedReminders = []
            cachedRoutines = []
            cachedRoutineDays = [:]
            calendarError = nil
            remindersError = nil
            routinesError = nil
            latestTaskUndo = nil
        } else if !usesLegacyScope {
            cachedEvents.removeAll { !scope.calendarIDs.contains($0.calendarID) }
            cachedReminders.removeAll { !scope.reminderListIDs.contains($0.listID) }
            cachedRoutines.removeAll { !scope.routineIDs.contains($0.id) }
            cachedRoutineDays = cachedRoutineDays.filter { scope.routineIDs.contains($0.key) }
            if let undo = latestTaskUndo,
               !scope.reminderListIDs.contains(undo.snapshot.listID) {
                latestTaskUndo = nil
            }
        }

        cachedScopeIdentity = scope.identity
        cachedScope = scope
        isProfileEmpty = profileIsEmpty(scope)
        compose(day: localDay, calendar: calendarProvider(), scope: scope)
    }

    private func failScopeResolution() {
        cachedEvents = []
        cachedReminders = []
        cachedRoutines = []
        cachedRoutineDays = [:]
        cachedScopeIdentity = nil
        cachedScope = nil
        latestTaskUndo = nil
        isProfileEmpty = false
        showsCalendarPermissionCard = calendar.accessState != .granted
        showsRemindersPermissionCard = reminders.accessState != .granted
        agenda = DayAgenda(allDay: [], scheduled: [], priority: [])
        nextUp = nil
        nextUpEvents = []
        nextUpReminders = []
        calendarError = "The selected profile could not be loaded. Try again."
        remindersError = nil
        routinesError = nil
        hasLoaded = true
    }

    private func profileIsEmpty(_ scope: ProfileScope) -> Bool {
        guard case .saved = scope.identity else { return false }
        return scope.calendarIDs.isEmpty
            && scope.reminderListIDs.isEmpty
            && scope.routineIDs.isEmpty
    }

    private func invalidateOlderReminderWork() {
        loadGeneration += 1
        reminderRefreshGeneration += 1
        isLoading = false
    }
}
