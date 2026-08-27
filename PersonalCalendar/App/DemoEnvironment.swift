import Foundation

enum DemoProfileFixture {
    static let homeCalendarID = "demo-calendar-home"
    static let schoolCalendarID = "demo-calendar-school"
    static let workCalendarID = "demo-calendar-work"
    static let birthdaysCalendarID = "demo-calendar-birthdays"

    static let personalListID = "demo-list-personal"
    static let assignmentsListID = "demo-list-assignments"
    static let workListID = "demo-list-work"

    static let personalRoutineID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    static let schoolRoutineID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    static let workRoutineID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!

    @MainActor
    static func configure(profiles: any ProfileRepository) throws {
        try profiles.update(
            id: SeedProfile.personalID,
            draft: ProfileDraft(
                name: "Personal",
                colorHex: "#3A8D7C",
                symbolName: "person.fill",
                calendarIDs: [homeCalendarID],
                reminderListIDs: [personalListID],
                routineIDs: [personalRoutineID, schoolRoutineID],
                defaultCalendarID: homeCalendarID,
                defaultReminderListID: personalListID
            )
        )
        try profiles.update(
            id: SeedProfile.schoolID,
            draft: ProfileDraft(
                name: "School",
                colorHex: "#4868A8",
                symbolName: "graduationcap.fill",
                calendarIDs: [schoolCalendarID],
                reminderListIDs: [assignmentsListID],
                routineIDs: [schoolRoutineID],
                defaultCalendarID: schoolCalendarID,
                defaultReminderListID: assignmentsListID
            )
        )
        try profiles.update(
            id: SeedProfile.workID,
            draft: ProfileDraft(
                name: "Work",
                colorHex: "#CB6B4F",
                symbolName: "briefcase.fill",
                calendarIDs: [workCalendarID],
                reminderListIDs: [workListID],
                routineIDs: [workRoutineID],
                defaultCalendarID: workCalendarID,
                defaultReminderListID: workListID
            )
        )
    }
}

@MainActor
final class DemoCalendarService: CalendarServicing {
    var accessState: AccessState
    private(set) var events: [CalendarEventSnapshot]
    private(set) var successfulWriteCount = 0
    private let profileFixtures: Bool
    private var shouldFailNextCreate: Bool
    private var shouldFailNextUpdate: Bool
    private var shouldFailNextDelete: Bool
    private let multipleSources: Bool
    private let includeReadOnlySource: Bool
    private let replacePrimaryEventWithReadOnly: Bool
    private let includeRecurringItems: Bool
    private let includeUnsupportedItems: Bool

