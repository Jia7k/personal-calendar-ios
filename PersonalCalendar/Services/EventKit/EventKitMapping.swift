import EventKit
import UIKit

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

extension CalendarEventSnapshot {
    init(event: EKEvent) {
        let calendar = event.calendar

        self.init(
            id: event.eventIdentifier ?? event.calendarItemIdentifier,
            title: event.title ?? "",
            start: event.startDate,
            end: event.endDate,
            isAllDay: event.isAllDay,
            calendarID: calendar?.calendarIdentifier ?? "",
            calendarTitle: calendar?.title ?? "",
            allowsModification: calendar?.allowsContentModifications ?? false,
            hasRecurrence: event.hasRecurrenceRules
        )
    }
}

extension ReminderSnapshot {
    init(reminder: EKReminder) {
        let list = reminder.calendar
        let dueComponents = reminder.dueDateComponents

        self = ReminderSnapshotMapper.snapshot(
            from: ReminderOccurrenceInput(
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
                hasRecurrence: reminder.hasRecurrenceRules
            )
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
            hasRecurrence: occurrence.hasRecurrence
        )
    }
}
