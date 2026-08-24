import Foundation

enum AgendaSource: String, Equatable, Sendable {
    case event, task, routine
}

enum AgendaPlacement: Equatable, Sendable {
    case allDay, timed(Date), window(RoutineWindow), unscheduled
}

enum AgendaItemOrigin: Equatable, Sendable {
    case event(id: String)
    case reminder(id: String)
    case routine(id: UUID, day: LocalDay)
}

struct AgendaItem: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let source: AgendaSource
    let placement: AgendaPlacement
    let sortDate: Date?
    let priority: Int
    let isCompleted: Bool
    let allowsModification: Bool
    let origin: AgendaItemOrigin

    init(id: String, title: String, source: AgendaSource, placement: AgendaPlacement, sortDate: Date?, priority: Int, isCompleted: Bool, allowsModification: Bool, origin: AgendaItemOrigin? = nil) {
        self.id = id; self.title = title; self.source = source; self.placement = placement; self.sortDate = sortDate
        self.priority = priority; self.isCompleted = isCompleted; self.allowsModification = allowsModification
        self.origin = origin ?? .event(id: id)
    }
}

extension AgendaItem {
    init(reminder: ReminderSnapshot) {
        let placement: AgendaPlacement
        if reminder.dueHasTime, let dueDate = reminder.dueDate {
            placement = .timed(dueDate)
        } else {
            placement = .unscheduled
        }

        self.init(
            id: "task|\(reminder.id)",
            title: reminder.title,
            source: .task,
            placement: placement,
            sortDate: reminder.dueHasTime ? reminder.dueDate : nil,
            priority: reminder.priority,
            isCompleted: reminder.isCompleted,
            allowsModification: reminder.allowsModification
            , origin: .reminder(id: reminder.id)
        )
    }

    init(event: CalendarEventSnapshot) {
        self.init(
            id: "event|\(event.id)",
            title: event.title,
            source: .event,
            placement: event.isAllDay ? .allDay : .timed(event.start),
            sortDate: event.isAllDay ? nil : event.start,
            priority: 0,
            isCompleted: false,
            allowsModification: event.allowsModification
            , origin: .event(id: event.id)
        )
    }

    init(routine: RoutineSnapshot, completed: Bool, day: LocalDay, calendar: Calendar) {
        let sortDate = routine.window.anchorHour.flatMap {
            calendar.date(bySettingHour: $0, minute: 0, second: 0, of: day.startDate(in: calendar))
        }

        self.init(
            id: "routine|\(routine.id.uuidString)|\(day.year)-\(day.month)-\(day.day)",
            title: routine.title,
            source: .routine,
            placement: .window(routine.window),
            sortDate: sortDate,
            priority: 0,
            isCompleted: completed,
            allowsModification: true
            , origin: .routine(id: routine.id, day: day)
        )
    }

    static func stableSort(_ lhs: AgendaItem, _ rhs: AgendaItem) -> Bool {
        switch (lhs.sortDate, rhs.sortDate) {
        case let (left?, right?) where left != right:
            return left < right
        default:
            return (lhs.source.rawValue, lhs.title, lhs.id) < (rhs.source.rawValue, rhs.title, rhs.id)
        }
    }

    static func prioritySort(_ lhs: AgendaItem, _ rhs: AgendaItem) -> Bool {
        lhs.priority == rhs.priority ? stableSort(lhs, rhs) : lhs.priority > rhs.priority
    }
}
