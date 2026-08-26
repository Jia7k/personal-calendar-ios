import XCTest
@testable import PersonalCalendar

@MainActor
final class CalendarSearchViewModelTests: XCTestCase {
    private let reference = Date(timeIntervalSince1970: 1_785_123_200) // 2026-07-30 12:00:00 UTC

    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    func testLoadUsesExactScopeAndCalendarYearBoundsThenFiltersProviderOverReturn() async {
        let scope = makeScope(calendarIDs: ["included-calendar"], reminderListIDs: ["included-list"], routineIDs: [includedRoutineID])
        let events = SearchCalendarService(events: [
            event(id: "included-event", title: "Match event", calendarID: "included-calendar"),
            event(id: "excluded-event", title: "Match excluded event", calendarID: "other-calendar")
        ])
        let reminders = SearchRemindersService(reminders: [
            reminder(id: "included-task", title: "Match task", listID: "included-list"),
            reminder(id: "excluded-task", title: "Match excluded task", listID: "other-list")
        ])
        let routines = FakeRoutineRepository(routines: [
            routine(id: includedRoutineID, title: "Match routine"),
            routine(id: UUID(), title: "Match excluded routine")
        ])
        let categories = SearchCategoryRepository()
        let model = makeModel(events: events, reminders: reminders, routines: routines, categories: categories, scope: { scope })

        model.query = "match"
        await model.load()
        await settle()

        XCTAssertEqual(events.requestedIDs, [Set(["included-calendar"])])
        XCTAssertEqual(events.requestedIntervals, [expectedSearchInterval])
        XCTAssertEqual(reminders.requestedIDs, [Set(["included-list"])])
        XCTAssertEqual(routines.listCallCount, 1)
        XCTAssertEqual(categories.listCallCount, 1)
        XCTAssertEqual(resultTitles(model), ["Match event", "Match task", "Match routine"])
        XCTAssertFalse(resultTitles(model).contains { $0.contains("excluded") })
    }

    func testEmptyExternalAndRoutineScopePerformsZeroProviderAndRepositoryFetches() async {
        let events = SearchCalendarService(events: [event(id: "event", title: "Match", calendarID: "calendar")])
        let reminders = SearchRemindersService(reminders: [reminder(id: "task", title: "Match", listID: "list")])
        let routines = FakeRoutineRepository(routines: [routine(id: includedRoutineID, title: "Match")])
        let model = makeModel(
            events: events,
            reminders: reminders,
            routines: routines,
            scope: { self.makeScope() }
        )

        model.query = "match"
        await model.load()
        await settle()

        XCTAssertTrue(events.requestedIDs.isEmpty)
        XCTAssertTrue(reminders.requestedIDs.isEmpty)
        XCTAssertEqual(routines.listCallCount, 0)
        XCTAssertTrue(model.isProfileEmpty)
        XCTAssertEqual(model.sections, .empty)
    }

    func testPartialCalendarFailureStillPublishesTaskAndRoutineMatches() async {
        let scope = makeScope(calendarIDs: ["calendar"], reminderListIDs: ["list"], routineIDs: [includedRoutineID])
        let events = SearchCalendarService(events: [], error: SearchTestError.failed)
        let reminders = SearchRemindersService(reminders: [reminder(id: "task", title: "Match task", listID: "list")])
        let routines = FakeRoutineRepository(routines: [routine(id: includedRoutineID, title: "Match routine")])
        let model = makeModel(events: events, reminders: reminders, routines: routines, scope: { scope })

        model.query = "match"
        await model.load()
        await settle()

        XCTAssertEqual(resultTitles(model), ["Match task", "Match routine"])
        XCTAssertEqual(model.notices.map(\.source), [.calendar])
    }

    func testSameProfileFailureRetainsConfirmedStillScopedCorpus() async {
        let scope = makeScope(calendarIDs: ["calendar"], reminderListIDs: [], routineIDs: [])
        let events = SearchCalendarService(events: [event(id: "confirmed", title: "Match confirmed", calendarID: "calendar")])
        let model = makeModel(events: events, scope: { scope })

        model.query = "match"
        await model.load()
        await settle()
        events.error = SearchTestError.failed
        await model.retry()
        await settle()

        XCTAssertEqual(resultTitles(model), ["Match confirmed"])
        XCTAssertEqual(model.notices.map(\.source), [.calendar])
    }