    init(access: AccessState, failFirstCreate: Bool = false, failFirstUpdate: Bool = false, failFirstDelete: Bool = false, multipleSources: Bool = false, includeReadOnlySource: Bool = false, replacePrimaryEventWithReadOnly: Bool = false, includeRecurringItems: Bool = false, includeUnsupportedItems: Bool = false, profileFixtures: Bool = false, dailyQOLFixtures: Bool = false) {
        accessState = access
        shouldFailNextCreate = failFirstCreate
        shouldFailNextUpdate = failFirstUpdate
        shouldFailNextDelete = failFirstDelete
        self.multipleSources = multipleSources
        self.includeReadOnlySource = includeReadOnlySource
        self.replacePrimaryEventWithReadOnly = replacePrimaryEventWithReadOnly
        self.includeRecurringItems = includeRecurringItems
        self.includeUnsupportedItems = includeUnsupportedItems
        self.profileFixtures = profileFixtures
        let start = dailyQOLFixtures
            ? Date().addingTimeInterval(-300)
            : Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: .now)!
        if profileFixtures {
            let startOfDay = Calendar.current.startOfDay(for: start)
            events = [
                .init(id: "demo-personal-event", mutationID: "demo-personal-event", title: "Coffee", start: start.addingTimeInterval(-3_600), end: start, isAllDay: false, calendarID: DemoProfileFixture.homeCalendarID, calendarTitle: "Home", allowsModification: true, hasRecurrence: false),
                .init(id: "demo-school-event", mutationID: "demo-school-event", title: "INF 2003 Lecture", start: start, end: start.addingTimeInterval(7_200), isAllDay: false, calendarID: DemoProfileFixture.schoolCalendarID, calendarTitle: "Google School", allowsModification: true, hasRecurrence: true, location: "Online"),
                .init(id: "demo-work-event", mutationID: "demo-work-event", title: "Planning", start: start.addingTimeInterval(10_800), end: start.addingTimeInterval(14_400), isAllDay: false, calendarID: DemoProfileFixture.workCalendarID, calendarTitle: "Work", allowsModification: true, hasRecurrence: false),
                .init(id: "demo-birthday-event", mutationID: nil, title: "Birthday", start: startOfDay, end: Calendar.current.date(byAdding: .day, value: 1, to: startOfDay)!, isAllDay: true, calendarID: DemoProfileFixture.birthdaysCalendarID, calendarTitle: "Birthdays", allowsModification: false, hasRecurrence: true)
            ]
        } else {
            events = [
                .init(
                    id: "demo-event",
                    mutationID: "demo-event",
                    title: replacePrimaryEventWithReadOnly ? "Public holiday" : "Coffee",
                    start: start,
                    end: start.addingTimeInterval(3_600),
                    isAllDay: false,
                    calendarID: replacePrimaryEventWithReadOnly ? "demo-calendar-read-only" : "demo-calendar",
                    calendarTitle: replacePrimaryEventWithReadOnly ? "Read Only" : "Personal",
                    allowsModification: !replacePrimaryEventWithReadOnly,
                    hasRecurrence: false
                )
            ]
        }
        if multipleSources {
            events.append(.init(id: "demo-event-work", mutationID: "demo-event-work", title: "Planning", start: start.addingTimeInterval(1_800), end: start.addingTimeInterval(5_400), isAllDay: false, calendarID: "demo-calendar-work", calendarTitle: "Work", allowsModification: true, hasRecurrence: false))
        }
        if includeReadOnlySource {
            events.append(.init(id: "demo-event-read-only", mutationID: "demo-event-read-only", title: "Read-only event", start: start.addingTimeInterval(2_700), end: start.addingTimeInterval(4_500), isAllDay: false, calendarID: "demo-calendar-read-only", calendarTitle: "Read Only", allowsModification: false, hasRecurrence: false))
            events.append(.init(id: "demo-event-nonaddressable", mutationID: nil, title: "Event without editing ID", start: start.addingTimeInterval(5_400), end: start.addingTimeInterval(6_300), isAllDay: false, calendarID: "demo-calendar-read-only", calendarTitle: "Read Only", allowsModification: false, hasRecurrence: false))
        }
        if includeRecurringItems {
            let endDate = Calendar.current.date(byAdding: .day, value: 30, to: start)
            let recurrence = RecurrenceRuleDraft(frequency: .weekly, interval: 2, weekdays: [2, 4], endDate: endDate)
            events.append(
                .init(
                    id: "demo-event-recurring",
                    mutationID: "demo-event-recurring",
                    title: "Biweekly planning",
                    start: start.addingTimeInterval(7_200),
                    end: start.addingTimeInterval(10_800),
                    isAllDay: false,
                    calendarID: "demo-calendar",
                    calendarTitle: "Personal",
                    allowsModification: true,
                    hasRecurrence: true,
                    alarms: .editable([-900, -3_600]),
                    recurrence: .editable(recurrence)
                )
            )
        }
        if includeUnsupportedItems {
            events.append(
                .init(
                    id: "demo-event-unsupported",
                    mutationID: "demo-event-unsupported",
                    title: "Provider-defined event",
                    start: start.addingTimeInterval(14_400),
                    end: start.addingTimeInterval(18_000),
                    isAllDay: false,
                    calendarID: "demo-calendar",
                    calendarTitle: "Personal",
                    allowsModification: true,
                    hasRecurrence: true,
                    notes: "Provider metadata must survive ordinary edits.",
                    alarms: .unsupported(summary: "Provider-defined alerts"),
                    recurrence: .unsupported(summary: "Provider-defined repeat")
                )
            )
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
        if profileFixtures {
            return [
                .init(id: DemoProfileFixture.homeCalendarID, title: "Home", colorHex: "#3A8D7C", allowsContentModifications: true),
                .init(id: DemoProfileFixture.schoolCalendarID, title: "Google School", colorHex: "#4868A8", allowsContentModifications: true),
                .init(id: DemoProfileFixture.workCalendarID, title: "Work", colorHex: "#CB6B4F", allowsContentModifications: true),
                .init(id: DemoProfileFixture.birthdaysCalendarID, title: "Birthdays", colorHex: "#8A63B8", allowsContentModifications: false)
            ]
        }
        var values = [descriptor]
        if multipleSources { values.append(.init(id: "demo-calendar-work", title: "Work", colorHex: "#4868A8", allowsContentModifications: true)) }
        if includeReadOnlySource || replacePrimaryEventWithReadOnly { values.append(.init(id: "demo-calendar-read-only", title: "Read Only", colorHex: "#777777", allowsContentModifications: false)) }
        return values
    }

