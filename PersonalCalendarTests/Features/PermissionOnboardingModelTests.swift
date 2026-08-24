import XCTest
@testable import PersonalCalendar

@MainActor
final class PermissionOnboardingModelTests: XCTestCase {
    func testPagesAreInAuthoritativeOrder() async {
        let subject = makeSubject()
        await subject.start()
        XCTAssertEqual(subject.title, "Calendar")
        subject.notNow()
        await waitUntilActionsEnable(subject)
        XCTAssertEqual(subject.title, "Reminders")
        subject.notNow()
        await waitUntilActionsEnable(subject)
        XCTAssertEqual(subject.title, "Notifications")
    }

    func testRefreshGatesAllActionsUntilItFinishes() async {
        let calendar = FakeCalendarService(access: .notDetermined)
        let reminders = FakeRemindersService(access: .notDetermined)
        let notifications = FakeNotificationAuthorizer(access: .notDetermined, suspendRead: true)
        let permissions = PermissionCoordinator(calendar: calendar, reminders: reminders, notifications: notifications)
        let subject = PermissionOnboardingModel(permissions: permissions, onFinish: {})

        let refresh = Task { await subject.start() }
        await Task.yield()
        XCTAssertFalse(subject.actionsEnabled)
        subject.notNow()
        await subject.primaryAction()
        XCTAssertEqual(subject.title, "Calendar")
        XCTAssertEqual(calendar.requestCount, 0)
        notifications.resumeRead()
        await refresh.value
        XCTAssertTrue(subject.actionsEnabled)
    }

    func testAllowStaysOnCurrentPageWhileMatchingRequestIsSuspended() async {
        let calendar = FakeCalendarService(access: .notDetermined, requestedAccess: .granted)
        calendar.suspendNextRequest = true
        let reminders = FakeRemindersService(access: .notDetermined)
        let notifications = FakeNotificationAuthorizer(access: .notDetermined)
        let permissions = PermissionCoordinator(calendar: calendar, reminders: reminders, notifications: notifications)
        let subject = PermissionOnboardingModel(permissions: permissions, onFinish: {})
        await subject.start()

        let request = Task { await subject.primaryAction() }
        await Task.yield()
        XCTAssertTrue(calendar.isRequestSuspended)
        XCTAssertEqual(subject.title, "Calendar")
        XCTAssertTrue(subject.isAdvancing)
        XCTAssertEqual(calendar.requestCount, 1)
        calendar.resumeSuspendedRequest()
        await request.value
        XCTAssertEqual(subject.title, "Reminders")
    }

    func testDoublePrimaryOnlyRequestsOnceAndAdvancesOnce() async {
        let calendar = FakeCalendarService(access: .notDetermined, requestedAccess: .granted)
        calendar.suspendNextRequest = true
        let reminders = FakeRemindersService(access: .notDetermined)
        let notifications = FakeNotificationAuthorizer(access: .notDetermined)
        let permissions = PermissionCoordinator(calendar: calendar, reminders: reminders, notifications: notifications)
        let subject = PermissionOnboardingModel(permissions: permissions, onFinish: {})
        await subject.start()

        let first = Task { await subject.primaryAction() }
        await Task.yield()
        let second = Task { await subject.primaryAction() }
        await Task.yield()
        XCTAssertEqual(calendar.requestCount, 1)
        calendar.resumeSuspendedRequest()
        _ = await (first.value, second.value)
        XCTAssertEqual(subject.title, "Reminders")
    }

    func testTerminalStatesContinueWithoutRequestingAnySource() async {
        for state in [AccessState.granted, .denied, .restricted] {
            let calendar = FakeCalendarService(access: state)
            let reminders = FakeRemindersService(access: state)
            let notifications = FakeNotificationAuthorizer(access: state)
            let permissions = PermissionCoordinator(calendar: calendar, reminders: reminders, notifications: notifications)
            let subject = PermissionOnboardingModel(permissions: permissions, onFinish: {})
            await subject.start()

            XCTAssertEqual(subject.primaryTitle, "Continue")
            await subject.primaryAction()
            await subject.primaryAction()
            await subject.primaryAction()
            XCTAssertEqual(calendar.requestCount, 0)
            XCTAssertEqual(reminders.requestCount, 0)
            XCTAssertEqual(notifications.requestCount, 0)
        }
    }