    func testProfileChangeClearsOldResultsBeforeSuspendedNewLoadCompletes() async {
        var activeScope = makeScope(calendarIDs: [], reminderListIDs: ["old"], routineIDs: [])
        let reminders = SearchRemindersService(reminders: [reminder(id: "old", title: "Match old", listID: "old")])
        let model = makeModel(reminders: reminders, scope: { activeScope })

        model.query = "match"
        await model.load()
        await settle()
        XCTAssertEqual(resultTitles(model), ["Match old"])

        activeScope = makeScope(calendarIDs: [], reminderListIDs: ["new"], routineIDs: [])
        reminders.reminders = [reminder(id: "new", title: "Match new", listID: "new")]
        reminders.suspendNextFetch = true
        let load = Task { await model.load() }
        await reminders.waitUntilSuspended()

        XCTAssertEqual(model.sections, .empty)
        reminders.resume()
        await load.value
        await settle()
        XCTAssertEqual(resultTitles(model), ["Match new"])
    }

    func testOlderGenerationCannotPublishAfterNewerProfileLoad() async {
        var activeScope = makeScope(calendarIDs: [], reminderListIDs: ["old"], routineIDs: [])
        let reminders = SearchRemindersService(reminders: [reminder(id: "old", title: "Match old", listID: "old")])
        let model = makeModel(reminders: reminders, scope: { activeScope })

        model.query = "match"
        reminders.suspendNextFetch = true
        let older = Task { await model.load() }
        await reminders.waitUntilSuspended()

        activeScope = makeScope(calendarIDs: [], reminderListIDs: ["new"], routineIDs: [])
        reminders.reminders = [reminder(id: "new", title: "Match new", listID: "new")]
        await model.load()
        await settle()
        reminders.resume()
        await older.value
        await settle()

        XCTAssertEqual(resultTitles(model), ["Match new"])
    }

    func testDebouncedQueryPublishesOnlyLatestMatcherResult() async {
        let scope = makeScope(calendarIDs: ["calendar"], reminderListIDs: [], routineIDs: [])
        let events = SearchCalendarService(events: [
            event(id: "first", title: "First match", calendarID: "calendar"),
            event(id: "second", title: "Second match", calendarID: "calendar")
        ])
        let model = makeModel(events: events, scope: { scope }, debounce: .milliseconds(20))

        await model.load()
        model.query = "first"
        model.query = "second"
        try? await Task.sleep(for: .milliseconds(80))

        XCTAssertEqual(resultTitles(model), ["Second match"])
    }

    private var expectedSearchInterval: DateInterval {
        .init(
            start: calendar.date(byAdding: .year, value: -1, to: reference)!,
            end: calendar.date(byAdding: .year, value: 2, to: reference)!
        )
    }

    private var includedRoutineID: UUID {
        UUID(uuidString: "00000000-0000-0000-0000-000000000123")!
    }

    private func makeModel(
        events: SearchCalendarService = .init(),
        reminders: SearchRemindersService = .init(),
        routines: FakeRoutineRepository = .init(),
        categories: SearchCategoryRepository = .init(),
        scope: @escaping @MainActor () throws -> ProfileScope,
        debounce: Duration = .zero
    ) -> CalendarSearchViewModel {
        CalendarSearchViewModel(
            calendarService: events,
            remindersService: reminders,
            routines: routines,
            categories: categories,
            currentScope: scope,
            calendar: calendar,
            locale: Locale(identifier: "en_SG"),
            now: { self.reference },
            debounce: debounce
        )
    }

    private func makeScope(
        calendarIDs: Set<String> = [],
        reminderListIDs: Set<String> = [],
        routineIDs: Set<UUID> = []
    ) -> ProfileScope {
        .init(
            identity: .saved(UUID()),
            calendarIDs: calendarIDs,
            reminderListIDs: reminderListIDs,
            routineIDs: routineIDs,
            defaultCalendarID: nil,
            defaultReminderListID: nil
        )
    }

    private func event(id: String, title: String, calendarID: String) -> CalendarEventSnapshot {
        .init(
            id: id,
            title: title,
            start: reference.addingTimeInterval(3_600),
            end: reference.addingTimeInterval(7_200),
            isAllDay: false,
            calendarID: calendarID,
            calendarTitle: calendarID,
            allowsModification: true,
            hasRecurrence: false
        )
    }

    private func reminder(id: String, title: String, listID: String) -> ReminderSnapshot {
        .init(
            id: id,
            title: title,
            notes: nil,
            dueDate: reference.addingTimeInterval(3_600),
            dueHasTime: true,
            priority: 0,
            listID: listID,
            listTitle: listID,
            isCompleted: false,
            allowsModification: true,
            hasRecurrence: false
        )
    }

