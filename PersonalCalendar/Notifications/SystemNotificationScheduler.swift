import UserNotifications

@MainActor
final class SystemNotificationScheduler: NotificationScheduling {
    private let center: UNUserNotificationCenter
    private var replacementTail: Task<Void, Error>?

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func pendingRequests() async -> [LocalNotificationRequest] {
        await center.pendingNotificationRequests().compactMap { request in
            guard let trigger = request.trigger as? UNCalendarNotificationTrigger,
                  let fireDate = trigger.nextTriggerDate()
            else { return nil }
            return .init(
                identifier: request.identifier,
                title: request.content.title,
                body: request.content.body,
                fireDate: fireDate
            )
        }
    }

    func replaceAppRequests(with requests: [LocalNotificationRequest]) async throws {
        let previous = replacementTail
        let replacement = Task { @MainActor [self] in
            if let previous {
                _ = try? await previous.value
            }
            try await replaceImmediately(with: requests)
        }
        replacementTail = replacement
        try await replacement.value
    }

    private func replaceImmediately(with requests: [LocalNotificationRequest]) async throws {
        let ownedIdentifiers = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter(isAppOwned)
        center.removePendingNotificationRequests(withIdentifiers: ownedIdentifiers)

        for request in requests {
            let content = UNMutableNotificationContent()
            content.title = request.title
            content.body = request.body
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: Calendar.current.dateComponents([.calendar, .timeZone, .year, .month, .day, .hour, .minute, .second], from: request.fireDate),
                repeats: false
            )
            try await center.add(UNNotificationRequest(identifier: request.identifier, content: content, trigger: trigger))
        }
    }

    private func isAppOwned(_ identifier: String) -> Bool {
        identifier == "morning-summary" || identifier.hasPrefix("routine|")
    }
}
