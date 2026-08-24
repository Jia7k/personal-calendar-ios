import Foundation
@testable import PersonalCalendar

@MainActor
final class FakeCalendarService: CalendarServicing {
    var accessState: AccessState
    private(set) var requestCount = 0
    var requestedAccess: AccessState
    var events: [CalendarEventSnapshot]
    var descriptors: [CalendarDescriptor]
    var createdDrafts: [EventDraft] = []
    var fetchError: Error?
    var createError: Error?

    init(
        access: AccessState,
        requestedAccess: AccessState? = nil,
        events: [CalendarEventSnapshot] = [],
        descriptors: [CalendarDescriptor] = [],
        fetchError: Error? = nil,
        createError: Error? = nil
    ) {
        accessState = access
        self.requestedAccess = requestedAccess ?? access
        self.events = events
        self.descriptors = descriptors
        self.fetchError = fetchError
        self.createError = createError
    }

    func requestFullAccess() async -> AccessState {
        requestCount += 1
        accessState = requestedAccess
        return accessState
    }

    func calendars() -> [CalendarDescriptor] { descriptors }

    func fetchEvents(in interval: DateInterval, calendarIDs: Set<String>) throws -> [CalendarEventSnapshot] {
        if let fetchError { throw fetchError }
        return events.filter { calendarIDs.isEmpty || calendarIDs.contains($0.calendarID) }
    }

    func createEvent(_ draft: EventDraft) throws -> String {
        if let createError { throw createError }
        createdDrafts.append(draft)
        return "created-event"
    }
}

struct CompletionCall: Equatable {
    let id: String
    let completed: Bool
}

struct RoutineCompletionCall: Equatable {
    let id: UUID
    let day: LocalDay
    let completed: Bool
}
struct RoutineUpdateCall: Equatable { let id: UUID; let draft: RoutineDraft }
struct RoutineBooleanCall: Equatable { let id: UUID; let value: Bool }

extension RoutineSnapshot {
    static let sampleRoutine = RoutineSnapshot(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        title: "Read",
        weekdays: [1, 2, 3, 4, 5, 6, 7],
        window: .evening,
        reminderHour: nil,
        reminderMinute: nil,
        isPaused: false,
        isArchived: false
    )
}

@MainActor
final class FakeRoutineRepository: RoutineRepository {
    var routines: [RoutineSnapshot]
    var createdDrafts: [RoutineDraft] = []
    var updateCalls: [RoutineUpdateCall] = []
    var pauseCalls: [RoutineBooleanCall] = []
    var archiveCalls: [RoutineBooleanCall] = []
    var deleteCalls: [UUID] = []
    var completionCalls: [RoutineCompletionCall] = []
    var completedDaysCallCount = 0
    var listCallCount = 0
    var completedDaysCallCounts: [UUID: Int] = [:]
    var completedDaysError: Error?
    var completedDaysErrors: [UUID: Error] = [:]
    var completionError: Error?
    var listError: Error?
    var createError: Error?
    var updateError: Error?
    var deleteError: Error?
    var pauseError: Error?
    var archiveError: Error?
    private var completions: [UUID: Set<LocalDay>] = [:]

    init(routines: [RoutineSnapshot] = []) {
        self.routines = routines
    }
    func seedCompletedDays(_ days: Set<LocalDay>, routineID: UUID) { completions[routineID] = days }

    func list(includeArchived: Bool) throws -> [RoutineSnapshot] {
        listCallCount += 1
        if let listError { throw listError }
        return includeArchived ? routines : routines.filter { !$0.isArchived }
    }

    func create(_ draft: RoutineDraft) throws -> UUID {
        if let createError { throw createError }
        createdDrafts.append(draft)
        let id = UUID(); routines.append(.init(id: id, title: draft.title, weekdays: draft.weekdays, window: draft.window, reminderHour: draft.reminderHour, reminderMinute: draft.reminderMinute, isPaused: false, isArchived: false)); return id
    }

