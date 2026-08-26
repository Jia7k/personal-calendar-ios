import Foundation
import Observation

struct CalendarSearchNotice: Identifiable, Equatable, Sendable {
    enum Source: Hashable, Sendable {
        case calendar
        case reminders
        case routines
    }

    let source: Source
    let message: String
    let accessState: AccessState?

    init(source: Source, message: String, accessState: AccessState? = nil) {
        self.source = source
        self.message = message
        self.accessState = accessState
    }

    var id: Source { source }

    var canOpenSettings: Bool {
        accessState == .denied || accessState == .notDetermined
    }

    var settingsActionIdentifier: String? {
        switch source {
        case .calendar: "calendar-permission-settings"
        case .reminders: "reminders-permission-settings"
        case .routines: nil
        }
    }
}

@MainActor
@Observable
final class CalendarSearchViewModel {
    var query = "" {
        didSet { scheduleSearch() }
    }

    private(set) var sections: CalendarSearchSections = .empty
    private(set) var isLoading = false
    private(set) var notices: [CalendarSearchNotice] = []
    private(set) var isProfileEmpty = false

    @ObservationIgnored private let calendarService: any CalendarServicing
    @ObservationIgnored private let remindersService: any RemindersServicing
    @ObservationIgnored private let routines: any RoutineRepository
    @ObservationIgnored private let categories: any CategoryRepository
    @ObservationIgnored private let currentScope: @MainActor () throws -> ProfileScope
    @ObservationIgnored private let matcher: CalendarSearchMatcher
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let debounce: Duration
    @ObservationIgnored private var searchTask: Task<Void, Never>?

    private var corpus: [CalendarSearchResult] = []
    private var confirmedEvents: [CalendarEventSnapshot] = []
    private var confirmedReminders: [ReminderSnapshot] = []
    private var confirmedRoutines: [RoutineSnapshot] = []
    private var confirmedCategories: [CategorySnapshot] = []
    private var cachedScope: ProfileScope?
    private var loadGeneration = 0

    init(
        calendarService: any CalendarServicing,
        remindersService: any RemindersServicing,
        routines: any RoutineRepository,
        categories: any CategoryRepository,
        currentScope: @escaping @MainActor () throws -> ProfileScope,
        calendar: Calendar,
        locale: Locale,
        now: @escaping () -> Date,
        debounce: Duration = .milliseconds(250)
    ) {
        self.calendarService = calendarService
        self.remindersService = remindersService
        self.routines = routines
        self.categories = categories
        self.currentScope = currentScope
        self.calendar = calendar
        matcher = CalendarSearchMatcher(calendar: calendar, locale: locale)
        self.now = now
        self.debounce = debounce
    }

