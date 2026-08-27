import Foundation

struct TodayOverdueTask: Identifiable, Equatable, Sendable {
    let reminder: ReminderSnapshot
    let daysOverdue: Int

    var id: String { reminder.id }

    static func order(_ left: Self, _ right: Self) -> Bool {
        let leftDue = left.reminder.dueDate ?? .distantFuture
        let rightDue = right.reminder.dueDate ?? .distantFuture
        if leftDue != rightDue { return leftDue < rightDue }
        return left.id < right.id
    }
}
