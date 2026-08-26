import XCTest
@testable import PersonalCalendar

@MainActor
final class TimetableLiveActivityCoordinatorTests: XCTestCase {
    func testStartProjectsOnlyTodaysCurrentAndUpcomingEntries() async throws {
        let fixture = TimetableTestFixture()
        let now = fixture.date(day: 1, hour: 9, minute: 30)
        let snapshot = TimetableSnapshotV1(
            version: TimetableSnapshotV1.currentVersion,
            availability: .ready,
            generatedAt: now,
            weekStart: fixture.mondayStart,
            timeZoneIdentifier: fixture.timeZone.identifier,
            entries: [
                entry(
                    id: "past",
                    title: "Past",
                    start: fixture.date(day: 1, hour: 7),
                    end: fixture.date(day: 1, hour: 8)
                ),
                entry(
                    id: "current",
                    title: "Current",
                    start: fixture.date(day: 1, hour: 9),
                    end: fixture.date(day: 1, hour: 11)
                ),
                entry(
                    id: "upcoming",
                    title: "Upcoming",
                    start: fixture.date(day: 1, hour: 14),
                    end: fixture.date(day: 1, hour: 15)
                ),
                entry(
                    id: "tomorrow",
                    title: "Tomorrow",
                    start: fixture.date(day: 2, hour: 9),
                    end: fixture.date(day: 2, hour: 10)
                )
            ]
        )
        let driver = RecordingTimetableActivityDriver()
        let subject = TimetableLiveActivityCoordinator(driver: driver, calendar: fixture.calendar)

        await subject.start(profile: makeProfile(snapshot: snapshot), now: now)

        let state = try XCTUnwrap(driver.requestedStates.first)
        XCTAssertEqual(state.entries.map(\.id), ["current", "upcoming"])
        XCTAssertEqual(state.generatedAt, now)
        XCTAssertEqual(state.omittedEntryCount, 0)
    }

    func testStartPreservesKnownSourceSnapshotOmissionsSeparatelyFromTodayOmissions() async throws {
        let fixture = TimetableTestFixture()
        let now = fixture.date(day: 1, hour: 9, minute: 30)
        let snapshot = TimetableSnapshotV1(
            version: TimetableSnapshotV1.currentVersion,
            availability: .ready,
            generatedAt: now,
            weekStart: fixture.mondayStart,
            timeZoneIdentifier: fixture.timeZone.identifier,
            entries: [
                entry(
                    id: "current",
                    title: "Current",
                    start: fixture.date(day: 1, hour: 9),
                    end: fixture.date(day: 1, hour: 11)
                )
            ],
            omittedEntryCount: 7
        )
        let driver = RecordingTimetableActivityDriver()
        let subject = TimetableLiveActivityCoordinator(driver: driver, calendar: fixture.calendar)

        await subject.start(profile: makeProfile(snapshot: snapshot), now: now)

        let state = try XCTUnwrap(driver.requestedStates.first)
        XCTAssertEqual(state.omittedEntryCount, 0)
        XCTAssertEqual(state.sourceOmittedEntryCount, 7)
    }

    func testStartIncludesCurrentEntryThatCrossedMidnightIntoToday() async throws {
        let fixture = TimetableTestFixture()
        let now = fixture.date(day: 2, hour: 0, minute: 15)
        let snapshot = TimetableSnapshotV1(
            version: TimetableSnapshotV1.currentVersion,
            availability: .ready,
            generatedAt: now,
            weekStart: fixture.mondayStart,
            timeZoneIdentifier: fixture.timeZone.identifier,
            entries: [
                entry(
                    id: "overnight",
                    title: "Overnight Studio",
                    start: fixture.date(day: 1, hour: 23, minute: 30),
                    end: fixture.date(day: 2, hour: 0, minute: 30)
                ),
                entry(
                    id: "upcoming",
                    title: "Morning Studio",
                    start: fixture.date(day: 2, hour: 8),
                    end: fixture.date(day: 2, hour: 9)
                )
            ]
        )
        let driver = RecordingTimetableActivityDriver()
        let subject = TimetableLiveActivityCoordinator(driver: driver, calendar: fixture.calendar)

        await subject.start(profile: makeProfile(snapshot: snapshot), now: now)

        let state = try XCTUnwrap(driver.requestedStates.first)
        XCTAssertEqual(state.entries.map(\.id), ["overnight", "upcoming"])
    }

