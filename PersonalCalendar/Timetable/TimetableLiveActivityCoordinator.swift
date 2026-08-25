import Foundation
import Observation

enum TimetableLiveActivityStatus: Equatable {
    case idle
    case unavailable(String)
    case running
    case failed(String)
}

@MainActor
@Observable
final class TimetableLiveActivityCoordinator {
    private(set) var status: TimetableLiveActivityStatus = .idle

    @ObservationIgnored private let driver: any TimetableActivityDriving
    @ObservationIgnored private var calendar: Calendar
    @ObservationIgnored private var isWriting = false

    init(driver: any TimetableActivityDriving, calendar: Calendar) {
        self.driver = driver
        self.calendar = calendar
    }

    func start(snapshot: TimetableSnapshotV1, now: Date = .now) async {
        guard !isWriting else { return }
        isWriting = true
        defer { isWriting = false }

        guard await prepare(snapshot: snapshot, now: now) else { return }

        let state = TimetableActivityAttributes.ContentState(snapshot: snapshot)
        let staleDate = nextBoundary(in: snapshot, after: now)
        let IDs = driver.activityIDs()

        if let primaryID = IDs.first {
            await driver.update(id: primaryID, state: state, staleDate: staleDate)
            await end(IDs.dropFirst(), immediately: true)
            status = .running
            return
        }

        do {
            _ = try driver.request(
                attributes: TimetableActivityAttributes(
                    weekStart: snapshot.weekStart,
                    timeZoneIdentifier: snapshot.timeZoneIdentifier
                ),
                state: state,
                staleDate: staleDate
            )
            status = .running
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    func reconcile(snapshot: TimetableSnapshotV1, now: Date = .now) async {
        guard !isWriting else { return }
        isWriting = true
        defer { isWriting = false }

        guard await prepare(snapshot: snapshot, now: now) else { return }

        let IDs = driver.activityIDs()
        guard let primaryID = IDs.first else {
            status = .idle
            return
        }

        await driver.update(
            id: primaryID,
            state: TimetableActivityAttributes.ContentState(snapshot: snapshot),
            staleDate: nextBoundary(in: snapshot, after: now)
        )
        await end(IDs.dropFirst(), immediately: true)
        status = .running
    }

    func stop() async {
        guard !isWriting else { return }
        isWriting = true
        defer { isWriting = false }

        await end(driver.activityIDs()[...], immediately: true)
        status = .idle
    }

    private func prepare(snapshot: TimetableSnapshotV1, now: Date) async -> Bool {
        guard snapshot.availability == .ready else {
            await end(driver.activityIDs()[...], immediately: true)
            status = .unavailable("Calendar access is required.")
            return false
        }
        guard driver.activitiesEnabled else {
            status = .unavailable("Live Activities are disabled.")
            return false
        }
        guard snapshot.entries.contains(where: { calendar.isDate($0.start, inSameDayAs: now) }) else {
            await end(driver.activityIDs()[...], immediately: true)
            status = .unavailable("There are no classes today.")
            return false
        }
        return true
    }

    private func nextBoundary(in snapshot: TimetableSnapshotV1, after now: Date) -> Date? {
        snapshot.entries
            .filter { calendar.isDate($0.start, inSameDayAs: now) }
            .flatMap { [$0.start, $0.end] }
            .filter { $0 > now }
            .min()
    }

    private func end<S: Sequence>(_ IDs: S, immediately: Bool) async where S.Element == String {
        for id in IDs {
            await driver.end(id: id, immediately: immediately)
        }
    }
}
