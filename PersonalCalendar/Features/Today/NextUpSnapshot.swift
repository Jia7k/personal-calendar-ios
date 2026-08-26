import Foundation

struct NextUpSnapshot: Equatable, Sendable {
    let event: NextUpEventSnapshot?
    let deadline: NextUpDeadlineSnapshot?
}

struct NextUpEventSnapshot: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case current
        case upcoming
    }

    let title: String
    let start: Date
    let end: Date
    let location: String?
    let origin: AgendaItemOrigin
    let phase: Phase
}

struct NextUpDeadlineSnapshot: Equatable, Sendable {
    let title: String
    let dueDate: Date
    let dueHasTime: Bool
    let origin: AgendaItemOrigin
}

struct NextUpBuilder: Sendable {
    func build(
        agenda: DayAgenda,
        events: [CalendarEventSnapshot],
        reminders: [ReminderSnapshot],
        now: Date,
        calendar: Calendar = .current
    ) -> NextUpSnapshot? {
        let agendaEventIDs = Set(agenda.scheduled.compactMap { item -> String? in
            guard case let .event(id) = item.origin else { return nil }
            return id
        })
        let timedEvents = events.filter {
            !$0.isAllDay
                && $0.end > $0.start
                && $0.end > now
                && agendaEventIDs.contains($0.id)
        }
        let currentEvent = timedEvents
            .filter { $0.start <= now }
            .sorted(by: eventSort)
            .first
        let upcomingEvent = timedEvents
            .filter { $0.start > now }
            .sorted(by: eventSort)
            .first
        let selectedEvent = currentEvent ?? upcomingEvent

        let event = selectedEvent.map { value in
            NextUpEventSnapshot(
                title: value.title,
                start: value.start,
                end: value.end,
                location: normalizedLocation(value.location),
                origin: .event(id: value.id),
                phase: value.start <= now ? .current : .upcoming
            )
        }

        let deadline = reminders
            .filter {
                guard !$0.isCompleted, let dueDate = $0.dueDate else {
                    return false
                }
                if $0.dueHasTime { return dueDate > now }
                return calendar.startOfDay(for: dueDate)
                    >= calendar.startOfDay(for: now)
            }
            .sorted(by: reminderSort)
            .first
            .flatMap { value -> NextUpDeadlineSnapshot? in
                guard let dueDate = value.dueDate else { return nil }
                return NextUpDeadlineSnapshot(
                    title: value.title,
                    dueDate: dueDate,
                    dueHasTime: value.dueHasTime,
                    origin: .reminder(id: value.id)
                )
            }

        guard event != nil || deadline != nil else { return nil }
        return NextUpSnapshot(event: event, deadline: deadline)
    }

    private func eventSort(_ lhs: CalendarEventSnapshot, _ rhs: CalendarEventSnapshot) -> Bool {
        if lhs.start != rhs.start { return lhs.start < rhs.start }
        if lhs.end != rhs.end { return lhs.end < rhs.end }
        if lhs.title != rhs.title { return lhs.title < rhs.title }
        return lhs.id < rhs.id
    }

    private func reminderSort(_ lhs: ReminderSnapshot, _ rhs: ReminderSnapshot) -> Bool {
        guard let leftDueDate = lhs.dueDate, let rightDueDate = rhs.dueDate else {
            return lhs.dueDate != nil
        }
        if leftDueDate != rightDueDate { return leftDueDate < rightDueDate }
        if lhs.title != rhs.title { return lhs.title < rhs.title }
        return lhs.id < rhs.id
    }

    private func normalizedLocation(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
