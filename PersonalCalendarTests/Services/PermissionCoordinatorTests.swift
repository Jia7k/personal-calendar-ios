import XCTest
@testable import PersonalCalendar

@MainActor
final class PermissionCoordinatorTests: XCTestCase {
    func testDuplicateRequestOnlyCallsMatchingSourceOnce() async {
        let calendar = FakeCalendarService(access: .notDetermined, requestedAccess: .granted)
        let reminders = FakeRemindersService(access: .notDetermined, requestedAccess: .granted)
        let notifications = FakeNotificationAuthorizer(access: .granted)
        let subject = PermissionCoordinator(calendar: calendar, reminders: reminders, notifications: notifications)
        await subject.refresh()
        async let first: Void = subject.requestCalendar()
        async let second: Void = subject.requestCalendar()
        _ = await (first, second)
        XCTAssertEqual(calendar.requestCount, 1)
        await subject.requestReminders()
        XCTAssertEqual(reminders.requestCount, 1)
    }

    func testRefreshDoesNotPublishPartialStateWhileNotificationIsSuspended() async {
        let calendar = FakeCalendarService(access: .denied)
        let reminders = FakeRemindersService(access: .restricted)
        let notifications = FakeNotificationAuthorizer(access: .granted, suspendRead: true)
        let subject = PermissionCoordinator(calendar: calendar, reminders: reminders, notifications: notifications)
        let task = Task { await subject.refresh() }
        await Task.yield()
        XCTAssertTrue(subject.isRefreshing)
        XCTAssertEqual(subject.calendarAccess, .denied)
        XCTAssertEqual(subject.remindersAccess, .restricted)
        notifications.resumeRead()
        await task.value
        XCTAssertEqual(subject.notificationAccess, .granted)
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
}
