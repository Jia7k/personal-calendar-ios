import UserNotifications

@MainActor
final class SystemNotificationScheduler: NotificationScheduling {
    private let center: UNUserNotificationCenter
    private var mutationTail: Task<Void, Error>?

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
        registerCategories()
    }

    func pendingRequests() async -> [LocalNotificationRequest] {
        if let mutationTail {
            _ = try? await mutationTail.value
        }
        return await mappedPendingRequests()
    }

    func mutateAppRequests(
        _ transform: @escaping @MainActor @Sendable (
            [LocalNotificationRequest]
        ) throws -> [LocalNotificationRequest]
    ) async throws {
        let previous = mutationTail
        let mutation = Task { @MainActor [self] in
            if let previous {
                _ = try? await previous.value
            }
            let pending = await mappedPendingRequests()
            try await replaceImmediately(with: transform(pending))
        }
        mutationTail = mutation
        try await mutation.value
    }

    private func mappedPendingRequests() async -> [LocalNotificationRequest] {
        await center.pendingNotificationRequests().compactMap { request -> LocalNotificationRequest? in
            guard let trigger = request.trigger as? UNCalendarNotificationTrigger,
                  let fireDate = trigger.nextTriggerDate()
            else { return nil }
            return .init(
                identifier: request.identifier,
                title: request.content.title,
                body: request.content.body,
                fireDate: fireDate,
                categoryIdentifier: request.content.categoryIdentifier.isEmpty
                    ? nil
                    : request.content.categoryIdentifier,
                userInfo: request.content.userInfo.reduce(into: [:]) { result, pair in
                    guard let key = pair.key.base as? String,
                          let value = pair.value as? String else { return }
                    result[key] = value
                }
            )
        }
    }

    func replaceAppRequests(with requests: [LocalNotificationRequest]) async throws {
        let previous = mutationTail
        let replacement = Task { @MainActor [self] in
            if let previous {
                _ = try? await previous.value
            }
            try await replaceImmediately(with: requests)
        }
        mutationTail = replacement
        try await replacement.value
    }

    func schedule(_ request: LocalNotificationRequest) async throws {
        let previous = mutationTail
        let addition = Task { @MainActor [self] in
            if let previous {
                _ = try? await previous.value
            }
            try await add(request)
        }
        mutationTail = addition
        try await addition.value
    }

    private func replaceImmediately(with requests: [LocalNotificationRequest]) async throws {
        let ownedIdentifiers = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter(isAppOwned)
        center.removePendingNotificationRequests(withIdentifiers: ownedIdentifiers)

        for request in requests {
            try await add(request)
        }
    }

    private func isAppOwned(_ identifier: String) -> Bool {
        identifier == "morning-summary"
            || identifier.hasPrefix("routine|")
            || identifier.hasPrefix("class|")
            || identifier.hasPrefix("snooze|")
    }

    private func add(_ request: LocalNotificationRequest) async throws {
        let content = UNMutableNotificationContent()
        content.title = request.title
        content.body = request.body
        content.sound = .default
        content.categoryIdentifier = request.categoryIdentifier ?? ""
        content.userInfo = request.userInfo
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: Calendar.current.dateComponents(
                [.calendar, .timeZone, .year, .month, .day, .hour, .minute, .second],
                from: request.fireDate
            ),
            repeats: false
        )
        try await center.add(UNNotificationRequest(
            identifier: request.identifier,
            content: content,
            trigger: trigger
        ))
    }

    private func registerCategories() {
        let complete = UNNotificationAction(
            identifier: NotificationActionIdentifier.routineComplete,
            title: "Complete"
        )
        let snooze = UNNotificationAction(
            identifier: NotificationActionIdentifier.routineSnooze15,
            title: "Snooze 15 min"
        )
        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: NotificationCategoryIdentifier.routineReminder,
                actions: [complete, snooze],
                intentIdentifiers: []
            ),
            UNNotificationCategory(
                identifier: NotificationCategoryIdentifier.morningSummary,
                actions: [],
                intentIdentifiers: []
            ),
            UNNotificationCategory(
                identifier: NotificationCategoryIdentifier.classAlert,
                actions: [],
                intentIdentifiers: []
            )
        ])
    }
}
