import Foundation

@MainActor
final class DemoCalendarService: CalendarServicing {
    var accessState: AccessState
    private(set) var events: [CalendarEventSnapshot]
    private(set) var successfulWriteCount = 0
    private let descriptor = CalendarDescriptor(
        id: "demo-calendar",
        title: "Personal",
        colorHex: "#3A8D7C",
        allowsContentModifications: true
    )
    private var shouldFailNextCreate: Bool
    private var shouldFailNextUpdate: Bool
    private var shouldFailNextDelete: Bool
    private let multipleSources: Bool
    private let includeReadOnlySource: Bool

    init(access: AccessState, failFirstCreate: Bool = false, failFirstUpdate: Bool = false, failFirstDelete: Bool = false, multipleSources: Bool = false, includeReadOnlySource: Bool = false) {
        accessState = access
        shouldFailNextCreate = failFirstCreate
        shouldFailNextUpdate = failFirstUpdate
        shouldFailNextDelete = failFirstDelete
        self.multipleSources = multipleSources
        self.includeReadOnlySource = includeReadOnlySource
        let start = Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: .now)!
        events = [
            .init(
                id: "demo-event",
                mutationID: "demo-event",
                title: "Coffee",
                start: start,
                end: start.addingTimeInterval(3_600),
                isAllDay: false,
                calendarID: "demo-calendar",
                calendarTitle: "Personal",
                allowsModification: true,
                hasRecurrence: false
            )
        ]
        if multipleSources {
            events.append(.init(id: "demo-event-work", mutationID: "demo-event-work", title: "Planning", start: start.addingTimeInterval(1_800), end: start.addingTimeInterval(5_400), isAllDay: false, calendarID: "demo-calendar-work", calendarTitle: "Work", allowsModification: true, hasRecurrence: false))
        }
        if includeReadOnlySource {
            events.append(.init(id: "demo-event-read-only", mutationID: nil, title: "Read-only event", start: start.addingTimeInterval(2_700), end: start.addingTimeInterval(4_500), isAllDay: false, calendarID: "demo-calendar-read-only", calendarTitle: "Read Only", allowsModification: false, hasRecurrence: false))
        }
    }

    func requestFullAccess() async -> AccessState {
        if accessState == .notDetermined { accessState = .granted }
        return accessState
    }

    func calendars() -> [CalendarDescriptor] {
        guard accessState == .granted else { return [] }
        return descriptors
    }

    func fetchEvents(in interval: DateInterval, calendarIDs: Set<String>) throws -> [CalendarEventSnapshot] {
        guard accessState == .granted else { return [] }
        return events.filter {
            (calendarIDs.isEmpty || calendarIDs.contains($0.calendarID))
                && $0.start < interval.end && $0.end > interval.start
        }
    }

    func createEvent(_ draft: EventDraft) throws -> String? {
        guard accessState == .granted else { throw DraftValidationError.itemNotFound }
        try EventDraftValidator.validate(draft)
        let destination: CalendarDescriptor
        if let calendarID = draft.calendarID {
            guard let match = descriptors.first(where: { $0.id == calendarID }) else { throw DraftValidationError.invalidDestination }
            guard match.allowsContentModifications else { throw DraftValidationError.readOnlyDestination }
            destination = match
        } else {
            destination = descriptor
        }
        if shouldFailNextCreate {
            shouldFailNextCreate = false
            throw DemoCreateError.failed
        }
        let id = "demo-event-\(events.count + 1)"
        events.append(
            .init(
                id: id,
                mutationID: id,
                title: trimmed(draft.title),
                start: draft.start,
                end: draft.end,
                isAllDay: draft.isAllDay,
                calendarID: destination.id,
                calendarTitle: destination.title,
                allowsModification: destination.allowsContentModifications,
                hasRecurrence: recurrence(from: draft.recurrence) != .none,
                notes: draft.notes,
                location: draft.location,
                url: draft.url,
                alarms: alarms(from: draft.alarms),
                recurrence: recurrence(from: draft.recurrence)
            )
        )
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
        } else { destination = .init(id: old.calendarID, title: old.calendarTitle, colorHex: "#000000", allowsContentModifications: true) }
        if shouldFailNextUpdate { shouldFailNextUpdate = false; throw DemoCreateError.failed }
        let recurrence = recurrence(from: draft.recurrence, preserving: old.recurrence)
        events[index] = .init(id: old.id, mutationID: old.mutationID, title: trimmed(draft.title), start: draft.start, end: draft.end, isAllDay: draft.isAllDay, calendarID: destination.id, calendarTitle: destination.title, allowsModification: old.allowsModification, hasRecurrence: recurrence != .none, notes: draft.notes, location: draft.location, url: draft.url, alarms: alarms(from: draft.alarms, preserving: old.alarms), recurrence: recurrence)
        successfulWriteCount += 1
    }
    func deleteEvent(id: String, scope: RecurrenceEditScope) throws { guard accessState == .granted, let index = eventIndex(forMutationID: id) else { throw DraftValidationError.itemNotFound }; guard events[index].allowsModification else { throw DraftValidationError.readOnlyDestination }; guard scope != .futureOccurrences || events[index].hasRecurrence else { throw DraftValidationError.invalidRecurrenceScope }; if shouldFailNextDelete { shouldFailNextDelete = false; throw DemoCreateError.failed }; events.remove(at: index); successfulWriteCount += 1 }

    private func recurrence(from intent: RecurrenceMutationIntent, preserving previous: RecurrenceSnapshot = .none) -> RecurrenceSnapshot { switch intent { case .preserve: previous; case .clear: .none; case let .replace(rule): .editable(rule) } }
    private func alarms(from intent: EventAlarmMutationIntent, preserving previous: EventAlarmSnapshot = .none) -> EventAlarmSnapshot { switch intent { case .preserve: previous; case .clear: .none; case let .replace(offsets): .editable(offsets) } }
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

    private var descriptors: [CalendarDescriptor] {
        var values = [descriptor]
        if multipleSources { values.append(.init(id: "demo-calendar-work", title: "Work", colorHex: "#4868A8", allowsContentModifications: true)) }
        if includeReadOnlySource { values.append(.init(id: "demo-calendar-read-only", title: "Read Only", colorHex: "#777777", allowsContentModifications: false)) }
        return values
    }
}

