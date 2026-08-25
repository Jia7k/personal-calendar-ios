import Foundation

struct TimetableSnapshotBuilder: Sendable {
    let calendar: Calendar

    func makeSnapshot(
        access: AccessState,
        events: [CalendarEventSnapshot],
        now: Date
    ) -> TimetableSnapshotV1 {
        let interval = weekInterval(containing: now)
        guard access == .granted else {
            return TimetableSnapshotV1(
                version: TimetableSnapshotV1.currentVersion,
                availability: .calendarAccessRequired,
                generatedAt: now,
                weekStart: interval.start,
                timeZoneIdentifier: calendar.timeZone.identifier,
                entries: []
            )
        }

        let entries = events
            .filter { event in
                let weekday = calendar.component(.weekday, from: event.start)
                return !event.isAllDay
                    && interval.contains(event.start)
                    && (2...6).contains(weekday)
                    && event.start.timeIntervalSinceReferenceDate.isFinite
                    && event.end.timeIntervalSinceReferenceDate.isFinite
                    && event.start < event.end
            }
            .map(makeEntry)
            .sorted(by: entryOrder)

        return TimetableSnapshotV1(
            version: TimetableSnapshotV1.currentVersion,
            availability: .ready,
            generatedAt: now,
            weekStart: interval.start,
            timeZoneIdentifier: calendar.timeZone.identifier,
            entries: Array(entries.prefix(12))
        )
    }

    func weekInterval(containing now: Date) -> DateInterval {
        let startOfDay = calendar.startOfDay(for: now)
        let weekday = calendar.component(.weekday, from: startOfDay)
        let daysSinceMonday = (weekday + 5) % 7
        let monday = calendar.date(byAdding: .day, value: -daysSinceMonday, to: startOfDay) ?? startOfDay
        let nextMonday = calendar.date(byAdding: .day, value: 7, to: monday) ?? monday.addingTimeInterval(7 * 86_400)
        return DateInterval(start: monday, end: nextMonday)
    }

    private func makeEntry(_ event: CalendarEventSnapshot) -> TimetableEntry {
        let title = bounded(event.title.trimmingCharacters(in: .whitespacesAndNewlines), limit: 48)
        let trimmedLocation = event.location?.trimmingCharacters(in: .whitespacesAndNewlines)
        let location = trimmedLocation.flatMap { value in
            value.isEmpty ? nil : bounded(value, limit: 64)
        }
        let occurrence = Int(event.start.timeIntervalSince1970)

        return TimetableEntry(
            id: "\(event.id)|\(occurrence)",
            title: title,
            shortTitle: shortTitle(for: title),
            start: event.start,
            end: event.end,
            location: location
        )
    }

    private func shortTitle(for title: String) -> String {
        let range = NSRange(title.startIndex..<title.endIndex, in: title)
        let pattern = #"^([A-Za-z])[A-Za-z]{2}\s*([0-9]{2})([0-9]{2})\b"#
        if let expression = try? NSRegularExpression(pattern: pattern),
           let match = expression.firstMatch(in: title, range: range),
           let firstRange = Range(match.range(at: 1), in: title),
           let finalRange = Range(match.range(at: 3), in: title) {
            return (String(title[firstRange]) + String(title[finalRange])).uppercased()
        }

        let fallback = title.unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .prefix(4)
            .map(String.init)
            .joined()
            .uppercased()
        return fallback.isEmpty ? "ITEM" : fallback
    }

    private func bounded(_ value: String, limit: Int) -> String {
        String(value.prefix(limit))
    }

    private func entryOrder(_ left: TimetableEntry, _ right: TimetableEntry) -> Bool {
        if left.start != right.start { return left.start < right.start }
        if left.end != right.end { return left.end < right.end }
        return left.id < right.id
    }
}
