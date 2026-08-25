import XCTest
@testable import PersonalCalendar

@MainActor
final class AppRefreshCoordinatorTests: XCTestCase {
    func testStoreChangeBurstCoalescesOneOrderedRefresh() async {
        let debouncer = FakeRefreshDebouncer()
        let calls = RefreshCallRecorder()
        let subject = AppRefreshCoordinator(debouncer: debouncer, actions: calls.actions)

        subject.eventStoreDidChange()
        subject.eventStoreDidChange()
        subject.eventStoreDidChange()
        await debouncer.fire()

        XCTAssertEqual(
            calls.steps,
            [.permissions, .sources, .agenda, .categoryCleanup, .notifications]
        )
        XCTAssertEqual(calls.completedRefreshes, 1)
    }
}
