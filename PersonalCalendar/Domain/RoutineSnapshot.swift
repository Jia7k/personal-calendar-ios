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
}
