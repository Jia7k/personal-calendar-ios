import EventKit

@MainActor
enum EventKitStructuredLocationPolicy {
    static func apply(submittedLocation: String?, to event: EKEvent) {
        guard submittedLocation != event.location else { return }
        event.structuredLocation = submittedLocation.map(EKStructuredLocation.init(title:))
    }
}

@MainActor
final class SystemEventKitStoreDriver: EventKitStoreDriving {
    private let store: EKEventStore
    init(store: EKEventStore) { self.store = store }

    func eventAccessGranted() -> Bool { EventKitAccessMapper.map(EKEventStore.authorizationStatus(for: .event)) == .granted }
    func reminderAccessGranted() -> Bool { EventKitAccessMapper.map(EKEventStore.authorizationStatus(for: .reminder)) == .granted }
    func event(id: String) -> (any EventMutationHandling)? { store.event(withIdentifier: id).map { SystemEventHandle(event: $0, store: store) } }
    func event(id: String, occurrence: EventOccurrenceAddress?) -> (any EventMutationHandling)? {
        guard let occurrence else { return event(id: id) }
        guard occurrence.isValid else {
            return nil
        }
        let predicate = store.predicateForEvents(
            withStart: occurrence.displayStart.addingTimeInterval(-1),
            end: occurrence.displayStart.addingTimeInterval(1),
            calendars: nil
        )
        let candidates = store.events(matching: predicate).compactMap { event in
            event.eventIdentifier.map {
                EventOccurrenceCandidate(
                    id: $0,
                    displayStart: event.startDate,
                    occurrenceDate: event.occurrenceDate ?? event.startDate,
                    value: event
                )
            }
        }
        guard let event = EventOccurrenceSelector.exact(
            id: id,
            occurrence: occurrence,
            candidates: candidates
        ) else { return nil }
        return SystemEventHandle(event: event, store: store)
    }
    func reminder(id: String) -> (any ReminderMutationHandling)? { (store.calendarItem(withIdentifier: id) as? EKReminder).map { SystemReminderHandle(reminder: $0, store: store) } }
    func newEvent() -> any EventMutationHandling { SystemEventHandle(event: EKEvent(eventStore: store), store: store, isNew: true) }
    func newReminder() -> any ReminderMutationHandling { SystemReminderHandle(reminder: EKReminder(eventStore: store), store: store, isNew: true) }

    func resolveEventDestination(_ destination: CreateDestination) throws -> String {
        switch destination {
        case .defaultWritable:
            guard let calendar = store.defaultCalendarForNewEvents else { throw EventKitMutationError.defaultUnavailable }
            guard calendar.allowsContentModifications else { throw EventKitMutationError.destinationReadOnly }
            return calendar.calendarIdentifier
        case let .explicit(id): return try writableCalendar(id, entityType: .event).calendarIdentifier
        }
    }
    func resolveEventDestination(_ destination: UpdateDestination) throws -> String? {
        switch destination { case .preserveCurrent: return nil; case let .explicit(id): return try writableCalendar(id, entityType: .event).calendarIdentifier }
    }
    func resolveReminderDestination(_ destination: CreateDestination) throws -> String {
        switch destination {
        case .defaultWritable:
            guard let calendar = store.defaultCalendarForNewReminders() else { throw EventKitMutationError.defaultUnavailable }
            guard calendar.allowsContentModifications else { throw EventKitMutationError.destinationReadOnly }
            return calendar.calendarIdentifier
        case let .explicit(id): return try writableCalendar(id, entityType: .reminder).calendarIdentifier
        }
    }
    func resolveReminderDestination(_ destination: UpdateDestination) throws -> String? {
        switch destination { case .preserveCurrent: return nil; case let .explicit(id): return try writableCalendar(id, entityType: .reminder).calendarIdentifier }
    }

    private func writableCalendar(_ id: String, entityType: EKEntityType) throws -> EKCalendar {
        guard let calendar = store.calendars(for: entityType).first(where: { $0.calendarIdentifier == id }) else { throw EventKitMutationError.destinationMissing }
        guard calendar.allowsContentModifications else { throw EventKitMutationError.destinationReadOnly }
        return calendar
    }
}

@MainActor
private final class SystemEventHandle: EventMutationHandling {
    private let event: EKEvent
    private let store: EKEventStore
    private let isNew: Bool
    init(event: EKEvent, store: EKEventStore, isNew: Bool = false) { self.event = event; self.store = store; self.isNew = isNew }
    var allowsModification: Bool { isNew || event.calendar.allowsContentModifications }
    var hasRecurrence: Bool { event.hasRecurrenceRules }

