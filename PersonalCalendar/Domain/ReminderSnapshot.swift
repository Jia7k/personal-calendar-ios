import Foundation

struct ReminderSnapshot: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let notes: String?
    let dueDate: Date?
    var dueHasTime: Bool = false
    let priority: Int
    let listID: String
    let listTitle: String
    let isCompleted: Bool
    let allowsModification: Bool
    let hasRecurrence: Bool
}
