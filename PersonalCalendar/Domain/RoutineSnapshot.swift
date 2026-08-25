import Foundation

struct RoutineSnapshot: Identifiable, Equatable, Sendable {
    let id: UUID
    let title: String
    let weekdays: Set<Int>
    let window: RoutineWindow
    let reminderHour: Int?
    let reminderMinute: Int?
    let isPaused: Bool
    let isArchived: Bool
    let categoryID: UUID?

    init(
        id: UUID,
        title: String,
        weekdays: Set<Int>,
        window: RoutineWindow,
        reminderHour: Int?,
        reminderMinute: Int?,
        isPaused: Bool,
        isArchived: Bool,
        categoryID: UUID? = nil
    ) {
        self.id = id
        self.title = title
        self.weekdays = weekdays
        self.window = window
        self.reminderHour = reminderHour
        self.reminderMinute = reminderMinute
        self.isPaused = isPaused
        self.isArchived = isArchived
        self.categoryID = categoryID
    }
}
