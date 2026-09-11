import Foundation

enum EditorOptionsSummary {
    static func event(
        alarmIntent: EventAlarmMutationIntent,
        alarmSnapshot: EventAlarmSnapshot,
        recurrenceIntent: RecurrenceMutationIntent,
        recurrenceSnapshot: RecurrenceSnapshot,
        destinationTitle: String,
        categoryTitle: String?,
        notes: String?,
        url: URL?
    ) -> String {
        var parts = ["Calendar: \(destinationTitle)"]
        appendCategory(categoryTitle, to: &parts)
        if let alarm = eventAlarm(intent: alarmIntent, snapshot: alarmSnapshot) {
            parts.append(alarm)
        }
        if let recurrence = recurrence(intent: recurrenceIntent, snapshot: recurrenceSnapshot) {
            parts.append(recurrence)
        }
        appendPresence(notes, label: "Notes", to: &parts)
        if url != nil { parts.append("Link") }
        return parts.joined(separator: " · ")
    }

    static func task(
        alarmIntent: ReminderAlarmMutationIntent,
        alarmSnapshot: ReminderAlarmSnapshot?,
        recurrenceIntent: RecurrenceMutationIntent,
        recurrenceSnapshot: RecurrenceSnapshot?,
        destinationTitle: String,
        categoryTitle: String?,
        priority: Int,
        notes: String?
    ) -> String {
        var parts = ["List: \(destinationTitle)"]
        appendCategory(categoryTitle, to: &parts)
        if let alarm = reminderAlarm(intent: alarmIntent, snapshot: alarmSnapshot) {
            parts.append(alarm)
        }
        if let recurrence = recurrence(intent: recurrenceIntent, snapshot: recurrenceSnapshot) {
            parts.append(recurrence)
        }
        if let priority = priorityDescription(priority) { parts.append(priority) }
        appendPresence(notes, label: "Notes", to: &parts)
        return parts.joined(separator: " · ")
    }

    private static func eventAlarm(
        intent: EventAlarmMutationIntent,
        snapshot: EventAlarmSnapshot
    ) -> String? {
        switch intent {
        case .clear:
            nil
        case let .replace(offsets):
            alertCount(offsets.count)
        case .preserve:
            switch snapshot {
            case .none: nil
            case let .editable(offsets): alertCount(offsets.count)
            case let .unsupported(summary): nonempty(summary)
            }
        }
    }

    private static func reminderAlarm(
        intent: ReminderAlarmMutationIntent,
        snapshot: ReminderAlarmSnapshot?
    ) -> String? {
        switch intent {
        case .clear:
            nil
        case .replace:
            "Alert set"
        case .preserve:
            switch snapshot {
            case .none, .some(.none): nil
            case .some(.editable): "Alert set"
            case let .some(.unsupported(summary)): nonempty(summary)
            }
        }
    }

    private static func recurrence(
        intent: RecurrenceMutationIntent,
        snapshot: RecurrenceSnapshot?
    ) -> String? {
        switch intent {
        case .clear:
            nil
        case let .replace(rule):
            recurrenceDescription(rule)
        case .preserve:
            switch snapshot {
            case .none, .some(.none): nil
            case let .some(.editable(rule)): recurrenceDescription(rule)
            case let .some(.unsupported(summary)): nonempty(summary)
            }
        }
    }

    private static func recurrenceDescription(_ rule: RecurrenceRuleDraft) -> String {
        let unit = recurrenceUnit(rule.frequency, plural: rule.interval != 1)
        var parts = [rule.interval == 1 ? "Every \(unit)" : "Every \(rule.interval) \(unit)"]
        if rule.frequency == .weekly, !rule.weekdays.isEmpty {
            let symbols = Calendar.current.shortWeekdaySymbols
            let weekdays = rule.weekdays.sorted().compactMap { day in
                symbols.indices.contains(day - 1) ? symbols[day - 1] : nil
            }
            if !weekdays.isEmpty { parts.append("on \(weekdays.joined(separator: ", "))") }
        }
        if let endDate = rule.endDate {
            parts.append("until \(endDate.formatted(date: .abbreviated, time: .omitted))")
        }
        return parts.joined(separator: " ")
    }

    private static func recurrenceUnit(
        _ frequency: RecurrenceFrequency,
        plural: Bool
    ) -> String {
        switch frequency {
        case .daily: plural ? "days" : "day"
        case .weekly: plural ? "weeks" : "week"
        case .monthly: plural ? "months" : "month"
        case .yearly: plural ? "years" : "year"
        }
    }

    private static func priorityDescription(_ priority: Int) -> String? {
        switch priority {
        case 0: nil
        case 1: "High priority"
        case 5: "Medium priority"
        case 9: "Low priority"
        default: "Provider priority \(priority)"
        }
    }

    private static func alertCount(_ count: Int) -> String? {
        guard count > 0 else { return nil }
        return "\(count) \(count == 1 ? "alert" : "alerts")"
    }

    private static func appendCategory(_ category: String?, to parts: inout [String]) {
        guard let category = nonempty(category) else { return }
        parts.append("Category: \(category)")
    }

    private static func appendPresence(
        _ value: String?,
        label: String,
        to parts: inout [String]
    ) {
        if nonempty(value) != nil { parts.append(label) }
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
