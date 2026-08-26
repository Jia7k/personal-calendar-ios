import Foundation

struct TaskTimeBlockSuggestion: Identifiable, Equatable, Sendable {
    let id: String
    let interval: DateInterval
    let conflicts: [String]
}

struct TaskTimeBlockPlanner: Sendable {
    private static let supportedDurations = Set([30, 60, 90])

    let calendar: Calendar
    let workingStartHour: Int
    let workingEndHour: Int

    init(
        calendar: Calendar,
        workingStartHour: Int = 8,
        workingEndHour: Int = 21
    ) {
        self.calendar = calendar
        self.workingStartHour = workingStartHour
        self.workingEndHour = workingEndHour
    }

    func suggestions(
        task: ReminderSnapshot,
        durationMinutes: Int,
        events: [CalendarEventSnapshot],
        now: Date
    ) -> [TaskTimeBlockSuggestion] {
        guard Self.supportedDurations.contains(durationMinutes),
              now.timeIntervalSinceReferenceDate.isFinite,
              let day = candidateDay(for: task, now: now),
              let workingInterval = workingInterval(on: day),
              let duration = calendar.date(
                byAdding: .minute,
                value: durationMinutes,
                to: workingInterval.start
              )?.timeIntervalSince(workingInterval.start),
              duration > 0
        else {
            return []
        }

        let lowerBound: Date
        if calendar.isDate(day, inSameDayAs: now) {
            lowerBound = max(workingInterval.start, now)
        } else {
            lowerBound = workingInterval.start
        }
        guard lowerBound < workingInterval.end else { return [] }

        let availableInterval = DateInterval(start: lowerBound, end: workingInterval.end)
        let busy = mergedBusyIntervals(events: events, within: availableInterval)
        let free = freeIntervals(within: availableInterval, excluding: busy)

        let due = effectiveDue(for: task, on: day, workingEnd: workingInterval.end)
        var proposed: [DateInterval] = []

        if let due, due > availableInterval.start {
            let cutoff = min(due, availableInterval.end)
            let beforeDue = free.compactMap { gap -> DateInterval? in
                let end = min(gap.end, cutoff)
                guard gap.start < end,
                      let start = calendar.date(
                        byAdding: .minute,
                        value: -durationMinutes,
                        to: end
                      ),
                      start >= gap.start
                else {
                    return nil
                }
                return DateInterval(start: start, end: end)
            }
            proposed.append(contentsOf: beforeDue.sorted { $0.start > $1.start })
        }

        let laterStart = due.map { max($0, availableInterval.start) } ?? availableInterval.start
        if proposed.count < 3 {
            let later = free.compactMap { gap -> DateInterval? in
                let start = max(gap.start, laterStart)
                guard start < gap.end,
                      let end = calendar.date(
                        byAdding: .minute,
                        value: durationMinutes,
                        to: start
                      ),
                      end <= gap.end
                else {
                    return nil
                }
                return DateInterval(start: start, end: end)
            }
            proposed.append(contentsOf: later.sorted { $0.start < $1.start })
        }

        var seen = Set<String>()
        return proposed.compactMap { interval in
            let id = suggestionID(for: interval)
            guard seen.insert(id).inserted else { return nil }
            return TaskTimeBlockSuggestion(
                id: id,
                interval: interval,
                conflicts: conflicts(for: interval, events: events)
            )
        }
        .prefix(3)
        .map { $0 }
    }

    func conflicts(
        for interval: DateInterval,
        events: [CalendarEventSnapshot]
    ) -> [String] {
        guard interval.start.timeIntervalSinceReferenceDate.isFinite,
              interval.end.timeIntervalSinceReferenceDate.isFinite,
              interval.start < interval.end
        else {
            return []
        }

        return events
            .filter { event in
                !event.isAllDay
                    && event.start.timeIntervalSinceReferenceDate.isFinite
                    && event.end.timeIntervalSinceReferenceDate.isFinite
                    && event.start < event.end
                    && event.start < interval.end
                    && event.end > interval.start
            }
            .sorted(by: stableEventOrder)
            .reduce(into: [String]()) { result, event in
                let title = event.title.trimmingCharacters(in: .whitespacesAndNewlines)
                let value = title.isEmpty ? "Busy" : title
                if !result.contains(value) {
                    result.append(value)
                }
            }
    }