    func testDoubleNotNowAdvancesOnlyOnce() async {
        let subject = makeSubject()
        await subject.start()
        subject.notNow()
        subject.notNow()
        XCTAssertEqual(subject.title, "Reminders")
    }

    func testAllowRequestsOnlyTheCurrentPageSourceInOrder() async {
        let calendar = FakeCalendarService(access: .notDetermined, requestedAccess: .granted)
        let reminders = FakeRemindersService(access: .notDetermined, requestedAccess: .granted)
        let notifications = FakeNotificationAuthorizer(access: .notDetermined, requestedAccess: .granted)
        let permissions = PermissionCoordinator(calendar: calendar, reminders: reminders, notifications: notifications)
        let subject = PermissionOnboardingModel(permissions: permissions, onFinish: {})
        await subject.start()

        await subject.primaryAction()
        XCTAssertEqual(calendar.requestCount, 1)
        XCTAssertEqual(reminders.requestCount, 0)
        XCTAssertEqual(notifications.requestCount, 0)
        await waitUntilActionsEnable(subject)
        await subject.primaryAction()
        XCTAssertEqual(calendar.requestCount, 1)
        XCTAssertEqual(reminders.requestCount, 1)
        XCTAssertEqual(notifications.requestCount, 0)
        await waitUntilActionsEnable(subject)
        await subject.primaryAction()
        XCTAssertEqual(calendar.requestCount, 1)
        XCTAssertEqual(reminders.requestCount, 1)
        XCTAssertEqual(notifications.requestCount, 1)
    }

    func testNotNowNeverRequestsAnySource() async {
        let calendar = FakeCalendarService(access: .notDetermined)
        let reminders = FakeRemindersService(access: .notDetermined)
        let notifications = FakeNotificationAuthorizer(access: .notDetermined)
        let permissions = PermissionCoordinator(calendar: calendar, reminders: reminders, notifications: notifications)
        let subject = PermissionOnboardingModel(permissions: permissions, onFinish: {})
        await subject.start()

        subject.notNow()
        await waitUntilActionsEnable(subject)
        subject.notNow()
        await waitUntilActionsEnable(subject)
        subject.notNow()
        XCTAssertEqual(calendar.requestCount, 0)
        XCTAssertEqual(reminders.requestCount, 0)
        XCTAssertEqual(notifications.requestCount, 0)
    }

    func testFinishingIsExactlyOnceAndIdempotent() async {
        var completionCount = 0
        let subject = makeSubject { completionCount += 1 }
        await subject.start()
        subject.notNow()
        await waitUntilActionsEnable(subject)
        subject.notNow()
        await waitUntilActionsEnable(subject)
        subject.notNow()
        subject.notNow()
        XCTAssertTrue(subject.isFinished)
        XCTAssertEqual(completionCount, 1)
    }

    private func makeSubject(onFinish: @escaping () -> Void = {}) -> PermissionOnboardingModel {
        let permissions = PermissionCoordinator(
            calendar: FakeCalendarService(access: .notDetermined),
            reminders: FakeRemindersService(access: .notDetermined),
            notifications: FakeNotificationAuthorizer(access: .notDetermined)
        )
        return PermissionOnboardingModel(permissions: permissions, onFinish: onFinish)
    }

    private func waitUntilActionsEnable(_ subject: PermissionOnboardingModel) async {
        for _ in 0..<10 where !subject.actionsEnabled {
            await Task.yield()
        }
        XCTAssertTrue(subject.actionsEnabled)
    }
}
