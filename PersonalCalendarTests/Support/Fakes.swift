import Foundation
@testable import PersonalCalendar

@MainActor
final class FakeRefreshDebouncer: RefreshDebouncing {
    private var pending: (@MainActor () async -> Void)?

    func schedule(_ operation: @escaping @MainActor () async -> Void) {
        pending = operation
    }

    func fire() async {
        let operation = pending
        pending = nil
        await operation?()
    }
}

enum RefreshStep: Equatable {
    case permissions
    case profiles
    case sources
    case profileCatalog
    case agenda
    case categoryCleanup
    case timetable
    case notifications
}

@MainActor
final class RefreshCallRecorder {
    private(set) var steps: [RefreshStep] = []
    var agendaOperation: (@MainActor () async -> Void)?
    var timetableOperation: (@MainActor () async -> Void)?

    var completedRefreshes: Int {
        steps.filter { $0 == .notifications }.count
    }

    var actions: RefreshActions {
        .init(
            refreshPermissions: { self.steps.append(.permissions) },
            migrateProfiles: { self.steps.append(.profiles) },
            refreshSources: { self.steps.append(.sources) },
            reloadProfiles: { self.steps.append(.profileCatalog) },
            refreshAgenda: {
                self.steps.append(.agenda)
                await self.agendaOperation?()
            },
            cleanCategoryLinks: { self.steps.append(.categoryCleanup) },
            refreshTimetable: {
                self.steps.append(.timetable)
                await self.timetableOperation?()
            },
            rescheduleNotifications: { self.steps.append(.notifications) }
        )
    }
}

@MainActor
final class FakeRefreshGate {
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        await withCheckedContinuation { continuation = $0 }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
final class RecordingEventKitMutationBacking: EventKitMutationBacking {
    var eventCreates: [EventCreateRequest] = []
    var eventUpdates: [(String, EventUpdateRequest)] = []
    var eventRemovals: [(String, RecurrenceEditScope)] = []
    var reminderCreates: [ReminderCreateRequest] = []
    var reminderUpdates: [(String, ReminderUpdateRequest)] = []
    var reminderRemovals: [String] = []
    var reminderCompletionUpdates: [CompletionCall] = []
    var error: Error?
    var nextEventID: String? = "created-event"
    var nextReminderID: String? = "created-reminder"
    func createEvent(_ request: EventCreateRequest) throws -> String? { if let error { throw error }; eventCreates.append(request); return normalized(nextEventID) }
    func updateEvent(id: String, request: EventUpdateRequest) throws { if let error { throw error }; eventUpdates.append((id, request)) }
    func removeEvent(id: String, span: RecurrenceEditScope) throws { if let error { throw error }; eventRemovals.append((id, span)) }
    func createReminder(_ request: ReminderCreateRequest) throws -> String? { if let error { throw error }; reminderCreates.append(request); return normalized(nextReminderID) }
    func updateReminder(id: String, request: ReminderUpdateRequest) throws { if let error { throw error }; reminderUpdates.append((id, request)) }
    func removeReminder(id: String) throws { if let error { throw error }; reminderRemovals.append(id) }
    func setReminderCompleted(id: String, completed: Bool) throws { if let error { throw error }; reminderCompletionUpdates.append(.init(id: id, completed: completed)) }
    private func normalized(_ identifier: String?) -> String? { guard let identifier, !identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }; return identifier }
}

@MainActor
final class FakeCalendarService: CalendarServicing {
    var accessState: AccessState
    private(set) var requestCount = 0
    var requestedAccess: AccessState
    var events: [CalendarEventSnapshot]
    var descriptors: [CalendarDescriptor]
    var createdDrafts: [EventDraft] = []
    private(set) var eventUpdateCalls: [EventUpdateCall] = []
    private(set) var eventDeleteCalls: [EventDeleteCall] = []
    private(set) var successfulWriteCount = 0
    private(set) var fetchCalendarIDs: [Set<String>] = []
    private(set) var fetchIntervals: [DateInterval] = []
    var fetchError: Error?
    var createError: Error?
    var updateError: Error?
    var deleteError: Error?
    var suspendNextRequest = false
    private var requestContinuation: CheckedContinuation<Void, Never>?
    private(set) var isRequestSuspended = false
    private let defaultCalendarID: String?

    init(
        access: AccessState,
        requestedAccess: AccessState? = nil,
        events: [CalendarEventSnapshot] = [],
        descriptors: [CalendarDescriptor] = [],
        fetchError: Error? = nil,
        createError: Error? = nil,
        defaultCalendarID: String? = nil
    ) {
        accessState = access
        self.requestedAccess = requestedAccess ?? access
        self.events = events
        self.descriptors = descriptors
        self.fetchError = fetchError
        self.createError = createError
        self.defaultCalendarID = defaultCalendarID
    }