    func testStartAfterFinalEventEndsExistingActivityWithoutCreatingEmptyState() async {
        let fixture = TimetableTestFixture()
        let now = fixture.date(day: 1, hour: 18)
        let snapshot = TimetableSnapshotV1(
            version: TimetableSnapshotV1.currentVersion,
            availability: .ready,
            generatedAt: now,
            weekStart: fixture.mondayStart,
            timeZoneIdentifier: fixture.timeZone.identifier,
            entries: [
                entry(
                    id: "finished",
                    title: "Finished Class",
                    start: fixture.date(day: 1, hour: 9),
                    end: fixture.date(day: 1, hour: 10)
                )
            ]
        )
        let profile = makeProfile(snapshot: snapshot)
        let driver = RecordingTimetableActivityDriver(
            existingIDs: ["old-activity"],
            profile: profile
        )
        let subject = TimetableLiveActivityCoordinator(
            driver: driver,
            calendar: fixture.calendar
        )

        await subject.start(profile: profile, now: now)

        XCTAssertEqual(driver.requestCount, 0)
        XCTAssertEqual(driver.updatedIDs, [])
        XCTAssertEqual(driver.endedIDs, ["old-activity"])
        XCTAssertEqual(subject.status, .unavailable("There are no events today."))
    }

    func testStartCapsEncodedContentStateAndReportsExactProjectionOmissions() async throws {
        let fixture = TimetableTestFixture()
        let now = fixture.date(day: 1, hour: 9)
        let entries = (0..<80).map { index in
            entry(
                id: "entry-\(index)",
                title: "Course \(index) " + String(repeating: "T", count: 80),
                start: now.addingTimeInterval(TimeInterval(index * 60)),
                end: fixture.date(day: 1, hour: 23),
                location: "Room \(index) " + String(repeating: "L", count: 96)
            )
        }
        let snapshot = TimetableSnapshotV1(
            version: TimetableSnapshotV1.currentVersion,
            availability: .ready,
            generatedAt: now,
            weekStart: fixture.mondayStart,
            timeZoneIdentifier: fixture.timeZone.identifier,
            entries: entries
        )
        let driver = RecordingTimetableActivityDriver()
        let subject = TimetableLiveActivityCoordinator(driver: driver, calendar: fixture.calendar)

        await subject.start(profile: makeProfile(snapshot: snapshot), now: now)

        let state = try XCTUnwrap(driver.requestedStates.first)
        let encoded = try JSONEncoder().encode(state)
        XCTAssertLessThanOrEqual(
            encoded.count,
            TimetableActivityAttributes.ContentState.maximumEncodedBytes
        )
        XCTAssertGreaterThan(state.omittedEntryCount, 0)
        XCTAssertEqual(state.entries.count + state.omittedEntryCount, entries.count)
        XCTAssertEqual(
            state.entries.map(\.id),
            Array(entries.prefix(state.entries.count)).map(\.id)
        )
    }

    func testStartCarriesFreshnessAndUsesItsBoundaryBeforeLaterClassBoundary() async throws {
        let fixture = TimetableTestFixture()
        let generatedAt = fixture.date(day: 1, hour: 9)
        let now = fixture.date(day: 1, hour: 9, minute: 30)
        let snapshot = TimetableSnapshotV1(
            version: TimetableSnapshotV1.currentVersion,
            availability: .ready,
            generatedAt: generatedAt,
            weekStart: fixture.mondayStart,
            timeZoneIdentifier: fixture.timeZone.identifier,
            entries: [
                entry(
                    id: "all-day-class",
                    title: "Studio",
                    start: generatedAt,
                    end: fixture.date(day: 1, hour: 18)
                )
            ]
        )
        let driver = RecordingTimetableActivityDriver()
        let subject = TimetableLiveActivityCoordinator(driver: driver, calendar: fixture.calendar)

        await subject.start(profile: makeProfile(snapshot: snapshot), now: now)

        let state = try XCTUnwrap(driver.requestedStates.first)
        let staleAt = generatedAt.addingTimeInterval(TimetableFreshness.defaultThreshold)
        XCTAssertEqual(state.freshness(at: staleAt.addingTimeInterval(-1)), .fresh)
        XCTAssertEqual(state.freshness(at: staleAt), .stale)
        XCTAssertEqual(driver.requestedStaleDates, [staleAt])
    }

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

