import Foundation

@MainActor
protocol EventKitStoreDriving: AnyObject {
    func eventAccessGranted() -> Bool
    func reminderAccessGranted() -> Bool
    func event(id: String) -> (any EventMutationHandling)?
    func reminder(id: String) -> (any ReminderMutationHandling)?
    func newEvent() -> any EventMutationHandling
    func newReminder() -> any ReminderMutationHandling
    func resolveEventDestination(_ destination: CreateDestination) throws -> String
    func resolveEventDestination(_ destination: UpdateDestination) throws -> String?
    func resolveReminderDestination(_ destination: CreateDestination) throws -> String
    func resolveReminderDestination(_ destination: UpdateDestination) throws -> String?
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
