import Foundation

enum QuickEntryKind: String, CaseIterable, Codable, Sendable {
    case event, task, routine
}

struct QuickEntryParseContext: Sendable {
    let now: Date
    let calendar: Calendar
    let locale: Locale
    let timeZone: TimeZone

    init(now: Date, calendar: Calendar, locale: Locale, timeZone: TimeZone) {
        let resolvedTimeZone = timeZone
        var configuredCalendar = calendar
        configuredCalendar.locale = locale
        configuredCalendar.timeZone = resolvedTimeZone
        self.now = now
        self.calendar = configuredCalendar
        self.locale = locale
        self.timeZone = resolvedTimeZone
    }
}

enum QuickEntryParseError: Error, Equatable, Sendable {
    case emptyInput
    case noUsableTitle
    case invalidClock
    case invalidDate
    case nonexistentLocalTime
    case ambiguousExpression
}

enum QuickEntryParseWarning: Hashable, Sendable {
    case scheduledTimeIsPast
}

struct QuickEntryPreview: Equatable, Sendable {
    var kind: QuickEntryKind
    var title: String
    var startDate: Date?
    var endDate: Date?
    var isAllDay: Bool
    var dueDate: Date?
    var dueHasTime: Bool
    var routineWindow: RoutineWindow?
    var weekdays: Set<Int>
    var recurrence: RecurrenceRuleDraft?
    var reminderDate: Date?
    var destinationID: String?
    var categoryID: UUID?
    var warnings: Set<QuickEntryParseWarning>

    init(
        kind: QuickEntryKind,
        title: String,
        startDate: Date? = nil,
        endDate: Date? = nil,
        isAllDay: Bool = false,
        dueDate: Date? = nil,
        dueHasTime: Bool = false,
        routineWindow: RoutineWindow? = nil,
        weekdays: Set<Int> = [],
        recurrence: RecurrenceRuleDraft? = nil,
        reminderDate: Date? = nil,
        destinationID: String? = nil,
        categoryID: UUID? = nil,
        warnings: Set<QuickEntryParseWarning> = []
    ) {
        self.kind = kind; self.title = title; self.startDate = startDate; self.endDate = endDate
        self.isAllDay = isAllDay; self.dueDate = dueDate; self.dueHasTime = dueHasTime
        self.routineWindow = routineWindow; self.weekdays = weekdays; self.recurrence = recurrence
        self.reminderDate = reminderDate; self.destinationID = destinationID; self.categoryID = categoryID
        self.warnings = warnings
    }
}