    private func routine(id: UUID, title: String) -> RoutineSnapshot {
        .init(
            id: id,
            title: title,
            weekdays: [2],
            window: .evening,
            reminderHour: nil,
            reminderMinute: nil,
            isPaused: false,
            isArchived: false
        )
    }

    private func resultTitles(_ model: CalendarSearchViewModel) -> [String] {
        model.sections.upcoming.map(\.title)
            + model.sections.pastAndCompleted.map(\.title)
            + model.sections.routines.map(\.title)
    }

    private func settle() async {
        for _ in 0..<10 { await Task.yield() }
    }
}

private enum SearchTestError: Error { case failed }

/// A test-local provider deliberately returns every configured item, independent
/// of the requested IDs. This proves the view model owns its scope filter.
@MainActor
private final class SearchCalendarService: CalendarServicing {
    var accessState: AccessState = .granted
    var events: [CalendarEventSnapshot]
    var error: Error?
    private(set) var requestedIDs: [Set<String>] = []
    private(set) var requestedIntervals: [DateInterval] = []

    init(events: [CalendarEventSnapshot] = [], error: Error? = nil) {
        self.events = events
        self.error = error
    }

    func requestFullAccess() async -> AccessState { accessState }
    func calendars() -> [CalendarDescriptor] { [] }
    func fetchEvents(in interval: DateInterval, calendarIDs: Set<String>) throws -> [CalendarEventSnapshot] {
        requestedIntervals.append(interval)
        requestedIDs.append(calendarIDs)
        if let error { throw error }
        return events
    }
    func createEvent(_ draft: EventDraft) throws -> String? { nil }
    func event(id: String) -> CalendarEventSnapshot? { nil }
    func updateEvent(id: String, draft: EventDraft, scope: RecurrenceEditScope) throws {}
    func deleteEvent(id: String, scope: RecurrenceEditScope) throws {}

}

@MainActor
private final class SearchRemindersService: RemindersServicing {
    var accessState: AccessState = .granted
    var reminders: [ReminderSnapshot]
    var error: Error?
    private(set) var requestedIDs: [Set<String>] = []
    var suspendNextFetch = false
    private var gate: SearchLoadGate?

    init(reminders: [ReminderSnapshot] = [], error: Error? = nil) {
        self.reminders = reminders
        self.error = error
    }

    func requestFullAccess() async -> AccessState { accessState }
    func lists() -> [ReminderListDescriptor] { [] }
    func fetchReminders(listIDs: Set<String>) async throws -> [ReminderSnapshot] {
        requestedIDs.append(listIDs)
        if suspendNextFetch {
            suspendNextFetch = false
            let gate = SearchLoadGate()
            self.gate = gate
            await gate.wait()
            self.gate = nil
        }
        if let error { throw error }
        return reminders
    }
    func createReminder(_ draft: ReminderDraft) throws -> String? { nil }
    func setCompleted(id: String, completed: Bool) throws {}
    func reminder(id: String) -> ReminderSnapshot? { nil }
    func updateReminder(id: String, draft: ReminderDraft) throws {}
    func deleteReminder(id: String) throws {}

    func waitUntilSuspended() async {
        for _ in 0..<100 {
            if gate != nil { return }
            await Task.yield()
        }
        XCTFail("Reminder fetch did not suspend")
    }

    func resume() {
        let gate = gate
        self.gate = nil
        Task { await gate?.resume() }
    }
}

private actor SearchLoadGate {
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        await withCheckedContinuation { continuation = $0 }
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
private final class SearchCategoryRepository: CategoryRepository {
    var values: [CategorySnapshot] = []
    var error: Error?
    private(set) var listCallCount = 0

    func list() throws -> [CategorySnapshot] {
        listCallCount += 1
        if let error { throw error }
        return values
    }
    func create(name: String, colorHex: String) throws -> UUID { UUID() }
    func update(id: UUID, name: String, colorHex: String) throws {}
    func reorder(ids: [UUID]) throws {}
    func delete(id: UUID, reassignedTo replacementID: UUID?) throws {}
    func assign(categoryID: UUID?, to source: ExternalItemSource, externalID: String) throws {}
    func category(for source: ExternalItemSource, externalID: String) throws -> CategorySnapshot? { nil }
    func removeUnresolvedLinks(for source: ExternalItemSource, validExternalIDs: Set<String>) throws {}
    func seedDefaultsIfNeeded(settings: AppSettingsStore) throws {}
}
