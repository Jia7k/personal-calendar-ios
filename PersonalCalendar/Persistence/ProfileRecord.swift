import Foundation
import SwiftData

@Model
final class ProfileRecord {
    @Attribute(.unique) var id: UUID
    var name: String
    var colorHex: String
    var symbolName: String
    var sortOrder: Int
    var calendarIDs: [String]
    var reminderListIDs: [String]
    var routineIDs: [UUID]
    var defaultCalendarID: String?
    var defaultReminderListID: String?

    init(
        id: UUID = UUID(),
        name: String,
        colorHex: String,
        symbolName: String,
        sortOrder: Int,
        calendarIDs: [String],
        reminderListIDs: [String],
        routineIDs: [UUID],
        defaultCalendarID: String?,
        defaultReminderListID: String?
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.symbolName = symbolName
        self.sortOrder = sortOrder
        self.calendarIDs = calendarIDs
        self.reminderListIDs = reminderListIDs
        self.routineIDs = routineIDs
        self.defaultCalendarID = defaultCalendarID
        self.defaultReminderListID = defaultReminderListID
    }

    static func nameKey(for name: String) -> String {
        let locale = Locale(identifier: "en_US_POSIX")
        return name.precomposedStringWithCanonicalMapping
            .folding(options: [.caseInsensitive], locale: locale)
            .lowercased(with: locale)
    }
}
