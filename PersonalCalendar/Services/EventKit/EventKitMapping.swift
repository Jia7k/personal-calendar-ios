import EventKit
import UIKit

@MainActor
enum EventKitRecurrenceMapper {
    static let unsupportedSummary = RecurrenceSnapshot.unsupportedSummary

    static func validate(_ draft: RecurrenceRuleDraft, startsAt: Date?) throws {
        let hasOnlyValidWeekdays = draft.weekdays.allSatisfy { (1...7).contains($0) }
        let usesWeekdaysOnlyForWeeklyRules = draft.frequency == .weekly || draft.weekdays.isEmpty
        let hasFiniteStart = startsAt?.timeIntervalSinceReferenceDate.isFinite ?? true
        let hasFiniteEnd = draft.endDate?.timeIntervalSinceReferenceDate.isFinite ?? true
        let endsOnOrAfterStart = draft.endDate.map { end in
            startsAt.map { start in start <= end } ?? true
        } ?? true

        guard draft.interval > 0, hasOnlyValidWeekdays, usesWeekdaysOnlyForWeeklyRules, hasFiniteStart, hasFiniteEnd, endsOnOrAfterStart else {
            throw DraftValidationError.invalidRecurrence
        }
    }

    static func makeRule(from draft: RecurrenceRuleDraft, startsAt: Date?) throws -> EKRecurrenceRule {
        try validate(draft, startsAt: startsAt)

        let frequency: EKRecurrenceFrequency
        switch draft.frequency {
        case .daily: frequency = .daily
        case .weekly: frequency = .weekly
        case .monthly: frequency = .monthly
        case .yearly: frequency = .yearly
        }

        let weekdays = draft.weekdays.sorted().compactMap(EKWeekday.init(rawValue:)).map(EKRecurrenceDayOfWeek.init)
        return EKRecurrenceRule(
            recurrenceWith: frequency,
            interval: draft.interval,
            daysOfTheWeek: weekdays.isEmpty ? nil : weekdays,
            daysOfTheMonth: nil,
            monthsOfTheYear: nil,
            weeksOfTheYear: nil,
            daysOfTheYear: nil,
            setPositions: nil,
            end: draft.endDate.map(EKRecurrenceEnd.init(end:))
        )
    }

    static func snapshot(from rules: [EKRecurrenceRule], startsAt: Date? = nil) -> RecurrenceSnapshot {
        guard !rules.isEmpty else { return .none }
        guard rules.count == 1, let rule = rules.first,
              rule.interval > 0,
              isGregorian(rule),
              hasRepresentableFirstDay(rule),
              hasOnlyDateOrNoEnd(rule),
              hasNoSelectors(rule),
              hasUnnumberedWeekdays(rule),
              let frequency = frequency(from: rule),
              frequency == .weekly || (rule.daysOfTheWeek?.isEmpty ?? true) else {
            return .unsupported(summary: unsupportedSummary)
        }

        let weekdays = Set(rule.daysOfTheWeek?.map(\.dayOfTheWeek.rawValue) ?? [])
        let draft = RecurrenceRuleDraft(
            frequency: frequency,
            interval: rule.interval,
            weekdays: weekdays,
            endDate: rule.recurrenceEnd?.endDate
        )
        do {
            try validate(draft, startsAt: startsAt)
            return .editable(draft)
        } catch {
            return .unsupported(summary: unsupportedSummary)
        }
    }

    private static func frequency(from rule: EKRecurrenceRule) -> RecurrenceFrequency? {
        switch rule.frequency {
        case .daily: .daily
        case .weekly: .weekly
        case .monthly: .monthly
        case .yearly: .yearly
        @unknown default: nil
        }
    }

    private static func isGregorian(_ rule: EKRecurrenceRule) -> Bool {
        rule.calendarIdentifier == "gregorian"
    }

    static func isRepresentableFirstDayOfTheWeek(_ firstDayOfTheWeek: Int) -> Bool {
        firstDayOfTheWeek == 0 || firstDayOfTheWeek == EKWeekday.monday.rawValue
    }

    private static func hasRepresentableFirstDay(_ rule: EKRecurrenceRule) -> Bool {
        // EventKit normalizes the rules we create to Gregorian/Monday. The draft
        // has no first-weekday field, so only its unset default or Monday can
        // round-trip without silently changing provider-owned semantics.
        isRepresentableFirstDayOfTheWeek(rule.firstDayOfTheWeek)
    }

    private static func hasOnlyDateOrNoEnd(_ rule: EKRecurrenceRule) -> Bool {
        guard let end = rule.recurrenceEnd else { return true }
        return end.endDate != nil && end.occurrenceCount == 0
    }

    private static func hasNoSelectors(_ rule: EKRecurrenceRule) -> Bool {
        [rule.daysOfTheMonth, rule.monthsOfTheYear, rule.weeksOfTheYear, rule.daysOfTheYear, rule.setPositions]
            .allSatisfy { $0?.isEmpty ?? true }
    }

    private static func hasUnnumberedWeekdays(_ rule: EKRecurrenceRule) -> Bool {
        (rule.daysOfTheWeek ?? []).allSatisfy { weekday in
            weekday.weekNumber == 0 && (1...7).contains(weekday.dayOfTheWeek.rawValue)
        }
    }
}

enum EventKitEventCapabilityMapper {
    static func mutationID(from eventIdentifier: String?) -> String? {
        guard let eventIdentifier,
              !eventIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return eventIdentifier
    }

    static func allowsModification(eventIdentifier: String?, calendarAllowsContentModifications: Bool) -> Bool {
        calendarAllowsContentModifications && mutationID(from: eventIdentifier) != nil
    }
}

