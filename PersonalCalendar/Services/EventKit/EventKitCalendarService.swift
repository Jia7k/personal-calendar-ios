import EventKit

enum DraftValidationError: Error, Equatable {
    case emptyTitle
    case invalidDateRange
    case readOnlyDestination
    case itemNotFound
    case invalidDestination
    case invalidRecurrence
    case invalidRecurrenceScope
    case recurringReminderRequiresDueDate
}

@MainActor
enum EventDraftValidator {
    static func validate(_ draft: EventDraft) throws {
        guard !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DraftValidationError.emptyTitle
        }
        guard draft.start.timeIntervalSinceReferenceDate.isFinite,
              draft.end.timeIntervalSinceReferenceDate.isFinite,
              draft.end > draft.start else {
            throw DraftValidationError.invalidDateRange
        }
        if case let .replace(offsets) = draft.alarms,
           !offsets.allSatisfy(\.isFinite) {
            throw DraftValidationError.invalidDateRange
        }
        if case let .replace(rule) = draft.recurrence { try EventKitRecurrenceMapper.validate(rule, startsAt: draft.start) }
    }
}

enum EventKitAccessMapper {
    static func map(_ status: EKAuthorizationStatus) -> AccessState {
        switch status {
        case .fullAccess, .authorized:
            .granted
        case .notDetermined:
            .notDetermined
        case .denied:
            .denied
        case .restricted, .writeOnly:
            .restricted
        @unknown default:
            .restricted
        }
    }
}

@MainActor
struct EventKitEventDetailResolver {
    let eventForIdentifier: (String) -> EKEvent?
    let calendarItemForIdentifier: (String) -> EKCalendarItem?

    func requiredEvent(id: String) -> CalendarEventSnapshot? {
        if let event = eventForIdentifier(id) {
            return CalendarEventSnapshot(event: event)
        }
        guard let event = calendarItemForIdentifier(id) as? EKEvent else { return nil }
        return viewOnlySnapshot(for: event, displayID: id)
    }

    private func viewOnlySnapshot(for event: EKEvent, displayID: String) -> CalendarEventSnapshot {
        let eventSnapshot = CalendarEventSnapshot(event: event)
        return CalendarEventSnapshot(
            id: displayID,
            mutationID: nil,
            title: eventSnapshot.title,
            start: eventSnapshot.start,
            end: eventSnapshot.end,
            isAllDay: eventSnapshot.isAllDay,
            calendarID: eventSnapshot.calendarID,
            calendarTitle: eventSnapshot.calendarTitle,
            allowsModification: false,
            hasRecurrence: eventSnapshot.hasRecurrence,
            notes: eventSnapshot.notes,
            location: eventSnapshot.location,
            url: eventSnapshot.url,
            alarms: eventSnapshot.alarms,
            recurrence: eventSnapshot.recurrence,
            occurrenceDate: eventSnapshot.occurrenceDate
        )
    }
}

@MainActor
final class EventKitCalendarService: CalendarServicing {
    private let store: EKEventStore
    private let mutations: any EventKitMutationBacking

    init(store: EKEventStore, mutations: (any EventKitMutationBacking)? = nil) {
        self.store = store
        self.mutations = mutations ?? SystemEventKitMutationBacking(store: store)
    }

    var accessState: AccessState {
        EventKitAccessMapper.map(EKEventStore.authorizationStatus(for: .event))
    }

    func requestFullAccess() async -> AccessState {
        do {
            return try await store.requestFullAccessToEvents() ? .granted : .denied
        } catch {
            return .denied
        }
    }

    func calendars() -> [CalendarDescriptor] {
        guard accessState == .granted else { return [] }

        return store.calendars(for: .event).map {
            CalendarDescriptor(
                id: $0.calendarIdentifier,
                title: $0.title,
                colorHex: $0.cgColor.hexRGB,
                allowsContentModifications: $0.allowsContentModifications
            )
        }
    }

    func fetchEvents(in interval: DateInterval, calendarIDs: Set<String>) throws -> [CalendarEventSnapshot] {
        guard accessState == .granted else { return [] }

        let selectedCalendars = store.calendars(for: .event).filter {
            calendarIDs.isEmpty || calendarIDs.contains($0.calendarIdentifier)
        }
        let predicate = store.predicateForEvents(
            withStart: interval.start,
            end: interval.end,
            calendars: selectedCalendars
        )
        return store.events(matching: predicate).map(CalendarEventSnapshot.init(event:))
    }

    func createEvent(_ draft: EventDraft) throws -> String? {
        try mutations.createEvent(.init(draft: draft, destination: draft.calendarID.map(CreateDestination.explicit) ?? .defaultWritable))
    }

    func event(id: String) -> CalendarEventSnapshot? {
        guard accessState == .granted else { return nil }
        let resolver = EventKitEventDetailResolver(
            eventForIdentifier: { [store] in store.event(withIdentifier: $0) },
            calendarItemForIdentifier: { [store] in store.calendarItem(withIdentifier: $0) }
        )
        return resolver.requiredEvent(id: id)
    }

    func event(id: String, occurrence: EventOccurrenceAddress?) -> CalendarEventSnapshot? {
        guard let occurrence else { return event(id: id) }
        guard accessState == .granted, occurrence.isValid else {
            return nil
        }
        let predicate = store.predicateForEvents(
            withStart: occurrence.displayStart.addingTimeInterval(-1),
            end: occurrence.displayStart.addingTimeInterval(1),
            calendars: nil
        )
        let candidates = store.events(matching: predicate).map { event in
            EventOccurrenceCandidate(
                id: EventKitEventCapabilityMapper.mutationID(
                    from: event.eventIdentifier
                ) ?? event.calendarItemIdentifier,
                displayStart: event.startDate,
                occurrenceDate: event.occurrenceDate ?? event.startDate,
                value: event
            )
        }
        return EventOccurrenceSelector.exact(
            id: id,
            occurrence: occurrence,
            candidates: candidates
        ).map {
            CalendarEventSnapshot(event: $0)
        }
    }

    func updateEvent(id: String, draft: EventDraft, scope: RecurrenceEditScope) throws {
        try mutations.updateEvent(id: id, request: .init(draft: draft, destination: draft.calendarID.map(UpdateDestination.explicit) ?? .preserveCurrent, scope: scope))
    }

    func updateEvent(
        id: String,
        occurrence: EventOccurrenceAddress?,
        draft: EventDraft,
        scope: RecurrenceEditScope
    ) throws {
        try mutations.updateEvent(
            id: id,
            occurrence: occurrence,
            request: .init(
                draft: draft,
                destination: draft.calendarID.map(UpdateDestination.explicit)
                    ?? .preserveCurrent,
                scope: scope
            )
        )
    }

    func deleteEvent(id: String, scope: RecurrenceEditScope) throws {
        try mutations.removeEvent(id: id, span: scope)
    }

    func deleteEvent(
        id: String,
        occurrence: EventOccurrenceAddress?,
        scope: RecurrenceEditScope
    ) throws {
        try mutations.removeEvent(
            id: id,
            occurrence: occurrence,
            span: scope
        )
    }
}