    func requestFullAccess() async -> AccessState {
        requestCount += 1
        if suspendNextRequest {
            suspendNextRequest = false
            isRequestSuspended = true
            await withCheckedContinuation { requestContinuation = $0 }
            isRequestSuspended = false
        }
        accessState = requestedAccess
        return accessState
    }

    func resumeSuspendedRequest() { requestContinuation?.resume(); requestContinuation = nil }

    func calendars() -> [CalendarDescriptor] { accessState == .granted ? descriptors : [] }

    func fetchEvents(in interval: DateInterval, calendarIDs: Set<String>) throws -> [CalendarEventSnapshot] {
        fetchIntervals.append(interval)
        fetchCalendarIDs.append(calendarIDs)
        guard accessState == .granted else { return [] }
        if let fetchError { throw fetchError }
        return events.filter { calendarIDs.isEmpty || calendarIDs.contains($0.calendarID) }
    }

    func createEvent(_ draft: EventDraft) throws -> String? {
        guard accessState == .granted else { throw DraftValidationError.itemNotFound }
        if let createError { throw createError }
        try EventDraftValidator.validate(draft)
        let destination: CalendarDescriptor
        if let id = draft.calendarID {
            guard let found = descriptors.first(where: { $0.id == id }) else { throw DraftValidationError.invalidDestination }
            guard found.allowsContentModifications else { throw DraftValidationError.readOnlyDestination }
            destination = found
        } else {
            guard let defaultCalendarID,
                  !defaultCalendarID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let found = descriptors.first(where: { $0.id == defaultCalendarID }) else { throw DraftValidationError.invalidDestination }
            guard found.allowsContentModifications else { throw DraftValidationError.readOnlyDestination }
            destination = found
        }
        createdDrafts.append(draft)
        let id = "created-event-\(createdDrafts.count)"
        events.append(.init(id: id, mutationID: id, title: trimmed(draft.title), start: draft.start, end: draft.end, isAllDay: draft.isAllDay, calendarID: destination.id, calendarTitle: destination.title, allowsModification: true, hasRecurrence: recurrence(from: draft.recurrence) != .none, notes: draft.notes, location: draft.location, url: draft.url, alarms: alarms(from: draft.alarms), recurrence: recurrence(from: draft.recurrence)))
        successfulWriteCount += 1
        return id
    }
    func event(id: String) -> CalendarEventSnapshot? {
        guard accessState == .granted, let index = eventIndex(forDetailID: id) else { return nil }
        return events[index]
    }
    func updateEvent(id: String, draft: EventDraft, scope: RecurrenceEditScope) throws {
        guard accessState == .granted, let index = eventIndex(forMutationID: id) else { throw DraftValidationError.itemNotFound }
        let old = events[index]
        guard old.allowsModification else { throw DraftValidationError.readOnlyDestination }
        guard scope != .futureOccurrences || old.hasRecurrence else { throw DraftValidationError.invalidRecurrenceScope }
        try EventDraftValidator.validate(draft)
        if old.hasRecurrence { try draft.recurrence.validate(scope: scope) }
        let destination: CalendarDescriptor
        if let destinationID = draft.calendarID {
            guard let found = descriptors.first(where: { $0.id == destinationID }) else { throw DraftValidationError.invalidDestination }
            guard found.allowsContentModifications else { throw DraftValidationError.readOnlyDestination }
            destination = found
        } else {
            destination = .init(id: old.calendarID, title: old.calendarTitle, colorHex: "#000000", allowsContentModifications: true)
        }
        let resultRecurrence = recurrence(from: draft.recurrence, preserving: old.recurrence)
        let resultAlarms = alarms(from: draft.alarms, preserving: old.alarms)
        if let updateError { throw updateError }
        events[index] = .init(id: old.id, mutationID: old.mutationID, title: trimmed(draft.title), start: draft.start, end: draft.end, isAllDay: draft.isAllDay, calendarID: destination.id, calendarTitle: destination.title, allowsModification: old.allowsModification, hasRecurrence: resultRecurrence != .none, notes: draft.notes, location: draft.location, url: draft.url, alarms: resultAlarms, recurrence: resultRecurrence)
        eventUpdateCalls.append(.init(id: id, draft: draft, scope: scope))
        successfulWriteCount += 1
    }
    func deleteEvent(id: String, scope: RecurrenceEditScope) throws {
        guard accessState == .granted, let index = eventIndex(forMutationID: id) else { throw DraftValidationError.itemNotFound }
        guard events[index].allowsModification else { throw DraftValidationError.readOnlyDestination }
        guard scope != .futureOccurrences || events[index].hasRecurrence else { throw DraftValidationError.invalidRecurrenceScope }
        if let deleteError { throw deleteError }
        events.remove(at: index)
        eventDeleteCalls.append(.init(id: id, scope: scope))
        successfulWriteCount += 1
    }

