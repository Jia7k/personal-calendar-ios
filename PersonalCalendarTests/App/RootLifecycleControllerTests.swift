import XCTest
@testable import PersonalCalendar

@MainActor
final class RootLifecycleControllerTests: XCTestCase {
    func testSceneActivationWaitsForPermissionRefreshBeforeAdvancingRevision() async {
        let permissions = SuspendedPermissionRefresh()
        let subject = RootLifecycleController(permissions: permissions)

        let activation = Task { await subject.sceneBecameActive() }
        for _ in 0..<30 where !permissions.isSuspended { await Task.yield() }
        XCTAssertEqual(subject.revision, 0)
        permissions.resume()
        await activation.value

        XCTAssertEqual(subject.revision, 1)
    }

    func testOnboardingStartAndSceneActivationBothWaitForLatestPermissionRefresh() async {
        let calendar = FakeCalendarService(access: .notDetermined)
        let reminders = FakeRemindersService(access: .notDetermined)
        let notifications = FakeNotificationAuthorizer(access: .notDetermined, suspendRead: true)
        let permissions = PermissionCoordinator(
            calendar: calendar,
            reminders: reminders,
            notifications: notifications
        )
        let onboarding = PermissionOnboardingModel(permissions: permissions, onFinish: {})
        let subject = RootLifecycleController(permissions: permissions)

        let onboardingStart = Task { await onboarding.start() }
        await waitUntil { notifications.isReadSuspended && notifications.readCount == 1 }
        calendar.accessState = .denied
        reminders.accessState = .restricted
        notifications.setAccessState(.granted)
        notifications.suspendNextRead = true
        let activation = Task { await subject.sceneBecameActive() }
        await Task.yield()

        notifications.resumeRead()
        await waitUntil {
            notifications.completedReadCount == 1
                && notifications.isReadSuspended
                && notifications.readCount == 2
        }
        XCTAssertFalse(onboarding.actionsEnabled)
        XCTAssertEqual(subject.revision, 0)
        XCTAssertTrue(permissions.isRefreshing)
        XCTAssertEqual(permissions.calendarAccess, .notDetermined)
        XCTAssertEqual(permissions.remindersAccess, .notDetermined)
        XCTAssertEqual(permissions.notificationAccess, .notDetermined)

        notifications.resumeRead()
        _ = await (onboardingStart.value, activation.value)

        XCTAssertTrue(onboarding.actionsEnabled)
        XCTAssertEqual(subject.revision, 1)
        XCTAssertEqual(permissions.calendarAccess, .denied)
        XCTAssertEqual(permissions.remindersAccess, .restricted)
        XCTAssertEqual(permissions.notificationAccess, .granted)
        XCTAssertFalse(permissions.isRefreshing)
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<30 where !condition() { await Task.yield() }
        XCTAssertTrue(condition())
    }
}

@MainActor
private final class SuspendedPermissionRefresh: PermissionRefreshing {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var isSuspended = false
    func refresh() async {
        isSuspended = true
        await withCheckedContinuation { continuation = $0 }
        isSuspended = false
    }
    func resume() { continuation?.resume(); continuation = nil }
}
