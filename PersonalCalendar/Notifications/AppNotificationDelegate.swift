import UIKit
import UserNotifications

@MainActor
final class AppNotificationDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    private weak var routeController: AppRouteController?
    private var actionHandler: AppNotificationActionHandler?

    func configure(
        routeController: AppRouteController,
        actionHandler: AppNotificationActionHandler
    ) {
        self.routeController = routeController
        self.actionHandler = actionHandler
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let actionIdentifier = response.actionIdentifier
        let userInfo = Self.stringPayload(from: response.notification.request.content.userInfo)
        let completion = NotificationResponseCompletion(completionHandler)

        Task { @MainActor [weak self] in
            defer { completion.call() }
            guard let self else { return }

            switch actionIdentifier {
            case UNNotificationDefaultActionIdentifier:
                guard let encodedRoute = userInfo[NotificationPayloadKey.route],
                      let url = URL(string: encodedRoute),
                      let route = try? AppRouteCodec().route(from: url)
                else { return }
                _ = AppNotificationRouteSubmission.submit(route, to: routeController)

            case NotificationActionIdentifier.routineComplete,
                 NotificationActionIdentifier.routineSnooze15:
                await actionHandler?.handle(
                    actionIdentifier: actionIdentifier,
                    userInfo: userInfo
                )

            default:
                return
            }
        }
    }

    private nonisolated static func stringPayload(from userInfo: [AnyHashable: Any]) -> [String: String] {
        userInfo.reduce(into: [:]) { payload, pair in
            guard let key = pair.key.base as? String,
                  let value = pair.value as? String else { return }
            payload[key] = value
        }
    }
}

@MainActor
enum AppNotificationRouteSubmission {
    @discardableResult
    static func submit(_ route: AppRoute, to routeController: AppRouteController?) -> Bool {
        guard let routeController else { return false }
        return routeController.submit(route)
    }
}

private final class NotificationResponseCompletion: @unchecked Sendable {
    private let completionHandler: () -> Void

    init(_ completionHandler: @escaping () -> Void) {
        self.completionHandler = completionHandler
    }

    func call() {
        completionHandler()
    }
}