    private func recurrence(from intent: RecurrenceMutationIntent, preserving previous: RecurrenceSnapshot = .none) -> RecurrenceSnapshot {
        switch intent { case .preserve: previous; case .clear: .none; case let .replace(rule): .editable(rule) }
    }
    private func alarms(from intent: EventAlarmMutationIntent, preserving previous: EventAlarmSnapshot = .none) -> EventAlarmSnapshot {
        switch intent { case .preserve: previous; case .clear: .none; case let .replace(offsets): .editable(offsets) }
    }
    private func eventIndex(forMutationID id: String) -> Int? {
        guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return events.firstIndex { event in
            guard let mutationID = event.mutationID,
                  !mutationID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
            return mutationID == id
        }
    }
    private func eventIndex(forDetailID id: String) -> Int? {
        events.firstIndex { event in
            if event.id == id { return true }
            guard let mutationID = event.mutationID,
                  !mutationID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
            return mutationID == id
        }
    }
    private func trimmed(_ title: String) -> String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
}

struct CompletionCall: Equatable {
    let id: String
    let completed: Bool
}

struct EventUpdateCall: Equatable { let id: String; let draft: EventDraft; let scope: RecurrenceEditScope }
struct EventDeleteCall: Equatable { let id: String; let scope: RecurrenceEditScope }
struct ReminderUpdateCall: Equatable { let id: String; let draft: ReminderDraft }

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
        let id = UUID(); routines.append(.init(id: id, title: draft.title, weekdays: draft.weekdays, window: draft.window, reminderHour: draft.reminderHour, reminderMinute: draft.reminderMinute, isPaused: false, isArchived: false, categoryID: draft.categoryID)); return id
    }

    func update(id: UUID, draft: RoutineDraft) throws { if let updateError { throw updateError }; guard let index = routines.firstIndex(where: { $0.id == id }) else { throw RoutineRepositoryError.routineNotFound }; updateCalls.append(.init(id: id, draft: draft)); let old = routines[index]; routines[index] = .init(id: id, title: draft.title, weekdays: draft.weekdays, window: draft.window, reminderHour: draft.reminderHour, reminderMinute: draft.reminderMinute, isPaused: old.isPaused, isArchived: old.isArchived, categoryID: draft.categoryID) }

    func setPaused(id: UUID, paused: Bool) throws { if let pauseError { throw pauseError }; guard let index = routines.firstIndex(where: { $0.id == id }) else { throw RoutineRepositoryError.routineNotFound }; pauseCalls.append(.init(id: id, value: paused)); let old = routines[index]; routines[index] = .init(id: id, title: old.title, weekdays: old.weekdays, window: old.window, reminderHour: old.reminderHour, reminderMinute: old.reminderMinute, isPaused: paused, isArchived: old.isArchived, categoryID: old.categoryID) }

    func setArchived(id: UUID, archived: Bool) throws { if let archiveError { throw archiveError }; guard let index = routines.firstIndex(where: { $0.id == id }) else { throw RoutineRepositoryError.routineNotFound }; archiveCalls.append(.init(id: id, value: archived)); let old = routines[index]; routines[index] = .init(id: id, title: old.title, weekdays: old.weekdays, window: old.window, reminderHour: old.reminderHour, reminderMinute: old.reminderMinute, isPaused: old.isPaused, isArchived: archived, categoryID: old.categoryID) }

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
    private(set) var reminderUpdateCalls: [ReminderUpdateCall] = []
    private(set) var reminderDeleteCalls: [String] = []
    private(set) var successfulWriteCount = 0
    var completedCalls: [CompletionCall] = []
    var completionError: Error?
    var createError: Error?
    var updateError: Error?
    var deleteError: Error?
    var fetchErrorAfterCompletion: Error?
    var fetchErrorAfterCreate: Error?
    var suspendNextRequest = false
    private(set) var fetchListIDs: [Set<String>] = []
    var suspendFetchAfterUndo = false
    var suspendNextFetch = false
    var allowMissingCompletion = false
    var omitCompletedAfterMutation = false
    private var fetchContinuation: CheckedContinuation<Void, Never>?
    private(set) var isFetchSuspended = false
    private var requestContinuation: CheckedContinuation<Void, Never>?
    private(set) var isRequestSuspended = false
    private let defaultListID: String?

    init(
        access: AccessState,
        requestedAccess: AccessState? = nil,
        reminders: [ReminderSnapshot] = [],
        descriptors: [ReminderListDescriptor] = [],
        fetchError: Error? = nil,
        defaultListID: String? = nil
    ) {
        accessState = access
        self.requestedAccess = requestedAccess ?? access
        self.reminders = reminders
        self.descriptors = descriptors
        self.fetchError = fetchError
        self.defaultListID = defaultListID
    }

    func requestFullAccess() async -> AccessState {
        requestCount += 1
        if suspendNextRequest {
            suspendNextRequest = false
            isRequestSuspended = true
            await withCheckedContinuation { requestContinuation = $0 }
            isRequestSuspended = false
        }
        accessState = requestedAccess
        return accessState
    }

    func resumeSuspendedRequest() { requestContinuation?.resume(); requestContinuation = nil }

    func lists() -> [ReminderListDescriptor] { accessState == .granted ? descriptors : [] }

    func fetchReminders(listIDs: Set<String>) async throws -> [ReminderSnapshot] {
        fetchListIDs.append(listIDs)
        guard accessState == .granted else { return [] }
        let result = reminders.filter { listIDs.isEmpty || listIDs.contains($0.listID) }
        let error = fetchError
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
        if let error {
            throw error
        }
        return result
    }

    func resumeSuspendedFetch() { fetchContinuation?.resume(); fetchContinuation = nil }

    func createReminder(_ draft: ReminderDraft) throws -> String? {
        guard accessState == .granted else { throw DraftValidationError.itemNotFound }
        if let createError { throw createError }
        if case .preserve = draft.schedule { throw DraftValidationError.recurringReminderRequiresDueDate }
        try validate(draft, preserving: nil)
        let destination: ReminderListDescriptor
        if let id = draft.listID {
            guard let found = descriptors.first(where: { $0.id == id }) else { throw DraftValidationError.invalidDestination }
            guard found.allowsContentModifications else { throw DraftValidationError.readOnlyDestination }
            destination = found
        } else {
            guard let defaultListID,
                  !defaultListID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let found = descriptors.first(where: { $0.id == defaultListID }) else { throw DraftValidationError.invalidDestination }
            guard found.allowsContentModifications else { throw DraftValidationError.readOnlyDestination }
            destination = found
        }
        createdDrafts.append(draft)
        let id = "created-task-\(createdDrafts.count)"
        let schedule = schedule(from: draft.schedule, preserving: nil)
        let recurrence = recurrence(from: draft.recurrence)
        reminders.append(.init(id: id, title: trimmed(draft.title), notes: draft.notes, dueDate: schedule?.date, dueHasTime: schedule?.hasTime ?? false, priority: draft.priority, listID: destination.id, listTitle: destination.title, isCompleted: false, allowsModification: true, hasRecurrence: recurrence != .none, alarm: alarm(from: draft.alarm), recurrence: recurrence))
        successfulWriteCount += 1
        return id
    }

    func setCompleted(id: String, completed: Bool) throws {
        guard accessState == .granted else { throw DraftValidationError.itemNotFound }
        if let completionError { throw completionError }
        guard allowMissingCompletion || reminders.contains(where: { $0.id == id }) else { throw RoutineRepositoryError.routineNotFound }
        if let item = reminders.first(where: { $0.id == id }), !item.allowsModification { throw DraftValidationError.readOnlyDestination }
        completedCalls.append(.init(id: id, completed: completed))
        if let index = reminders.firstIndex(where: { $0.id == id }) {
            let old = reminders[index]
            reminders[index] = old.withCompletion(completed)
        }
        if completed && omitCompletedAfterMutation { reminders.removeAll { $0.id == id } }
        successfulWriteCount += 1
    }
    func reminder(id: String) -> ReminderSnapshot? { guard accessState == .granted else { return nil }; return reminders.first { $0.id == id } }
    func updateReminder(id: String, draft: ReminderDraft) throws {
        guard accessState == .granted, let index = reminders.firstIndex(where: { $0.id == id }) else { throw DraftValidationError.itemNotFound }
        let old = reminders[index]
        guard old.allowsModification else { throw DraftValidationError.readOnlyDestination }
        try validate(draft, preserving: .init(date: old.dueDate ?? .distantPast, hasTime: old.dueHasTime), hasSchedule: old.dueDate != nil, hasRecurrence: old.hasRecurrence)
        let destination: ReminderListDescriptor
        if let destinationID = draft.listID {
            guard let found = descriptors.first(where: { $0.id == destinationID }) else { throw DraftValidationError.invalidDestination }
            guard found.allowsContentModifications else { throw DraftValidationError.readOnlyDestination }
            destination = found
        } else { destination = .init(id: old.listID, title: old.listTitle, colorHex: "#000000", allowsContentModifications: true) }
        let resultSchedule = schedule(from: draft.schedule, preserving: old.dueDate.map { .init(date: $0, hasTime: old.dueHasTime) })
        let resultRecurrence = recurrence(from: draft.recurrence, preserving: old.recurrence)
        if let updateError { throw updateError }
        reminders[index] = .init(id: old.id, title: trimmed(draft.title), notes: draft.notes, dueDate: resultSchedule?.date, dueHasTime: resultSchedule?.hasTime ?? false, priority: draft.priority, listID: destination.id, listTitle: destination.title, isCompleted: old.isCompleted, allowsModification: old.allowsModification, hasRecurrence: resultRecurrence != .none, alarm: alarm(from: draft.alarm, preserving: old.alarm), recurrence: resultRecurrence)
        reminderUpdateCalls.append(.init(id: id, draft: draft))
        successfulWriteCount += 1
    }
    func deleteReminder(id: String) throws { guard accessState == .granted, let index = reminders.firstIndex(where: { $0.id == id }) else { throw DraftValidationError.itemNotFound }; guard reminders[index].allowsModification else { throw DraftValidationError.readOnlyDestination }; if let deleteError { throw deleteError }; reminders.remove(at: index); reminderDeleteCalls.append(id); successfulWriteCount += 1 }

    private func validate(_ draft: ReminderDraft, preserving current: ReminderScheduleValue?, hasSchedule: Bool = false, hasRecurrence: Bool = false) throws {
        var effective = draft
        switch draft.schedule {
        case .preserve: effective.schedule = hasSchedule ? .replace(current!) : .clear
        case .clear, .replace: break
        }
        if hasRecurrence, case .clear = effective.schedule, effective.recurrence == .preserve { throw DraftValidationError.recurringReminderRequiresDueDate }
        try ReminderDraftValidator.validate(effective)
    }
    private func schedule(from intent: ReminderScheduleMutationIntent, preserving previous: ReminderScheduleValue?) -> ReminderScheduleValue? { switch intent { case .preserve: previous; case .clear: nil; case let .replace(value): value } }
    private func recurrence(from intent: RecurrenceMutationIntent, preserving previous: RecurrenceSnapshot = .none) -> RecurrenceSnapshot { switch intent { case .preserve: previous; case .clear: .none; case let .replace(rule): .editable(rule) } }
    private func alarm(from intent: ReminderAlarmMutationIntent, preserving previous: ReminderAlarmSnapshot = .none) -> ReminderAlarmSnapshot { switch intent { case .preserve: previous; case .clear: .none; case let .replace(date): .editable(date) } }
    private func trimmed(_ title: String) -> String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
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
    private var readContinuations: [CheckedContinuation<Void, Never>] = []
    private var requestContinuation: CheckedContinuation<Void, Never>?
    var suspendNextRead: Bool
    var suspendNextRequest = false
    private(set) var readCount = 0
    private(set) var completedReadCount = 0
    private(set) var requestCount = 0
    private(set) var isRequestSuspended = false
    var isReadSuspended: Bool { !readContinuations.isEmpty }

    init(access: AccessState, requestedAccess: AccessState? = nil, suspendRead: Bool = false) {
        state = access
        requested = requestedAccess ?? access
        suspendNextRead = suspendRead
    }

    var accessState: AccessState {
        get async {
            readCount += 1
            if suspendNextRead {
                suspendNextRead = false
                await withCheckedContinuation { readContinuations.append($0) }
            }
            completedReadCount += 1
            return state
        }
    }

    func requestAccess() async -> AccessState {
        requestCount += 1
        if suspendNextRequest {
            suspendNextRequest = false
            isRequestSuspended = true
            await withCheckedContinuation { requestContinuation = $0 }
            isRequestSuspended = false
        }
        state = requested
        return state
    }
    func resumeRead() {
        guard !readContinuations.isEmpty else { return }
        readContinuations.removeFirst().resume()
    }
    func resumeSuspendedRequest() { requestContinuation?.resume(); requestContinuation = nil }
    func setAccessState(_ state: AccessState) { self.state = state }
}
