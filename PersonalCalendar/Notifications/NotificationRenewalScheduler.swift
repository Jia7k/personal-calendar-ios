import BackgroundTasks
import Foundation

struct NotificationRenewalRequest: Equatable, Sendable {
    let identifier: String
    let earliestBeginDate: Date
}

@MainActor
protocol NotificationRenewalTask: AnyObject {
    func attachExpirationHandler(
        _ handler: @escaping @MainActor @Sendable () -> Void
    )
    func reportCompletion(success: Bool)
}

@MainActor
protocol NotificationRenewalDriving: AnyObject {
    @discardableResult
    func register(
        identifier: String,
        handler: @escaping @MainActor @Sendable (any NotificationRenewalTask) -> Void
    ) -> Bool
    func submitReplacement(_ request: NotificationRenewalRequest) throws
}

@MainActor
final class NotificationRenewalScheduler {
    static let taskIdentifier = "local.personalcalendar.notification-renewal"
    static let defaultRenewalDelay: TimeInterval = 12 * 60 * 60

    private let driver: any NotificationRenewalDriving
    private let renewalDelay: TimeInterval
    private let now: @MainActor @Sendable () -> Date
    private let reschedule:
        @MainActor @Sendable () async -> NotificationRescheduleOutcome
    private var isRegistered = false

    init(
        driver: any NotificationRenewalDriving,
        renewalDelay: TimeInterval = NotificationRenewalScheduler.defaultRenewalDelay,
        now: @escaping @MainActor @Sendable () -> Date = Date.init,
        reschedule: @escaping @MainActor @Sendable () async -> NotificationRescheduleOutcome
    ) {
        self.driver = driver
        self.renewalDelay = renewalDelay
        self.now = now
        self.reschedule = reschedule
    }

    func register() {
        guard !isRegistered else { return }
        isRegistered = driver.register(
            identifier: Self.taskIdentifier,
            handler: { [weak self] task in
                self?.handle(task)
            }
        )
    }

    func rescheduleNotifications() async -> NotificationRescheduleOutcome {
        let outcome = await reschedule()
        if outcome == .success {
            try? submitSuccessor()
        }
        return outcome
    }

    private func handle(_ task: any NotificationRenewalTask) {
        let successorWasSubmitted: Bool
        do {
            try submitSuccessor()
            successorWasSubmitted = true
        } catch {
            successorWasSubmitted = false
        }

        let execution = NotificationRenewalExecution(
            task: task,
            successorWasSubmitted: successorWasSubmitted,
            reschedule: reschedule
        )
        task.attachExpirationHandler { [weak execution] in
            execution?.expire()
        }
        execution.start()
    }

    private func submitSuccessor() throws {
        try driver.submitReplacement(.init(
            identifier: Self.taskIdentifier,
            earliestBeginDate: now().addingTimeInterval(renewalDelay)
        ))
    }
}

@MainActor
private final class NotificationRenewalExecution {
    private let task: any NotificationRenewalTask
    private let successorWasSubmitted: Bool
    private let reschedule:
        @MainActor @Sendable () async -> NotificationRescheduleOutcome
    private var work: Task<Void, Never>?
    private var didReportCompletion = false

    init(
        task: any NotificationRenewalTask,
        successorWasSubmitted: Bool,
        reschedule: @escaping @MainActor @Sendable () async -> NotificationRescheduleOutcome
    ) {
        self.task = task
        self.successorWasSubmitted = successorWasSubmitted
        self.reschedule = reschedule
    }

    func start() {
        guard work == nil else { return }
        work = Task { @MainActor [self] in
            let outcome = await reschedule()
            guard !Task.isCancelled else {
                work = nil
                return
            }
            reportCompletion(
                success: successorWasSubmitted && outcome == .success
            )
            work = nil
        }
    }

    func expire() {
        work?.cancel()
        reportCompletion(success: false)
    }

    private func reportCompletion(success: Bool) {
        guard !didReportCompletion else { return }
        didReportCompletion = true
        task.reportCompletion(success: success)
    }
}

@MainActor
final class SystemNotificationRenewalDriver: NotificationRenewalDriving {
    private let scheduler: BGTaskScheduler

    init(scheduler: BGTaskScheduler = .shared) {
        self.scheduler = scheduler
    }

    @discardableResult
    func register(
        identifier: String,
        handler: @escaping @MainActor @Sendable (any NotificationRenewalTask) -> Void
    ) -> Bool {
        scheduler.register(forTaskWithIdentifier: identifier, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in
                handler(SystemNotificationRenewalTask(task: refreshTask))
            }
        }
    }

    func submitReplacement(_ request: NotificationRenewalRequest) throws {
        scheduler.cancel(taskRequestWithIdentifier: request.identifier)
        let taskRequest = BGAppRefreshTaskRequest(
            identifier: request.identifier
        )
        taskRequest.earliestBeginDate = request.earliestBeginDate
        try scheduler.submit(taskRequest)
    }
}

@MainActor
private final class SystemNotificationRenewalTask: NotificationRenewalTask {
    private let task: BGAppRefreshTask

    init(task: BGAppRefreshTask) {
        self.task = task
    }

    func attachExpirationHandler(
        _ handler: @escaping @MainActor @Sendable () -> Void
    ) {
        task.expirationHandler = {
            Task { @MainActor in
                handler()
            }
        }
    }

    func reportCompletion(success: Bool) {
        task.setTaskCompleted(success: success)
    }
}

@MainActor
final class NoopNotificationRenewalDriver: NotificationRenewalDriving {
    @discardableResult
    func register(
        identifier: String,
        handler: @escaping @MainActor @Sendable (any NotificationRenewalTask) -> Void
    ) -> Bool {
        true
    }

    func submitReplacement(_ request: NotificationRenewalRequest) throws {}
}