    func load() async {
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true
        defer {
            if generation == loadGeneration { isLoading = false }
        }

        let scope: ProfileScope
        do {
            scope = try currentScope()
        } catch {
            clearAll()
            notices = [CalendarSearchNotice(source: .routines, message: "This profile could not be loaded. Try again.")]
            return
        }

        prepare(for: scope)
        isProfileEmpty = scope.calendarIDs.isEmpty && scope.reminderListIDs.isEmpty && scope.routineIDs.isEmpty
        if isProfileEmpty {
            confirmedEvents = []
            confirmedReminders = []
            confirmedRoutines = []
            confirmedCategories = []
            corpus = []
            notices = []
            sections = .empty
            return
        }

        var nextNotices: [CalendarSearchNotice] = []

        if scope.calendarIDs.isEmpty {
            confirmedEvents = []
        } else if calendarService.accessState != .granted {
            confirmedEvents = []
            nextNotices.append(accessNotice(source: .calendar, state: calendarService.accessState))
        } else {
            do {
                let reference = now()
                let interval = DateInterval(
                    start: calendar.date(byAdding: .year, value: -1, to: reference) ?? reference,
                    end: calendar.date(byAdding: .year, value: 2, to: reference) ?? reference
                )
                let fetched = try calendarService.fetchEvents(in: interval, calendarIDs: scope.calendarIDs)
                guard generation == loadGeneration else { return }
                confirmedEvents = fetched.filter { scope.calendarIDs.contains($0.calendarID) }
            } catch {
                guard generation == loadGeneration else { return }
                nextNotices.append(.init(source: .calendar, message: "Calendar events could not be refreshed."))
            }
        }

        if scope.reminderListIDs.isEmpty {
            confirmedReminders = []
        } else if remindersService.accessState != .granted {
            confirmedReminders = []
            nextNotices.append(accessNotice(source: .reminders, state: remindersService.accessState))
        } else {
            do {
                let fetched = try await remindersService.fetchReminders(listIDs: scope.reminderListIDs)
                guard generation == loadGeneration else { return }
                confirmedReminders = fetched.filter { scope.reminderListIDs.contains($0.listID) }
            } catch {
                guard generation == loadGeneration else { return }
                nextNotices.append(.init(source: .reminders, message: "Tasks could not be refreshed."))
            }
        }

        if scope.routineIDs.isEmpty {
            confirmedRoutines = []
        } else {
            do {
                let fetched = try routines.list(includeArchived: true)
                guard generation == loadGeneration else { return }
                confirmedRoutines = fetched.filter { scope.routineIDs.contains($0.id) }
            } catch {
                guard generation == loadGeneration else { return }
                nextNotices.append(.init(source: .routines, message: "Routines could not be refreshed."))
            }
        }

        do {
            confirmedCategories = try categories.list()
        } catch {
            confirmedCategories = []
        }

        guard generation == loadGeneration else { return }
        cachedScope = scope
        notices = nextNotices
        rebuildCorpus()
    }

    func retry() async {
        await load()
    }

    private func prepare(for scope: ProfileScope) {
        if cachedScope?.identity != scope.identity {
            clearAll()
        } else {
            confirmedEvents.removeAll { !scope.calendarIDs.contains($0.calendarID) }
            confirmedReminders.removeAll { !scope.reminderListIDs.contains($0.listID) }
            confirmedRoutines.removeAll { !scope.routineIDs.contains($0.id) }
            rebuildCorpus()
        }
        cachedScope = scope
    }

    private func clearAll() {
        confirmedEvents = []
        confirmedReminders = []
        confirmedRoutines = []
        confirmedCategories = []
        corpus = []
        sections = .empty
        notices = []
        cachedScope = nil
    }

    private func rebuildCorpus() {
        corpus = matcher.makeCorpus(
            events: confirmedEvents,
            reminders: confirmedReminders,
            routines: confirmedRoutines,
            categories: confirmedCategories,
            now: now()
        )
        publishSearch()
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        let delay = debounce
        searchTask = Task { [weak self] in
            if delay > .zero {
                try? await Task.sleep(for: delay)
            }
            guard !Task.isCancelled else { return }
            self?.publishSearch()
        }
    }

    private func publishSearch() {
        sections = matcher.sections(matching: query, corpus: corpus)
    }

    private func accessNotice(source: CalendarSearchNotice.Source, state: AccessState) -> CalendarSearchNotice {
        let message: String
        switch (source, state) {
        case (.calendar, .restricted):
            message = "Calendar access is restricted. Calendar events are hidden because this access is controlled by your device or account."
        case (.reminders, .restricted):
            message = "Reminders access is restricted. Tasks are hidden because this access is controlled by your device or account."
        case (.calendar, .denied), (.calendar, .notDetermined):
            message = "Calendar access is unavailable. Calendar events are hidden."
        case (.reminders, .denied), (.reminders, .notDetermined):
            message = "Reminders access is unavailable. Tasks are hidden."
        case (.calendar, .granted):
            message = "Calendar access is available."
        case (.reminders, .granted):
            message = "Reminders access is available."
        case (.routines, _):
            message = "Routines could not be refreshed."
        }
        return .init(source: source, message: message, accessState: state)
    }
}
