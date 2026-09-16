import Foundation
import XCTest
@testable import PersonalCalendar

/// In-memory-only regression coverage, reserved for the physical iPhone 16 Pro run.
@MainActor
final class DailyActivityLifecycleTests: XCTestCase {
    func testTaskOnlyProfileStartsDailyPayloadWithoutWeeklyEntries() async throws {
        let snapshot = snapshot()
        let provider = DailyLifecycleSnapshotProvider(snapshots: [snapshot])
        let driver = DailyLifecycleRecordingDriver()
        let subject = coordinator(driver: driver, provider: provider)

        await subject.start(profileIdentity: .everything, now: now)

        let request = try XCTUnwrap(driver.requests.first)
        XCTAssertEqual(driver.requests.count, 1)
        XCTAssertEqual(provider.requestedProfiles, [.everything])
        XCTAssertEqual(request.attributes.profileIdentity, .everything)
        XCTAssertEqual(request.attributes.dayStart, snapshot.dayStart)
        XCTAssertEqual(request.state.daily?.snapshot.items.map(\.kind), [.task])
        XCTAssertTrue(request.state.entries.isEmpty)
        XCTAssertEqual(request.state.daily?.presentation(at: now, rowLimit: 3).hero?.id, "task")
        XCTAssertEqual(request.staleDate, min(snapshot.dayEnd,
            snapshot.generatedAt.addingTimeInterval(TimetableFreshness.defaultThreshold)))
        XCTAssertEqual(subject.status, .running)
    }

    func testReconcileWithNoActiveActivityDoesNotFetchOrAutomaticallyStart() async {
        let provider = DailyLifecycleSnapshotProvider(snapshots: [snapshot()])
        let driver = DailyLifecycleRecordingDriver()
        let subject = coordinator(driver: driver, provider: provider)

        await subject.reconcileActive(now: now)

        XCTAssertTrue(provider.requestedProfiles.isEmpty)
        XCTAssertTrue(driver.requests.isEmpty)
        XCTAssertTrue(driver.updates.isEmpty)
        XCTAssertTrue(driver.ends.isEmpty)
        XCTAssertEqual(subject.status, .idle)
    }

    func testForegroundAutomaticStartIsOptInAndRepeatedForegroundDoesNotDuplicate() async {
        let provider = DailyLifecycleSnapshotProvider(snapshots: [snapshot()])
        let driver = DailyLifecycleRecordingDriver()
        let subject = coordinator(driver: driver, provider: provider)

        await subject.applyForegroundPreference(isEnabled: false, preferredProfileIdentity: .everything, now: now)
        XCTAssertTrue(driver.requests.isEmpty)
        XCTAssertTrue(provider.requestedProfiles.isEmpty)

        await subject.applyForegroundPreference(isEnabled: true, preferredProfileIdentity: .everything, now: now)
        await subject.applyForegroundPreference(isEnabled: true, preferredProfileIdentity: .everything, now: now)

        XCTAssertEqual(driver.requests.count, 1)
        XCTAssertEqual(driver.updates.map(\.id), ["requested-1"])
        XCTAssertEqual(driver.activityDescriptors().count, 1)
        XCTAssertEqual(subject.status, .running)
    }

    func testTurningAutomaticStartOffStopsExistingActivity() async {
        let snapshot = snapshot()
        let provider = DailyLifecycleSnapshotProvider(snapshots: [snapshot])
        let driver = DailyLifecycleRecordingDriver(activities: [descriptor("active", snapshot: snapshot)])
        let subject = coordinator(driver: driver, provider: provider)

        await subject.applyAutomaticStartSettingChange(isEnabled: false,
            preferredProfileIdentity: .everything, now: now)

        XCTAssertEqual(driver.ends.map(\.id), ["active"])
        XCTAssertEqual(driver.ends.map(\.immediately), [true])
        XCTAssertTrue(driver.activityDescriptors().isEmpty)
        XCTAssertTrue(provider.requestedProfiles.isEmpty)
        XCTAssertEqual(subject.status, .idle)
    }

