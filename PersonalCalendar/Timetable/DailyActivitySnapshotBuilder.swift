import Foundation

struct DailyActivitySnapshotBuilder: Sendable {
    let calendar: Calendar

    func makeSnapshot(profile: DailyActivityProfile, scope: ProfileScope,
                      events: [CalendarEventSnapshot], reminders: [ReminderSnapshot], now: Date,
                      calendarUnavailable: Bool = false, tasksUnavailable: Bool = false) -> DailyActivitySnapshot {
        guard now.timeIntervalSinceReferenceDate.isFinite else {
            return DailyActivitySnapshot(profile: profile, dayStart: .distantPast, dayEnd: .distantPast,
                timeZoneIdentifier: calendar.timeZone.identifier, generatedAt: .distantPast, items: [],
                calendarUnavailable: true, tasksUnavailable: true)
        }
        let dayStart = calendar.startOfDay(for: now)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        let empty = DailyActivitySnapshot(profile: profile, dayStart: dayStart, dayEnd: dayEnd,
            timeZoneIdentifier: calendar.timeZone.identifier, generatedAt: now, items: [],
            calendarUnavailable: calendarUnavailable, tasksUnavailable: tasksUnavailable)
        guard profile.id == scope.identity, empty.hasValidDay else { return empty }
        let eventItems = events.filter {
            scope.calendarIDs.contains($0.calendarID)
                && !$0.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && $0.occurrenceDate.timeIntervalSinceReferenceDate.isFinite
        }.map { event in
            DailyActivityItem(
                id: "event:" + AppRouteEntryIdentity.make(
                    displayID: qualified(source: event.calendarID, id: event.id),
                    occurrenceStart: event.occurrenceDate),
                kind: .event, title: normalized(event.title, fallback: "Event"),
                shortTitle: shortTitle(event.title), start: event.start, end: event.end,
                isAllDay: event.isAllDay, location: event.location.flatMap {
                    let value = $0.trimmingCharacters(in: .whitespacesAndNewlines)
                    return value.isEmpty ? nil : value
                }, hasAlert: event.alarms != .none)
        }
        let taskItems = reminders.compactMap { reminder -> DailyActivityItem? in
            guard scope.reminderListIDs.contains(reminder.listID), !reminder.isCompleted,
                  !reminder.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let due = reminder.dueDate else { return nil }
            return DailyActivityItem(
                id: "task:" + AppRouteEntryIdentity.make(
                    displayID: qualified(source: reminder.listID, id: reminder.id),
                    occurrenceStart: Date(timeIntervalSinceReferenceDate: 0)),
                kind: .task, title: normalized(reminder.title, fallback: "Task"),
                shortTitle: shortTitle(reminder.title), start: due,
                isAllDay: !reminder.dueHasTime, hasAlert: reminder.alarm != .none)
        }
        var seen = Set<String>()
        let items = (eventItems + taskItems).filter { $0.isEligible(in: empty, at: now) }
            .sorted(by: DailyActivityPresentation.itemOrder)
            .filter { seen.insert($0.id).inserted }
        return empty.replacing(items: items)
    }

    private func qualified(source: String, id: String) -> String { "\(source.utf8.count):\(source)\(id)" }

    private func normalized(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private func shortTitle(_ title: String) -> String {
        let range = NSRange(title.startIndex..<title.endIndex, in: title)
        if let expression = try? NSRegularExpression(pattern: #"^([A-Za-z])[A-Za-z]{2}\s*([0-9]{2})([0-9]{2})\b"#),
           let match = expression.firstMatch(in: title, range: range),
           let first = Range(match.range(at: 1), in: title),
           let last = Range(match.range(at: 3), in: title) {
            return (String(title[first]) + String(title[last])).uppercased()
        }
        let result = title.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
            .prefix(4).map(String.init).joined().uppercased()
        return result.isEmpty ? "ITEM" : result
    }
}
