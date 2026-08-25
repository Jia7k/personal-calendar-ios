import XCTest
@testable import PersonalCalendar

@MainActor
final class TimetableLiveActivityCoordinatorTests: XCTestCase {
    func testStartUpdatesRecoveredActivityAndEndsDuplicates() async {
        let fixture = TimetableTestFixture()
        let profile = makeProfile(fixture)
        let driver = RecordingTimetableActivityDriver(
            existingIDs: ["old-a", "old-b"],
            profile: profile
        )
        let subject = TimetableLiveActivityCoordinator(driver: driver, calendar: fixture.calendar)

        await subject.start(profile: profile, now: fixture.tuesday0941)

        XCTAssertEqual(driver.requestCount, 0)
        XCTAssertEqual(driver.updatedIDs, ["old-a"])
        XCTAssertEqual(driver.endedIDs, ["old-b"])
        XCTAssertEqual(subject.status, .running)
    }

    func testStartWithoutExistingActivityRequestsExactlyOnce() async {
        let fixture = TimetableTestFixture()
        let driver = RecordingTimetableActivityDriver()
        let subject = TimetableLiveActivityCoordinator(driver: driver, calendar: fixture.calendar)
        let profile = makeProfile(fixture)

        await subject.start(profile: profile, now: fixture.tuesday0941)
        await subject.start(profile: profile, now: fixture.tuesday0941)

        XCTAssertEqual(driver.requestCount, 1)
        XCTAssertEqual(driver.updatedIDs, ["new-activity"])
        XCTAssertEqual(driver.endedIDs, [])
        XCTAssertEqual(subject.status, .running)
    }

    func testPermissionLossStopsAllActivitiesAndNeverRequests() async {
        let fixture = TimetableTestFixture()
        let snapshot = TimetableSnapshotBuilder(calendar: fixture.calendar)
            .makeSnapshot(access: .denied, events: fixture.weekEvents, now: fixture.tuesday0941)
        let profile = makeProfile(snapshot: snapshot)
        let driver = RecordingTimetableActivityDriver(
            existingIDs: ["old-a", "old-b"],
            profile: profile
        )
        let subject = TimetableLiveActivityCoordinator(driver: driver, calendar: fixture.calendar)

        await subject.start(profile: profile, now: fixture.tuesday0941)

        XCTAssertEqual(driver.requestCount, 0)
        XCTAssertEqual(driver.endedIDs, ["old-a", "old-b"])
        XCTAssertEqual(subject.status, .unavailable("Calendar access is required."))
    }

    func testReconcileNeverStartsANewActivity() async {
        let fixture = TimetableTestFixture()
        let driver = RecordingTimetableActivityDriver()
        let subject = TimetableLiveActivityCoordinator(driver: driver, calendar: fixture.calendar)
        let profile = makeProfile(fixture)

        await subject.reconcile(
            catalog: makeCatalog(profile: profile),
            now: fixture.tuesday0941
        )

        XCTAssertEqual(driver.requestCount, 0)
        XCTAssertEqual(subject.status, .idle)
    }

    func testStopEndsEveryRecoveredActivityImmediately() async {
        let fixture = TimetableTestFixture()
        let driver = RecordingTimetableActivityDriver(
            existingIDs: ["old-a", "old-b"],
            profile: makeProfile(fixture)
        )
        let subject = TimetableLiveActivityCoordinator(driver: driver, calendar: fixture.calendar)

        await subject.stop()

        XCTAssertEqual(driver.endedIDs, ["old-a", "old-b"])
        XCTAssertEqual(driver.immediateEndFlags, [true, true])
        XCTAssertEqual(subject.status, .idle)
    }

    func testOverlappingStartsDoNotWriteTwice() async {
        let fixture = TimetableTestFixture()
        let profile = makeProfile(fixture)
        let driver = RecordingTimetableActivityDriver(
            existingIDs: ["old-a"],
            profile: profile,
            suspendsUpdates: true
        )
        let subject = TimetableLiveActivityCoordinator(driver: driver, calendar: fixture.calendar)

        let first = Task { await subject.start(profile: profile, now: fixture.tuesday0941) }
        await driver.waitUntilUpdateSuspends()
        await subject.start(profile: profile, now: fixture.tuesday0941)
        driver.resumeUpdate()
        await first.value

        XCTAssertEqual(driver.updatedIDs, ["old-a", "old-a"])
        XCTAssertEqual(driver.requestCount, 0)
    }

    private func makeSnapshot(_ fixture: TimetableTestFixture) -> TimetableSnapshotV1 {
        TimetableSnapshotBuilder(calendar: fixture.calendar)
            .makeSnapshot(access: .granted, events: fixture.weekEvents, now: fixture.tuesday0941)
    }

    private func makeProfile(_ fixture: TimetableTestFixture) -> TimetableWidgetProfile {
        makeProfile(snapshot: makeSnapshot(fixture))
    }

    private func makeProfile(snapshot: TimetableSnapshotV1) -> TimetableWidgetProfile {
        TimetableWidgetProfile(
            id: .everything,
            name: "Everything",
            colorHex: "#4F6F64",
            symbolName: "rectangle.3.group.fill",
            snapshot: snapshot
        )
    }

    private func makeCatalog(profile: TimetableWidgetProfile) -> TimetableWidgetCatalogV1 {
        TimetableWidgetCatalogV1(
            version: TimetableWidgetCatalogV1.currentVersion,
            generatedAt: profile.snapshot.generatedAt,
            profiles: [profile]
        )
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

    init(
        existingIDs: [String] = [],
        profile: TimetableWidgetProfile? = nil,
        suspendsUpdates: Bool = false
    ) {
        let attributes = profile.map {
            TimetableActivityAttributes(
                profileIdentity: $0.id,
                profileName: $0.name,
                weekStart: $0.snapshot.weekStart,
                timeZoneIdentifier: $0.snapshot.timeZoneIdentifier
            )
        }
        IDs = existingIDs
        descriptors = existingIDs.map { id in
            TimetableActivityDescriptor(
                id: id,
                attributes: attributes ?? TimetableActivityAttributes(
                    profileIdentity: .everything,
                    profileName: "Everything",
                    weekStart: .distantPast,
                    timeZoneIdentifier: "UTC"
                )
            )
        }
        self.suspendsUpdates = suspendsUpdates
    }

    private var descriptors: [TimetableActivityDescriptor]

    func activityDescriptors() -> [TimetableActivityDescriptor] {
        descriptors
    }

    func request(
        attributes: TimetableActivityAttributes,
        state: TimetableActivityAttributes.ContentState,
        staleDate: Date?
    ) throws -> String {
        requestCount += 1
        IDs.append("new-activity")
        descriptors.append(.init(id: "new-activity", attributes: attributes))
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
        descriptors.removeAll { $0.id == id }
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