private enum DemoCreateError: Error { case failed }

@MainActor
final class DemoRemindersService: RemindersServicing {
    var accessState: AccessState
    private(set) var successfulWriteCount = 0
    private var values = [
        ReminderSnapshot(
            id: "demo-task",
            title: "Buy milk",
            notes: nil,
            dueDate: Calendar.current.date(bySettingHour: 14, minute: 0, second: 0, of: .now)!,
            dueHasTime: true,
            priority: 5,
            listID: "demo-list",
            listTitle: "Tasks",
            isCompleted: false,
            allowsModification: true,
            hasRecurrence: false
        )
    ]
    private let descriptor = ReminderListDescriptor(
        id: "demo-list",
        title: "Tasks",
        colorHex: "#CB6B4F",
        allowsContentModifications: true
    )
    private var shouldFailNextCreate: Bool
    private var shouldFailNextUpdate: Bool
    private var shouldFailNextDelete: Bool
    private let multipleSources: Bool
    private let includeReadOnlySource: Bool

    init(access: AccessState, failFirstCreate: Bool = false, failFirstUpdate: Bool = false, failFirstDelete: Bool = false, multipleSources: Bool = false, includeReadOnlySource: Bool = false) {
        accessState = access
        shouldFailNextCreate = failFirstCreate
        shouldFailNextUpdate = failFirstUpdate
        shouldFailNextDelete = failFirstDelete
        self.multipleSources = multipleSources
        self.includeReadOnlySource = includeReadOnlySource
    }

    func requestFullAccess() async -> AccessState {
        if accessState == .notDetermined { accessState = .granted }
        return accessState
    }

    func lists() -> [ReminderListDescriptor] { accessState == .granted ? descriptors : [] }

    func fetchReminders(listIDs: Set<String>) async throws -> [ReminderSnapshot] {
        guard accessState == .granted else { return [] }
        return values.filter { listIDs.isEmpty || listIDs.contains($0.listID) }
    }

    func createReminder(_ draft: ReminderDraft) throws -> String? {
        guard accessState == .granted else { throw DraftValidationError.itemNotFound }
        if case .preserve = draft.schedule { throw DraftValidationError.recurringReminderRequiresDueDate }
        try validate(draft, preserving: nil)
        let destination: ReminderListDescriptor
        if let listID = draft.listID {
            guard let match = descriptors.first(where: { $0.id == listID }) else { throw DraftValidationError.invalidDestination }
            guard match.allowsContentModifications else { throw DraftValidationError.readOnlyDestination }
            destination = match
        } else {
            destination = descriptor
        }
        if shouldFailNextCreate { shouldFailNextCreate = false; throw DemoCreateError.failed }
        let id = "demo-task-\(values.count + 1)"
        values.append(
            .init(
                id: id,
                title: trimmed(draft.title),
                notes: draft.notes,
                dueDate: schedule(from: draft.schedule, preserving: nil)?.date,
                dueHasTime: schedule(from: draft.schedule, preserving: nil)?.hasTime ?? false,
                priority: draft.priority,
                listID: destination.id,
                listTitle: destination.title,
                isCompleted: false,
                allowsModification: true,
                hasRecurrence: recurrence(from: draft.recurrence) != .none,
                alarm: alarm(from: draft.alarm),
                recurrence: recurrence(from: draft.recurrence)
            )
        )
        successfulWriteCount += 1
        return id
    }