extension CGColor {
    var hexRGB: String {
        let color = UIColor(cgColor: self)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0

        guard color.getRed(&red, green: &green, blue: &blue, alpha: nil) else {
            return "#000000"
        }

        return String(
            format: "#%02X%02X%02X",
            Int((red * 255).rounded()),
            Int((green * 255).rounded()),
            Int((blue * 255).rounded())
        )
    }
}

@MainActor
extension CalendarEventSnapshot {
    init(event: EKEvent) {
        let calendar = event.calendar
        let mutationID = EventKitEventCapabilityMapper.mutationID(from: event.eventIdentifier)
        let viewIdentity = mutationID ?? event.calendarItemIdentifier

        self.init(
            id: viewIdentity,
            mutationID: mutationID,
            title: event.title ?? "",
            start: event.startDate,
            end: event.endDate,
            isAllDay: event.isAllDay,
            calendarID: calendar?.calendarIdentifier ?? "",
            calendarTitle: calendar?.title ?? "",
            allowsModification: EventKitEventCapabilityMapper.allowsModification(
                eventIdentifier: event.eventIdentifier,
                calendarAllowsContentModifications: calendar?.allowsContentModifications ?? false
            ),
            hasRecurrence: event.hasRecurrenceRules,
            notes: event.notes,
            location: event.location,
            url: event.url,
            alarms: eventAlarmSnapshot(event.alarms),
            recurrence: EventKitRecurrenceMapper.snapshot(from: event.recurrenceRules ?? [], startsAt: event.startDate),
            occurrenceDate: event.occurrenceDate
        )
    }
}

@MainActor
extension ReminderOccurrenceInput {
    init(reminder: EKReminder) {
        let list = reminder.calendar
        let dueComponents = reminder.dueDateComponents

        self.init(
            id: reminder.calendarItemIdentifier,
            title: reminder.title ?? "",
            notes: reminder.notes,
            dueDate: dueComponents?.date,
            dueHasTime: dueComponents?.hour != nil,
            priority: reminder.priority,
            listID: list?.calendarIdentifier ?? "",
            listTitle: list?.title ?? "",
            isCompleted: reminder.isCompleted,
            allowsModification: list?.allowsContentModifications ?? false,
            hasRecurrence: reminder.hasRecurrenceRules,
            alarm: reminderAlarmSnapshot(reminder.alarms),
            recurrence: EventKitRecurrenceMapper.snapshot(from: reminder.recurrenceRules ?? [], startsAt: dueComponents?.date)
        )
    }
}

struct ReminderOccurrenceInput: Sendable {
    let id: String
    let title: String
    let notes: String?
    let dueDate: Date?
    let dueHasTime: Bool
    let priority: Int
    let listID: String
    let listTitle: String
    let isCompleted: Bool
    let allowsModification: Bool
    let hasRecurrence: Bool
    let alarm: ReminderAlarmSnapshot
    let recurrence: RecurrenceSnapshot

    init(id: String, title: String, notes: String?, dueDate: Date?, dueHasTime: Bool, priority: Int, listID: String, listTitle: String, isCompleted: Bool, allowsModification: Bool, hasRecurrence: Bool, alarm: ReminderAlarmSnapshot = .none, recurrence: RecurrenceSnapshot = .none) {
        self.id = id; self.title = title; self.notes = notes; self.dueDate = dueDate; self.dueHasTime = dueHasTime; self.priority = priority; self.listID = listID; self.listTitle = listTitle; self.isCompleted = isCompleted; self.allowsModification = allowsModification; self.hasRecurrence = hasRecurrence; self.alarm = alarm; self.recurrence = recurrence
    }
}

enum ReminderSnapshotMapper {
    // Inputs correspond one-for-one with the occurrences EventKit supplied; this mapper never expands recurrence rules.
    static func snapshots(from occurrences: [ReminderOccurrenceInput]) -> [ReminderSnapshot] {
        occurrences.map(snapshot)
    }

    static func snapshot(from occurrence: ReminderOccurrenceInput) -> ReminderSnapshot {
        ReminderSnapshot(
            id: occurrence.id,
            title: occurrence.title,
            notes: occurrence.notes,
            dueDate: occurrence.dueDate,
            dueHasTime: occurrence.dueHasTime,
            priority: occurrence.priority,
            listID: occurrence.listID,
            listTitle: occurrence.listTitle,
            isCompleted: occurrence.isCompleted,
            allowsModification: occurrence.allowsModification,
            hasRecurrence: occurrence.hasRecurrence,
            alarm: occurrence.alarm,
            recurrence: occurrence.recurrence
        )
    }
}

@MainActor
func eventAlarmSnapshot(_ alarms: [EKAlarm]?) -> EventAlarmSnapshot {
    guard let alarms, !alarms.isEmpty else { return .none }
    let offsets = alarms.compactMap { alarm -> TimeInterval? in
        guard alarm.absoluteDate == nil,
              alarm.structuredLocation == nil,
              alarm.proximity == .none,
              alarm.relativeOffset.isFinite else {
            return nil
        }
        return alarm.relativeOffset
    }
    return offsets.count == alarms.count ? .editable(offsets) : .unsupported(summary: EventKitAlarmMapper.unsupportedSummary)
}

@MainActor
func reminderAlarmSnapshot(_ alarms: [EKAlarm]?) -> ReminderAlarmSnapshot {
    guard let alarms, !alarms.isEmpty else { return .none }
    guard alarms.count == 1,
          let date = alarms[0].absoluteDate,
          alarms[0].structuredLocation == nil,
          alarms[0].proximity == .none else {
        return .unsupported(summary: EventKitAlarmMapper.unsupportedSummary)
    }
    return .editable(date)
}

enum EventKitAlarmMapper {
    static let unsupportedSummary = "This alert pattern can’t be edited here."
}
