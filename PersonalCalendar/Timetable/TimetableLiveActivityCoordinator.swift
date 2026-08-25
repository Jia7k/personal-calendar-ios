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
    private struct PendingReconciliation {
        let catalog: TimetableWidgetCatalogV1
        let now: Date
    }

    private struct PendingStart {
        let profile: TimetableWidgetProfile
        let now: Date
    }

    private(set) var status: TimetableLiveActivityStatus = .idle

    @ObservationIgnored private let driver: any TimetableActivityDriving
    @ObservationIgnored private var calendar: Calendar
    @ObservationIgnored private var isWriting = false
    @ObservationIgnored private var pendingStop = false
    @ObservationIgnored private var pendingStart: PendingStart?
    @ObservationIgnored private var pendingReconciliation: PendingReconciliation?

    init(driver: any TimetableActivityDriving, calendar: Calendar) {
        self.driver = driver
        self.calendar = calendar
    }

    var activeProfileIdentity: ProfileIdentity? {
        driver.activityDescriptors().first?.attributes.profileIdentity
    }

    var activeProfileName: String? {
        driver.activityDescriptors().first?.attributes.profileName
    }

    func start(profile: TimetableWidgetProfile, now: Date = .now) async {
        guard beginWriting() else {
            pendingStart = .init(profile: profile, now: now)
            return
        }
        await performStart(profile: profile, now: now)
        await finishWriting()
    }

    func reconcile(catalog: TimetableWidgetCatalogV1, now: Date = .now) async {
        guard beginWriting() else {
            pendingReconciliation = .init(catalog: catalog, now: now)
            return
        }
        await performReconciliation(catalog: catalog, now: now)
        await finishWriting()
    }

    func stop() async {
        guard beginWriting() else {
            pendingStop = true
            pendingStart = nil
            pendingReconciliation = nil
            return
        }
        await end(driver.activityDescriptors().map(\.id), immediately: true)
        status = .idle
        await finishWriting()
    }

    private func performStart(profile: TimetableWidgetProfile, now: Date) async {
        let snapshot = profile.snapshot
        let descriptors = driver.activityDescriptors()

        if let message = unavailableMessage(for: snapshot, now: now) {
            await end(descriptors.map(\.id), immediately: true)
            status = .unavailable(message)
            return
        }
        guard driver.activitiesEnabled else {
            await end(descriptors.map(\.id), immediately: true)
            status = .unavailable("Live Activities are disabled.")
            return
        }

        let expected = attributes(for: profile)
        if let matching = descriptors.first(where: { $0.attributes == expected }) {
            await driver.update(
                id: matching.id,
                state: .init(snapshot: snapshot),
                staleDate: nextBoundary(in: snapshot, after: now)
            )
            await end(
                descriptors.lazy.filter { $0.id != matching.id }.map(\.id),
                immediately: true
            )
            status = .running
            return
        }

        await end(descriptors.map(\.id), immediately: true)
        request(profile: profile, now: now)
    }

    private func performReconciliation(
        catalog: TimetableWidgetCatalogV1,
        now: Date
    ) async {
        let descriptors = driver.activityDescriptors()
        guard !descriptors.isEmpty else {
            status = .idle
            return
        }
        guard driver.activitiesEnabled else {
            await end(descriptors.map(\.id), immediately: true)
            status = .unavailable("Live Activities are disabled.")
            return
        }

        var handledProfiles: Set<ProfileIdentity> = []
        var keptActivity = false
        var replacementFailed = false

        for descriptor in descriptors {
            guard !descriptor.attributes.isLegacy else {
                await driver.end(id: descriptor.id, immediately: true)
                continue
            }
            let identity = descriptor.attributes.profileIdentity
            guard handledProfiles.insert(identity).inserted else {
                await driver.end(id: descriptor.id, immediately: true)
                continue
            }
            guard let profile = catalog.profile(for: identity) else {
                await driver.end(id: descriptor.id, immediately: true)
                continue
            }
            guard unavailableMessage(for: profile.snapshot, now: now) == nil else {
                await driver.end(id: descriptor.id, immediately: true)
                continue
            }

            let state = TimetableActivityAttributes.ContentState(snapshot: profile.snapshot)
            let staleDate = nextBoundary(in: profile.snapshot, after: now)
            if descriptor.attributes == attributes(for: profile) {
                await driver.update(id: descriptor.id, state: state, staleDate: staleDate)
                keptActivity = true
            } else {
                await driver.end(id: descriptor.id, immediately: true)
                do {
                    _ = try driver.request(
                        attributes: attributes(for: profile),
                        state: state,
                        staleDate: staleDate
                    )
                    keptActivity = true
                } catch {
                    replacementFailed = true
                    status = .failed(error.localizedDescription)
                }
            }
        }

        if !replacementFailed {
            status = keptActivity ? .running : .idle
        }
    }

    private func request(profile: TimetableWidgetProfile, now: Date) {
        do {
            _ = try driver.request(
                attributes: attributes(for: profile),
                state: .init(snapshot: profile.snapshot),
                staleDate: nextBoundary(in: profile.snapshot, after: now)
            )
            status = .running
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    private func attributes(for profile: TimetableWidgetProfile) -> TimetableActivityAttributes {
        TimetableActivityAttributes(
            profileIdentity: profile.id,
            profileName: profile.name,
            weekStart: profile.snapshot.weekStart,
            timeZoneIdentifier: profile.snapshot.timeZoneIdentifier
        )
    }

    private func unavailableMessage(
        for snapshot: TimetableSnapshotV1,
        now: Date
    ) -> String? {
        switch snapshot.availability {
        case .calendarAccessRequired:
            return "Calendar access is required."
        case .emptyProfile:
            return "This profile has no calendars."
        case .noClasses:
            return "There are no events this week."
        case .ready:
            break
        }
        let snapshotCalendar = calendar(for: snapshot)
        guard snapshot.entries.contains(where: {
            snapshotCalendar.isDate($0.start, inSameDayAs: now)
        }) else {
            return "There are no events today."
        }
        return nil
    }

    private func nextBoundary(in snapshot: TimetableSnapshotV1, after now: Date) -> Date? {
        let snapshotCalendar = calendar(for: snapshot)
        return snapshot.entries
            .filter { snapshotCalendar.isDate($0.start, inSameDayAs: now) }
            .flatMap { [$0.start, $0.end] }
            .filter { $0 > now }
            .min()
    }

    private func calendar(for snapshot: TimetableSnapshotV1) -> Calendar {
        var value = calendar
        value.timeZone = TimeZone(identifier: snapshot.timeZoneIdentifier) ?? calendar.timeZone
        return value
    }

    private func beginWriting() -> Bool {
        guard !isWriting else { return false }
        isWriting = true
        return true
    }

    private func finishWriting() async {
        isWriting = false
        if pendingStop {
            pendingStop = false
            pendingStart = nil
            pendingReconciliation = nil
            await stop()
        } else if let pendingStart {
            self.pendingStart = nil
            await start(profile: pendingStart.profile, now: pendingStart.now)
        } else if let pendingReconciliation {
            self.pendingReconciliation = nil
            await reconcile(
                catalog: pendingReconciliation.catalog,
                now: pendingReconciliation.now
            )
        }
    }

    private func end<S: Sequence>(_ IDs: S, immediately: Bool) async where S.Element == String {
        for id in IDs {
            await driver.end(id: id, immediately: immediately)
        }
    }
}
