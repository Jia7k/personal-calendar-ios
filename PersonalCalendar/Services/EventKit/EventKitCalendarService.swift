import EventKit

enum DraftValidationError: Error, Equatable {
    case emptyTitle
    case invalidDateRange
    case readOnlyDestination
}

enum EventDraftValidator {
    static func validate(_ draft: EventDraft) throws {
        guard !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DraftValidationError.emptyTitle
        }
        guard draft.end > draft.start else {
            throw DraftValidationError.invalidDateRange
        }
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
final class EventKitCalendarService: CalendarServicing {
    private let store: EKEventStore

    init(store: EKEventStore) {
        self.store = store
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

    func createEvent(_ draft: EventDraft) throws -> String {
        try EventDraftValidator.validate(draft)

        let destination: EKCalendar?
        if let calendarID = draft.calendarID {
            destination = store.calendars(for: .event).first {
                $0.calendarIdentifier == calendarID
            }
        } else {
            destination = store.defaultCalendarForNewEvents
        }
        guard let destination, destination.allowsContentModifications else {
            throw DraftValidationError.readOnlyDestination
        }

        let event = EKEvent(eventStore: store)
        event.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        event.startDate = draft.start
        event.endDate = draft.end
        event.isAllDay = draft.isAllDay
        event.calendar = destination
        try store.save(event, span: .thisEvent, commit: true)
        return event.eventIdentifier
    }
}