    private var descriptors: [ReminderListDescriptor] {
        var descriptors = [descriptor]
        if multipleSources { descriptors.append(.init(id: "demo-list-alternate", title: "Alternate", colorHex: "#4868A8", allowsContentModifications: true)) }
        if includeReadOnlySource { descriptors.append(.init(id: "demo-list-read-only", title: "Read Only", colorHex: "#777777", allowsContentModifications: false)) }
        return descriptors
    }

    func setCompleted(id: String, completed: Bool) throws {
        guard accessState == .granted else { throw DraftValidationError.itemNotFound }
        guard let index = values.firstIndex(where: { $0.id == id }) else { throw DraftValidationError.itemNotFound }
        let old = values[index]
        guard old.allowsModification else { throw DraftValidationError.readOnlyDestination }
        values[index] = old.withCompletion(completed)
        successfulWriteCount += 1
    }
    func reminder(id: String) -> ReminderSnapshot? { guard accessState == .granted else { return nil }; return values.first { $0.id == id } }
    func updateReminder(id: String, draft: ReminderDraft) throws {
        guard accessState == .granted, let index = values.firstIndex(where: { $0.id == id }) else { throw DraftValidationError.itemNotFound }
        let old = values[index]
        guard old.allowsModification else { throw DraftValidationError.readOnlyDestination }
        try validate(draft, preserving: old.dueDate.map { .init(date: $0, hasTime: old.dueHasTime) }, hasRecurrence: old.hasRecurrence)
        let destination: ReminderListDescriptor
        if let destinationID = draft.listID { guard let found = descriptors.first(where: { $0.id == destinationID }) else { throw DraftValidationError.invalidDestination }; guard found.allowsContentModifications else { throw DraftValidationError.readOnlyDestination }; destination = found } else { destination = .init(id: old.listID, title: old.listTitle, colorHex: "#000000", allowsContentModifications: true) }
        if shouldFailNextUpdate { shouldFailNextUpdate = false; throw DemoCreateError.failed }
        let schedule = schedule(from: draft.schedule, preserving: old.dueDate.map { .init(date: $0, hasTime: old.dueHasTime) })
        let recurrence = recurrence(from: draft.recurrence, preserving: old.recurrence)
        values[index] = .init(id: old.id, title: trimmed(draft.title), notes: draft.notes, dueDate: schedule?.date, dueHasTime: schedule?.hasTime ?? false, priority: draft.priority, listID: destination.id, listTitle: destination.title, isCompleted: old.isCompleted, allowsModification: old.allowsModification, hasRecurrence: recurrence != .none, alarm: alarm(from: draft.alarm, preserving: old.alarm), recurrence: recurrence)
        successfulWriteCount += 1
    }
    func deleteReminder(id: String) throws { guard accessState == .granted, let index = values.firstIndex(where: { $0.id == id }) else { throw DraftValidationError.itemNotFound }; guard values[index].allowsModification else { throw DraftValidationError.readOnlyDestination }; if shouldFailNextDelete { shouldFailNextDelete = false; throw DemoCreateError.failed }; values.remove(at: index); successfulWriteCount += 1 }

    private func validate(_ draft: ReminderDraft, preserving current: ReminderScheduleValue?, hasRecurrence: Bool = false) throws { var effective = draft; if case .preserve = draft.schedule { effective.schedule = current.map(ReminderScheduleMutationIntent.replace) ?? .clear }; if hasRecurrence, case .clear = effective.schedule, effective.recurrence == .preserve { throw DraftValidationError.recurringReminderRequiresDueDate }; try ReminderDraftValidator.validate(effective) }
    private func schedule(from intent: ReminderScheduleMutationIntent, preserving previous: ReminderScheduleValue?) -> ReminderScheduleValue? { switch intent { case .preserve: previous; case .clear: nil; case let .replace(value): value } }
    private func recurrence(from intent: RecurrenceMutationIntent, preserving previous: RecurrenceSnapshot = .none) -> RecurrenceSnapshot { switch intent { case .preserve: previous; case .clear: .none; case let .replace(rule): .editable(rule) } }
    private func alarm(from intent: ReminderAlarmMutationIntent, preserving previous: ReminderAlarmSnapshot = .none) -> ReminderAlarmSnapshot { switch intent { case .preserve: previous; case .clear: .none; case let .replace(date): .editable(date) } }
    private func trimmed(_ title: String) -> String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
}