    private var descriptor: CalendarDescriptor {
        profileFixtures
            ? .init(id: DemoProfileFixture.homeCalendarID, title: "Home", colorHex: "#3A8D7C", allowsContentModifications: true)
            : .init(id: "demo-calendar", title: "Personal", colorHex: "#3A8D7C", allowsContentModifications: true)
    }
}

private enum DemoCreateError: Error { case failed }

@MainActor
final class DemoRemindersService: RemindersServicing {
    var accessState: AccessState
    private(set) var successfulWriteCount = 0
    private var values: [ReminderSnapshot]
    private let profileFixtures: Bool
    private var shouldFailNextCreate: Bool
    private var shouldFailNextUpdate: Bool
    private var shouldFailNextDelete: Bool
    private let multipleSources: Bool
    private let includeReadOnlySource: Bool
    private let includeRecurringItems: Bool
    private let includeUnsupportedItems: Bool

    init(access: AccessState, failFirstCreate: Bool = false, failFirstUpdate: Bool = false, failFirstDelete: Bool = false, multipleSources: Bool = false, includeReadOnlySource: Bool = false, includeRecurringItems: Bool = false, includeUnsupportedItems: Bool = false, includeOverdueTask: Bool = false, profileFixtures: Bool = false, dailyQOLFixtures: Bool = false, dailyTaskRescueFixtures: Bool = false) {
        accessState = access
        shouldFailNextCreate = failFirstCreate
        shouldFailNextUpdate = failFirstUpdate
        shouldFailNextDelete = failFirstDelete
        self.multipleSources = multipleSources
        self.includeReadOnlySource = includeReadOnlySource
        self.includeRecurringItems = includeRecurringItems
        self.includeUnsupportedItems = includeUnsupportedItems
        self.profileFixtures = profileFixtures
        let calendar = Calendar.current
        let capturedToday = calendar.startOfDay(for: Date())
        let due = dailyQOLFixtures
            ? Date().addingTimeInterval(7_200)
            : calendar.date(bySettingHour: 14, minute: 0, second: 0, of: capturedToday)!
        if profileFixtures {
            values = [
                .init(id: "demo-personal-task", title: "Buy milk", notes: nil, dueDate: due, dueHasTime: true, priority: 5, listID: DemoProfileFixture.personalListID, listTitle: "Personal", isCompleted: false, allowsModification: true, hasRecurrence: false),
                .init(id: "demo-school-task", title: "Assignment 1", notes: nil, dueDate: due.addingTimeInterval(3_600), dueHasTime: true, priority: 7, listID: DemoProfileFixture.assignmentsListID, listTitle: "Assignments", isCompleted: false, allowsModification: true, hasRecurrence: false),
                .init(id: "demo-work-task", title: "Send report", notes: nil, dueDate: due.addingTimeInterval(7_200), dueHasTime: true, priority: 3, listID: DemoProfileFixture.workListID, listTitle: "Work", isCompleted: false, allowsModification: true, hasRecurrence: false)
            ]
        } else {
            values = [
                .init(id: "demo-task", title: "Buy milk", notes: nil, dueDate: due, dueHasTime: true, priority: 5, listID: "demo-list", listTitle: "Tasks", isCompleted: false, allowsModification: true, hasRecurrence: false)
            ]
        }
        if includeOverdueTask {
            values.append(
                .init(
                    id: "demo-overdue-task",
                    title: "Submit assignment",
                    notes: nil,
                    dueDate: calendar.date(byAdding: .day, value: -1, to: due),
                    dueHasTime: true,
                    priority: 7,
                    listID: "demo-list",
                    listTitle: "Tasks",
                    isCompleted: false,
                    allowsModification: true,
                    hasRecurrence: false
                )
            )
        }
        if dailyTaskRescueFixtures {
            let weekDue = calendar.date(
                bySettingHour: 16,
                minute: 0,
                second: 0,
                of: capturedToday
            )!
            values.append(contentsOf: [
                .init(
                    id: "demo-undated-task",
                    title: "Plan reading time",
                    notes: nil,
                    dueDate: nil,
                    dueHasTime: false,
                    priority: 5,
                    listID: "demo-list",
                    listTitle: "Tasks",
                    isCompleted: false,
                    allowsModification: true,
                    hasRecurrence: false
                ),
                .init(
                    id: "demo-overdue-task",
                    title: "Submit assignment",
                    notes: nil,
                    dueDate: calendar.date(
                        byAdding: .day,
                        value: -2,
                        to: weekDue
                    ),
                    dueHasTime: true,
                    priority: 7,
                    listID: "demo-list",
                    listTitle: "Tasks",
                    isCompleted: false,
                    allowsModification: true,
                    hasRecurrence: false
                ),
                .init(
                    id: "demo-week-task",
                    title: "Prepare weekly review",
                    notes: nil,
                    dueDate: weekDue,
                    dueHasTime: true,
                    priority: 3,
                    listID: "demo-list",
                    listTitle: "Tasks",
                    isCompleted: false,
                    allowsModification: true,
                    hasRecurrence: false
                )
            ])
        }
        if includeReadOnlySource {
            values.append(
                .init(
                    id: "demo-task-read-only",
                    title: "Read-only task",
                    notes: "Provider-managed",
                    dueDate: Calendar.current.date(bySettingHour: 15, minute: 0, second: 0, of: .now),
                    dueHasTime: true,
                    priority: 3,
                    listID: "demo-list-read-only",
                    listTitle: "Read Only",
                    isCompleted: false,
                    allowsModification: false,
                    hasRecurrence: false
                )
            )
        }
        if includeUnsupportedItems {
            let due = Calendar.current.date(bySettingHour: 17, minute: 45, second: 0, of: .now)!
            values.append(
                .init(
                    id: "demo-task-unsupported",
                    title: "Provider-defined task",
                    notes: "Provider metadata must survive ordinary edits.",
                    dueDate: due,
                    dueHasTime: true,
                    priority: 4,
                    listID: "demo-list",
                    listTitle: "Tasks",
                    isCompleted: false,
                    allowsModification: true,
                    hasRecurrence: true,
                    alarm: .unsupported(summary: "Provider-defined alert"),
                    recurrence: .unsupported(summary: "Provider-defined repeat")
                )
            )
        }
        if includeRecurringItems {
            let due = Calendar.current.date(bySettingHour: 16, minute: 30, second: 0, of: .now)!
            let endDate = Calendar.current.date(byAdding: .day, value: 30, to: due)
            let recurrence = RecurrenceRuleDraft(frequency: .weekly, interval: 2, weekdays: [2, 4], endDate: endDate)
            values.append(
                .init(
                    id: "demo-task-recurring",
                    title: "Biweekly review",
                    notes: nil,
                    dueDate: due,
                    dueHasTime: true,
                    priority: 7,
                    listID: "demo-list",
                    listTitle: "Tasks",
                    isCompleted: false,
                    allowsModification: true,
                    hasRecurrence: true,
                    alarm: .editable(due.addingTimeInterval(-1_800)),
                    recurrence: .editable(recurrence)
                )
            )
        }
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
        if profileFixtures {
            return [
                .init(id: DemoProfileFixture.personalListID, title: "Personal", colorHex: "#3A8D7C", allowsContentModifications: true),
                .init(id: DemoProfileFixture.assignmentsListID, title: "Assignments", colorHex: "#4868A8", allowsContentModifications: true),
                .init(id: DemoProfileFixture.workListID, title: "Work", colorHex: "#CB6B4F", allowsContentModifications: true)
            ]
        }
        var descriptors = [descriptor]
        if multipleSources { descriptors.append(.init(id: "demo-list-alternate", title: "Alternate", colorHex: "#4868A8", allowsContentModifications: true)) }
        if includeReadOnlySource { descriptors.append(.init(id: "demo-list-read-only", title: "Read Only", colorHex: "#777777", allowsContentModifications: false)) }
        return descriptors
    }

