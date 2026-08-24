import Foundation
@testable import PersonalCalendar

@MainActor
final class FakeCalendarService: CalendarServicing {
    var accessState: AccessState
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
    var completionCalls: [RoutineCompletionCall] = []
    var completedDaysCallCount = 0
    var completedDaysError: Error?
    var completionError: Error?
    private var completions: [UUID: Set<LocalDay>] = [:]

    init(routines: [RoutineSnapshot] = []) {
        self.routines = routines
    }

    func list(includeArchived: Bool) throws -> [RoutineSnapshot] {
        includeArchived ? routines : routines.filter { !$0.isArchived }
    }

    func create(_ draft: RoutineDraft) throws -> UUID {
        createdDrafts.append(draft)
        return UUID()
    }

    func update(id: UUID, draft: RoutineDraft) throws { }

    func setPaused(id: UUID, paused: Bool) throws { }

    func setArchived(id: UUID, archived: Bool) throws { }

    func delete(id: UUID) throws {
        routines.removeAll { $0.id == id }
        completions[id] = nil
    }

    func setCompleted(routineID: UUID, day: LocalDay, completed: Bool) throws {
        if let completionError { throw completionError }
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
        if let completedDaysError { throw completedDaysError }
        return completions[routineID, default: []]
    }
}

@MainActor
final class FakeRemindersService: RemindersServicing {
    var accessState: AccessState
    var requestedAccess: AccessState
    var reminders: [ReminderSnapshot]
    var descriptors: [ReminderListDescriptor]
    var fetchError: Error?
    var createdDrafts: [ReminderDraft] = []
    var completedCalls: [CompletionCall] = []
    var completionError: Error?
    var fetchErrorAfterCompletion: Error?
    var suspendFetchAfterUndo = false
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
        accessState = requestedAccess
        return accessState
    }

    func lists() -> [ReminderListDescriptor] { descriptors }

    func fetchReminders(listIDs: Set<String>) async throws -> [ReminderSnapshot] {
        if suspendFetchAfterUndo, completedCalls.last?.completed == false {
            isFetchSuspended = true
            await withCheckedContinuation { continuation in fetchContinuation = continuation }
            isFetchSuspended = false
        }
        if let fetchErrorAfterCompletion, !completedCalls.isEmpty { throw fetchErrorAfterCompletion }
        if let fetchError {
            throw fetchError
        }
        return reminders.filter { listIDs.isEmpty || listIDs.contains($0.listID) }
    }

    func resumeSuspendedFetch() { fetchContinuation?.resume(); fetchContinuation = nil }

    func createReminder(_ draft: ReminderDraft) throws -> String {
        createdDrafts.append(draft)
        return "created-task"
    }

    func setCompleted(id: String, completed: Bool) throws {
        if let completionError { throw completionError }
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

    init(access: AccessState, requestedAccess: AccessState? = nil) {
        state = access
        requested = requestedAccess ?? access
    }

    var accessState: AccessState {
        get async { state }
    }

    func requestAccess() async -> AccessState {
        state = requested
        return state
    }
}
