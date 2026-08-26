import Foundation

struct WeekPlannerBuilder {
    let calendar: Calendar

    func build(
        days: [LocalDay],
        agendas: [LocalDay: DayAgenda],
        events: [CalendarEventSnapshot],
        reminders: [ReminderSnapshot],
        selectedDay: LocalDay
    ) -> WeekPlannerSnapshot {
        let eventByID = events.reduce(into: [String: CalendarEventSnapshot]()) { result, event in
            result[event.id] = event
        }
        let reminderByID = reminders.reduce(into: [String: ReminderSnapshot]()) { result, reminder in
            result[reminder.id] = reminder
        }

        var allDayItems: [WeekPlannerAllDayItem] = []
        var timedItems: [WeekPlannerTimedItem] = []

        for day in days {
            let agenda = agendas[day] ?? DayAgenda(allDay: [], scheduled: [], priority: [])
            allDayItems.append(contentsOf: agenda.allDay.map {
                WeekPlannerAllDayItem(id: occurrenceID(for: $0, day: day), day: day, item: $0)
            })

            for item in agenda.priority where item.source == .task {
                guard case let .reminder(id) = item.origin,
                      let reminder = reminderByID[id],
                      !reminder.dueHasTime,
                      let dueDate = reminder.dueDate,
                      LocalDay(date: dueDate, calendar: calendar) == day else {
                    continue
                }
                allDayItems.append(
                    WeekPlannerAllDayItem(
                        id: occurrenceID(for: item, day: day),
                        day: day,
                        item: item
                    )
                )
            }

            let scheduledEvents = agenda.scheduled.compactMap { item -> EventDraft? in
                guard case let .event(id) = item.origin,
                      let event = eventByID[id],
                      !event.isAllDay else {
                    return nil
                }
                let dayStart = day.startDate(in: calendar)
                let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
                let start = max(event.start, dayStart)
                let end = min(event.end, dayEnd)
                guard start < end else { return nil }
                return EventDraft(item: item, day: day, start: start, end: end)
            }
            timedItems.append(contentsOf: layoutEvents(scheduledEvents))

            timedItems.append(contentsOf: agenda.scheduled.compactMap { item in
                guard case let .reminder(id) = item.origin,
                      let reminder = reminderByID[id],
                      reminder.dueHasTime,
                      let dueDate = reminder.dueDate,
                      LocalDay(date: dueDate, calendar: calendar) == day else {
                    return nil
                }
                return WeekPlannerTimedItem(
                    id: occurrenceID(for: item, day: day),
                    day: day,
                    item: item,
                    kind: .taskDue,
                    start: dueDate,
                    end: nil,
                    overlapColumn: 0,
                    overlapColumnCount: 1
                )
            })
        }

        allDayItems = uniqueAllDayItems(allDayItems).sorted(by: allDaySort)
        timedItems.sort(by: timedSort)
        let bounds = hourBounds(for: timedItems)
        let selectedAgenda = agendas[selectedDay] ?? DayAgenda(allDay: [], scheduled: [], priority: [])
        let laterItems = (selectedAgenda.scheduled + selectedAgenda.priority)
            .filter { $0.source == .routine }
            .sorted(by: AgendaItem.stableSort)

        return WeekPlannerSnapshot(
            days: days,
            allDayItems: allDayItems,
            timedItems: timedItems,
            laterItems: laterItems,
            startHour: bounds.start,
            endHour: bounds.end
        )
    }

    private struct EventDraft {
        let item: AgendaItem
        let day: LocalDay
        let start: Date
        let end: Date
    }

    private func layoutEvents(_ values: [EventDraft]) -> [WeekPlannerTimedItem] {
        let sorted = values.sorted {
            ($0.start, $0.end, $0.item.title, $0.item.id) <
                ($1.start, $1.end, $1.item.title, $1.item.id)
        }
        var result: [WeekPlannerTimedItem] = []
        var cluster: [EventDraft] = []
        var clusterEnd: Date?

        func layoutCluster(_ cluster: [EventDraft]) -> [WeekPlannerTimedItem] {
            guard !cluster.isEmpty else { return [] }
            var columnEnds: [Date] = []
            var assignments: [Int] = []

            for event in cluster {
                if let reusable = columnEnds.firstIndex(where: { $0 <= event.start }) {
                    assignments.append(reusable)
                    columnEnds[reusable] = event.end
                } else {
                    assignments.append(columnEnds.count)
                    columnEnds.append(event.end)
                }
            }

            let count = max(1, columnEnds.count)
            return zip(cluster, assignments).map { event, column in
                WeekPlannerTimedItem(
                    id: occurrenceID(for: event.item, day: event.day),
                    day: event.day,
                    item: event.item,
                    kind: .event,
                    start: event.start,
                    end: event.end,
                    overlapColumn: column,
                    overlapColumnCount: count
                )
            }
        }

        for event in sorted {
            if let currentClusterEnd = clusterEnd, event.start >= currentClusterEnd {
                result.append(contentsOf: layoutCluster(cluster))
                cluster = []
                clusterEnd = nil
            }
            cluster.append(event)
            clusterEnd = max(clusterEnd ?? event.end, event.end)
        }
        result.append(contentsOf: layoutCluster(cluster))
        return result
    }

    private func hourBounds(for items: [WeekPlannerTimedItem]) -> (start: Int, end: Int) {
        guard !items.isEmpty else { return (8, 18) }
        var earliest = 8 * 60
        var latest = 18 * 60

        for item in items {
            let dayStart = item.day.startDate(in: calendar)
            let startMinutes = calendar.dateComponents([.minute], from: dayStart, to: item.start).minute ?? 0
            let endDate = item.end ?? calendar.date(byAdding: .minute, value: 1, to: item.start)!
            let endMinutes = calendar.dateComponents([.minute], from: dayStart, to: endDate).minute ?? startMinutes
            earliest = min(earliest, max(0, startMinutes))
            latest = max(latest, min(24 * 60, endMinutes))
        }

        let startHour = max(0, min(8, earliest / 60))
        let endHour = min(24, max(18, Int(ceil(Double(latest) / 60.0))))
        return (startHour, max(startHour + 1, endHour))
    }

    private func occurrenceID(for item: AgendaItem, day: LocalDay) -> String {
        "\(item.id)|\(day.year)-\(day.month)-\(day.day)"
    }

    private func uniqueAllDayItems(_ values: [WeekPlannerAllDayItem]) -> [WeekPlannerAllDayItem] {
        var seen: Set<String> = []
        return values.filter { seen.insert($0.id).inserted }
    }

    private func allDaySort(_ lhs: WeekPlannerAllDayItem, _ rhs: WeekPlannerAllDayItem) -> Bool {
        if lhs.day != rhs.day { return lhs.day < rhs.day }
        return AgendaItem.stableSort(lhs.item, rhs.item)
    }

    private func timedSort(_ lhs: WeekPlannerTimedItem, _ rhs: WeekPlannerTimedItem) -> Bool {
        if lhs.day != rhs.day { return lhs.day < rhs.day }
        let leftEnd = lhs.end ?? lhs.start
        let rightEnd = rhs.end ?? rhs.start
        return (lhs.start, leftEnd, lhs.item.title, lhs.id) <
            (rhs.start, rightEnd, rhs.item.title, rhs.id)
    }
}
