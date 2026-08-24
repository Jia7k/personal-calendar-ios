import Foundation

struct ReminderListDescriptor: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let colorHex: String
    let allowsContentModifications: Bool
}

@MainActor
protocol RemindersServicing: AnyObject {
    var accessState: AccessState { get }

    func requestFullAccess() async -> AccessState
    func lists() -> [ReminderListDescriptor]
    func fetchReminders(listIDs: Set<String>) async throws -> [ReminderSnapshot]
    func createReminder(_ draft: ReminderDraft) throws -> String
    func setCompleted(id: String, completed: Bool) throws
}
