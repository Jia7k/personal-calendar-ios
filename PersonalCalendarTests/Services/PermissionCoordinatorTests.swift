import XCTest
@testable import PersonalCalendar

@MainActor
final class PermissionCoordinatorTests: XCTestCase {
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
