import Foundation

struct DayAgenda: Equatable, Sendable {
    var allDay: [AgendaItem]
    var scheduled: [AgendaItem]
    var priority: [AgendaItem]
}

struct AgendaComposer {
    func compose(
        day: LocalDay,
        events: [CalendarEventSnapshot],
        reminders: [ReminderSnapshot],
        routines: [RoutineSnapshot],
        completedRoutineIDs: Set<UUID>,
        includeOverdueTasks: Bool,
        calendar: Calendar
    ) -> DayAgenda {
        let start = day.startDate(in: calendar)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        let interval = DateInterval(start: start, end: end)
        let eventItems = events
            .filter { $0.start < interval.end && $0.end > interval.start }
            .map(AgendaItem.init(event:))
        let reminderItems = reminders
            .filter { shouldInclude($0, on: day, interval: interval, includeOverdueTasks: includeOverdueTasks, calendar: calendar) }
            .map(AgendaItem.init(reminder:))
        let weekday = calendar.component(.weekday, from: start)
        let routineItems = routines
            .filter { !$0.isPaused && !$0.isArchived && $0.weekdays.contains(weekday) }
            .map { AgendaItem(routine: $0, completed: completedRoutineIDs.contains($0.id), day: day, calendar: calendar) }
        let items = eventItems + reminderItems + routineItems

        return DayAgenda(
            allDay: items.filter { $0.placement == .allDay }.sorted(by: AgendaItem.stableSort),
            scheduled: items.filter { $0.placement.isScheduled }.sorted(by: AgendaItem.stableSort),
            priority: items.filter { $0.placement.isPriority }.sorted(by: AgendaItem.prioritySort)
        )
    }

    private func shouldInclude(
        _ reminder: ReminderSnapshot,
        on day: LocalDay,
        interval: DateInterval,
        includeOverdueTasks: Bool,
        calendar: Calendar
    ) -> Bool {
        guard !reminder.isCompleted, let dueDate = reminder.dueDate else { return false }
        let dueOnDay = reminder.dueHasTime
            ? interval.contains(dueDate)
            : LocalDay(date: dueDate, calendar: calendar) == day
        return dueOnDay || (includeOverdueTasks && dueDate < interval.start)
    }
}

private extension AgendaPlacement {
    var isScheduled: Bool {
        switch self {
        case .timed:
            true
        case let .window(window):
            window.anchorHour != nil
        case .allDay, .unscheduled:
            false
        }
    }

    var isPriority: Bool {
        self == .unscheduled || self == .window(.anytime)
    }
}
