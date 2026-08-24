import Foundation

struct ReminderSnapshot: Identifiable, Equatable, Sendable {
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

    init(
        id: String,
        title: String,
        notes: String?,
        dueDate: Date?,
        dueHasTime: Bool = false,
        priority: Int,
        listID: String,
        listTitle: String,
        isCompleted: Bool,
        allowsModification: Bool,
        hasRecurrence: Bool,
        alarm: ReminderAlarmSnapshot = .none,
        recurrence: RecurrenceSnapshot = .none
    ) {
        let normalizedRecurrence = RecurrenceSnapshot.normalized(recurrence, legacyHasRecurrence: hasRecurrence)
        self.id = id
        self.title = title
        self.notes = notes
        self.dueDate = dueDate
        self.dueHasTime = dueHasTime
        self.priority = priority
        self.listID = listID
        self.listTitle = listTitle
        self.isCompleted = isCompleted
        self.allowsModification = allowsModification
        self.hasRecurrence = normalizedRecurrence != .none
        self.alarm = alarm
        self.recurrence = normalizedRecurrence
    }

    func withCompletion(_ isCompleted: Bool) -> ReminderSnapshot {
        .init(id: id, title: title, notes: notes, dueDate: dueDate, dueHasTime: dueHasTime, priority: priority, listID: listID, listTitle: listTitle, isCompleted: isCompleted, allowsModification: allowsModification, hasRecurrence: hasRecurrence, alarm: alarm, recurrence: recurrence)
    }
}
