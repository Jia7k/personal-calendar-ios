import Foundation

/// Demo launches must never replace the user's scheduled system notifications.
@MainActor
final class InMemoryNotificationScheduler: NotificationScheduling {
    private var requests: [LocalNotificationRequest] = []

    func pendingRequests() async -> [LocalNotificationRequest] { requests }

    func replaceAppRequests(with requests: [LocalNotificationRequest]) async throws {
        self.requests = requests
    }

    func mutateAppRequests(
        _ transform: @escaping @MainActor @Sendable ([LocalNotificationRequest]) throws -> [LocalNotificationRequest]
    ) async throws {
        requests = try transform(requests)
    }

    func schedule(_ request: LocalNotificationRequest) async throws {
        requests.removeAll { $0.identifier == request.identifier }
        requests.append(request)
    }
}
