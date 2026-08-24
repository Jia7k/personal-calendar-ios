import Foundation
import Observation

@MainActor
protocol NotificationAuthorizing: AnyObject {
    var accessState: AccessState { get async }

    func requestAccess() async -> AccessState
}

@MainActor
@Observable
final class PermissionCoordinator: PermissionRefreshing {
    private struct RefreshSnapshot {
        let calendar: AccessState
        let reminders: AccessState
        let notifications: AccessState
        let calendarGeneration: Int
        let remindersGeneration: Int
        let notificationsGeneration: Int
    }

    private(set) var calendarAccess: AccessState
    private(set) var remindersAccess: AccessState
    private(set) var notificationAccess: AccessState
    private(set) var isRefreshing = true
    private(set) var pendingSources: Set<String> = []
    private var sourceGenerations: [String: Int] = [:]
    private var requestedRefreshGeneration = 0
    private var completedRefreshGeneration = 0
    private var isRefreshSequenceRunning = false
    private var refreshWaiters: [CheckedContinuation<Void, Never>] = []

    func isPending(_ source: String) -> Bool { pendingSources.contains(source) }

    private let calendar: any CalendarServicing
    private let reminders: any RemindersServicing
    private let notifications: any NotificationAuthorizing

    init(
        calendar: any CalendarServicing,
        reminders: any RemindersServicing,
        notifications: any NotificationAuthorizing
    ) {
        self.calendar = calendar
        self.reminders = reminders
        self.notifications = notifications
        calendarAccess = calendar.accessState
        remindersAccess = reminders.accessState
        notificationAccess = .notDetermined
    }

    func refresh() async {
        requestedRefreshGeneration &+= 1
        while completedRefreshGeneration != requestedRefreshGeneration {
            if isRefreshSequenceRunning {
                await withCheckedContinuation { refreshWaiters.append($0) }
            } else {
                await runRefreshSequence()
            }
        }
    }

    private func runRefreshSequence() async {
        isRefreshSequenceRunning = true
        isRefreshing = true
        while completedRefreshGeneration != requestedRefreshGeneration {
            let generation = requestedRefreshGeneration
            let snapshot = await readRefreshSnapshot()
            if generation == requestedRefreshGeneration {
                publish(snapshot)
            }
            completedRefreshGeneration = generation
        }
        isRefreshSequenceRunning = false
        isRefreshing = false
        let waiters = refreshWaiters
        refreshWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    private func readRefreshSnapshot() async -> RefreshSnapshot {
        let calendarGeneration = sourceGenerations["calendar", default: 0]
        let remindersGeneration = sourceGenerations["reminders", default: 0]
        let notificationsGeneration = sourceGenerations["notifications", default: 0]
        let calendarState = calendar.accessState
        let reminderState = reminders.accessState
        let notificationState = await notifications.accessState

        return RefreshSnapshot(
            calendar: calendarState,
            reminders: reminderState,
            notifications: notificationState,
            calendarGeneration: calendarGeneration,
            remindersGeneration: remindersGeneration,
            notificationsGeneration: notificationsGeneration
        )
    }

    private func publish(_ snapshot: RefreshSnapshot) {
        if sourceCanAcceptRefresh("calendar", generation: snapshot.calendarGeneration) {
            calendarAccess = snapshot.calendar
        }
        if sourceCanAcceptRefresh("reminders", generation: snapshot.remindersGeneration) {
            remindersAccess = snapshot.reminders
        }
        if sourceCanAcceptRefresh("notifications", generation: snapshot.notificationsGeneration) {
            notificationAccess = snapshot.notifications
        }
    }

    func requestCalendar() async {
        guard calendarAccess == .notDetermined, !pendingSources.contains("calendar") else { return }
        let generation = nextGeneration(for: "calendar")
        pendingSources.insert("calendar"); defer { pendingSources.remove("calendar") }
        let state = await calendar.requestFullAccess()
        guard sourceGenerations["calendar"] == generation else { return }
        calendarAccess = state
        _ = nextGeneration(for: "calendar")
    }

    func requestReminders() async {
        guard remindersAccess == .notDetermined, !pendingSources.contains("reminders") else { return }
        let generation = nextGeneration(for: "reminders")
        pendingSources.insert("reminders"); defer { pendingSources.remove("reminders") }
        let state = await reminders.requestFullAccess()
        guard sourceGenerations["reminders"] == generation else { return }
        remindersAccess = state
        _ = nextGeneration(for: "reminders")
    }

    func requestNotifications() async {
        guard notificationAccess == .notDetermined, !pendingSources.contains("notifications") else { return }
        let generation = nextGeneration(for: "notifications")
        pendingSources.insert("notifications"); defer { pendingSources.remove("notifications") }
        let state = await notifications.requestAccess()
        guard sourceGenerations["notifications"] == generation else { return }
        notificationAccess = state
        _ = nextGeneration(for: "notifications")
    }

    private func sourceCanAcceptRefresh(_ source: String, generation: Int) -> Bool {
        sourceGenerations[source, default: 0] == generation && !pendingSources.contains(source)
    }

    private func nextGeneration(for source: String) -> Int {
        let next = sourceGenerations[source, default: 0] + 1
        sourceGenerations[source] = next
        return next
    }
}
