import Foundation

struct EventDraft: Equatable, Sendable {
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool
    var calendarID: String?
}

struct ReminderDraft: Equatable, Sendable {
    var title: String
    var notes: String?
    var dueDate: Date?
    var dueHasTime: Bool = false
    var priority: Int
    var listID: String?
}

struct RoutineDraft: Equatable, Sendable {
    var title: String
    var weekdays: Set<Int>
    var window: RoutineWindow
    var reminderHour: Int?
    var reminderMinute: Int?
}
