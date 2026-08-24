import UserNotifications

@MainActor
final class SystemNotificationAuthorizer: NotificationAuthorizing {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    var accessState: AccessState {
        get async {
            let status = await center.notificationSettings().authorizationStatus
            switch status {
            case .authorized, .provisional, .ephemeral:
                return .granted
            case .notDetermined:
                return .notDetermined
            case .denied:
                return .denied
            @unknown default:
                return .restricted
            }
        }
    }

    func requestAccess() async -> AccessState {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound]) ? .granted : .denied
        } catch {
            return .denied
        }
    }
}
