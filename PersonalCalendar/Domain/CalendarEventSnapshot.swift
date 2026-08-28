import Foundation

struct EventOccurrenceAddress: Hashable, Sendable {
    let displayStart: Date
    let occurrenceDate: Date

    var isValid: Bool {
        displayStart.timeIntervalSinceReferenceDate.isFinite
            && occurrenceDate.timeIntervalSinceReferenceDate.isFinite
    }
}

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
    /// EventKit's stable original date for a recurring occurrence. Unlike
    /// `start`, this remains unchanged when a single occurrence is moved.
    let occurrenceDate: Date

    init(id: String, mutationID: String? = nil, title: String, start: Date, end: Date, isAllDay: Bool, calendarID: String, calendarTitle: String, allowsModification: Bool, hasRecurrence: Bool, notes: String? = nil, location: String? = nil, url: URL? = nil, alarms: EventAlarmSnapshot = .none, recurrence: RecurrenceSnapshot = .none, occurrenceDate: Date? = nil) {
        let normalizedRecurrence = RecurrenceSnapshot.normalized(recurrence, legacyHasRecurrence: hasRecurrence)
        let hasNonblankMutationID = mutationID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        self.id = id; self.mutationID = hasNonblankMutationID ? mutationID : nil; self.title = title; self.start = start; self.end = end; self.isAllDay = isAllDay; self.calendarID = calendarID; self.calendarTitle = calendarTitle; self.allowsModification = allowsModification && self.mutationID != nil; self.hasRecurrence = normalizedRecurrence != .none; self.notes = notes; self.location = location; self.url = url; self.alarms = alarms; self.recurrence = normalizedRecurrence; self.occurrenceDate = occurrenceDate ?? start
    }

    var isAddressable: Bool { mutationID != nil }

    var occurrenceAddress: EventOccurrenceAddress {
        EventOccurrenceAddress(
            displayStart: start,
            occurrenceDate: occurrenceDate
        )
    }
}
