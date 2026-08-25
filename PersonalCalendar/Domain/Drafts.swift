import Foundation

struct ReminderScheduleValue: Equatable, Sendable { let date: Date; let hasTime: Bool }
enum ReminderScheduleMutationIntent: Equatable, Sendable { case preserve(current: ReminderScheduleValue?), clear, replace(ReminderScheduleValue) }

struct EventDraft: Equatable, Sendable {
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool
    var calendarID: String?
    var notes: String?
    var location: String?
    var url: URL?
    var alarms: EventAlarmMutationIntent
    var recurrence: RecurrenceMutationIntent

    init(title: String, start: Date, end: Date, isAllDay: Bool, calendarID: String?, notes: String? = nil, location: String? = nil, url: URL? = nil, alarms: EventAlarmMutationIntent = .preserve, recurrence: RecurrenceMutationIntent = .preserve) {
        self.title = title; self.start = start; self.end = end; self.isAllDay = isAllDay; self.calendarID = calendarID
        self.notes = notes; self.location = location; self.url = url; self.alarms = alarms; self.recurrence = recurrence
    }
}

struct ReminderDraft: Equatable, Sendable {
    var title: String
    var notes: String?
    var dueDate: Date? { switch schedule { case let .preserve(current): current?.date; case .clear: nil; case let .replace(value): value.date } }
    var dueHasTime: Bool { switch schedule { case let .preserve(current): current?.hasTime ?? false; case .clear: false; case let .replace(value): value.hasTime } }
    private(set) var hasInvalidLegacyDueTimeWithoutDate: Bool
    var priority: Int
    var listID: String?
    var alarm: ReminderAlarmMutationIntent
    var recurrence: RecurrenceMutationIntent
    var schedule: ReminderScheduleMutationIntent {
        didSet { hasInvalidLegacyDueTimeWithoutDate = false }
    }

    init(title: String, notes: String?, dueDate: Date?, dueHasTime: Bool = false, priority: Int, listID: String? = nil, alarm: ReminderAlarmMutationIntent = .preserve, recurrence: RecurrenceMutationIntent = .preserve) {
        self.title = title; self.notes = notes; self.priority = priority; self.listID = listID
        self.alarm = alarm; self.recurrence = recurrence
        self.hasInvalidLegacyDueTimeWithoutDate = dueDate == nil && dueHasTime
        self.schedule = dueDate.map { .replace(.init(date: $0, hasTime: dueHasTime)) } ?? .clear
    }
}

struct RoutineDraft: Equatable, Sendable {
    var title: String
    var weekdays: Set<Int>
    var window: RoutineWindow
    var reminderHour: Int?
    var reminderMinute: Int?
    var categoryID: UUID? = nil
}
