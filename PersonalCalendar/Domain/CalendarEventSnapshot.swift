import Foundation

struct CalendarEventSnapshot: Identifiable, Equatable, Sendable {
    let id: String
    /// EventKit's opaque event identifier, when one exists. `id` remains a display
    /// identity so an event that only has a calendar-item identifier is never used
    /// as a mutable EventKit address.
    let mutationID: String?
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let calendarID: String
    let calendarTitle: String
    let allowsModification: Bool
    let hasRecurrence: Bool
    let notes: String?
    let location: String?
    let url: URL?
    let alarms: EventAlarmSnapshot
    let recurrence: RecurrenceSnapshot

    init(id: String, mutationID: String? = nil, title: String, start: Date, end: Date, isAllDay: Bool, calendarID: String, calendarTitle: String, allowsModification: Bool, hasRecurrence: Bool, notes: String? = nil, location: String? = nil, url: URL? = nil, alarms: EventAlarmSnapshot = .none, recurrence: RecurrenceSnapshot = .none) {
        let normalizedRecurrence = RecurrenceSnapshot.normalized(recurrence, legacyHasRecurrence: hasRecurrence)
        let hasNonblankMutationID = mutationID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        self.id = id; self.mutationID = hasNonblankMutationID ? mutationID : nil; self.title = title; self.start = start; self.end = end; self.isAllDay = isAllDay; self.calendarID = calendarID; self.calendarTitle = calendarTitle; self.allowsModification = allowsModification && self.mutationID != nil; self.hasRecurrence = normalizedRecurrence != .none; self.notes = notes; self.location = location; self.url = url; self.alarms = alarms; self.recurrence = normalizedRecurrence
    }

    var isAddressable: Bool { mutationID != nil }
}