    func testDisabledForegroundPreferenceDoesNotRequestAnActivity() async {
        let fixture = TimetableTestFixture()
        let driver = RecordingTimetableActivityDriver()
        let subject = TimetableLiveActivityCoordinator(
            driver: driver,
            calendar: fixture.calendar
        )
        let profile = makeProfile(fixture)

        await subject.applyForegroundPreference(
            isEnabled: false,
            preferredProfileIdentity: profile.id,
            catalog: makeCatalog(profile: profile),
            now: fixture.tuesday0941
        )

        XCTAssertEqual(driver.requestCount, 0)
        XCTAssertEqual(driver.endedIDs, [])
        XCTAssertEqual(subject.status, .idle)
    }

    func testDisablingAutomaticStartSettingStopsExistingActivity() async {
        let fixture = TimetableTestFixture()
        let profile = makeProfile(fixture)
        let driver = RecordingTimetableActivityDriver(
            existingIDs: ["old-activity"],
            profile: profile
        )
        let subject = TimetableLiveActivityCoordinator(
            driver: driver,
            calendar: fixture.calendar
        )

        await subject.applyAutomaticStartSettingChange(
            isEnabled: false,
            preferredProfileIdentity: profile.id,
            catalog: nil,
            now: fixture.tuesday0941
        )

        XCTAssertEqual(driver.requestCount, 0)
        XCTAssertEqual(driver.endedIDs, ["old-activity"])
        XCTAssertNil(subject.activeProfileIdentity)
        XCTAssertEqual(subject.status, .idle)
    }

    func testEnabledForegroundPreferenceStartsExactReadyProfile() async {
        let fixture = TimetableTestFixture()
        let driver = RecordingTimetableActivityDriver()
        let subject = TimetableLiveActivityCoordinator(
            driver: driver,
            calendar: fixture.calendar
        )
        let profile = makeProfile(fixture)

        await subject.applyForegroundPreference(
            isEnabled: true,
            preferredProfileIdentity: profile.id,
            catalog: makeCatalog(profile: profile),
            now: fixture.tuesday0941
        )

        XCTAssertEqual(driver.requestCount, 1)
        XCTAssertEqual(subject.activeProfileIdentity, profile.id)
        XCTAssertEqual(subject.status, .running)
    }

    func testEnabledForegroundPreferenceWithDeletedProfileStopsWithoutFallback() async {
        let fixture = TimetableTestFixture()
        let profile = makeProfile(fixture)
        let driver = RecordingTimetableActivityDriver(
            existingIDs: ["old-activity"],
            profile: profile
        )
        let subject = TimetableLiveActivityCoordinator(
            driver: driver,
            calendar: fixture.calendar
        )

        await subject.applyForegroundPreference(
            isEnabled: true,
            preferredProfileIdentity: .saved(UUID()),
            catalog: makeCatalog(profile: profile),
            now: fixture.tuesday0941
        )

        XCTAssertEqual(driver.requestCount, 0)
        XCTAssertEqual(driver.endedIDs, ["old-activity"])
        XCTAssertNil(subject.activeProfileIdentity)
        XCTAssertEqual(subject.status, .idle)
    }