    private func candidateDay(for task: ReminderSnapshot, now: Date) -> Date? {
        let today = calendar.startOfDay(for: now)
        guard let due = task.dueDate,
              due.timeIntervalSinceReferenceDate.isFinite,
              calendar.startOfDay(for: due) >= today
        else {
            return today
        }
        return calendar.startOfDay(for: due)
    }

    private func workingInterval(on day: Date) -> DateInterval? {
        guard workingStartHour >= 0,
              workingEndHour <= 24,
              workingStartHour < workingEndHour,
              let start = calendar.date(
                bySettingHour: workingStartHour,
                minute: 0,
                second: 0,
                of: day
              ),
              let end = workingEnd(on: day),
              start < end
        else {
            return nil
        }
        return DateInterval(start: start, end: end)
    }

    private func workingEnd(on day: Date) -> Date? {
        if workingEndHour == 24 {
            return calendar.date(
                byAdding: .day,
                value: 1,
                to: calendar.startOfDay(for: day)
            )
        }
        return calendar.date(
            bySettingHour: workingEndHour,
            minute: 0,
            second: 0,
            of: day
        )
    }

    private func effectiveDue(
        for task: ReminderSnapshot,
        on day: Date,
        workingEnd: Date
    ) -> Date? {
        guard let due = task.dueDate,
              due.timeIntervalSinceReferenceDate.isFinite,
              calendar.isDate(due, inSameDayAs: day)
        else {
            return nil
        }
        return task.dueHasTime ? due : workingEnd
    }

    private func mergedBusyIntervals(
        events: [CalendarEventSnapshot],
        within bounds: DateInterval
    ) -> [DateInterval] {
        let intervals = events.compactMap { event -> DateInterval? in
            guard !event.isAllDay,
                  event.start.timeIntervalSinceReferenceDate.isFinite,
                  event.end.timeIntervalSinceReferenceDate.isFinite,
                  event.start < event.end,
                  event.start < bounds.end,
                  event.end > bounds.start
            else {
                return nil
            }
            return DateInterval(
                start: max(event.start, bounds.start),
                end: min(event.end, bounds.end)
            )
        }
        .sorted {
            if $0.start != $1.start { return $0.start < $1.start }
            return $0.end < $1.end
        }

        return intervals.reduce(into: [DateInterval]()) { result, interval in
            guard let last = result.last else {
                result.append(interval)
                return
            }
            if interval.start <= last.end {
                result[result.count - 1] = DateInterval(
                    start: last.start,
                    end: max(last.end, interval.end)
                )
            } else {
                result.append(interval)
            }
        }
    }

    private func freeIntervals(
        within bounds: DateInterval,
        excluding busy: [DateInterval]
    ) -> [DateInterval] {
        var cursor = bounds.start
        var free: [DateInterval] = []
        for interval in busy {
            if cursor < interval.start {
                free.append(DateInterval(start: cursor, end: interval.start))
            }
            cursor = max(cursor, interval.end)
        }
        if cursor < bounds.end {
            free.append(DateInterval(start: cursor, end: bounds.end))
        }
        return free
    }

    private func suggestionID(for interval: DateInterval) -> String {
        let start = Int64((interval.start.timeIntervalSince1970 * 1_000).rounded())
        let end = Int64((interval.end.timeIntervalSince1970 * 1_000).rounded())
        return "time-block:\(start):\(end)"
    }

    private func stableEventOrder(
        _ lhs: CalendarEventSnapshot,
        _ rhs: CalendarEventSnapshot
    ) -> Bool {
        let leftTitle = lhs.title.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        let rightTitle = rhs.title.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        if leftTitle != rightTitle { return leftTitle < rightTitle }
        if lhs.title != rhs.title { return lhs.title < rhs.title }
        if lhs.start != rhs.start { return lhs.start < rhs.start }
        return lhs.id < rhs.id
    }
}
