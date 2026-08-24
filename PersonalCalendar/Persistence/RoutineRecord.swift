import Foundation
import SwiftData

@Model
final class RoutineRecord {
    @Attribute(.unique) var id: UUID
    var title: String
    var weekdays: [Int]
    var windowRaw: String
    var reminderHour: Int?
    var reminderMinute: Int?
    var isPaused: Bool
    var isArchived: Bool
    var createdAt: Date

    init(id: UUID = UUID(), draft: RoutineDraft, createdAt: Date = .now) {
        self.id = id
        title = draft.title
        weekdays = draft.weekdays.sorted()
        windowRaw = draft.window.rawValue
        reminderHour = draft.reminderHour
        reminderMinute = draft.reminderMinute
        isPaused = false
        isArchived = false
        self.createdAt = createdAt
    }
}