    func testDisabledForegroundPreferenceLeavesManualActivityRunning() async {
        let snapshot = snapshot()
        let provider = DailyLifecycleSnapshotProvider(snapshots: [snapshot])
        let driver = DailyLifecycleRecordingDriver(activities: [descriptor("manual", snapshot: snapshot)])
        let subject = coordinator(driver: driver, provider: provider)

        await subject.applyForegroundPreference(isEnabled: false, preferredProfileIdentity: .everything, now: now)
        await subject.applyPreferenceSelectionChange(wasAutomaticallyEnabled: false,
            preferredProfileIdentity: .saved(Self.secondProfileID), now: now)

        XCTAssertEqual(driver.activityDescriptors().map(\.id), ["manual"])
        XCTAssertTrue(driver.ends.isEmpty)
        XCTAssertTrue(provider.requestedProfiles.isEmpty)
    }

    func testSuccessfulReconcileReplacesVersionTwoLegacyActivityWithDailyState() async throws {
        let snapshot = snapshot()
        let provider = DailyLifecycleSnapshotProvider(snapshots: [snapshot])
        let legacy: [String: Any] = ["schemaVersion": 2, "profileIdentity": "everything",
            "profileName": "Everything", "weekStart": snapshot.dayStart.timeIntervalSinceReferenceDate,
            "timeZoneIdentifier": snapshot.timeZoneIdentifier]
        let attributes = try JSONDecoder().decode(TimetableActivityAttributes.self,
            from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertTrue(attributes.isLegacy)
        let driver = DailyLifecycleRecordingDriver(activities: [.init(id: "legacy", attributes: attributes)])
        let subject = coordinator(driver: driver, provider: provider)

        await subject.reconcileActive(now: now)

        XCTAssertEqual(driver.operations, ["end:legacy", "request:everything"])
        XCTAssertEqual(driver.requests.count, 1)
        XCTAssertNotNil(driver.requests.first?.state.daily)
        XCTAssertEqual(driver.requests.first?.attributes.isLegacy, false)
        XCTAssertTrue(driver.updates.isEmpty)
        XCTAssertEqual(subject.status, .running)
    }

    func testReconcileUpdatesMatchingActivityAndEndsDuplicatesWithoutRequesting() async {
        let snapshot = snapshot()
        let provider = DailyLifecycleSnapshotProvider(snapshots: [snapshot])
        let driver = DailyLifecycleRecordingDriver(activities: [
            descriptor("keep", snapshot: snapshot), descriptor("duplicate", snapshot: snapshot)
        ])
        let subject = coordinator(driver: driver, provider: provider)

        await subject.reconcileActive(now: now)

        XCTAssertEqual(driver.updates.map(\.id), ["keep"])
        XCTAssertEqual(driver.updates.first?.state.daily?.snapshot.profile.id, .everything)
        XCTAssertEqual(driver.ends.map(\.id), ["duplicate"])
        XCTAssertTrue(driver.requests.isEmpty)
        XCTAssertEqual(driver.activityDescriptors().map(\.id), ["keep"])
        XCTAssertEqual(subject.status, .running)
    }

    func testExplicitProfileSwitchEndsOldBeforeRequestingSelectedProfile() async {
        let original = snapshot()
        let selected = snapshot(profile: .saved(Self.secondProfileID), name: "Personal")
        let provider = DailyLifecycleSnapshotProvider(snapshots: [original, selected])
        let driver = DailyLifecycleRecordingDriver(activities: [descriptor("original", snapshot: original)])
        let subject = coordinator(driver: driver, provider: provider)

        await subject.start(profileIdentity: selected.profile.id, now: now)

        XCTAssertEqual(provider.requestedProfiles, [selected.profile.id])
        XCTAssertEqual(driver.operations, ["end:original", "request:\(selected.profile.id.storageKey)"])
        XCTAssertEqual(driver.requests.first?.attributes.profileIdentity, selected.profile.id)
        XCTAssertEqual(subject.activeProfileIdentity, selected.profile.id)
        XCTAssertEqual(subject.activeProfileName, "Personal")
    }

    func testStopDuringSuspendedSnapshotPreventsLateRequestAndEndsExistingActivity() async {
        let snapshot = snapshot()
        let provider = DailyLifecycleSnapshotProvider(snapshots: [snapshot])
        provider.suspendNextFetch = true
        let driver = DailyLifecycleRecordingDriver(activities: [descriptor("existing", snapshot: snapshot)])
        let subject = coordinator(driver: driver, provider: provider)
        let start = Task { await subject.start(profileIdentity: .everything, now: self.now) }
        await provider.waitUntilSuspended()

        await subject.stop()
        provider.resumeFetch(returning: snapshot)
        await start.value

        XCTAssertEqual(driver.ends.map(\.id), ["existing"])
        XCTAssertTrue(driver.requests.isEmpty)
        XCTAssertTrue(driver.updates.isEmpty)
        XCTAssertTrue(driver.activityDescriptors().isEmpty)
        XCTAssertEqual(subject.status, .idle)
    }

    func testQueuedExplicitStartSurvivesSubsequentBackgroundReconcile() async {
        let original = snapshot()
        let selected = snapshot(profile: .saved(Self.secondProfileID), name: "Personal")
        let provider = DailyLifecycleSnapshotProvider(snapshots: [original, selected])
        provider.suspendNextFetch = true
        let driver = DailyLifecycleRecordingDriver(activities: [descriptor("original", snapshot: original)])
        let subject = coordinator(driver: driver, provider: provider)
        let reconcile = Task { await subject.reconcileActive(now: self.now) }
        await provider.waitUntilSuspended()

        await subject.start(profileIdentity: selected.profile.id, now: now)
        await subject.reconcileActive(now: now)
        provider.resumeFetch(returning: original)
        await reconcile.value

        XCTAssertEqual(provider.requestedProfiles, [.everything, selected.profile.id])
        XCTAssertEqual(driver.requests.map(\.attributes.profileIdentity), [selected.profile.id])
        XCTAssertEqual(driver.ends.map(\.id), ["original"])
        XCTAssertTrue(driver.updates.isEmpty, "The superseded first fetch must not update old content.")
        XCTAssertEqual(subject.activeProfileIdentity, selected.profile.id)
        XCTAssertEqual(subject.status, .running)
    }

    func testStopBeforeFirstSnapshotReturnsNeverRequestsAnActivity() async {
        let snapshot = snapshot()
        let provider = DailyLifecycleSnapshotProvider(snapshots: [snapshot])
        provider.suspendNextFetch = true
        let driver = DailyLifecycleRecordingDriver()
        let subject = coordinator(driver: driver, provider: provider)
        let start = Task { await subject.start(profileIdentity: .everything, now: self.now) }
        await provider.waitUntilSuspended()

        await subject.stop()
        provider.resumeFetch(returning: snapshot)
        await start.value

        XCTAssertTrue(driver.requests.isEmpty)
        XCTAssertTrue(driver.updates.isEmpty)
        XCTAssertTrue(driver.ends.isEmpty)
        XCTAssertTrue(driver.activityDescriptors().isEmpty)
        XCTAssertEqual(subject.status, .idle)
    }

    func testBackgroundReconcileDoesNotLoseInitialSuspendedExplicitStart() async {
        let snapshot = snapshot()
        let provider = DailyLifecycleSnapshotProvider(snapshots: [snapshot])
        provider.suspendNextFetch = true
        let driver = DailyLifecycleRecordingDriver()
        let subject = coordinator(driver: driver, provider: provider)
        let start = Task { await subject.start(profileIdentity: .everything, now: self.now) }
        await provider.waitUntilSuspended()

        await subject.reconcileActive(now: now)
        provider.resumeFetch(returning: snapshot)
        await start.value

        XCTAssertEqual(provider.requestedProfiles, [.everything, .everything])
        XCTAssertEqual(driver.requests.count, 1)
        XCTAssertEqual(driver.activityDescriptors().count, 1)
        XCTAssertEqual(subject.status, .running)
    }

    func testBackupStyleStopThenNewForegroundStartSurvivesSuspendedReconcile() async {
        let original = snapshot()
        let selected = snapshot(profile: .saved(Self.secondProfileID), name: "Restored profile")
        let provider = DailyLifecycleSnapshotProvider(snapshots: [original, selected])
        provider.suspendNextFetch = true
        let driver = DailyLifecycleRecordingDriver(activities: [descriptor("before-restore", snapshot: original)])
        let subject = coordinator(driver: driver, provider: provider)
        let reconcile = Task { await subject.reconcileActive(now: self.now) }
        await provider.waitUntilSuspended()

        await subject.stop()
        await subject.applyForegroundPreference(isEnabled: true,
            preferredProfileIdentity: selected.profile.id, now: now)
        provider.resumeFetch(returning: original)
        await reconcile.value

        XCTAssertEqual(provider.requestedProfiles, [.everything, selected.profile.id])
        XCTAssertEqual(driver.operations, ["end:before-restore", "request:\(selected.profile.id.storageKey)"])
        XCTAssertEqual(driver.requests.map(\.attributes.profileIdentity), [selected.profile.id])
        XCTAssertTrue(driver.updates.isEmpty)
        XCTAssertEqual(driver.activityDescriptors().count, 1)
        XCTAssertEqual(subject.activeProfileIdentity, selected.profile.id)
        XCTAssertEqual(subject.status, .running)
    }

    func testBackgroundReconcileAfterStopDoesNotResurrectSuspendedOriginalStart() async {
        let snapshot = snapshot()
        let provider = DailyLifecycleSnapshotProvider(snapshots: [snapshot])
        provider.suspendNextFetch = true
        let driver = DailyLifecycleRecordingDriver()
        let subject = coordinator(driver: driver, provider: provider)
        let start = Task { await subject.start(profileIdentity: .everything, now: self.now) }
        await provider.waitUntilSuspended()

        await subject.stop()
        await subject.reconcileActive(now: now)
        provider.resumeFetch(returning: snapshot)
        await start.value

        XCTAssertEqual(provider.requestedProfiles, [.everything])
        XCTAssertTrue(driver.requests.isEmpty)
        XCTAssertTrue(driver.updates.isEmpty)
        XCTAssertTrue(driver.ends.isEmpty)
        XCTAssertTrue(driver.activityDescriptors().isEmpty)
        XCTAssertEqual(subject.status, .idle)
    }

    func testOneHourRefreshPreservesOriginalStartAndExpiryWithoutDuplicateActivity() async throws {
        let original = snapshot()
        let provider = DailyLifecycleSnapshotProvider(snapshots: [original])
        let driver = DailyLifecycleRecordingDriver()
        let subject = coordinator(driver: driver, provider: provider)
        await subject.start(profileIdentity: .everything, now: now)
        let originalAttributes = try XCTUnwrap(driver.activityDescriptors().first?.attributes)
        let later = now.addingTimeInterval(3_600)
        let refreshed = DailyActivitySnapshot(profile: original.profile, dayStart: original.dayStart,
            dayEnd: original.dayEnd, timeZoneIdentifier: original.timeZoneIdentifier,
            generatedAt: later, items: original.items)
        provider.replaceSnapshot(refreshed)

        await subject.reconcileActive(now: later)

        let current = try XCTUnwrap(driver.activityDescriptors().first)
        XCTAssertEqual(driver.requests.count, 1)
        XCTAssertEqual(driver.updates.map(\.id), ["requested-1"])
        XCTAssertEqual(driver.updates.first?.state.daily?.snapshot.generatedAt, later)
        XCTAssertTrue(driver.ends.isEmpty)
        XCTAssertEqual(driver.activityDescriptors().count, 1)
        XCTAssertEqual(current.attributes, originalAttributes)
        XCTAssertEqual(current.attributes.activityStartedAt, now)
        XCTAssertEqual(current.attributes.activityEndsAt, now.addingTimeInterval(8 * 3_600))
        XCTAssertEqual(subject.status, .running)
    }

    func testProviderFailureEndsActiveContentAndReportsRetryableFailure() async {
        let snapshot = snapshot()
        let provider = DailyLifecycleSnapshotProvider(snapshots: [snapshot])
        provider.nextError = DailyLifecycleProviderError.fetchFailed
        let driver = DailyLifecycleRecordingDriver(activities: [descriptor("active", snapshot: snapshot)])
        let subject = coordinator(driver: driver, provider: provider)

        await subject.reconcileActive(now: now)

        XCTAssertEqual(driver.ends.map(\.id), ["active"])
        XCTAssertTrue(driver.requests.isEmpty)
        XCTAssertTrue(driver.updates.isEmpty)
        XCTAssertTrue(driver.activityDescriptors().isEmpty)
        guard case let .failed(message) = subject.status else {
            return XCTFail("Expected retryable failure, got \(subject.status)")
        }
        XCTAssertTrue(message.contains("try again"))
    }

    func testSupersededProviderFetchDoesNotEndOrReplaceKnownActiveContent() async {
        let provider = DailyLifecycleSnapshotProvider(snapshots: [snapshot()])
        let driver = DailyLifecycleRecordingDriver()
        let subject = coordinator(driver: driver, provider: provider)
        await subject.start(profileIdentity: .everything, now: now)
        let activeBefore = driver.activityDescriptors()
        driver.clearRecords()
        provider.nextError = DailyActivitySnapshotCoordinatorError.superseded

        await subject.reconcileActive(now: now)

        XCTAssertEqual(driver.activityDescriptors(), activeBefore)
        XCTAssertTrue(driver.ends.isEmpty)
        XCTAssertTrue(driver.updates.isEmpty)
        XCTAssertTrue(driver.requests.isEmpty)
        XCTAssertEqual(subject.status, .running)
    }

    func testSupersededInFlightFetchStillDrainsNewerQueuedProfileStart() async {
        let original = snapshot()
        let selected = snapshot(profile: .saved(Self.secondProfileID), name: "Personal")
        let provider = DailyLifecycleSnapshotProvider(snapshots: [original, selected])
        provider.suspendNextFetch = true
        let driver = DailyLifecycleRecordingDriver(activities: [descriptor("original", snapshot: original)])
        let subject = coordinator(driver: driver, provider: provider)
        let reconcile = Task { await subject.reconcileActive(now: self.now) }
        await provider.waitUntilSuspended()

        await subject.start(profileIdentity: selected.profile.id, now: now)
        provider.resumeFetch(throwing: DailyActivitySnapshotCoordinatorError.superseded)
        await reconcile.value

        XCTAssertEqual(provider.requestedProfiles, [.everything, selected.profile.id])
        XCTAssertEqual(driver.operations, ["end:original", "request:\(selected.profile.id.storageKey)"])
        XCTAssertEqual(subject.activeProfileIdentity, selected.profile.id)
        XCTAssertEqual(subject.status, .running)
    }

    func testEmptyFreshSnapshotEndsActivityInsteadOfPublishingAllDone() async {
        let original = snapshot()
        let empty = original.replacing(items: [])
        let provider = DailyLifecycleSnapshotProvider(snapshots: [empty])
        let driver = DailyLifecycleRecordingDriver(activities: [descriptor("completed", snapshot: original)])
        let subject = coordinator(driver: driver, provider: provider)

        await subject.reconcileActive(now: now)

        XCTAssertEqual(driver.ends.map(\.id), ["completed"])
        XCTAssertTrue(driver.requests.isEmpty)
        XCTAssertTrue(driver.updates.isEmpty)
        guard case .unavailable = subject.status else { return XCTFail("Expected empty-day unavailability") }
    }

    private static let secondProfileID = UUID(uuidString: "A7300000-0000-4000-8000-000000000001")!
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Singapore")!
        return calendar
    }
    private var dayStart: Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 19))!
    }
    private var now: Date { dayStart.addingTimeInterval(10 * 3_600) }
    private func snapshot(profile: ProfileIdentity = .everything, name: String = "Everything") -> DailyActivitySnapshot {
        .init(profile: .init(id: profile, name: name, symbolName: "calendar"), dayStart: dayStart,
            dayEnd: calendar.date(byAdding: .day, value: 1, to: dayStart)!,
            timeZoneIdentifier: calendar.timeZone.identifier, generatedAt: now,
            items: [.init(id: "task", kind: .task, title: "Pending task", shortTitle: "TASK",
                start: now.addingTimeInterval(3_600))])
    }
    private func descriptor(_ id: String, snapshot: DailyActivitySnapshot) -> TimetableActivityDescriptor {
        .init(id: id, attributes: .init(snapshot: snapshot))
    }
    private func coordinator(driver: DailyLifecycleRecordingDriver,
                             provider: DailyLifecycleSnapshotProvider) -> TimetableLiveActivityCoordinator {
        .init(driver: driver, calendar: calendar, dailySnapshots: provider)
    }
}

