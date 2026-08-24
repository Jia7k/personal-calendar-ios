import Foundation
import Observation

enum TrayState: Equatable {
    case resting
    case expanded
}

@MainActor
@Observable
final class CalendarViewModel {
    var displayedMonth: LocalDay
    var selectedDay: LocalDay
    var trayState: TrayState = .resting
    private(set) var agenda = DayAgenda(allDay: [], scheduled: [], priority: [])
    private(set) var visibleAgendas: [LocalDay: DayAgenda] = [:]
    private(set) var errorMessage: String?
    private(set) var eventDraftOnFailure: EventDraft?
    private(set) var isLoading = false
    private(set) var deniedSourceMessages: [String] = []

    private var cachedEvents: [CalendarEventSnapshot] = []
    private var cachedReminders: [ReminderSnapshot] = []
    private var cachedRoutines: [RoutineSnapshot] = []
    private var cachedRoutineCompletions: [UUID: Set<LocalDay>] = [:]
    private let today: LocalDay
    private let calendarService: any CalendarServicing
    private let remindersService: any RemindersServicing
    private let routines: any RoutineRepository
    private let composer: AgendaComposer
    private let settings: AppSettingsStore
    private let systemCalendar: Calendar

    init(today: LocalDay, calendarService: any CalendarServicing, remindersService: any RemindersServicing, routines: any RoutineRepository, composer: AgendaComposer, settings: AppSettingsStore, systemCalendar: Calendar) {
        self.today = today
        self.calendarService = calendarService
        self.remindersService = remindersService
        self.routines = routines
        self.composer = composer
        self.settings = settings
        self.systemCalendar = systemCalendar
        displayedMonth = LocalDay(year: today.year, month: today.month, day: 1)
        selectedDay = today
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        deniedSourceMessages = []
        var encounteredFailure = false
        let cells = MonthGridBuilder(calendar: systemCalendar).days(containing: displayedMonth)
        let interval = DateInterval(start: cells.first!.day.startDate(in: systemCalendar), end: systemCalendar.date(byAdding: .day, value: 1, to: cells.last!.day.startDate(in: systemCalendar))!)

        if calendarService.accessState == .granted {
            do { cachedEvents = try calendarService.fetchEvents(in: interval, calendarIDs: settings.selectedCalendarIDs) }
            catch { encounteredFailure = true }
        } else {
            cachedEvents = []
            deniedSourceMessages.append("Calendar access is unavailable. Calendar events are hidden.")
        }

        if remindersService.accessState == .granted {
            do { cachedReminders = try await remindersService.fetchReminders(listIDs: settings.selectedReminderListIDs) }
            catch { encounteredFailure = true }
        } else {
            cachedReminders = []
            deniedSourceMessages.append("Reminders access is unavailable. Tasks are hidden.")
        }

        do {
            let refreshed = try routines.list(includeArchived: false)
            let completions = try Dictionary(uniqueKeysWithValues: refreshed.map { ($0.id, try routines.completedDays(routineID: $0.id)) })
            cachedRoutines = refreshed
            cachedRoutineCompletions = completions
        } catch { encounteredFailure = true }

        rebuildVisibleAgendas()
        errorMessage = encounteredFailure ? "Your schedule could not be refreshed. Try again." : nil
    }

    func select(_ day: LocalDay) async {
        selectedDay = day
        agenda = visibleAgendas[selectedDay] ?? DayAgenda(allDay: [], scheduled: [], priority: [])
    }

    func setTray(_ state: TrayState) { trayState = state }

    func showToday() async {
        selectedDay = today
        displayedMonth = LocalDay(year: today.year, month: today.month, day: 1)
        await load()
    }

    func moveMonth(by value: Int) async {
        let moved = systemCalendar.date(byAdding: .month, value: value, to: displayedMonth.startDate(in: systemCalendar))!
        displayedMonth = LocalDay(date: moved, calendar: systemCalendar)
        await load()
    }

    func createEvent(_ draft: EventDraft) async {
        do {
            _ = try calendarService.createEvent(draft)
            eventDraftOnFailure = nil
            await load()
        } catch {
            eventDraftOnFailure = draft
            errorMessage = "Your event was not saved. You can try again."
        }
    }

    private func rebuildVisibleAgendas() {
        let days = MonthGridBuilder(calendar: systemCalendar).days(containing: displayedMonth).map(\.day)
        visibleAgendas = Dictionary(uniqueKeysWithValues: days.map { day in
            let completed = Set(cachedRoutines.filter { cachedRoutineCompletions[$0.id]?.contains(day) == true }.map(\.id))
            return (day, composer.compose(day: day, events: cachedEvents, reminders: cachedReminders, routines: cachedRoutines, completedRoutineIDs: completed, includeOverdueTasks: day == today, calendar: systemCalendar))
        })
        agenda = visibleAgendas[selectedDay] ?? DayAgenda(allDay: [], scheduled: [], priority: [])
    }
}
