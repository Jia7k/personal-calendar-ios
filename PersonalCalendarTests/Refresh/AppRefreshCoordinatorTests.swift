import XCTest
@testable import PersonalCalendar

@MainActor
final class AppRefreshCoordinatorTests: XCTestCase {
    func testStoreChangeBurstCoalescesOneOrderedRefresh() async {
        let debouncer = FakeRefreshDebouncer()
        let agendaRefreshes = AgendaRefreshRegistry()
        let agendaGate = FakeRefreshGate()
        let calls = RefreshCallRecorder()
        calls.agendaOperation = {
            await agendaRefreshes.refreshAll()
        }
        agendaRefreshes.register(id: UUID()) {
            await agendaGate.wait()
        }
        let subject = AppRefreshCoordinator(debouncer: debouncer, actions: calls.actions)

        subject.eventStoreDidChange()
        subject.eventStoreDidChange()
        subject.eventStoreDidChange()
        let refresh = Task { await debouncer.fire() }
        for _ in 0..<100 where calls.steps != [.permissions, .sources, .agenda] {
            await Task.yield()
        }

        XCTAssertEqual(calls.steps, [.permissions, .sources, .agenda])
        agendaGate.release()
        await refresh.value

        XCTAssertEqual(
            calls.steps,
            [.permissions, .sources, .agenda, .categoryCleanup, .notifications]
        )
        XCTAssertEqual(calls.completedRefreshes, 1)
    }
}
