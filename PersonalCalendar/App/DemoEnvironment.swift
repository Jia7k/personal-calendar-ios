import Foundation

@MainActor
final class DemoCalendarService: CalendarServicing {
    var accessState: AccessState
    private(set) var events: [CalendarEventSnapshot]
    private let descriptor = CalendarDescriptor(
        id: "demo-calendar",
        title: "Personal",
        colorHex: "#3A8D7C",
        allowsContentModifications: true
    )
    private var shouldFailNextCreate: Bool

    init(access: AccessState, failFirstCreate: Bool = false) {
        accessState = access
        shouldFailNextCreate = failFirstCreate
        let start = Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: .now)!
        events = [
            .init(
                id: "demo-event",
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
    }

    func requestFullAccess() async -> AccessState {
        accessState = .granted
        return accessState
    }

    func calendars() -> [CalendarDescriptor] { [descriptor] }

    func fetchEvents(in interval: DateInterval, calendarIDs: Set<String>) throws -> [CalendarEventSnapshot] {
        guard accessState == .granted else { return [] }
        return events.filter {
            (calendarIDs.isEmpty || calendarIDs.contains($0.calendarID))
                && $0.start < interval.end && $0.end > interval.start
        }
    }

    func createEvent(_ draft: EventDraft) throws -> String {
        if shouldFailNextCreate {
            shouldFailNextCreate = false
            throw DemoCreateError.failed
        }
        let id = "demo-event-\(events.count + 1)"
        events.append(
            .init(
                id: id,
                title: draft.title,
                start: draft.start,
                end: draft.end,
                isAllDay: draft.isAllDay,
                calendarID: descriptor.id,
                calendarTitle: descriptor.title,
                allowsModification: true,
                hasRecurrence: false
            )
        )
        return id
    }
}

private enum DemoCreateError: Error { case failed }

@MainActor
final class DemoRemindersService: RemindersServicing {
    var accessState: AccessState
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

    init(access: AccessState, failFirstCreate: Bool = false) { accessState = access; shouldFailNextCreate = failFirstCreate }

    func requestFullAccess() async -> AccessState {
        accessState = .granted
        return accessState
    }

    func lists() -> [ReminderListDescriptor] { [descriptor] }

    func fetchReminders(listIDs: Set<String>) async throws -> [ReminderSnapshot] {
        guard accessState == .granted else { return [] }
        return values.filter { listIDs.isEmpty || listIDs.contains($0.listID) }
    }

    func createReminder(_ draft: ReminderDraft) throws -> String {
        if shouldFailNextCreate { shouldFailNextCreate = false; throw DemoCreateError.failed }
        let id = "demo-task-\(values.count + 1)"
        values.append(
            .init(
                id: id,
                title: draft.title,
                notes: draft.notes,
                dueDate: draft.dueDate,
                dueHasTime: draft.dueHasTime,
                priority: draft.priority,
                listID: descriptor.id,
                listTitle: descriptor.title,
                isCompleted: false,
                allowsModification: true,
                hasRecurrence: false
            )
        )
        return id
    }

    func setCompleted(id: String, completed: Bool) throws {
        guard let index = values.firstIndex(where: { $0.id == id }) else { throw RoutineRepositoryError.routineNotFound }
        let old = values[index]
        values[index] = .init(
            id: old.id,
            title: old.title,
            notes: old.notes,
            dueDate: old.dueDate,
            dueHasTime: old.dueHasTime,
            priority: old.priority,
            listID: old.listID,
            listTitle: old.listTitle,
            isCompleted: completed,
            allowsModification: old.allowsModification,
            hasRecurrence: old.hasRecurrence
        )
    }
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
    init(failFirstDelete: Bool = false) { shouldFailNextDelete = failFirstDelete }

    func list(includeArchived: Bool) throws -> [RoutineSnapshot] {
        includeArchived ? values : values.filter { !$0.isArchived }
    }

    func create(_ draft: RoutineDraft) throws -> UUID {
        let id = UUID()
        values.append(.init(id: id, title: draft.title, weekdays: draft.weekdays, window: draft.window, reminderHour: draft.reminderHour, reminderMinute: draft.reminderMinute, isPaused: false, isArchived: false))
        return id
    }

    func update(id: UUID, draft: RoutineDraft) throws {
        guard let index = values.firstIndex(where: { $0.id == id }) else { throw RoutineRepositoryError.routineNotFound }
        let old = values[index]
        values[index] = .init(id: id, title: draft.title, weekdays: draft.weekdays, window: draft.window, reminderHour: draft.reminderHour, reminderMinute: draft.reminderMinute, isPaused: old.isPaused, isArchived: old.isArchived)
    }

    func setPaused(id: UUID, paused: Bool) throws {
        mutate(id) { .init(id: $0.id, title: $0.title, weekdays: $0.weekdays, window: $0.window, reminderHour: $0.reminderHour, reminderMinute: $0.reminderMinute, isPaused: paused, isArchived: $0.isArchived) }
    }

    func setArchived(id: UUID, archived: Bool) throws {
        mutate(id) { .init(id: $0.id, title: $0.title, weekdays: $0.weekdays, window: $0.window, reminderHour: $0.reminderHour, reminderMinute: $0.reminderMinute, isPaused: $0.isPaused, isArchived: archived) }
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

    private func mutate(_ id: UUID, _ transform: (RoutineSnapshot) -> RoutineSnapshot) {
        if let index = values.firstIndex(where: { $0.id == id }) {
            values[index] = transform(values[index])
        }
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
        state = .granted
        return state
    }
}
