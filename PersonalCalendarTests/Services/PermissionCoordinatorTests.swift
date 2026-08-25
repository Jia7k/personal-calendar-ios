import XCTest
@testable import PersonalCalendar

@MainActor
final class PermissionCoordinatorTests: XCTestCase {
    func testDuplicateRequestOnlyCallsMatchingSourceOnce() async {
        let calendar = FakeCalendarService(access: .notDetermined, requestedAccess: .granted)
        calendar.suspendNextRequest = true
        let reminders = FakeRemindersService(access: .notDetermined, requestedAccess: .granted)
        let notifications = FakeNotificationAuthorizer(access: .granted)
        let subject = PermissionCoordinator(calendar: calendar, reminders: reminders, notifications: notifications)
        async let first: Void = subject.requestCalendar()
        await Task.yield()
        XCTAssertTrue(calendar.isRequestSuspended)
        XCTAssertTrue(subject.isPending("calendar"))
        async let second: Void = subject.requestCalendar()
        await Task.yield()
        XCTAssertEqual(calendar.requestCount, 1)
        calendar.resumeSuspendedRequest()
        _ = await (first, second)
        XCTAssertEqual(calendar.requestCount, 1)
        XCTAssertFalse(subject.isPending("calendar"))
        XCTAssertEqual(reminders.requestCount, 0)
    }

    func testRefreshDoesNotPublishPartialStateWhileNotificationIsSuspended() async {
        let calendar = FakeCalendarService(access: .notDetermined)
        let reminders = FakeRemindersService(access: .notDetermined)
        let notifications = FakeNotificationAuthorizer(access: .granted, suspendRead: true)
        let subject = PermissionCoordinator(calendar: calendar, reminders: reminders, notifications: notifications)
        calendar.accessState = .denied
        reminders.accessState = .restricted
        let task = Task { await subject.refresh() }
        await Task.yield()
        XCTAssertTrue(subject.isRefreshing)
        XCTAssertEqual(subject.calendarAccess, .notDetermined)
        XCTAssertEqual(subject.remindersAccess, .notDetermined)
        XCTAssertEqual(subject.notificationAccess, .notDetermined)
        notifications.resumeRead()
        await task.value
        XCTAssertFalse(subject.isRefreshing)
        XCTAssertEqual(subject.calendarAccess, .denied)
        XCTAssertEqual(subject.remindersAccess, .restricted)
        XCTAssertEqual(subject.notificationAccess, .granted)
    }

    func testSuspendedCalendarRequestDoesNotBlockRemindersRequest() async {
        let calendar = FakeCalendarService(access: .notDetermined, requestedAccess: .granted)
        calendar.suspendNextRequest = true
        let reminders = FakeRemindersService(access: .notDetermined, requestedAccess: .denied)
        let notifications = FakeNotificationAuthorizer(access: .granted)
        let subject = PermissionCoordinator(calendar: calendar, reminders: reminders, notifications: notifications)

        let calendarRequest = Task { await subject.requestCalendar() }
        await waitUntil { calendar.isRequestSuspended }
        guard calendar.isRequestSuspended else {
            calendar.suspendNextRequest = false
            await calendarRequest.value
            XCTFail("Calendar request did not reach its suspension point")
            return
        }
        XCTAssertTrue(subject.isPending("calendar"))
        XCTAssertFalse(subject.isPending("reminders"))
        await subject.requestReminders()

        XCTAssertEqual(calendar.requestCount, 1)
        XCTAssertEqual(reminders.requestCount, 1)
        XCTAssertTrue(subject.isPending("calendar"))
        XCTAssertFalse(subject.isPending("reminders"))
        XCTAssertEqual(subject.remindersAccess, .denied)
        calendar.resumeSuspendedRequest()
        await calendarRequest.value
        XCTAssertEqual(subject.calendarAccess, .granted)
        XCTAssertFalse(subject.isPending("calendar"))
    }

    func testTerminalStatesNeverRequestAnySource() async {
        for state in [AccessState.granted, .denied, .restricted] {
            let calendar = FakeCalendarService(access: state)
            let reminders = FakeRemindersService(access: state)
            let notifications = FakeNotificationAuthorizer(access: state)
            let subject = PermissionCoordinator(calendar: calendar, reminders: reminders, notifications: notifications)

            await subject.refresh()
            await subject.requestCalendar()
            await subject.requestReminders()
            await subject.requestNotifications()

            XCTAssertEqual(calendar.requestCount, 0, "Calendar \(state) requested")
            XCTAssertEqual(reminders.requestCount, 0, "Reminders \(state) requested")
            XCTAssertEqual(notifications.requestCount, 0, "Notifications \(state) requested")
            XCTAssertFalse(subject.isPending("calendar"))
            XCTAssertFalse(subject.isPending("reminders"))
            XCTAssertFalse(subject.isPending("notifications"))
        }
    }

