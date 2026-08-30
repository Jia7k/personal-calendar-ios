import XCTest
@testable import PersonalCalendar

@MainActor
final class NotificationRenewalSchedulerTests: XCTestCase {
    func testRegisterUsesExactIdentifierOnce() {
        let fixture = makeFixture(outcome: .success)

        fixture.subject.register()
        fixture.subject.register()

        XCTAssertEqual(
            fixture.driver.registeredIdentifiers,
            ["local.personalcalendar.notification-renewal"]
        )
    }

    func testSuccessfulForegroundRefreshReplacesOneRequestTwelveHoursLater() async {
        let fixture = makeFixture(outcome: .success)

        let firstOutcome = await fixture.subject.rescheduleNotifications()
        let secondOutcome = await fixture.subject.rescheduleNotifications()

        XCTAssertEqual(firstOutcome, .success)
        XCTAssertEqual(secondOutcome, .success)
        XCTAssertEqual(fixture.driver.pendingRequests.count, 1)
        XCTAssertEqual(
            fixture.driver.pendingRequests.first,
            .init(
                identifier: "local.personalcalendar.notification-renewal",
                earliestBeginDate: fixture.now.addingTimeInterval(12 * 60 * 60)
            )
        )
    }

    func testFailedForegroundRefreshDoesNotSubmitImmediateRetry() async {
        let fixture = makeFixture(outcome: .failure)

        let outcome = await fixture.subject.rescheduleNotifications()

        XCTAssertEqual(outcome, .failure)
        XCTAssertTrue(fixture.driver.submissions.isEmpty)
    }

    func testBackgroundLaunchSubmitsSuccessorBeforeRenewalAndCompletesSuccess() async {
        let fixture = makeFixture(outcome: .success)
        fixture.subject.register()

        let task = RenewalTaskSpy(events: fixture.events)
        fixture.driver.launch(task)
        await waitUntil { task.completionResults == [true] }

        XCTAssertEqual(
            fixture.events.values,
            ["submit", "renew", "complete:true"]
        )
        XCTAssertEqual(fixture.driver.submissions.count, 1)
        XCTAssertEqual(
            fixture.driver.pendingRequests.first?.earliestBeginDate,
            fixture.now.addingTimeInterval(12 * 60 * 60)
        )
    }

    func testBackgroundFailureCompletesFailedWithoutImmediateRetryLoop() async {
        let fixture = makeFixture(outcome: .failure)
        fixture.subject.register()

        let task = RenewalTaskSpy(events: fixture.events)
        fixture.driver.launch(task)
        await waitUntil { task.completionResults == [false] }

        XCTAssertEqual(fixture.driver.submissions.count, 1)
        XCTAssertEqual(fixture.driver.pendingRequests.count, 1)
        XCTAssertEqual(task.completionResults, [false])
    }

    func testExpirationCancelsRenewalAndCompletesFailedOnce() async {
        var cancellationObserved = false
        let fixture = makeFixture {
            while !Task.isCancelled {
                await Task.yield()
            }
            cancellationObserved = true
            return .failure
        }
        fixture.subject.register()
        let task = RenewalTaskSpy(events: fixture.events)

        fixture.driver.launch(task)
        await waitUntil { fixture.events.values.contains("renew") }
        task.expire()
        await waitUntil { cancellationObserved }
        await Task.yield()

        XCTAssertTrue(cancellationObserved)
        XCTAssertEqual(task.completionResults, [false])
        XCTAssertEqual(fixture.driver.submissions.count, 1)
    }

    private func makeFixture(
        outcome: NotificationRescheduleOutcome
    ) -> RenewalFixture {
        makeFixture { outcome }
    }

    private func makeFixture(
        reschedule: @escaping @MainActor @Sendable () async -> NotificationRescheduleOutcome
    ) -> RenewalFixture {
        let now = Date(timeIntervalSince1970: 1_787_544_000)
        let events = RenewalEventLog()
        let driver = NotificationRenewalDriverSpy(events: events)
        let subject = NotificationRenewalScheduler(
            driver: driver,
            now: { now },
            reschedule: {
                events.values.append("renew")
                return await reschedule()
            }
        )
        return .init(subject: subject, driver: driver, events: events, now: now)
    }

    private func waitUntil(
        _ predicate: @escaping @MainActor () -> Bool
    ) async {
        for _ in 0..<100 where !predicate() {
            await Task.yield()
        }
        XCTAssertTrue(predicate(), "Timed out waiting for asynchronous renewal state")
    }
}

@MainActor
private struct RenewalFixture {
    let subject: NotificationRenewalScheduler
    let driver: NotificationRenewalDriverSpy
    let events: RenewalEventLog
    let now: Date
}

@MainActor
private final class RenewalEventLog {
    var values: [String] = []
}

@MainActor
private final class NotificationRenewalDriverSpy: NotificationRenewalDriving {
    private(set) var registeredIdentifiers: [String] = []
    private(set) var submissions: [NotificationRenewalRequest] = []
    private(set) var pendingRequests: [NotificationRenewalRequest] = []
    private var handler: (@MainActor @Sendable (any NotificationRenewalTask) -> Void)?
    private let events: RenewalEventLog

    init(events: RenewalEventLog) {
        self.events = events
    }

    @discardableResult
    func register(
        identifier: String,
        handler: @escaping @MainActor @Sendable (any NotificationRenewalTask) -> Void
    ) -> Bool {
        registeredIdentifiers.append(identifier)
        self.handler = handler
        return true
    }

    func submitReplacement(_ request: NotificationRenewalRequest) throws {
        events.values.append("submit")
        submissions.append(request)
        pendingRequests.removeAll { $0.identifier == request.identifier }
        pendingRequests.append(request)
    }

    func launch(_ task: any NotificationRenewalTask) {
        guard let handler else {
            XCTFail("Expected scheduler registration before launch")
            return
        }
        handler(task)
    }
}

@MainActor
private final class RenewalTaskSpy: NotificationRenewalTask {
    private(set) var completionResults: [Bool] = []
    private var expirationHandler: (@MainActor @Sendable () -> Void)?
    private let events: RenewalEventLog

    init(events: RenewalEventLog) {
        self.events = events
    }

    func attachExpirationHandler(
        _ handler: @escaping @MainActor @Sendable () -> Void
    ) {
        expirationHandler = handler
    }

    func reportCompletion(success: Bool) {
        events.values.append("complete:\(success)")
        completionResults.append(success)
    }

    func expire() {
        guard let expirationHandler else {
            XCTFail("Expected an expiration handler")
            return
        }
        expirationHandler()
    }
}
