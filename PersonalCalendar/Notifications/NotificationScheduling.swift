import Foundation

struct LocalNotificationRequest: Equatable, Sendable {
    let identifier: String
    let title: String
    let body: String
    let fireDate: Date
    let categoryIdentifier: String?
    let userInfo: [String: String]

    init(
        identifier: String,
        title: String,
        body: String,
        fireDate: Date,
        categoryIdentifier: String? = nil,
        userInfo: [String: String] = [:]
    ) {
        self.identifier = identifier
        self.title = title
        self.body = body
        self.fireDate = fireDate
        self.categoryIdentifier = categoryIdentifier
        self.userInfo = userInfo
    }
}

@MainActor
protocol NotificationScheduling: AnyObject {
    func pendingRequests() async -> [LocalNotificationRequest]
    func replaceAppRequests(with requests: [LocalNotificationRequest]) async throws
    func mutateAppRequests(
        _ transform: @escaping @MainActor @Sendable (
            [LocalNotificationRequest]
        ) throws -> [LocalNotificationRequest]
    ) async throws
    func schedule(_ request: LocalNotificationRequest) async throws
}

extension NotificationScheduling {
    func mutateAppRequests(
        _ transform: @escaping @MainActor @Sendable (
            [LocalNotificationRequest]
        ) throws -> [LocalNotificationRequest]
    ) async throws {
        let pending = await pendingRequests()
        try await replaceAppRequests(with: transform(pending))
    }
}

struct MorningSummaryInput: Sendable {
    let enabled: Bool
    let hour: Int
    let minute: Int
    let day: LocalDay
    let agenda: DayAgenda
    let showsNextTitle: Bool
}