private enum DailyLifecycleProviderError: Error { case fetchFailed, missingProfile }

@MainActor
private final class DailyLifecycleSnapshotProvider: DailyActivitySnapshotProviding {
    var suspendNextFetch = false
    var nextError: (any Error)?
    private(set) var requestedProfiles: [ProfileIdentity] = []
    private var snapshots: [ProfileIdentity: DailyActivitySnapshot]
    private var suspendedFetch: CheckedContinuation<DailyActivitySnapshot, any Error>?
    private var suspensionWaiter: CheckedContinuation<Void, Never>?

    init(snapshots: [DailyActivitySnapshot]) {
        self.snapshots = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.profile.id, $0) })
    }

    func snapshot(for profile: ProfileIdentity, now: Date) async throws -> DailyActivitySnapshot {
        requestedProfiles.append(profile)
        if suspendNextFetch {
            suspendNextFetch = false
            return try await withCheckedThrowingContinuation { continuation in
                suspendedFetch = continuation
                suspensionWaiter?.resume()
                suspensionWaiter = nil
            }
        }
        if let error = nextError {
            nextError = nil
            throw error
        }
        guard let snapshot = snapshots[profile] else { throw DailyLifecycleProviderError.missingProfile }
        return snapshot
    }

    func invalidate() {}

    func replaceSnapshot(_ snapshot: DailyActivitySnapshot) {
        snapshots[snapshot.profile.id] = snapshot
    }

    func waitUntilSuspended() async {
        guard suspendedFetch == nil else { return }
        await withCheckedContinuation { suspensionWaiter = $0 }
    }

    func resumeFetch(returning snapshot: DailyActivitySnapshot) {
        let continuation = suspendedFetch
        suspendedFetch = nil
        continuation?.resume(returning: snapshot)
    }

    func resumeFetch(throwing error: any Error) {
        let continuation = suspendedFetch
        suspendedFetch = nil
        continuation?.resume(throwing: error)
    }
}

