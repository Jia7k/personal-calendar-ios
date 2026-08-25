import Foundation

struct LocalNotificationRequest: Equatable, Sendable {
    let identifier: String
    let title: String
    let body: String
    let fireDate: Date
}

@MainActor
protocol NotificationScheduling: AnyObject {
    func pendingRequests() async -> [LocalNotificationRequest]
    func replaceAppRequests(with requests: [LocalNotificationRequest]) async throws
}

struct MorningSummaryInput: Sendable {
    let enabled: Bool
    let hour: Int
    let minute: Int
    let day: LocalDay
    let agenda: DayAgenda
    let showsNextTitle: Bool
}
