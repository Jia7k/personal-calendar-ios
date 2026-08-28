import Foundation

enum AccessState: Equatable, Sendable {
    case notDetermined
    case granted
    case denied
    case restricted
}

struct CalendarDescriptor: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let colorHex: String
    let allowsContentModifications: Bool
}

@MainActor
protocol CalendarServicing: AnyObject {
    var accessState: AccessState { get }

    func requestFullAccess() async -> AccessState
    func calendars() -> [CalendarDescriptor]
    func fetchEvents(in interval: DateInterval, calendarIDs: Set<String>) throws -> [CalendarEventSnapshot]
    func createEvent(_ draft: EventDraft) throws -> String?
    func event(id: String) -> CalendarEventSnapshot?
    func event(id: String, occurrence: EventOccurrenceAddress?) -> CalendarEventSnapshot?
    func updateEvent(id: String, draft: EventDraft, scope: RecurrenceEditScope) throws
    func updateEvent(id: String, occurrence: EventOccurrenceAddress?, draft: EventDraft, scope: RecurrenceEditScope) throws
    func deleteEvent(id: String, scope: RecurrenceEditScope) throws
    func deleteEvent(id: String, occurrence: EventOccurrenceAddress?, scope: RecurrenceEditScope) throws
}

extension CalendarServicing {
    func event(id: String, occurrence: EventOccurrenceAddress?) -> CalendarEventSnapshot? {
        guard occurrence == nil else { return nil }
        return event(id: id)
    }

    func updateEvent(
        id: String,
        occurrence: EventOccurrenceAddress?,
        draft: EventDraft,
        scope: RecurrenceEditScope
    ) throws {
        guard occurrence == nil else { throw EventKitMutationError.itemNotFound }
        try updateEvent(id: id, draft: draft, scope: scope)
    }

    func deleteEvent(
        id: String,
        occurrence: EventOccurrenceAddress?,
        scope: RecurrenceEditScope
    ) throws {
        guard occurrence == nil else { throw EventKitMutationError.itemNotFound }
        try deleteEvent(id: id, scope: scope)
    }
}
