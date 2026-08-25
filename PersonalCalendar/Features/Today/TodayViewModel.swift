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

    private var cachedEvents: [CalendarEventSnapshot] = []
    private var cachedReminders: [ReminderSnapshot] = []
    private var cachedRoutines: [RoutineSnapshot] = []
    private var cachedRoutineDays: [UUID: Set<LocalDay>] = [:]
    private let calendar: any CalendarServicing
    private let reminders: any RemindersServicing
    private let routines: any RoutineRepository
    private let composer: AgendaComposer
    private let settings: AppSettingsStore
    private let calendarProvider: () -> Calendar
    private let now: () -> Date
    private var loadGeneration = 0
    private var reminderRefreshGeneration = 0

    init(
        calendar: any CalendarServicing,
        reminders: any RemindersServicing,
        routines: any RoutineRepository,
        composer: AgendaComposer,
        settings: AppSettingsStore,
        calendarProvider: @escaping () -> Calendar = { .current },
        now: @escaping () -> Date = Date.init
    ) {
        self.calendar = calendar
        self.reminders = reminders
        self.routines = routines
        self.composer = composer
        self.settings = settings
        self.calendarProvider = calendarProvider
        self.now = now
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
            do {
                let descriptorIDs = Set(calendar.calendars().map(\.id))
                let ids = descriptorIDs.isEmpty ? settings.selectedCalendarIDs : settings.visibleCalendarIDs(availableIDs: descriptorIDs)
                nextEvents = settings.calendarSelectionIsExplicit && ids.isEmpty ? [] : try calendar.fetchEvents(in: DateInterval(start: start, end: end), calendarIDs: ids)
            } catch {
                nextCalendarError = "Calendar events could not be refreshed. Pull to try again."
            }
        } else {
            nextEvents = []
        }
        _ = await refreshReminders(failureMessage: "Tasks could not be refreshed. Pull to try again.")
        do {
            let values = try routines.list(includeArchived: false)
            let days = try Dictionary(uniqueKeysWithValues: values.map { ($0.id, try routines.completedDays(routineID: $0.id)) })
            nextRoutines = values
            nextDays = days
        } catch {
            nextRoutinesError = "Routines could not be refreshed. Pull to try again."
        }
        guard generation == loadGeneration else { return }
        cachedEvents = nextEvents
        cachedRoutines = nextRoutines
        cachedRoutineDays = nextDays
        calendarError = nextCalendarError
        routinesError = nextRoutinesError
        showsCalendarPermissionCard = nextCalendarCard
        reconcileReminderState()
        compose(day: day, calendar: systemCalendar)
        hasLoaded = true
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
        reconcileReminderState()
        guard case let .reminder(id) = item.origin,
              item.allowsModification,
              !mutatingItemIDs.contains(item.id),
              let snapshot = writableSelectedReminder(id: id)
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
            compose(day: localDay, calendar: calendarProvider())
            _ = await refreshReminders(failureMessage: "Task changes were saved, but tasks could not be refreshed. Pull to try again.")
        } catch {
            remindersError = "This task could not be updated. Pull to try again."
            reconcileReminderState()
        }
    }

    func undoLastTaskCompletion() async {
        reconcileReminderState()
        guard var undo = latestTaskUndo,
              !undo.isPending,
              capturedUndoIsEligible(undo)
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
            compose(day: localDay, calendar: calendarProvider())
            _ = await refreshReminders(failureMessage: "Task changes were saved, but tasks could not be refreshed. Pull to try again.")
            if latestTaskUndo?.generation == undoGeneration { latestTaskUndo = nil }
        } catch {
            undo.isPending = false
            if latestTaskUndo?.generation == undoGeneration { latestTaskUndo = undo }
            remindersError = "This task could not be updated. Pull to try again."
            reconcileReminderState()
        }
    }

    func setRoutineCompleted(_ item: AgendaItem, completed: Bool) async {
        guard case let .routine(id, day) = item.origin else { return }
        mutatingItemIDs.insert(item.id)
        defer { mutatingItemIDs.remove(item.id) }
        do {
            try routines.setCompleted(routineID: id, day: day, completed: completed)
            if completed {
                cachedRoutineDays[id, default: []].insert(day)
            } else {
                cachedRoutineDays[id]?.remove(day)
            }
            compose(day: localDay, calendar: calendarProvider())
            do {
                let values = try routines.list(includeArchived: false)
                let days = try Dictionary(uniqueKeysWithValues: values.map { ($0.id, try routines.completedDays(routineID: $0.id)) })
                cachedRoutines = values
                cachedRoutineDays = days
                routinesError = nil
            } catch {
                routinesError = "Routine changes were saved, but routines could not be refreshed. Pull to try again."
            }
            compose(day: localDay, calendar: calendarProvider())
        } catch {
            routinesError = "This routine could not be updated. Pull to try again."
        }
    }

    private func compose(day: LocalDay, calendar: Calendar) {
        let descriptorCalendarIDs = Set(self.calendar.calendars().map(\.id))
        let descriptorReminderIDs = Set(self.reminders.lists().map(\.id))
        let calendarIDs = descriptorCalendarIDs.isEmpty ? Set(cachedEvents.map(\.calendarID)) : descriptorCalendarIDs
        let reminderIDs = descriptorReminderIDs.isEmpty ? Set(cachedReminders.map(\.listID)) : descriptorReminderIDs
        let events = cachedEvents.filter { settings.visibleCalendarIDs(availableIDs: calendarIDs).contains($0.calendarID) }
        let reminders = cachedReminders.filter { settings.visibleReminderListIDs(availableIDs: reminderIDs).contains($0.listID) }
        let completed = Set(cachedRoutines.filter { cachedRoutineDays[$0.id]?.contains(day) == true }.map(\.id))
        agenda = composer.compose(day: day, events: events, reminders: reminders, routines: cachedRoutines, completedRoutineIDs: completed, includeOverdueTasks: true, calendar: calendar)
    }

    private func refreshReminders(failureMessage: String) async -> ReminderRefreshOutcome {
        reminderRefreshGeneration += 1
        let generation = reminderRefreshGeneration
        let context = reminderContext()
        reconcileReminderState()
        guard context.access == .granted else {
            remindersError = nil
            return .unavailable
        }
        guard context.shouldFetch else {
            cachedReminders = []
            remindersError = nil
            reconcileReminderState()
            return .success
        }
        do {
            let refreshed = try await reminders.fetchReminders(listIDs: context.selectedIDs)
            guard generation == reminderRefreshGeneration, context == reminderContext() else {
                reconcileReminderState()
                return .stale
            }
            cachedReminders = refreshed
            remindersError = nil
            reconcileReminderState()
            return .success
        } catch {
            guard generation == reminderRefreshGeneration, context == reminderContext() else {
                reconcileReminderState()
                return .stale
            }
            remindersError = failureMessage
            reconcileReminderState()
            return .failure
        }
    }

    private func reminderContext() -> ReminderContext {
        let descriptors = reminders.lists()
        let descriptorIDs = Set(descriptors.map(\.id))
        let selectedIDs = descriptorIDs.isEmpty
            ? settings.selectedReminderListIDs
            : settings.visibleReminderListIDs(availableIDs: descriptorIDs)
        return ReminderContext(
            access: reminders.accessState,
            descriptorIDs: descriptorIDs,
            writableDescriptorIDs: Set(descriptors.filter(\.allowsContentModifications).map(\.id)),
            selectedIDs: selectedIDs,
            selectionIsExplicit: settings.reminderSelectionIsExplicit
        )
    }

    private func reconcileReminderState() {
        let context = reminderContext()
        showsRemindersPermissionCard = context.access != .granted
        guard context.access == .granted else {
            cachedReminders = []
            remindersError = nil
            latestTaskUndo = nil
            compose(day: localDay, calendar: calendarProvider())
            return
        }
        let availableIDs = context.descriptorIDs.isEmpty ? Set(cachedReminders.map(\.listID)) : context.descriptorIDs
        let selectedIDs = context.descriptorIDs.isEmpty && !context.selectionIsExplicit
            ? availableIDs
            : settings.visibleReminderListIDs(availableIDs: availableIDs)
        cachedReminders = cachedReminders.filter { selectedIDs.contains($0.listID) }
        if let undo = latestTaskUndo, !capturedUndoIsEligible(undo, context: context) {
            latestTaskUndo = nil
        }
        compose(day: localDay, calendar: calendarProvider())
    }

    private func writableSelectedReminder(id: String) -> ReminderSnapshot? {
        guard reminders.accessState == .granted,
              let value = cachedReminders.first(where: { $0.id == id }),
              value.allowsModification
        else {
            if latestTaskUndo?.rawID == id { latestTaskUndo = nil }
            return nil
        }
        let descriptorIDs = Set(reminders.lists().map(\.id))
        let availableIDs = descriptorIDs.isEmpty ? Set(cachedReminders.map(\.listID)) : descriptorIDs
        let selectedIDs = descriptorIDs.isEmpty && !settings.reminderSelectionIsExplicit
            ? availableIDs
            : settings.visibleReminderListIDs(availableIDs: availableIDs)
        guard availableIDs.contains(value.listID), selectedIDs.contains(value.listID) else {
            if latestTaskUndo?.rawID == id { latestTaskUndo = nil }
            return nil
        }
        return value
    }

    private func capturedUndoIsEligible(_ undo: TaskUndoState, context: ReminderContext? = nil) -> Bool {
        let context = context ?? reminderContext()
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

    private func invalidateOlderReminderWork() {
        loadGeneration += 1
        reminderRefreshGeneration += 1
        isLoading = false
    }
}
