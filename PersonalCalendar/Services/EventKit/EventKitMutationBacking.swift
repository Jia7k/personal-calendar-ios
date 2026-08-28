import Foundation

/// The only mutation surface used by the calendar and reminder services.  It is
/// deliberately value based: EventKit objects never cross this boundary.
@MainActor
protocol EventKitMutationBacking: AnyObject {
    func createEvent(_ request: EventCreateRequest) throws -> String?
    func updateEvent(id: String, request: EventUpdateRequest) throws
    func updateEvent(id: String, occurrence: EventOccurrenceAddress?, request: EventUpdateRequest) throws
    func removeEvent(id: String, span: RecurrenceEditScope) throws
    func removeEvent(id: String, occurrence: EventOccurrenceAddress?, span: RecurrenceEditScope) throws
    func createReminder(_ request: ReminderCreateRequest) throws -> String?
    func updateReminder(id: String, request: ReminderUpdateRequest) throws
    func removeReminder(id: String) throws
    func setReminderCompleted(id: String, completed: Bool) throws
}

extension EventKitMutationBacking {
    func updateEvent(
        id: String,
        occurrence: EventOccurrenceAddress?,
        request: EventUpdateRequest
    ) throws {
        guard occurrence == nil else { throw EventKitMutationError.itemNotFound }
        try updateEvent(id: id, request: request)
    }

    func removeEvent(
        id: String,
        occurrence: EventOccurrenceAddress?,
        span: RecurrenceEditScope
    ) throws {
        guard occurrence == nil else { throw EventKitMutationError.itemNotFound }
        try removeEvent(id: id, span: span)
    }

    /// Older value-only test backings that do not model completion stay safe:
    /// they fail instead of bypassing the live mutation policy.
    func setReminderCompleted(id: String, completed: Bool) throws {
        throw EventKitMutationError.itemNotFound
    }
}

enum CreateDestination: Equatable, Sendable { case defaultWritable, explicit(String) }
enum UpdateDestination: Equatable, Sendable { case preserveCurrent, explicit(String) }

struct EventCreateRequest: Equatable, Sendable { let draft: EventDraft; let destination: CreateDestination }
struct EventUpdateRequest: Equatable, Sendable { let draft: EventDraft; let destination: UpdateDestination; let scope: RecurrenceEditScope }
struct ReminderCreateRequest: Equatable, Sendable { let draft: ReminderDraft; let destination: CreateDestination }
struct ReminderUpdateRequest: Equatable, Sendable { let draft: ReminderDraft; let destination: UpdateDestination }

enum EventKitMutationError: Error, Equatable, Sendable {
    case accessUnavailable
    case itemNotFound
    case itemReadOnly
    case defaultUnavailable
    case destinationMissing
    case destinationReadOnly
    case invalidDraft
    case invalidRecurrence
    case invalidRecurrenceScope
    case saveFailed
    case removeFailed
}
