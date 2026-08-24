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

    func testSceneActivationRefreshesThenValidatesBeforeAdvancingRevision() async {
        var steps: [String] = []
        let permissions = SuspendedPermissionRefresh(
            onStart: { steps.append("refresh started") },
            onFinish: { steps.append("refresh finished") }
        )
        var subject: RootLifecycleController!
        subject = RootLifecycleController(permissions: permissions, validateDefaults: {
            XCTAssertEqual(subject.revision, 0)
            steps.append("defaults validated")
        })

        let activation = Task { await subject.sceneBecameActive() }
        for _ in 0..<30 where !permissions.isSuspended { await Task.yield() }
        XCTAssertEqual(steps, ["refresh started"])
        XCTAssertEqual(subject.revision, 0)

        permissions.resume()
        await activation.value

        XCTAssertEqual(steps, ["refresh started", "refresh finished", "defaults validated"])
        XCTAssertEqual(subject.revision, 1)
    }

    func testSceneActivationPreservesDeniedDefaultsThenClearsGrantedInvalidDefaults() async {
        let defaults = UserDefaults.ephemeral
        defaults.set("saved-calendar", forKey: "defaultCalendarID")
        defaults.set("saved-list", forKey: "defaultReminderListID")
        let settings = AppSettingsStore(defaults: defaults)
        let calendar = FakeCalendarService(access: .denied)
        let reminders = FakeRemindersService(access: .restricted)
        let subject = RootLifecycleController(permissions: ImmediatePermissionRefresh(), validateDefaults: {
            settings.validateDefaults(
                calendarAccess: calendar.accessState,
                calendars: calendar.calendars(),
                remindersAccess: reminders.accessState,
                lists: reminders.lists()
            )
        })

        await subject.sceneBecameActive()

        XCTAssertEqual(settings.defaultCalendarID, "saved-calendar")
        XCTAssertEqual(settings.defaultReminderListID, "saved-list")

        calendar.accessState = .granted
        calendar.descriptors = [.init(id: "other", title: "Other", colorHex: "#000000", allowsContentModifications: true)]
        reminders.accessState = .granted
        reminders.descriptors = [.init(id: "saved-list", title: "Read only", colorHex: "#000000", allowsContentModifications: false)]

        await subject.sceneBecameActive()

        XCTAssertNil(settings.defaultCalendarID)
        XCTAssertNil(settings.defaultReminderListID)
        XCTAssertNil(defaults.string(forKey: "defaultCalendarID"))
        XCTAssertNil(defaults.string(forKey: "defaultReminderListID"))
        XCTAssertEqual(subject.revision, 2)
    }

    func testOlderOverlappingActivationCannotValidateOrAdvanceRevision() async {
        let permissions = SequencedPermissionRefresh()
        var validationCount = 0
        let subject = RootLifecycleController(permissions: permissions, validateDefaults: { validationCount += 1 })

        let older = Task { await subject.sceneBecameActive() }
        await waitUntil { permissions.pendingCount == 1 }
        let newer = Task { await subject.sceneBecameActive() }
        await waitUntil { permissions.pendingCount == 2 }

        permissions.resume(at: 1)
        await newer.value
        permissions.resume(at: 0)
        await older.value

        XCTAssertEqual(validationCount, 1)
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
    private let onStart: () -> Void
    private let onFinish: () -> Void
    init(onStart: @escaping () -> Void = {}, onFinish: @escaping () -> Void = {}) {
        self.onStart = onStart
        self.onFinish = onFinish
    }
    func refresh() async {
        onStart()
        isSuspended = true
        await withCheckedContinuation { continuation = $0 }
        isSuspended = false
        onFinish()
    }
    func resume() { continuation?.resume(); continuation = nil }
}

@MainActor
private final class ImmediatePermissionRefresh: PermissionRefreshing {
    func refresh() async {}
}

@MainActor
private final class SequencedPermissionRefresh: PermissionRefreshing {
    private var continuations: [CheckedContinuation<Void, Never>?] = []
    var pendingCount: Int { continuations.count }
    func refresh() async {
        await withCheckedContinuation { continuations.append($0) }
    }
    func resume(at index: Int) {
        continuations[index]?.resume()
        continuations[index] = nil
    }
}
