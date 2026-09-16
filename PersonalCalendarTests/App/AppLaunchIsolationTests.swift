import XCTest
@testable import PersonalCalendar

@MainActor
final class AppLaunchIsolationTests: XCTestCase {
    func testTestingHandoffNeverOpensSharedStore() throws {
        var sharedWasOpened = false
        let store = try AppLaunchStorage.handoffStore(isTesting: true) {
            sharedWasOpened = true
            throw AppRouteHandoffStoreError.containerUnavailable
        }
        defer { try? FileManager.default.removeItem(at: store.fileURL.deletingLastPathComponent()) }
        try store.write(.quickEntry(text: "Isolated draft", profile: nil))
        XCTAssertFalse(sharedWasOpened)
        XCTAssertEqual(try store.consume(), .quickEntry(text: "Isolated draft", profile: nil))
    }

    func testNormalLaunchRetainsSharedHandoffStore() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("shared-fixture.json")
        let store = try AppLaunchStorage.handoffStore(isTesting: false) {
            AppRouteHandoffStore(fileURL: url)
        }
        XCTAssertEqual(store.fileURL, url)
    }

    func testDemoSchedulerReplacesOnlyItsOwnInMemoryQueue() async throws {
        let scheduler = InMemoryNotificationScheduler()
        let otherSession = InMemoryNotificationScheduler()
        let request = LocalNotificationRequest(identifier: "routine|fixture", title: "Read", body: "", fireDate: Date(timeIntervalSince1970: 10))
        try await scheduler.schedule(request)
        try await scheduler.schedule(request)
        let scheduled = await scheduler.pendingRequests()
        let untouched = await otherSession.pendingRequests()
        XCTAssertEqual(scheduled, [request])
        XCTAssertTrue(untouched.isEmpty)
        try await scheduler.mutateAppRequests { _ in [] }
        let cleared = await scheduler.pendingRequests()
        XCTAssertTrue(cleared.isEmpty)
    }
}
