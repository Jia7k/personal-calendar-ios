import Foundation

struct TimeRailPlacement: Hashable, Sendable {
    let entry: TimetableEntry
    let weekdayIndex: Int
    let startFraction: Double
    let heightFraction: Double
}

struct TimeRailsLayout: Sendable {
    let calendar: Calendar
    let startHour: Int
    let endHour: Int

    func placements(snapshot: TimetableSnapshotV1) -> [TimeRailPlacement] {
        guard endHour > startHour else { return [] }

        return snapshot.entries.compactMap { entry in
            let weekdayIndex = (calendar.component(.weekday, from: entry.start) + 5) % 7
            guard (0..<5).contains(weekdayIndex) else { return nil }

            let dayStart = calendar.startOfDay(for: entry.start)
            guard
                let railStart = calendar.date(
                    bySettingHour: startHour,
                    minute: 0,
                    second: 0,
                    of: dayStart
                ),
                let railEnd = calendar.date(
                    bySettingHour: endHour,
                    minute: 0,
                    second: 0,
                    of: dayStart
                )
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
}
