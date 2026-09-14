import Foundation

struct DayAgenda: Equatable, Sendable {
    var allDay: [AgendaItem]
    var scheduled: [AgendaItem]
    var priority: [AgendaItem]

    var eventCount: Int {
        allDay.lazy.filter { $0.source == .event }.count
            + scheduled.lazy.filter { $0.source == .event }.count
    }
}

@MainActor
struct AgendaComposer {
    private let categories: (any CategoryRepository)?

    init(categories: (any CategoryRepository)? = nil) {
        self.categories = categories
    }

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
        let categoriesByID = categoryLookup()
        let eventItems = events
            .filter { $0.start < interval.end && $0.end > interval.start }
            .map { event in
                let category = event.mutationID.flatMap { try? categories?.category(for: .event, externalID: $0) }
                return AgendaItem(event: event, category: category)
            }
        let reminderItems = reminders
            .filter { shouldInclude($0, on: day, interval: interval, includeOverdueTasks: includeOverdueTasks, calendar: calendar) }
            .map { reminder in
                let category = try? categories?.category(for: .task, externalID: reminder.id)
                return AgendaItem(reminder: reminder, category: category)
            }
        let weekday = calendar.component(.weekday, from: start)
        let routineItems = routines
            .filter { !$0.isPaused && !$0.isArchived && $0.weekdays.contains(weekday) }
            .map { routine in
                AgendaItem(
                    routine: routine,
                    completed: completedRoutineIDs.contains(routine.id),
                    day: day,
                    calendar: calendar,
                    category: routine.categoryID.flatMap { categoriesByID[$0] }
                )
            }
        let items = eventItems + reminderItems + routineItems

        return DayAgenda(
            allDay: items.filter { $0.placement == .allDay }.sorted(by: AgendaItem.stableSort),
            scheduled: items.filter { $0.placement.isScheduled }.sorted(by: AgendaItem.stableSort),
            priority: items.filter { $0.placement.isPriority }.sorted(by: AgendaItem.prioritySort)
        )
    }

    private func categoryLookup() -> [UUID: CategorySnapshot] {
        guard let values = try? categories?.list() else { return [:] }
        return Dictionary(uniqueKeysWithValues: values.map { ($0.id, $0) })
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
            ? dueDate >= interval.start && dueDate < interval.end
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
