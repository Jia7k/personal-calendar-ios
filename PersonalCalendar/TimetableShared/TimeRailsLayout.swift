import Foundation

struct TimeRailPlacement: Hashable, Sendable {
    let entry: TimetableEntry
    let weekdayIndex: Int
    let startFraction: Double
    let heightFraction: Double
}

struct TimeRailsLayout: Sendable {
    let calendar: Calendar
    let startMinute: Int
    let endMinute: Int

    init(calendar: Calendar, snapshot: TimetableSnapshotV1) {
        self.calendar = calendar
        let earliestStart = snapshot.entries
            .map { Self.roundedStartMinute(for: $0, calendar: calendar) }
            .min()
        let latestEnd = snapshot.entries
            .map { Self.roundedEndMinute(for: $0, calendar: calendar) }
            .max()
        startMinute = max(0, min(8 * 60, earliestStart ?? 8 * 60))
        endMinute = min(24 * 60, max(18 * 60, latestEnd ?? 18 * 60))
    }

    func placements(snapshot: TimetableSnapshotV1) -> [TimeRailPlacement] {
        guard endMinute > startMinute else { return [] }

        return snapshot.entries.compactMap { entry in
            let weekdayIndex = (calendar.component(.weekday, from: entry.start) + 5) % 7
            guard (0..<5).contains(weekdayIndex) else { return nil }

            let dayStart = calendar.startOfDay(for: entry.start)
            guard
                let railStart = date(at: startMinute, on: dayStart),
                let railEnd = date(at: endMinute, on: dayStart)
            else { return nil }

            let clippedStart = max(entry.start, railStart)
            let clippedEnd = min(entry.end, railEnd)
            guard clippedEnd > clippedStart else { return nil }

            let railDuration = railEnd.timeIntervalSince(railStart)
            return TimeRailPlacement(
                entry: entry,
                weekdayIndex: weekdayIndex,
                startFraction: clippedStart.timeIntervalSince(railStart) / railDuration,
                heightFraction: clippedEnd.timeIntervalSince(clippedStart) / railDuration
            )
        }
        .sorted { left, right in
            if left.weekdayIndex != right.weekdayIndex {
                return left.weekdayIndex < right.weekdayIndex
            }
            if left.entry.start != right.entry.start {
                return left.entry.start < right.entry.start
            }
            if left.entry.end != right.entry.end {
                return left.entry.end < right.entry.end
            }
            return left.entry.id < right.entry.id
        }
    }

    func fraction(for date: Date) -> Double? {
        let dayStart = calendar.startOfDay(for: date)
        guard
            let railStart = self.date(at: startMinute, on: dayStart),
            let railEnd = self.date(at: endMinute, on: dayStart),
            railEnd > railStart,
            railStart <= date,
            date <= railEnd
        else { return nil }

        return date.timeIntervalSince(railStart) / railEnd.timeIntervalSince(railStart)
    }

    private func date(at minute: Int, on dayStart: Date) -> Date? {
        if minute == 24 * 60 {
            return calendar.date(byAdding: .day, value: 1, to: dayStart)
        }
        return calendar.date(
            bySettingHour: minute / 60,
            minute: minute % 60,
            second: 0,
            of: dayStart
        )
    }

    private static func roundedStartMinute(
        for entry: TimetableEntry,
        calendar: Calendar
    ) -> Int {
        minuteOfDay(for: entry.start, calendar: calendar) / 60 * 60
    }

    private static func roundedEndMinute(
        for entry: TimetableEntry,
        calendar: Calendar
    ) -> Int {
        let dayStart = calendar.startOfDay(for: entry.start)
        guard
            let nextDayStart = calendar.date(byAdding: .day, value: 1, to: dayStart),
            entry.end < nextDayStart
        else { return 24 * 60 }

        let components = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: entry.end)
        let minute = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        let hasSubminuteRemainder = (components.second ?? 0) > 0
            || (components.nanosecond ?? 0) > 0
        let outwardMinute = minute + (hasSubminuteRemainder ? 1 : 0)
        return min(24 * 60, (outwardMinute + 59) / 60 * 60)
    }

    private static func minuteOfDay(for date: Date, calendar: Calendar) -> Int {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }
}