    func apply(_ patch: PreparedEventPatch) throws {
        let recurrence: [EKRecurrenceRule]?
        switch patch.draft.recurrence {
        case .preserve: recurrence = nil
        case .clear: recurrence = []
        case let .replace(rule): recurrence = [try EventKitRecurrenceMapper.makeRule(from: rule, startsAt: patch.draft.start)]
        }
        let alarms: [EKAlarm]?
        switch patch.draft.alarms {
        case .preserve: alarms = nil
        case .clear: alarms = []
        case let .replace(offsets): alarms = offsets.map(EKAlarm.init(relativeOffset:))
        }
        let calendar: EKCalendar?
        if let id = patch.destinationID {
            guard let resolved = store.calendars(for: .event).first(where: { $0.calendarIdentifier == id }) else { throw EventKitMutationError.destinationMissing }
            guard resolved.allowsContentModifications else { throw EventKitMutationError.destinationReadOnly }
            calendar = resolved
        } else { calendar = nil }

        // Prebuild every throwing/optional native value before touching the item.
        event.title = patch.draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        event.startDate = patch.draft.start
        event.endDate = patch.draft.end
        event.isAllDay = patch.draft.isAllDay
        event.notes = patch.draft.notes
        EventKitStructuredLocationPolicy.apply(submittedLocation: patch.draft.location, to: event)
        event.url = patch.draft.url
        if let recurrence { event.recurrenceRules = recurrence.isEmpty ? nil : recurrence }
        if let alarms { event.alarms = alarms }
        if let calendar { event.calendar = calendar }
    }
    func save(scope: RecurrenceEditScope, commit: Bool) throws { try store.save(event, span: scope == .thisOccurrence ? .thisEvent : .futureEvents, commit: commit) }
    func remove(scope: RecurrenceEditScope, commit: Bool) throws { try store.remove(event, span: scope == .thisOccurrence ? .thisEvent : .futureEvents, commit: commit) }
    func reset() { event.reset() }
    func discardNewItem() { if isNew { event.reset() } }
    // calendarItemIdentifier is intentionally not a fallback: it cannot safely
    // identify a mutable event occurrence.
    var savedIdentifier: String? { event.eventIdentifier }
}

@MainActor
private final class SystemReminderHandle: ReminderMutationHandling {
    private let reminder: EKReminder
    private let store: EKEventStore
    private let isNew: Bool
    init(reminder: EKReminder, store: EKEventStore, isNew: Bool = false) { self.reminder = reminder; self.store = store; self.isNew = isNew }
    var allowsModification: Bool { isNew || reminder.calendar.allowsContentModifications }
    var hasRecurrence: Bool { reminder.hasRecurrenceRules }
    var currentSchedule: ReminderScheduleValue? { scheduleValue(from: reminder.dueDateComponents) }
    var currentStartSchedule: ReminderScheduleValue? { scheduleValue(from: reminder.startDateComponents) }

    func apply(_ patch: PreparedReminderPatch) throws {
        let calendar: EKCalendar?
        if let id = patch.destinationID {
            guard let resolved = store.calendars(for: .reminder).first(where: { $0.calendarIdentifier == id }) else { throw EventKitMutationError.destinationMissing }
            guard resolved.allowsContentModifications else { throw EventKitMutationError.destinationReadOnly }
            calendar = resolved
        } else { calendar = nil }
        let recurrence: [EKRecurrenceRule]?
        switch patch.draft.recurrence {
        case .preserve: recurrence = nil
        case .clear: recurrence = []
        case let .replace(rule):
            guard let date = dueDate(from: patch.schedule) else { throw EventKitMutationError.invalidDraft }
            recurrence = [try EventKitRecurrenceMapper.makeRule(from: rule, startsAt: date)]
        }
        let alarms: [EKAlarm]?
        switch patch.draft.alarm {
        case .preserve: alarms = nil
        case .clear: alarms = []
        case let .replace(date): alarms = [EKAlarm(absoluteDate: date)]
        }
        let components: (DateComponents?, DateComponents?)
        switch patch.schedule {
        case .preserve: components = (nil, nil)
        case .clear: components = (nil, nil)
        case let .replace(due, start):
            let calendar = Calendar.autoupdatingCurrent
            components = (
                ReminderDueComponentBuilder.components(for: due.date, dueHasTime: due.hasTime, preferredCalendar: calendar),
                start.map { ReminderDueComponentBuilder.components(for: $0.date, dueHasTime: $0.hasTime, preferredCalendar: calendar) }
            )
        }
        reminder.title = patch.draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        reminder.notes = patch.draft.notes
        reminder.priority = patch.draft.priority
        if let recurrence { reminder.recurrenceRules = recurrence.isEmpty ? nil : recurrence }
        if let alarms { reminder.alarms = alarms }
        switch patch.schedule {
        case .preserve: break
        case .clear: reminder.dueDateComponents = nil; reminder.startDateComponents = nil
        case .replace: reminder.dueDateComponents = components.0; reminder.startDateComponents = components.1
        }
        if let calendar { reminder.calendar = calendar }
    }
    func setCompleted(_ completed: Bool) throws { reminder.isCompleted = completed }
    func save(commit: Bool) throws { try store.save(reminder, commit: commit) }
    func remove(commit: Bool) throws { try store.remove(reminder, commit: commit) }
    func reset() { reminder.reset() }
    func discardNewItem() { if isNew { reminder.reset() } }
    var savedIdentifier: String? { reminder.calendarItemIdentifier }

    private func dueDate(from schedule: PreparedReminderSchedule) -> Date? {
        guard case let .replace(due, _) = schedule else { return currentSchedule?.date }
        return due.date
    }
    private func scheduleValue(from components: DateComponents?) -> ReminderScheduleValue? {
        guard let components, let date = components.date else { return nil }
        return .init(date: date, hasTime: components.hour != nil)
    }
}