@MainActor
private final class DailyLifecycleRecordingDriver: TimetableActivityDriving {
    struct Request {
        let attributes: TimetableActivityAttributes
        let state: TimetableActivityAttributes.ContentState
        let staleDate: Date?
    }
    struct Update {
        let id: String
        let state: TimetableActivityAttributes.ContentState
    }
    struct End {
        let id: String
        let immediately: Bool
    }

    var activitiesEnabled = true
    private var activities: [TimetableActivityDescriptor]
    private var requestSequence = 0
    private(set) var requests: [Request] = []
    private(set) var updates: [Update] = []
    private(set) var ends: [End] = []
    private(set) var operations: [String] = []

    init(activities: [TimetableActivityDescriptor] = []) { self.activities = activities }

    func activityDescriptors() -> [TimetableActivityDescriptor] { activities }

    func request(attributes: TimetableActivityAttributes,
                 state: TimetableActivityAttributes.ContentState, staleDate: Date?) throws -> String {
        requestSequence += 1
        let id = "requested-\(requestSequence)"
        requests.append(.init(attributes: attributes, state: state, staleDate: staleDate))
        operations.append("request:\(attributes.profileIdentity.storageKey)")
        activities.append(.init(id: id, attributes: attributes))
        return id
    }

    func update(id: String, state: TimetableActivityAttributes.ContentState, staleDate: Date?) async {
        updates.append(.init(id: id, state: state))
        operations.append("update:\(id)")
    }

    func end(id: String, immediately: Bool) async {
        ends.append(.init(id: id, immediately: immediately))
        operations.append("end:\(id)")
        activities.removeAll { $0.id == id }
    }

    func clearRecords() {
        requests.removeAll()
        updates.removeAll()
        ends.removeAll()
        operations.removeAll()
    }
}
