import XCTest
@testable import PersonalCalendar

@MainActor
final class AppRefreshCoordinatorTests: XCTestCase {
    func testStoreChangeBurstCoalescesOneOrderedRefresh() async {
        let debouncer = FakeRefreshDebouncer()
        let agendaRefreshes = AgendaRefreshRegistry()
        let agendaGate = FakeRefreshGate()
        let timetableGate = FakeRefreshGate()
        let calls = RefreshCallRecorder()
        calls.agendaOperation = {
            await agendaRefreshes.refreshAll()
        }
        agendaRefreshes.register(id: UUID()) {
            await agendaGate.wait()
        }
        calls.timetableOperation = {
            await timetableGate.wait()
        }
        let subject = AppRefreshCoordinator(debouncer: debouncer, actions: calls.actions)

        subject.eventStoreDidChange()
        subject.eventStoreDidChange()
        subject.eventStoreDidChange()
        let refresh = Task { await debouncer.fire() }
        for _ in 0..<100 where calls.steps != [
            .permissions, .profiles, .sources, .profileCatalog, .agenda
        ] {
            await Task.yield()
        }

        XCTAssertEqual(
            calls.steps,
            [.permissions, .profiles, .sources, .profileCatalog, .agenda]
        )
        agendaGate.release()
        for _ in 0..<100 where calls.steps != [
            .permissions, .profiles, .sources, .profileCatalog, .agenda,
            .categoryCleanup, .timetable
        ] {
            await Task.yield()
        }

        XCTAssertEqual(
            calls.steps,
            [
                .permissions, .profiles, .sources, .profileCatalog, .agenda,
                .categoryCleanup, .timetable
            ]
        )
        timetableGate.release()
        await refresh.value

        XCTAssertEqual(
            calls.steps,
            [
                .permissions, .profiles, .sources, .profileCatalog, .agenda,
                .categoryCleanup, .timetable, .notifications
            ]
        )
        XCTAssertEqual(calls.completedRefreshes, 1)
    }
}