    func testPreviouslyEnabledPreferenceSelectionClearedStopsExistingActivity() async {
        let fixture = TimetableTestFixture()
        let profile = makeProfile(fixture)
        let driver = RecordingTimetableActivityDriver(
            existingIDs: ["old-activity"],
            profile: profile
        )
        let subject = TimetableLiveActivityCoordinator(
            driver: driver,
            calendar: fixture.calendar
        )

        await subject.applyPreferenceSelectionChange(
            wasAutomaticallyEnabled: true,
            preferredProfileIdentity: nil,
            catalog: makeCatalog(profile: profile),
            now: fixture.tuesday0941
        )

        XCTAssertEqual(driver.requestCount, 0)
        XCTAssertEqual(driver.endedIDs, ["old-activity"])
        XCTAssertNil(subject.activeProfileIdentity)
        XCTAssertEqual(subject.status, .idle)
    }

    func testPreviouslyEnabledPreferenceSelectionSwitchesToExactProfile() async {
        let fixture = TimetableTestFixture()
        let oldProfile = makeProfile(fixture)
        let newIdentity = ProfileIdentity.saved(UUID())
        let newProfile = TimetableWidgetProfile(
            id: newIdentity,
            name: "School",
            colorHex: "#4F6F64",
            symbolName: "graduationcap.fill",
            snapshot: makeSnapshot(fixture)
        )
        let driver = RecordingTimetableActivityDriver(
            existingIDs: ["old-activity"],
            profile: oldProfile
        )
        let subject = TimetableLiveActivityCoordinator(
            driver: driver,
            calendar: fixture.calendar
        )
        let catalog = TimetableWidgetCatalogV1(
            version: TimetableWidgetCatalogV1.currentVersion,
            generatedAt: newProfile.snapshot.generatedAt,
            profiles: [oldProfile, newProfile]
        )

        await subject.applyPreferenceSelectionChange(
            wasAutomaticallyEnabled: true,
            preferredProfileIdentity: newIdentity,
            catalog: catalog,
            now: fixture.tuesday0941
        )

        XCTAssertEqual(driver.endedIDs, ["old-activity"])
        XCTAssertEqual(driver.requestCount, 1)
        XCTAssertEqual(subject.activeProfileIdentity, newIdentity)
        XCTAssertEqual(subject.status, .running)
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

    func testOverlappingStartsQueueLatestStartWithoutConcurrentWrites() async {
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
        XCTAssertEqual(driver.maximumConcurrentUpdates, 1)
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

    private func entry(
        id: String,
        title: String,
        start: Date,
        end: Date,
        location: String? = nil
    ) -> TimetableEntry {
        TimetableEntry(
            id: id,
            title: title,
            shortTitle: String(title.prefix(4)).uppercased(),
            start: start,
            end: end,
            location: location
        )
    }
}

@MainActor
private final class RecordingTimetableActivityDriver: TimetableActivityDriving {
    var activitiesEnabled = true
    private var IDs: [String]
    private var suspendsNextUpdate: Bool
    private var updateContinuation: CheckedContinuation<Void, Never>?
    private var updateStarted = false

    private(set) var requestCount = 0
    private(set) var requestedStates: [TimetableActivityAttributes.ContentState] = []
    private(set) var requestedStaleDates: [Date?] = []
    private(set) var updatedIDs: [String] = []
    private(set) var maximumConcurrentUpdates = 0
    private(set) var endedIDs: [String] = []
    private(set) var immediateEndFlags: [Bool] = []
    private var activeUpdates = 0

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
        suspendsNextUpdate = suspendsUpdates
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
        requestedStates.append(state)
        requestedStaleDates.append(staleDate)
        IDs.append("new-activity")
        descriptors.append(.init(id: "new-activity", attributes: attributes))
        return "new-activity"
    }

    func update(
        id: String,
        state: TimetableActivityAttributes.ContentState,
        staleDate: Date?
    ) async {
        activeUpdates += 1
        maximumConcurrentUpdates = max(maximumConcurrentUpdates, activeUpdates)
        defer { activeUpdates -= 1 }
        updatedIDs.append(id)
        updateStarted = true
        if suspendsNextUpdate {
            suspendsNextUpdate = false
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
