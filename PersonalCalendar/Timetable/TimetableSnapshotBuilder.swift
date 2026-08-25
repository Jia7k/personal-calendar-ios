import Foundation

struct TimetableSnapshotBuilder: Sendable {
    let calendar: Calendar

    private struct EntryCandidate: Hashable {
        let displayID: String
        let title: String
        let start: Date
        let end: Date
        let location: String?
    }

    func makeSnapshot(
        access: AccessState,
        events: [CalendarEventSnapshot],
        now: Date
    ) -> TimetableSnapshotV1 {
        makeSnapshot(
            availability: access == .granted ? .ready : .calendarAccessRequired,
            events: events,
            now: now
        )
    }

    func makeSnapshot(
        availability: TimetableAvailability,
        events: [CalendarEventSnapshot],
        now: Date
    ) -> TimetableSnapshotV1 {
        let interval = weekInterval(containing: now)
        guard availability == .ready else {
            return emptySnapshot(availability: availability, now: now, interval: interval)
        }

        let candidates = events
            .filter { event in
                let weekday = calendar.component(.weekday, from: event.start)
                return !event.isAllDay
                    && interval.contains(event.start)
                    && (2...6).contains(weekday)
                    && event.start.timeIntervalSinceReferenceDate.isFinite
                    && event.end.timeIntervalSinceReferenceDate.isFinite
                    && event.start < event.end
            }
            .map(entryCandidate)
            .sorted(by: candidateOrder)
        var seen = Set<String>()
        let unique = candidates.filter { seen.insert($0.displayID).inserted }
        let entries = unique.enumerated().map {
            makeEntry(ordinal: $0.offset, identity: $0.element)
        }

        return TimetableSnapshotV1(
            version: TimetableSnapshotV1.currentVersion,
            availability: entries.isEmpty ? .noClasses : .ready,
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

    private func emptySnapshot(
        availability: TimetableAvailability,
        now: Date,
        interval: DateInterval
    ) -> TimetableSnapshotV1 {
        TimetableSnapshotV1(
            version: TimetableSnapshotV1.currentVersion,
            availability: availability,
            generatedAt: now,
            weekStart: interval.start,
            timeZoneIdentifier: calendar.timeZone.identifier,
            entries: []
        )
    }

    private func entryCandidate(_ event: CalendarEventSnapshot) -> EntryCandidate {
        let title = bounded(
            event.title.trimmingCharacters(in: .whitespacesAndNewlines),
            limit: 48
        )
        let trimmedLocation = event.location?.trimmingCharacters(in: .whitespacesAndNewlines)
        let location = trimmedLocation.flatMap { value in
            value.isEmpty ? nil : bounded(value, limit: 64)
        }
        return EntryCandidate(
            displayID: event.id,
            title: title,
            start: event.start,
            end: event.end,
            location: location
        )
    }

    private func makeEntry(ordinal: Int, identity: EntryCandidate) -> TimetableEntry {
        let milliseconds = Int64((identity.start.timeIntervalSince1970 * 1_000).rounded())

        return TimetableEntry(
            id: "occurrence:\(milliseconds):\(ordinal)",
            title: identity.title,
            shortTitle: shortTitle(for: identity.title),
            start: identity.start,
            end: identity.end,
            location: identity.location
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

    private func candidateOrder(_ left: EntryCandidate, _ right: EntryCandidate) -> Bool {
        if left.start != right.start { return left.start < right.start }
        if left.end != right.end { return left.end < right.end }
        if left.title != right.title { return left.title < right.title }
        let locationOrder = (left.location ?? "").localizedCaseInsensitiveCompare(right.location ?? "")
        if locationOrder != .orderedSame { return locationOrder == .orderedAscending }
        return left.displayID < right.displayID
    }
}
