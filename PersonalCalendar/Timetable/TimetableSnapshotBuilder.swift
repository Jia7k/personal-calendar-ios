import Foundation

struct TimetableSnapshotBuilder: Sendable {
    let calendar: Calendar
    let maximumEncodedBytes: Int

    init(
        calendar: Calendar,
        maximumEncodedBytes: Int = 256 * 1_024
    ) {
        self.calendar = calendar
        self.maximumEncodedBytes = max(0, maximumEncodedBytes)
    }

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
        let unique = candidates.filter { candidate in
            seen.insert(routeID(for: candidate)).inserted
        }
        let entries = unique.enumerated().map {
            makeEntry(ordinal: $0.offset, identity: $0.element)
        }

        return snapshotWithinBudget(
            entries: entries,
            availability: entries.isEmpty ? .noClasses : .ready,
            now: now,
            interval: interval
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
            entries: [],
            omittedEntryCount: 0
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
        let milliseconds = boundedMilliseconds(for: identity.start)

        return TimetableEntry(
            id: "occurrence:\(milliseconds):\(ordinal)",
            title: identity.title,
            shortTitle: shortTitle(for: identity.title),
            start: identity.start,
            end: identity.end,
            location: identity.location,
            routeID: routeID(for: identity)
        )
    }

    private func snapshotWithinBudget(
        entries: [TimetableEntry],
        availability: TimetableAvailability,
        now: Date,
        interval: DateInterval
    ) -> TimetableSnapshotV1 {
        var retainedEntries = entries

        while true {
            let snapshot = TimetableSnapshotV1(
                version: TimetableSnapshotV1.currentVersion,
                availability: availability,
                generatedAt: now,
                weekStart: interval.start,
                timeZoneIdentifier: calendar.timeZone.identifier,
                entries: retainedEntries,
                omittedEntryCount: entries.count - retainedEntries.count
            )
            if encodedSize(of: snapshot) <= maximumEncodedBytes {
                return snapshot
            }
            // An empty schema envelope has irreducible overhead. Preserve the truthful
            // ready/omitted state when a caller supplies a smaller, impossible budget.
            guard !retainedEntries.isEmpty else { return snapshot }
            retainedEntries.removeLast()
        }
    }

    private func encodedSize(of snapshot: TimetableSnapshotV1) -> Int {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(snapshot).count) ?? .max
    }

    private func routeID(for candidate: EntryCandidate) -> String {
        AppRouteEntryIdentity.make(
            displayID: candidate.displayID,
            occurrenceStart: candidate.start
        )
    }

    private func boundedMilliseconds(for date: Date) -> Int64 {
        let scaled = date.timeIntervalSince1970 * 1_000
        if scaled >= Double(Int64.max) { return .max }
        if scaled <= Double(Int64.min) { return .min }
        return Int64(scaled.rounded())
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
        let leftLocation = left.location ?? ""
        let rightLocation = right.location ?? ""
        let leftLocationKey = stableTextKey(leftLocation)
        let rightLocationKey = stableTextKey(rightLocation)
        if leftLocationKey != rightLocationKey { return leftLocationKey < rightLocationKey }
        if leftLocation != rightLocation { return leftLocation < rightLocation }
        return left.displayID < right.displayID
    }

    private func stableTextKey(_ value: String) -> String {
        value.precomposedStringWithCanonicalMapping
            .lowercased(with: Locale(identifier: "en_US_POSIX"))
    }
}