    func update(id: UUID, draft: RoutineDraft) throws { if let updateError { throw updateError }; guard let index = routines.firstIndex(where: { $0.id == id }) else { throw RoutineRepositoryError.routineNotFound }; updateCalls.append(.init(id: id, draft: draft)); let old = routines[index]; routines[index] = .init(id: id, title: draft.title, weekdays: draft.weekdays, window: draft.window, reminderHour: draft.reminderHour, reminderMinute: draft.reminderMinute, isPaused: old.isPaused, isArchived: old.isArchived) }

    func setPaused(id: UUID, paused: Bool) throws { if let pauseError { throw pauseError }; guard let index = routines.firstIndex(where: { $0.id == id }) else { throw RoutineRepositoryError.routineNotFound }; pauseCalls.append(.init(id: id, value: paused)); let old = routines[index]; routines[index] = .init(id: id, title: old.title, weekdays: old.weekdays, window: old.window, reminderHour: old.reminderHour, reminderMinute: old.reminderMinute, isPaused: paused, isArchived: old.isArchived) }

    func setArchived(id: UUID, archived: Bool) throws { if let archiveError { throw archiveError }; guard let index = routines.firstIndex(where: { $0.id == id }) else { throw RoutineRepositoryError.routineNotFound }; archiveCalls.append(.init(id: id, value: archived)); let old = routines[index]; routines[index] = .init(id: id, title: old.title, weekdays: old.weekdays, window: old.window, reminderHour: old.reminderHour, reminderMinute: old.reminderMinute, isPaused: old.isPaused, isArchived: archived) }

    func delete(id: UUID) throws {
        if let deleteError { throw deleteError }
        guard routines.contains(where: { $0.id == id }) else { throw RoutineRepositoryError.routineNotFound }
        deleteCalls.append(id); routines.removeAll { $0.id == id }
        completions[id] = nil
    }

    func setCompleted(routineID: UUID, day: LocalDay, completed: Bool) throws {
        if let completionError { throw completionError }
        guard routines.contains(where: { $0.id == routineID }) else { throw RoutineRepositoryError.routineNotFound }
        completionCalls.append(.init(id: routineID, day: day, completed: completed))
        if completed {
            completions[routineID, default: []].insert(day)
        } else {
            completions[routineID]?.remove(day)
        }
    }

    func isCompleted(routineID: UUID, day: LocalDay) throws -> Bool {
        completions[routineID, default: []].contains(day)
    }

    func completedDays(routineID: UUID) throws -> Set<LocalDay> {
        completedDaysCallCount += 1
        completedDaysCallCounts[routineID, default: 0] += 1
        if let error = completedDaysErrors[routineID] { throw error }
        if let completedDaysError { throw completedDaysError }
        return completions[routineID, default: []]
    }
}

@MainActor
final class FakeRemindersService: RemindersServicing {
    var accessState: AccessState
    private(set) var requestCount = 0
    var requestedAccess: AccessState
    var reminders: [ReminderSnapshot]
    var descriptors: [ReminderListDescriptor]
    var fetchError: Error?
    var createdDrafts: [ReminderDraft] = []
    var completedCalls: [CompletionCall] = []
    var completionError: Error?
    var createError: Error?
    var fetchErrorAfterCompletion: Error?
    var fetchErrorAfterCreate: Error?
    private(set) var fetchListIDs: [Set<String>] = []
    var suspendFetchAfterUndo = false
    var suspendNextFetch = false
    var allowMissingCompletion = false
    private var fetchContinuation: CheckedContinuation<Void, Never>?
    private(set) var isFetchSuspended = false

    init(
        access: AccessState,
        requestedAccess: AccessState? = nil,
        reminders: [ReminderSnapshot] = [],
        descriptors: [ReminderListDescriptor] = [],
        fetchError: Error? = nil
    ) {
        accessState = access
        self.requestedAccess = requestedAccess ?? access
        self.reminders = reminders
        self.descriptors = descriptors
        self.fetchError = fetchError
    }