    private var descriptor: ReminderListDescriptor {
        profileFixtures
            ? .init(id: DemoProfileFixture.personalListID, title: "Personal", colorHex: "#3A8D7C", allowsContentModifications: true)
            : .init(id: "demo-list", title: "Tasks", colorHex: "#CB6B4F", allowsContentModifications: true)
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
    private var values: [RoutineSnapshot]
    private var completed: [UUID: Set<LocalDay>] = [:]
    private var shouldFailNextDelete: Bool
    private var shouldFailNextCreate: Bool
    private var shouldFailNextUpdate: Bool
    init(failFirstDelete: Bool = false, failFirstCreate: Bool = false, failFirstUpdate: Bool = false, longTitle: Bool = false, profileFixtures: Bool = false) {
        shouldFailNextDelete = failFirstDelete
        shouldFailNextCreate = failFirstCreate
        shouldFailNextUpdate = failFirstUpdate
        values = [
            .init(id: DemoProfileFixture.personalRoutineID, title: "Read", weekdays: [1, 2, 3, 4, 5, 6, 7], window: .evening, reminderHour: nil, reminderMinute: nil, isPaused: false, isArchived: false)
        ]
        if profileFixtures {
            values.append(.init(id: DemoProfileFixture.schoolRoutineID, title: "Review notes", weekdays: [2, 3, 4, 5, 6], window: .evening, reminderHour: nil, reminderMinute: nil, isPaused: false, isArchived: false))
            values.append(.init(id: DemoProfileFixture.workRoutineID, title: "Plan week", weekdays: [2], window: .morning, reminderHour: nil, reminderMinute: nil, isPaused: false, isArchived: false))
        }
        if longTitle {
            let old = values[0]
            values[0] = .init(id: old.id, title: "Read a long and thoughtfully named routine before bed every evening", weekdays: old.weekdays, window: old.window, reminderHour: old.reminderHour, reminderMinute: old.reminderMinute, isPaused: old.isPaused, isArchived: old.isArchived)
        }
    }

    func list(includeArchived: Bool) throws -> [RoutineSnapshot] {
        includeArchived ? values : values.filter { !$0.isArchived }
    }

    func create(_ draft: RoutineDraft) throws -> UUID {
        if shouldFailNextCreate { shouldFailNextCreate = false; throw DemoCreateError.failed }
        let id = UUID()
        values.append(.init(id: id, title: draft.title, weekdays: draft.weekdays, window: draft.window, reminderHour: draft.reminderHour, reminderMinute: draft.reminderMinute, isPaused: false, isArchived: false, categoryID: draft.categoryID))
        return id
    }

    func update(id: UUID, draft: RoutineDraft) throws {
        if shouldFailNextUpdate { shouldFailNextUpdate = false; throw DemoCreateError.failed }
        guard let index = values.firstIndex(where: { $0.id == id }) else { throw RoutineRepositoryError.routineNotFound }
        let old = values[index]
        values[index] = .init(id: id, title: draft.title, weekdays: draft.weekdays, window: draft.window, reminderHour: draft.reminderHour, reminderMinute: draft.reminderMinute, isPaused: old.isPaused, isArchived: old.isArchived, categoryID: draft.categoryID)
    }

    func setPaused(id: UUID, paused: Bool) throws {
        try mutate(id) { .init(id: $0.id, title: $0.title, weekdays: $0.weekdays, window: $0.window, reminderHour: $0.reminderHour, reminderMinute: $0.reminderMinute, isPaused: paused, isArchived: $0.isArchived, categoryID: $0.categoryID) }
    }

    func setArchived(id: UUID, archived: Bool) throws {
        try mutate(id) { .init(id: $0.id, title: $0.title, weekdays: $0.weekdays, window: $0.window, reminderHour: $0.reminderHour, reminderMinute: $0.reminderMinute, isPaused: $0.isPaused, isArchived: archived, categoryID: $0.categoryID) }
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
final class DemoRoutineProfileMutationAdapter: RoutineProfileMutating {
    private let routines: DemoRoutineRepository
    private let profiles: any ProfileRepository

    init(routines: DemoRoutineRepository, profiles: any ProfileRepository) {
        self.routines = routines
        self.profiles = profiles
    }

    func create(draft: RoutineDraft, profileID: UUID) throws -> UUID {
        let profile = try profiles.profile(id: profileID)
        let routineID = try routines.create(draft)
        try profiles.update(
            id: profileID,
            draft: ProfileDraft(
                name: profile.name,
                colorHex: profile.colorHex,
                symbolName: profile.symbolName,
                calendarIDs: profile.calendarIDs,
                reminderListIDs: profile.reminderListIDs,
                routineIDs: profile.routineIDs.union([routineID]),
                defaultCalendarID: profile.defaultCalendarID,
                defaultReminderListID: profile.defaultReminderListID
            )
        )
        return routineID
    }

    func delete(id: UUID) throws {
        try routines.delete(id: id)
        try profiles.removeRoutineID(id)
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
