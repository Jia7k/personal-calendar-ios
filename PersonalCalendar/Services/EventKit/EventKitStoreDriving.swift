import Foundation

struct EventOccurrenceCandidate<Value> {
    let id: String
    let displayStart: Date
    let occurrenceDate: Date
    let value: Value
}

enum EventOccurrenceSelector {
    static func exact<Value>(
        id: String,
        occurrence: EventOccurrenceAddress,
        candidates: [EventOccurrenceCandidate<Value>]
    ) -> Value? {
        guard !id.isEmpty, occurrence.isValid else {
            return nil
        }
        return candidates.first {
            $0.id == id
                && $0.displayStart == occurrence.displayStart
                && $0.occurrenceDate == occurrence.occurrenceDate
        }?.value
    }
}

@MainActor
protocol EventKitStoreDriving: AnyObject {
    func eventAccessGranted() -> Bool
    func reminderAccessGranted() -> Bool
    func event(id: String) -> (any EventMutationHandling)?
    func event(id: String, occurrence: EventOccurrenceAddress?) -> (any EventMutationHandling)?
    func reminder(id: String) -> (any ReminderMutationHandling)?
    func newEvent() -> any EventMutationHandling
    func newReminder() -> any ReminderMutationHandling
    func resolveEventDestination(_ destination: CreateDestination) throws -> String
    func resolveEventDestination(_ destination: UpdateDestination) throws -> String?
    func resolveReminderDestination(_ destination: CreateDestination) throws -> String
    func resolveReminderDestination(_ destination: UpdateDestination) throws -> String?
}

extension EventKitStoreDriving {
    func event(id: String, occurrence: EventOccurrenceAddress?) -> (any EventMutationHandling)? {
        guard occurrence == nil else { return nil }
        return event(id: id)
    }
}

@MainActor
protocol EventMutationHandling: AnyObject {
    var allowsModification: Bool { get }
    var hasRecurrence: Bool { get }
    func apply(_ patch: PreparedEventPatch) throws
    func save(scope: RecurrenceEditScope, commit: Bool) throws
    func remove(scope: RecurrenceEditScope, commit: Bool) throws
    func reset()
    func discardNewItem()
    var savedIdentifier: String? { get }
}

@MainActor
protocol ReminderMutationHandling: AnyObject {
    var allowsModification: Bool { get }
    var hasRecurrence: Bool { get }
    var currentSchedule: ReminderScheduleValue? { get }
    var currentStartSchedule: ReminderScheduleValue? { get }
    func apply(_ patch: PreparedReminderPatch) throws
    func setCompleted(_ completed: Bool) throws
    func save(commit: Bool) throws
    func remove(commit: Bool) throws
    func reset()
    func discardNewItem()
    var savedIdentifier: String? { get }
}

struct PreparedEventPatch: Equatable, Sendable {
    let draft: EventDraft
    let destinationID: String?
}

enum PreparedReminderSchedule: Equatable, Sendable {
    case preserve
    case clear
    case replace(due: ReminderScheduleValue, start: ReminderScheduleValue?)
}

struct PreparedReminderPatch: Equatable, Sendable {
    let draft: ReminderDraft
    let destinationID: String?
    let schedule: PreparedReminderSchedule
}
