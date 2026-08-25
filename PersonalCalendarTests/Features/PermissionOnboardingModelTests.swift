import XCTest
@testable import PersonalCalendar

@MainActor
final class PermissionOnboardingModelTests: XCTestCase {
    func testBenefitDescriptionForEveryPage() async {
        let cases: [(page: PermissionOnboardingModel.Page, expected: String)] = [
            (.calendar, "Show your schedule and events in one place."),
            (.reminders, "Show and manage your tasks alongside your schedule."),
            (.notifications, "Deliver local reminders and summaries.")
        ]

        for testCase in cases {
            let subject = await makeSubject(page: testCase.page, access: .notDetermined)

            XCTAssertEqual(subject.benefitDescription, testCase.expected)
        }
    }

    func testStatusDescriptionForEveryPageAndAccessState() async {
        let cases: [(page: PermissionOnboardingModel.Page, access: AccessState, expected: String)] = [
            (.calendar, .notDetermined, "Calendar access has not been requested."),
            (.calendar, .granted, "Calendar access is allowed."),
            (.calendar, .denied, "Calendar access is denied. You can change it later in Settings."),
            (.calendar, .restricted, "Calendar access is restricted by device or account controls."),
            (.reminders, .notDetermined, "Reminders access has not been requested."),
            (.reminders, .granted, "Reminders access is allowed."),
            (.reminders, .denied, "Reminders access is denied. You can change it later in Settings."),
            (.reminders, .restricted, "Reminders access is restricted by device or account controls."),
            (.notifications, .notDetermined, "Notifications access has not been requested."),
            (.notifications, .granted, "Notifications access is allowed."),
            (.notifications, .denied, "Notifications access is denied. You can change it later in Settings."),
            (.notifications, .restricted, "Notifications access is restricted by device or account controls.")
        ]

        for testCase in cases {
            let subject = await makeSubject(page: testCase.page, access: testCase.access)

            XCTAssertEqual(subject.statusDescription, testCase.expected)
        }
    }

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

    func testLaterRefreshGatesActionsUntilTerminalSnapshotPublishes() async {
        let calendar = FakeCalendarService(access: .notDetermined)
        let reminders = FakeRemindersService(access: .notDetermined)
        let notifications = FakeNotificationAuthorizer(access: .notDetermined)
        let permissions = PermissionCoordinator(calendar: calendar, reminders: reminders, notifications: notifications)
        let subject = PermissionOnboardingModel(permissions: permissions, onFinish: {})
        await subject.start()

        calendar.accessState = .denied
        reminders.accessState = .restricted
        notifications.setAccessState(.denied)
        notifications.suspendNextRead = true
        let refresh = Task { await permissions.refresh() }
        for _ in 0..<10 where !notifications.isReadSuspended {
            await Task.yield()
        }

        XCTAssertTrue(permissions.isRefreshing)
        XCTAssertTrue(notifications.isReadSuspended)
        XCTAssertFalse(subject.actionsEnabled)
        subject.notNow()
        await subject.primaryAction()
        XCTAssertEqual(subject.title, "Calendar")
        XCTAssertEqual(calendar.requestCount, 0)
        XCTAssertEqual(reminders.requestCount, 0)
        XCTAssertEqual(notifications.requestCount, 0)

        notifications.resumeRead()
        await refresh.value

        XCTAssertTrue(subject.actionsEnabled)
        XCTAssertEqual(subject.primaryTitle, "Continue")
        XCTAssertFalse(subject.showsNotNow)
        await subject.primaryAction()
        XCTAssertEqual(subject.title, "Reminders")
        XCTAssertEqual(calendar.requestCount, 0)
        XCTAssertEqual(reminders.requestCount, 0)
        XCTAssertEqual(notifications.requestCount, 0)

        await waitUntilActionsEnable(subject)
        XCTAssertEqual(subject.primaryTitle, "Continue")
        XCTAssertFalse(subject.showsNotNow)
        await subject.primaryAction()
        XCTAssertEqual(subject.title, "Notifications")
        XCTAssertEqual(calendar.requestCount, 0)
        XCTAssertEqual(reminders.requestCount, 0)
        XCTAssertEqual(notifications.requestCount, 0)
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

    func testTerminalStatesTraverseEveryPageWithoutRequestsAndFinishExactlyOnce() async {
        for state in [AccessState.granted, .denied, .restricted] {
            let calendar = FakeCalendarService(access: state)
            let reminders = FakeRemindersService(access: state)
            let notifications = FakeNotificationAuthorizer(access: state)
            let permissions = PermissionCoordinator(calendar: calendar, reminders: reminders, notifications: notifications)
            var completionCount = 0
            let subject = PermissionOnboardingModel(permissions: permissions) { completionCount += 1 }
            await subject.start()

            XCTAssertEqual(subject.title, "Calendar")
            XCTAssertEqual(subject.primaryTitle, "Continue")
            XCTAssertFalse(subject.showsNotNow)
            assertNoPermissionRequests(calendar: calendar, reminders: reminders, notifications: notifications)
            await subject.primaryAction()
            await waitUntilActionsEnable(subject)

            XCTAssertEqual(subject.title, "Reminders")
            XCTAssertEqual(subject.primaryTitle, "Continue")
            XCTAssertFalse(subject.showsNotNow)
            assertNoPermissionRequests(calendar: calendar, reminders: reminders, notifications: notifications)
            await subject.primaryAction()
            await waitUntilActionsEnable(subject)

            XCTAssertEqual(subject.title, "Notifications")
            XCTAssertEqual(subject.primaryTitle, "Continue")
            XCTAssertFalse(subject.showsNotNow)
            assertNoPermissionRequests(calendar: calendar, reminders: reminders, notifications: notifications)
            await subject.primaryAction()

            XCTAssertTrue(subject.isFinished)
            XCTAssertEqual(completionCount, 1)
            assertNoPermissionRequests(calendar: calendar, reminders: reminders, notifications: notifications)
            await subject.primaryAction()
            subject.notNow()
            XCTAssertEqual(completionCount, 1)
            assertNoPermissionRequests(calendar: calendar, reminders: reminders, notifications: notifications)
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

    private func makeSubject(
        access: AccessState = .notDetermined,
        onFinish: @escaping () -> Void = {}
    ) -> PermissionOnboardingModel {
        let permissions = PermissionCoordinator(
            calendar: FakeCalendarService(access: access),
            reminders: FakeRemindersService(access: access),
            notifications: FakeNotificationAuthorizer(access: access)
        )
        return PermissionOnboardingModel(permissions: permissions, onFinish: onFinish)
    }

    private func makeSubject(
        page: PermissionOnboardingModel.Page,
        access: AccessState
    ) async -> PermissionOnboardingModel {
        let subject = makeSubject(access: access)
        await subject.start()
        while subject.page != page {
            if subject.showsNotNow {
                subject.notNow()
            } else {
                await subject.primaryAction()
            }
            await waitUntilActionsEnable(subject)
        }
        return subject
    }

    private func waitUntilActionsEnable(_ subject: PermissionOnboardingModel) async {
        for _ in 0..<100 where !subject.actionsEnabled {
            await Task.yield()
        }
        XCTAssertTrue(subject.actionsEnabled)
    }

    private func assertNoPermissionRequests(
        calendar: FakeCalendarService,
        reminders: FakeRemindersService,
        notifications: FakeNotificationAuthorizer,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(calendar.requestCount, 0, file: file, line: line)
        XCTAssertEqual(reminders.requestCount, 0, file: file, line: line)
        XCTAssertEqual(notifications.requestCount, 0, file: file, line: line)
    }
}
