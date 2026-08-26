import Foundation

struct CalendarSearchMatcher: Sendable {
    let calendar: Calendar
    let locale: Locale

    func makeCorpus(
        events: [CalendarEventSnapshot],
        reminders: [ReminderSnapshot],
        routines: [RoutineSnapshot],
        categories: [CategorySnapshot],
        now: Date
    ) -> [CalendarSearchResult] {
        let categoryNames = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0.name) })
        let day = LocalDay(date: now, calendar: calendar)

        let eventResults = events.map { event in
            let dateText = searchableDate(event.start, includesTime: !event.isAllDay)
            let sourceText = event.calendarTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            let subtitleParts = [
                sourceText,
                displayDate(event.start, includesTime: !event.isAllDay),
                event.location?.trimmingCharacters(in: .whitespacesAndNewlines)
            ].compactMap { value -> String? in
                guard let value, !value.isEmpty else { return nil }
                return value
            }

            return CalendarSearchResult(
                id: "event|\(event.id)",
                group: event.end >= now ? .upcoming : .pastAndCompleted,
                source: .event,
                title: event.title,
                subtitle: subtitleParts.joined(separator: " • "),
                date: event.start,
                origin: .event(id: event.id),
                searchableText: searchable([
                    event.title,
                    event.location,
                    event.notes,
                    sourceText,
                    "event",
                    dateText
                ])
            )
        }

        let reminderResults = reminders.map { reminder in
            let dateText = reminder.dueDate.map { searchableDate($0, includesTime: reminder.dueHasTime) }
            let priority = priorityLabel(reminder.priority)
            let subtitleParts = [
                reminder.listTitle,
                reminder.dueDate.map { displayDate($0, includesTime: reminder.dueHasTime) },
                priority
            ].compactMap { value -> String? in
                guard let value, !value.isEmpty else { return nil }
                return value
            }

            return CalendarSearchResult(
                id: "task|\(reminder.id)",
                group: reminder.isCompleted ? .pastAndCompleted : .upcoming,
                source: .task,
                title: reminder.title,
                subtitle: subtitleParts.joined(separator: " • "),
                date: reminder.dueDate,
                origin: .reminder(id: reminder.id),
                searchableText: searchable([
                    reminder.title,
                    reminder.notes,
                    reminder.listTitle,
                    "task",
                    dateText,
                    priority
                ])
            )
        }

        let routineResults = routines.compactMap { routine -> CalendarSearchResult? in
            guard !routine.isArchived else { return nil }
            let weekdays = routine.weekdays.sorted().compactMap(weekdayName).joined(separator: " ")
            let category = routine.categoryID.flatMap { categoryNames[$0] }
            let window = routine.window.rawValue.capitalized(with: locale)
            let subtitle = [window, category].compactMap { $0 }.joined(separator: " • ")

            return CalendarSearchResult(
                id: "routine|\(routine.id.uuidString)",
                group: .routines,
                source: .routine,
                title: routine.title,
                subtitle: subtitle,
                date: nil,
                origin: .routine(id: routine.id, day: day),
                searchableText: searchable([
                    routine.title,
                    "routine",
                    routine.window.rawValue,
                    weekdays,
                    category,
                    routine.isPaused ? "paused" : nil
                ])
            )
        }

        return eventResults + reminderResults + routineResults
    }

    func sections(matching query: String, corpus: [CalendarSearchResult]) -> CalendarSearchSections {
        let tokens = normalized(query)
            .split(whereSeparator: \Character.isWhitespace)
            .map(String.init)
        guard !tokens.isEmpty else { return .empty }

        let matches = corpus.filter { result in
            let haystack = normalized(result.searchableText)
            return tokens.allSatisfy(haystack.contains)
        }

        let upcoming = matches
            .filter { $0.group == .upcoming }
            .sorted(by: ascendingDate)
            .prefix(50)
        let past = matches
            .filter { $0.group == .pastAndCompleted }
            .sorted(by: descendingDate)
            .prefix(50)
        let routines = matches
            .filter { $0.group == .routines }
            .sorted(by: routineOrder)
            .prefix(50)

        return CalendarSearchSections(
            upcoming: Array(upcoming),
            pastAndCompleted: Array(past),
            routines: Array(routines)
        )
    }

    private func searchable(_ values: [String?]) -> String {
        values.compactMap { value in
            guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
            return value
        }.joined(separator: " ")
    }

    private func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: locale)
    }

    private func weekdayName(_ weekday: Int) -> String? {
        guard (1...7).contains(weekday) else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.timeZone = calendar.timeZone
        return formatter.weekdaySymbols[weekday - 1]
    }

    private func searchableDate(_ date: Date, includesTime: Bool) -> String {
        var parts = [
            displayDate(date, includesTime: includesTime),
            weekdayText(date)
        ]
        if includesTime {
            parts.append(timeText(date))
        }
        return parts.joined(separator: " ")
    }

    private func displayDate(_ date: Date, includesTime: Bool) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.timeZone = calendar.timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = includesTime ? .short : .none
        return formatter.string(from: date)
    }

    private func weekdayText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date)
    }

    private func timeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.timeZone = calendar.timeZone
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }

    private func priorityLabel(_ priority: Int) -> String? {
        switch priority {
        case 1...4: "High priority"
        case 5: "Medium priority"
        case 6...9: "Low priority"
        default: nil
        }
    }

    private func ascendingDate(_ lhs: CalendarSearchResult, _ rhs: CalendarSearchResult) -> Bool {
        switch (lhs.date, rhs.date) {
        case let (left?, right?) where left != right: left < right
        case (_?, nil): true
        case (nil, _?): false
        default: tieBreak(lhs, rhs)
        }
    }

    private func descendingDate(_ lhs: CalendarSearchResult, _ rhs: CalendarSearchResult) -> Bool {
        switch (lhs.date, rhs.date) {
        case let (left?, right?) where left != right: left > right
        case (_?, nil): true
        case (nil, _?): false
        default: tieBreak(lhs, rhs)
        }
    }

    private func routineOrder(_ lhs: CalendarSearchResult, _ rhs: CalendarSearchResult) -> Bool {
        let comparison = lhs.title.compare(rhs.title, options: [.caseInsensitive, .diacriticInsensitive], range: nil, locale: locale)
        return comparison == .orderedSame ? lhs.id < rhs.id : comparison == .orderedAscending
    }

    private func tieBreak(_ lhs: CalendarSearchResult, _ rhs: CalendarSearchResult) -> Bool {
        if lhs.source.rawValue != rhs.source.rawValue { return lhs.source.rawValue < rhs.source.rawValue }
        let comparison = lhs.title.compare(rhs.title, options: [.caseInsensitive, .diacriticInsensitive], range: nil, locale: locale)
        return comparison == .orderedSame ? lhs.id < rhs.id : comparison == .orderedAscending
    }
}