    func testSuspendedNotificationRequestIsOneShotAndClearsPending() async {
        let calendar = FakeCalendarService(access: .granted)
        let reminders = FakeRemindersService(access: .granted)
        let notifications = FakeNotificationAuthorizer(access: .notDetermined, requestedAccess: .granted)
        notifications.suspendNextRequest = true
        let subject = PermissionCoordinator(calendar: calendar, reminders: reminders, notifications: notifications)

        async let first: Void = subject.requestNotifications()
        await Task.yield()
        async let second: Void = subject.requestNotifications()
        await Task.yield()
        XCTAssertTrue(subject.isPending("notifications"))
        XCTAssertTrue(notifications.isRequestSuspended)
        XCTAssertEqual(notifications.requestCount, 1)
        notifications.resumeSuspendedRequest()
        _ = await (first, second)

        XCTAssertEqual(subject.notificationAccess, .granted)
        XCTAssertFalse(subject.isPending("notifications"))
    }

    func testRequestStartedDuringRefreshPreservesCalendarAndPublishesOtherSources() async {
        let calendar = FakeCalendarService(access: .notDetermined, requestedAccess: .granted)
        calendar.suspendNextRequest = true
        let reminders = FakeRemindersService(access: .restricted)
        let notifications = FakeNotificationAuthorizer(access: .denied, suspendRead: true)
        let subject = PermissionCoordinator(calendar: calendar, reminders: reminders, notifications: notifications)

        let refresh = Task { await subject.refresh() }
        await Task.yield()
        XCTAssertTrue(notifications.isReadSuspended)
        let request = Task { await subject.requestCalendar() }
        await Task.yield()
        XCTAssertTrue(calendar.isRequestSuspended)
        XCTAssertTrue(subject.isPending("calendar"))
        notifications.resumeRead()
        await refresh.value

        XCTAssertEqual(subject.calendarAccess, .notDetermined)
        XCTAssertEqual(subject.remindersAccess, .restricted)
        XCTAssertEqual(subject.notificationAccess, .denied)
        XCTAssertFalse(subject.isRefreshing)
        XCTAssertTrue(subject.isPending("calendar"))
        calendar.resumeSuspendedRequest()
        await request.value
        XCTAssertEqual(subject.calendarAccess, .granted)
        XCTAssertFalse(subject.isPending("calendar"))
    }

    func testRefreshDuringSuspendedRequestKeepsPromptAuthoritativeAndPublishesOtherSources() async {
        let calendar = FakeCalendarService(access: .notDetermined, requestedAccess: .granted)
        calendar.suspendNextRequest = true
        let reminders = FakeRemindersService(access: .restricted)
        let notifications = FakeNotificationAuthorizer(access: .denied, suspendRead: true)
        let subject = PermissionCoordinator(calendar: calendar, reminders: reminders, notifications: notifications)

        let request = Task { await subject.requestCalendar() }
        await Task.yield()
        XCTAssertTrue(calendar.isRequestSuspended)
        let refresh = Task { await subject.refresh() }
        await Task.yield()
        XCTAssertTrue(notifications.isReadSuspended)
        calendar.resumeSuspendedRequest()
        await request.value

        XCTAssertEqual(subject.calendarAccess, .granted)
        XCTAssertFalse(subject.isPending("calendar"))
        XCTAssertTrue(subject.isRefreshing)
        notifications.resumeRead()
        await refresh.value

        XCTAssertEqual(subject.calendarAccess, .granted)
        XCTAssertEqual(subject.remindersAccess, .restricted)
        XCTAssertEqual(subject.notificationAccess, .denied)
        XCTAssertFalse(subject.isRefreshing)
        XCTAssertFalse(subject.isPending("calendar"))
    }
    func testDeniedCalendarDoesNotBlockGrantedReminders() async {
        let calendar = FakeCalendarService(access: .denied)
        let reminders = FakeRemindersService(access: .notDetermined, requestedAccess: .granted)
        let notifications = FakeNotificationAuthorizer(access: .denied)
        let subject = PermissionCoordinator(
            calendar: calendar,
            reminders: reminders,
            notifications: notifications
        )

        await subject.refresh()
        await subject.requestReminders()

        XCTAssertEqual(subject.calendarAccess, .denied)
        XCTAssertEqual(subject.remindersAccess, .granted)
        XCTAssertEqual(subject.notificationAccess, .denied)
    }

    func testRequestCalendarDoesNotChangeOtherPermissionStates() async {
        let calendar = FakeCalendarService(access: .notDetermined, requestedAccess: .granted)
        let reminders = FakeRemindersService(access: .denied)
        let notifications = FakeNotificationAuthorizer(access: .restricted)
        let subject = PermissionCoordinator(
            calendar: calendar,
            reminders: reminders,
            notifications: notifications
        )

        await subject.refresh()
        await subject.requestCalendar()

        XCTAssertEqual(subject.calendarAccess, .granted)
        XCTAssertEqual(subject.remindersAccess, .denied)
        XCTAssertEqual(subject.notificationAccess, .restricted)
    }

    func testRequestNotificationsDoesNotChangeCalendarOrReminders() async {
        let calendar = FakeCalendarService(access: .restricted)
        let reminders = FakeRemindersService(access: .granted)
        let notifications = FakeNotificationAuthorizer(access: .notDetermined, requestedAccess: .denied)
        let subject = PermissionCoordinator(
            calendar: calendar,
            reminders: reminders,
            notifications: notifications
        )

        await subject.refresh()
        await subject.requestNotifications()

        XCTAssertEqual(subject.calendarAccess, .restricted)
        XCTAssertEqual(subject.remindersAccess, .granted)
        XCTAssertEqual(subject.notificationAccess, .denied)
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<100 {
            if condition() { return }
            await Task.yield()
        }
    }
}
