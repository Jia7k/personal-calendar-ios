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
        hasRecurrence: Bool
    ) {
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
        self.hasRecurrence = hasRecurrence
    }
}