@MainActor
final class DemoRoutineRepository: RoutineRepository {
    private var values = [
        RoutineSnapshot(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            title: "Read",
            weekdays: [1, 2, 3, 4, 5, 6, 7],
            window: .evening,
            reminderHour: nil,
            reminderMinute: nil,
            isPaused: false,
            isArchived: false
        )
    ]
    private var completed: [UUID: Set<LocalDay>] = [:]
    private var shouldFailNextDelete: Bool
    private var shouldFailNextCreate: Bool
    private var shouldFailNextUpdate: Bool
    init(failFirstDelete: Bool = false, failFirstCreate: Bool = false, failFirstUpdate: Bool = false, longTitle: Bool = false) { shouldFailNextDelete = failFirstDelete; shouldFailNextCreate = failFirstCreate; shouldFailNextUpdate = failFirstUpdate; if longTitle { let old = values[0]; values[0] = .init(id: old.id, title: "Read a long and thoughtfully named routine before bed every evening", weekdays: old.weekdays, window: old.window, reminderHour: old.reminderHour, reminderMinute: old.reminderMinute, isPaused: old.isPaused, isArchived: old.isArchived) } }

    func list(includeArchived: Bool) throws -> [RoutineSnapshot] {
        includeArchived ? values : values.filter { !$0.isArchived }
    }

    func create(_ draft: RoutineDraft) throws -> UUID {
        if shouldFailNextCreate { shouldFailNextCreate = false; throw DemoCreateError.failed }
        let id = UUID()
        values.append(.init(id: id, title: draft.title, weekdays: draft.weekdays, window: draft.window, reminderHour: draft.reminderHour, reminderMinute: draft.reminderMinute, isPaused: false, isArchived: false))
        return id
    }

    func update(id: UUID, draft: RoutineDraft) throws {
        if shouldFailNextUpdate { shouldFailNextUpdate = false; throw DemoCreateError.failed }
        guard let index = values.firstIndex(where: { $0.id == id }) else { throw RoutineRepositoryError.routineNotFound }
        let old = values[index]
        values[index] = .init(id: id, title: draft.title, weekdays: draft.weekdays, window: draft.window, reminderHour: draft.reminderHour, reminderMinute: draft.reminderMinute, isPaused: old.isPaused, isArchived: old.isArchived)
    }

    func setPaused(id: UUID, paused: Bool) throws {
        try mutate(id) { .init(id: $0.id, title: $0.title, weekdays: $0.weekdays, window: $0.window, reminderHour: $0.reminderHour, reminderMinute: $0.reminderMinute, isPaused: paused, isArchived: $0.isArchived) }
    }

    func setArchived(id: UUID, archived: Bool) throws {
        try mutate(id) { .init(id: $0.id, title: $0.title, weekdays: $0.weekdays, window: $0.window, reminderHour: $0.reminderHour, reminderMinute: $0.reminderMinute, isPaused: $0.isPaused, isArchived: archived) }
    }

    func delete(id: UUID) throws {
        if shouldFailNextDelete { shouldFailNextDelete = false; throw DemoCreateError.failed }
        guard values.contains(where: { $0.id == id }) else { throw RoutineRepositoryError.routineNotFound }
        values.removeAll { $0.id == id }
        completed[id] = nil
    }

    func setCompleted(routineID: UUID, day: LocalDay, completed state: Bool) throws {
        guard values.contains(where: { $0.id == routineID }) else { throw RoutineRepositoryError.routineNotFound }
        if state {
            completed[routineID, default: []].insert(day)
        } else {
            completed[routineID]?.remove(day)
        }
    }

    func isCompleted(routineID: UUID, day: LocalDay) throws -> Bool {
        completed[routineID, default: []].contains(day)
    }

    func completedDays(routineID: UUID) throws -> Set<LocalDay> {
        completed[routineID, default: []]
    }

    private func mutate(_ id: UUID, _ transform: (RoutineSnapshot) -> RoutineSnapshot) throws {
        guard let index = values.firstIndex(where: { $0.id == id }) else { throw RoutineRepositoryError.routineNotFound }
        values[index] = transform(values[index])
    }
}

@MainActor
final class DemoNotificationAuthorizer: NotificationAuthorizing {
    private var state: AccessState

    init(access: AccessState) { state = access }

    var accessState: AccessState {
        get async { state }
    }

    func requestAccess() async -> AccessState {
        if state == .notDetermined { state = .granted }
        return state
    }
}
