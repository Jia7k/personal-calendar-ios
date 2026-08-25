import Foundation

struct ProfileDraft: Equatable, Sendable {
    var name: String
    var colorHex: String
    var symbolName: String
    var calendarIDs: Set<String>
    var reminderListIDs: Set<String>
    var routineIDs: Set<UUID>
    var defaultCalendarID: String?
    var defaultReminderListID: String?
}

struct ProfileSnapshot: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let name: String
    let colorHex: String
    let symbolName: String
    let sortOrder: Int
    let calendarIDs: Set<String>
    let reminderListIDs: Set<String>
    let routineIDs: Set<UUID>
    let defaultCalendarID: String?
    let defaultReminderListID: String?
}

struct ProfileMembership: Equatable, Sendable {
    let calendarIDs: Set<String>
    let reminderListIDs: Set<String>
    let routineIDs: Set<UUID>
}

struct ProfileScope: Equatable, Sendable {
    let identity: ProfileIdentity
    let calendarIDs: Set<String>
    let reminderListIDs: Set<String>
    let routineIDs: Set<UUID>
    let defaultCalendarID: String?
    let defaultReminderListID: String?
}

enum ProfileSymbols {
    static let allowed: Set<String> = [
        "person.fill",
        "graduationcap.fill",
        "briefcase.fill",
        "house.fill",
        "calendar",
        "book.fill",
        "heart.fill",
        "figure.run",
        "star.fill"
    ]
}
