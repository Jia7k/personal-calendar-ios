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
