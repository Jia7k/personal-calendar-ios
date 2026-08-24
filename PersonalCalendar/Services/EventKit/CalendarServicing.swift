import Foundation

enum AccessState: Equatable, Sendable {
    case notDetermined
    case granted
    case denied
    case restricted
}

struct CalendarDescriptor: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let colorHex: String
    let allowsContentModifications: Bool
}

@MainActor
protocol CalendarServicing: AnyObject {
    var accessState: AccessState { get }

    func requestFullAccess() async -> AccessState
    func calendars() -> [CalendarDescriptor]
    func fetchEvents(in interval: DateInterval, calendarIDs: Set<String>) throws -> [CalendarEventSnapshot]
    func createEvent(_ draft: EventDraft) throws -> String
}
