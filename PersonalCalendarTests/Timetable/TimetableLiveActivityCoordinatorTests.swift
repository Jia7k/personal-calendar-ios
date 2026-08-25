import XCTest
@testable import PersonalCalendar

@MainActor
final class TimetableLiveActivityCoordinatorTests: XCTestCase {
    func testStartUpdatesRecoveredActivityAndEndsDuplicates() async {
        let fixture = TimetableTestFixture()
        let driver = RecordingTimetableActivityDriver(existingIDs: ["old-a", "old-b"])
        let subject = TimetableLiveActivityCoordinator(driver: driver, calendar: fixture.calendar)
        let snapshot = makeSnapshot(fixture)

        await subject.start(snapshot: snapshot, now: fixture.tuesday0941)

        XCTAssertEqual(driver.requestCount, 0)
        XCTAssertEqual(driver.updatedIDs, ["old-a"])
        XCTAssertEqual(driver.endedIDs, ["old-b"])
        XCTAssertEqual(subject.status, .running)
    }

    func testStartWithoutExistingActivityRequestsExactlyOnce() async {
        let fixture = TimetableTestFixture()
        let driver = RecordingTimetableActivityDriver()
        let subject = TimetableLiveActivityCoordinator(driver: driver, calendar: fixture.calendar)
        let snapshot = makeSnapshot(fixture)

        await subject.start(snapshot: snapshot, now: fixture.tuesday0941)
        await subject.start(snapshot: snapshot, now: fixture.tuesday0941)

        XCTAssertEqual(driver.requestCount, 1)
        XCTAssertEqual(driver.updatedIDs, ["new-activity"])
        XCTAssertEqual(driver.endedIDs, [])
        XCTAssertEqual(subject.status, .running)
    }

    func testPermissionLossStopsAllActivitiesAndNeverRequests() async {
        let fixture = TimetableTestFixture()
        let driver = RecordingTimetableActivityDriver(existingIDs: ["old-a", "old-b"])
        let subject = TimetableLiveActivityCoordinator(driver: driver, calendar: fixture.calendar)
        let snapshot = TimetableSnapshotBuilder(calendar: fixture.calendar)
            .makeSnapshot(access: .denied, events: fixture.weekEvents, now: fixture.tuesday0941)

        await subject.start(snapshot: snapshot, now: fixture.tuesday0941)

        XCTAssertEqual(driver.requestCount, 0)
        XCTAssertEqual(driver.endedIDs, ["old-a", "old-b"])
        XCTAssertEqual(subject.status, .unavailable("Calendar access is required."))
    }

    func testReconcileNeverStartsANewActivity() async {
        let fixture = TimetableTestFixture()
        let driver = RecordingTimetableActivityDriver()
        let subject = TimetableLiveActivityCoordinator(driver: driver, calendar: fixture.calendar)

        await subject.reconcile(snapshot: makeSnapshot(fixture), now: fixture.tuesday0941)

        XCTAssertEqual(driver.requestCount, 0)
        XCTAssertEqual(subject.status, .idle)
    }

    func testStopEndsEveryRecoveredActivityImmediately() async {
        let fixture = TimetableTestFixture()
        let driver = RecordingTimetableActivityDriver(existingIDs: ["old-a", "old-b"])
        let subject = TimetableLiveActivityCoordinator(driver: driver, calendar: fixture.calendar)

        await subject.stop()

        XCTAssertEqual(driver.endedIDs, ["old-a", "old-b"])
        XCTAssertEqual(driver.immediateEndFlags, [true, true])
        XCTAssertEqual(subject.status, .idle)
    }

    func testOverlappingStartsDoNotWriteTwice() async {
        let fixture = TimetableTestFixture()
        let driver = RecordingTimetableActivityDriver(existingIDs: ["old-a"], suspendsUpdates: true)
        let subject = TimetableLiveActivityCoordinator(driver: driver, calendar: fixture.calendar)
        let snapshot = makeSnapshot(fixture)

        let first = Task { await subject.start(snapshot: snapshot, now: fixture.tuesday0941) }
        await driver.waitUntilUpdateSuspends()
        await subject.start(snapshot: snapshot, now: fixture.tuesday0941)
        driver.resumeUpdate()
        await first.value

        XCTAssertEqual(driver.updatedIDs, ["old-a"])
        XCTAssertEqual(driver.requestCount, 0)
    }

    private func makeSnapshot(_ fixture: TimetableTestFixture) -> TimetableSnapshotV1 {
        TimetableSnapshotBuilder(calendar: fixture.calendar)
            .makeSnapshot(access: .granted, events: fixture.weekEvents, now: fixture.tuesday0941)
    }
}

@MainActor
private final class RecordingTimetableActivityDriver: TimetableActivityDriving {
    var activitiesEnabled = true
    private var IDs: [String]
    private let suspendsUpdates: Bool
    private var updateContinuation: CheckedContinuation<Void, Never>?
    private var updateStarted = false

    private(set) var requestCount = 0
    private(set) var updatedIDs: [String] = []
    private(set) var endedIDs: [String] = []
    private(set) var immediateEndFlags: [Bool] = []

    init(existingIDs: [String] = [], suspendsUpdates: Bool = false) {
        IDs = existingIDs
        self.suspendsUpdates = suspendsUpdates
    }

    func activityIDs() -> [String] { IDs }

    func request(
        attributes: TimetableActivityAttributes,
        state: TimetableActivityAttributes.ContentState,
        staleDate: Date?
    ) throws -> String {
        requestCount += 1
        IDs.append("new-activity")
        return "new-activity"
    }

    func update(
        id: String,
        state: TimetableActivityAttributes.ContentState,
        staleDate: Date?
    ) async {
        updatedIDs.append(id)
        updateStarted = true
        if suspendsUpdates {
            await withCheckedContinuation { updateContinuation = $0 }
        }
    }

    func end(id: String, immediately: Bool) async {
        endedIDs.append(id)
        immediateEndFlags.append(immediately)
        IDs.removeAll { $0 == id }
    }

    func waitUntilUpdateSuspends() async {
        while !updateStarted {
            await Task.yield()
        }
    }

    func resumeUpdate() {
        updateContinuation?.resume()
        updateContinuation = nil
    }
}
