import Foundation
import SwiftData

@Model
final class RoutineCompletionRecord {
    @Attribute(.unique) var key: String
    var routineID: UUID
    var year: Int
    var month: Int
    var day: Int
    var completedAt: Date

    init(routineID: UUID, day: LocalDay, completedAt: Date = .now) {
        key = "\(routineID.uuidString)|\(day.year)-\(day.month)-\(day.day)"
        self.routineID = routineID
        year = day.year
        month = day.month
        self.day = day.day
        self.completedAt = completedAt
    }

    static func key(routineID: UUID, day: LocalDay) -> String {
        "\(routineID.uuidString)|\(day.year)-\(day.month)-\(day.day)"
    }
}
