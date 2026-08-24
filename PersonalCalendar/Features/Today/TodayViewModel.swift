import Foundation
import Observation

struct TaskUndoState: Equatable {
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
        isLoading = true
        let systemCalendar = calendarProvider()
        let day = LocalDay(date: now(), calendar: systemCalendar)
        let start = day.startDate(in: systemCalendar)
        let end = systemCalendar.date(byAdding: .day, value: 1, to: start)!
        showsCalendarPermissionCard = calendar.accessState != .granted
        showsRemindersPermissionCard = reminders.accessState != .granted
        if calendar.accessState == .granted {
            do {
                cachedEvents = try calendar.fetchEvents(in: DateInterval(start: start, end: end), calendarIDs: settings.selectedCalendarIDs)
                calendarError = nil
            } catch {
                calendarError = "Calendar events could not be refreshed. Pull to try again."
            }
        } else {
            cachedEvents = []
            calendarError = nil
        }
        if reminders.accessState == .granted {
            do {
                cachedReminders = try await reminders.fetchReminders(listIDs: settings.selectedReminderListIDs)
                remindersError = nil
            } catch {
                remindersError = "Tasks could not be refreshed. Pull to try again."
            }
        } else {
            cachedReminders = []
            remindersError = nil
        }
        do {
            let values = try routines.list(includeArchived: false)
            let days = try Dictionary(uniqueKeysWithValues: values.map { ($0.id, try routines.completedDays(routineID: $0.id)) })
            cachedRoutines = values
            cachedRoutineDays = days
            routinesError = nil
        } catch {
            routinesError = "Routines could not be refreshed. Pull to try again."
        }
        compose(day: day, calendar: systemCalendar)
        hasLoaded = true
        isLoading = false
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
                latestTaskUndo = TaskUndoState(title: snapshot.title, rawID: id, snapshot: snapshot)
            }
            compose(day: localDay, calendar: calendarProvider())
            do {
                cachedReminders = try await reminders.fetchReminders(listIDs: settings.selectedReminderListIDs)
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
        guard var undo = latestTaskUndo else { return }
        undo.isPending = true
        latestTaskUndo = undo
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
            latestTaskUndo = nil
            do {
                cachedReminders = try await reminders.fetchReminders(listIDs: settings.selectedReminderListIDs)
                remindersError = nil
            } catch {
                remindersError = "Task changes were saved, but tasks could not be refreshed. Pull to try again."
            }
            compose(day: localDay, calendar: calendarProvider())
        } catch {
            undo.isPending = false
            latestTaskUndo = undo
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
        let events = cachedEvents.filter { settings.selectedCalendarIDs.isEmpty || settings.selectedCalendarIDs.contains($0.calendarID) }
        let reminders = cachedReminders.filter { settings.selectedReminderListIDs.isEmpty || settings.selectedReminderListIDs.contains($0.listID) }
        let completed = Set(cachedRoutines.filter { cachedRoutineDays[$0.id]?.contains(day) == true }.map(\.id))
        agenda = composer.compose(day: day, events: events, reminders: reminders, routines: cachedRoutines, completedRoutineIDs: completed, includeOverdueTasks: true, calendar: calendar)
    }
}