    func requestFullAccess() async -> AccessState {
        requestCount += 1
        accessState = requestedAccess
        return accessState
    }

    func lists() -> [ReminderListDescriptor] { descriptors }

    func fetchReminders(listIDs: Set<String>) async throws -> [ReminderSnapshot] {
        fetchListIDs.append(listIDs)
        if suspendNextFetch {
            isFetchSuspended = true
            suspendNextFetch = false
            await withCheckedContinuation { continuation in fetchContinuation = continuation }
            isFetchSuspended = false
        }
        if suspendFetchAfterUndo, completedCalls.last?.completed == false {
            isFetchSuspended = true
            suspendFetchAfterUndo = false
            await withCheckedContinuation { continuation in fetchContinuation = continuation }
            isFetchSuspended = false
        }
        if let fetchErrorAfterCompletion, !completedCalls.isEmpty { throw fetchErrorAfterCompletion }
        if let fetchErrorAfterCreate, !createdDrafts.isEmpty { throw fetchErrorAfterCreate }
        if let fetchError {
            throw fetchError
        }
        return reminders.filter { listIDs.isEmpty || listIDs.contains($0.listID) }
    }

    func resumeSuspendedFetch() { fetchContinuation?.resume(); fetchContinuation = nil }

    func createReminder(_ draft: ReminderDraft) throws -> String {
        if let createError { throw createError }
        createdDrafts.append(draft)
        let id = "created-task-\(createdDrafts.count)"; reminders.append(.init(id: id, title: draft.title, notes: draft.notes, dueDate: draft.dueDate, dueHasTime: draft.dueHasTime, priority: draft.priority, listID: draft.listID ?? descriptors.first?.id ?? "tasks", listTitle: descriptors.first(where: { $0.id == draft.listID })?.title ?? "Tasks", isCompleted: false, allowsModification: true, hasRecurrence: false)); return id
    }

    func setCompleted(id: String, completed: Bool) throws {
        if let completionError { throw completionError }
        guard allowMissingCompletion || reminders.contains(where: { $0.id == id }) else { throw RoutineRepositoryError.routineNotFound }
        completedCalls.append(.init(id: id, completed: completed))
        if let index = reminders.firstIndex(where: { $0.id == id }) {
            let old = reminders[index]
            reminders[index] = .init(id: old.id, title: old.title, notes: old.notes, dueDate: old.dueDate, dueHasTime: old.dueHasTime, priority: old.priority, listID: old.listID, listTitle: old.listTitle, isCompleted: completed, allowsModification: old.allowsModification, hasRecurrence: old.hasRecurrence)
        }
    }
}

extension ReminderSnapshot {
    static let sampleTask = ReminderSnapshot(
        id: "task",
        title: "Buy milk",
        notes: nil,
        dueDate: nil,
        dueHasTime: false,
        priority: 5,
        listID: "tasks",
        listTitle: "Tasks",
        isCompleted: false,
        allowsModification: true,
        hasRecurrence: false
    )
}

@MainActor
final class FakeNotificationAuthorizer: NotificationAuthorizing {
    private var state: AccessState
    private let requested: AccessState
    private var readContinuation: CheckedContinuation<Void, Never>?
    private let suspendRead: Bool

    init(access: AccessState, requestedAccess: AccessState? = nil, suspendRead: Bool = false) {
        state = access
        requested = requestedAccess ?? access
        self.suspendRead = suspendRead
    }

    var accessState: AccessState {
        get async { if suspendRead { await withCheckedContinuation { readContinuation = $0 } }; return state }
    }

    func requestAccess() async -> AccessState {
        state = requested
        return state
    }
    func resumeRead() { readContinuation?.resume(); readContinuation = nil }
}
