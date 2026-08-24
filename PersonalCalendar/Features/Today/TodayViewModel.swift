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
        var nextReminders = cachedReminders
        var nextRoutines = cachedRoutines
        var nextDays = cachedRoutineDays
        var nextCalendarError: String?
        var nextRemindersError: String?
        var nextRoutinesError: String?
        let systemCalendar = calendarProvider()
        let day = LocalDay(date: now(), calendar: systemCalendar)
        let start = day.startDate(in: systemCalendar)
        let end = systemCalendar.date(byAdding: .day, value: 1, to: start)!
        let nextCalendarCard = calendar.accessState != .granted
        let nextRemindersCard = reminders.accessState != .granted
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
        if reminders.accessState == .granted {
            do {
                let descriptorIDs = Set(reminders.lists().map(\.id))
                let ids = descriptorIDs.isEmpty ? settings.selectedReminderListIDs : settings.visibleReminderListIDs(availableIDs: descriptorIDs)
                nextReminders = settings.reminderSelectionIsExplicit && ids.isEmpty ? [] : try await reminders.fetchReminders(listIDs: ids)
            } catch {
                nextRemindersError = "Tasks could not be refreshed. Pull to try again."
            }
        } else {
            nextReminders = []
        }
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
        cachedReminders = nextReminders
        cachedRoutines = nextRoutines
        cachedRoutineDays = nextDays
        calendarError = nextCalendarError
        remindersError = nextRemindersError
        routinesError = nextRoutinesError
        showsCalendarPermissionCard = nextCalendarCard
        showsRemindersPermissionCard = nextRemindersCard
        compose(day: day, calendar: systemCalendar)
        hasLoaded = true
    }

    func setTaskCompleted(_ item: AgendaItem, completed: Bool) async {
        guard case let .reminder(id) = item.origin, item.allowsModification else { return }
        mutatingItemIDs.insert(item.id)
        defer { mutatingItemIDs.remove(item.id) }
        do {
            try reminders.setCompleted(id: id, completed: completed)
            cachedReminders = cachedReminders.map { value in
                guard value.id == id else { return value }
                return ReminderSnapshot(id: value.id, title: value.title, notes: value.notes, dueDate: value.dueDate, dueHasTime: value.dueHasTime, priority: value.priority, listID: value.listID, listTitle: value.listTitle, isCompleted: completed, allowsModification: value.allowsModification, hasRecurrence: value.hasRecurrence)
            }
            if completed, let snapshot = cachedReminders.first(where: { $0.id == id }) {
                latestTaskUndo = TaskUndoState(generation: UUID(), title: snapshot.title, rawID: id, snapshot: snapshot)
            }
            compose(day: localDay, calendar: calendarProvider())
            do {
                let descriptorIDs = Set(reminders.lists().map(\.id))
                let ids = descriptorIDs.isEmpty ? settings.selectedReminderListIDs : settings.visibleReminderListIDs(availableIDs: descriptorIDs)
                cachedReminders = settings.reminderSelectionIsExplicit && ids.isEmpty ? [] : try await reminders.fetchReminders(listIDs: ids)
                remindersError = nil
            } catch {
                remindersError = "Task changes were saved, but tasks could not be refreshed. Pull to try again."
            }
            compose(day: localDay, calendar: calendarProvider())
        } catch {
            remindersError = "This task could not be updated. Pull to try again."
        }
    }

    func undoLastTaskCompletion() async {
        guard var undo = latestTaskUndo, !undo.isPending else { return }
        let generation = undo.generation
        undo.isPending = true
        if latestTaskUndo?.generation == generation { latestTaskUndo = undo }
        do {
            try reminders.setCompleted(id: undo.rawID, completed: false)
            let restored = undo.snapshot
            let restoredSnapshot = ReminderSnapshot(id: restored.id, title: restored.title, notes: restored.notes, dueDate: restored.dueDate, dueHasTime: restored.dueHasTime, priority: restored.priority, listID: restored.listID, listTitle: restored.listTitle, isCompleted: false, allowsModification: restored.allowsModification, hasRecurrence: restored.hasRecurrence)
            cachedReminders = cachedReminders.map { value in
                guard value.id == undo.rawID else { return value }
                return restoredSnapshot
            }
            if !cachedReminders.contains(where: { $0.id == undo.rawID }) { cachedReminders.append(restoredSnapshot) }
            compose(day: localDay, calendar: calendarProvider())
            do {
                let descriptorIDs = Set(reminders.lists().map(\.id))
                let ids = descriptorIDs.isEmpty ? settings.selectedReminderListIDs : settings.visibleReminderListIDs(availableIDs: descriptorIDs)
                let refreshed = settings.reminderSelectionIsExplicit && ids.isEmpty ? [] : try await reminders.fetchReminders(listIDs: ids)
                guard latestTaskUndo?.generation == generation else { return }
                cachedReminders = refreshed
                remindersError = nil
            } catch {
                remindersError = "Task changes were saved, but tasks could not be refreshed. Pull to try again."
            }
            compose(day: localDay, calendar: calendarProvider())
            if latestTaskUndo?.generation == generation { latestTaskUndo = nil }
        } catch {
            undo.isPending = false
            if latestTaskUndo?.generation == generation { latestTaskUndo = undo }
            remindersError = "This task could not be updated. Pull to try again."
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
}
