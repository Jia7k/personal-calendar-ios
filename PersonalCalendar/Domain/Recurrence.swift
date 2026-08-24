import Foundation

enum RecurrenceFrequency: String, Codable, CaseIterable, Sendable { case daily, weekly, monthly, yearly }

struct RecurrenceRuleDraft: Codable, Equatable, Sendable {
    var frequency: RecurrenceFrequency
    var interval: Int
    var weekdays: Set<Int>
    var endDate: Date?
}

enum RecurrenceSnapshot: Equatable, Sendable {
    case none
    case editable(RecurrenceRuleDraft)
    case unsupported(summary: String)

    static let unsupportedSummary = "This repeat pattern can’t be edited here."

    static func normalized(_ recurrence: RecurrenceSnapshot, legacyHasRecurrence: Bool) -> RecurrenceSnapshot {
        switch recurrence {
        case .none where legacyHasRecurrence:
            .unsupported(summary: unsupportedSummary)
        case .none, .editable, .unsupported:
            recurrence
        }
    }
}

enum RecurrenceEditScope: Equatable, Sendable { case thisOccurrence, futureOccurrences }

enum RecurrenceMutationIntent: Equatable, Sendable {
    case preserve
    case clear
    case replace(RecurrenceRuleDraft)

    func validate(scope: RecurrenceEditScope) throws {
        guard self == .preserve || scope == .futureOccurrences else { throw DraftValidationError.invalidRecurrenceScope }
    }
}

enum EventAlarmSnapshot: Equatable, Sendable { case none, editable([TimeInterval]), unsupported(summary: String) }
enum ReminderAlarmSnapshot: Equatable, Sendable { case none, editable(Date), unsupported(summary: String) }
enum EventAlarmMutationIntent: Equatable, Sendable { case preserve, clear, replace([TimeInterval]) }
enum ReminderAlarmMutationIntent: Equatable, Sendable { case preserve, clear, replace(Date) }

struct ItemCapabilities: Equatable, Sendable {
    let allowsModification: Bool
    let hasRecurrence: Bool
    var canEdit: Bool { allowsModification }
    var canDelete: Bool { allowsModification }
    var explanation: String? { allowsModification ? nil : "This item belongs to a read-only source." }
}
