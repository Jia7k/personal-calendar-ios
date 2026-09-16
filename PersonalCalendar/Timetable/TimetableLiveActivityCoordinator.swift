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
    private struct ActivityContentProjection {
        let state: TimetableActivityAttributes.ContentState
        let staleDate: Date?
    }

    private struct PendingReconciliation {
        let catalog: TimetableWidgetCatalogV1
        let now: Date
    }

    private struct PendingStart {
        let profile: TimetableWidgetProfile
        let now: Date
    }

    private enum DailyIntent {
        case start(ProfileIdentity)
        case reconcile
    }

    private struct PendingDailyIntent {
        let intent: DailyIntent
        let now: Date
        let generation: UInt64
    }

    private(set) var status: TimetableLiveActivityStatus = .idle

    @ObservationIgnored private let driver: any TimetableActivityDriving
    @ObservationIgnored private var calendar: Calendar
    @ObservationIgnored private var isWriting = false
    @ObservationIgnored private var pendingStop = false
    @ObservationIgnored private var pendingStart: PendingStart?
    @ObservationIgnored private var pendingReconciliation: PendingReconciliation?
    @ObservationIgnored private let dailySnapshots: (any DailyActivitySnapshotProviding)?
    @ObservationIgnored private var dailyGeneration: UInt64 = 0
    @ObservationIgnored private var pendingDailyIntent: PendingDailyIntent?
    @ObservationIgnored private var activeDailyIntent: DailyIntent?

    init(
        driver: any TimetableActivityDriving,
        calendar: Calendar,
        dailySnapshots: (any DailyActivitySnapshotProviding)? = nil
    ) {
        self.driver = driver
        self.calendar = calendar
        self.dailySnapshots = dailySnapshots
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

    func applyForegroundPreference(
        isEnabled: Bool,
        preferredProfileIdentity: ProfileIdentity?,
        catalog: TimetableWidgetCatalogV1,
        now: Date = .now
    ) async {
        guard isEnabled else { return }
        guard let preferredProfileIdentity,
              let profile = catalog.profile(for: preferredProfileIdentity) else {
            await stop()
            return
        }
        await start(profile: profile, now: now)
    }

    func applyPreferenceSelectionChange(
        wasAutomaticallyEnabled: Bool,
        preferredProfileIdentity: ProfileIdentity?,
        catalog: TimetableWidgetCatalogV1?,
        now: Date = .now
    ) async {
        guard wasAutomaticallyEnabled else { return }
        guard let catalog else {
            await stop()
            return
        }
        await applyForegroundPreference(
            isEnabled: true,
            preferredProfileIdentity: preferredProfileIdentity,
            catalog: catalog,
            now: now
        )
    }

    func applyAutomaticStartSettingChange(
        isEnabled: Bool,
        preferredProfileIdentity: ProfileIdentity?,
        catalog: TimetableWidgetCatalogV1?,
        now: Date = .now
    ) async {
        guard isEnabled, let catalog else {
            await stop()
            return
        }
        await applyForegroundPreference(
            isEnabled: true,
            preferredProfileIdentity: preferredProfileIdentity,
            catalog: catalog,
            now: now
        )
    }

    func stop() async {
        dailyGeneration &+= 1
        pendingDailyIntent = nil
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
        guard let content = activityContent(for: snapshot, now: now) else {
            await end(descriptors.map(\.id), immediately: true)
            status = .failed("The timetable is too large for a Live Activity.")
            return
        }

        let expected = attributes(for: profile)
        if let matching = descriptors.first(where: { $0.attributes == expected }) {
            await driver.update(
                id: matching.id,
                state: content.state,
                staleDate: content.staleDate
            )
            await end(
                descriptors.lazy.filter { $0.id != matching.id }.map(\.id),
                immediately: true
            )
            status = .running
            return
        }

        await end(descriptors.map(\.id), immediately: true)
        request(profile: profile, content: content)
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
            guard let content = activityContent(for: profile.snapshot, now: now) else {
                await driver.end(id: descriptor.id, immediately: true)
                replacementFailed = true
                status = .failed("The timetable is too large for a Live Activity.")
                continue
            }

            if descriptor.attributes == attributes(for: profile) {
                await driver.update(
                    id: descriptor.id,
                    state: content.state,
                    staleDate: content.staleDate
                )
                keptActivity = true
            } else {
                await driver.end(id: descriptor.id, immediately: true)
                do {
                    _ = try driver.request(
                        attributes: attributes(for: profile),
                        state: content.state,
                        staleDate: content.staleDate
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

    private func request(
        profile: TimetableWidgetProfile,
        content: ActivityContentProjection
    ) {
        do {
            _ = try driver.request(
                attributes: attributes(for: profile),
                state: content.state,
                staleDate: content.staleDate
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

    private func activityContent(
        for snapshot: TimetableSnapshotV1,
        now: Date
    ) -> ActivityContentProjection? {
        guard let state = TimetableActivityAttributes.ContentState.projecting(
            snapshot: snapshot,
            now: now,
            calendar: calendar(for: snapshot)
        ) else { return nil }
        return ActivityContentProjection(
            state: state,
            staleDate: state.nextBoundary(after: now)
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
            ($0.start <= now && now < $0.end)
                || (snapshotCalendar.isDate($0.start, inSameDayAs: now) && $0.start > now)
        }) else {
            return "There are no events today."
        }
        return nil
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
            // stop() already invalidated the operation that was running. A new
            // explicit start queued after it (for example after restore) must
            // survive; calling stop() again would invalidate that newer intent.
            guard beginWriting() else { return }
            await end(driver.activityDescriptors().map(\.id), immediately: true)
            status = .idle
            await finishWriting()
        } else if let pendingDailyIntent {
            self.pendingDailyIntent = nil
            guard beginWriting() else { return }
            await performDaily(pendingDailyIntent)
            await finishWriting()
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

    // Daily callers are independent of the persisted weekly widget catalog.
    func start(profileIdentity: ProfileIdentity, now: Date = .now) async {
        await enqueueDaily(.start(profileIdentity), now: now)
    }

    func reconcileActive(now: Date = .now) async {
        await enqueueDaily(.reconcile, now: now)
    }

    func applyForegroundPreference(
        isEnabled: Bool,
        preferredProfileIdentity: ProfileIdentity?,
        now: Date = .now
    ) async {
        guard isEnabled else { return }
        guard let preferredProfileIdentity else { await stop(); return }
        await start(profileIdentity: preferredProfileIdentity, now: now)
    }

    func applyPreferenceSelectionChange(
        wasAutomaticallyEnabled: Bool,
        preferredProfileIdentity: ProfileIdentity?,
        now: Date = .now
    ) async {
        await applyForegroundPreference(isEnabled: wasAutomaticallyEnabled, preferredProfileIdentity: preferredProfileIdentity, now: now)
    }

    func applyAutomaticStartSettingChange(
        isEnabled: Bool,
        preferredProfileIdentity: ProfileIdentity?,
        now: Date = .now
    ) async {
        guard isEnabled else { await stop(); return }
        await applyForegroundPreference(isEnabled: true, preferredProfileIdentity: preferredProfileIdentity, now: now)
    }

    private func enqueueDaily(_ intent: DailyIntent, now: Date) async {
        if pendingStop, pendingDailyIntent == nil, case .reconcile = intent {
            return
        }
        dailyGeneration &+= 1
        var queued = PendingDailyIntent(intent: intent, now: now, generation: dailyGeneration)
        if isWriting {
            // A background refresh must not discard a queued explicit profile choice.
            if case .reconcile = intent,
               let selectedIntent = pendingDailyIntent?.intent ?? activeDailyIntent,
               case .start = selectedIntent {
                queued = PendingDailyIntent(intent: selectedIntent, now: now, generation: dailyGeneration)
            }
            pendingDailyIntent = queued
            return
        }
        guard beginWriting() else { return }
        await performDaily(queued)
        await finishWriting()
    }

    private func performDaily(_ operation: PendingDailyIntent) async {
        guard operation.generation == dailyGeneration else { return }
        activeDailyIntent = operation.intent
        defer { activeDailyIntent = nil }
        let descriptors = driver.activityDescriptors()
        let identity: ProfileIdentity
        switch operation.intent {
        case let .start(selected): identity = selected
        case .reconcile:
            guard let active = descriptors.first else { status = .idle; return }
            identity = active.attributes.profileIdentity
        }
        guard let dailySnapshots else {
            status = .failed("The daily schedule is unavailable. Open the app and try again.")
            return
        }
        do {
            let snapshot = try await dailySnapshots.snapshot(for: identity, now: operation.now)
            guard operation.generation == dailyGeneration else { return }
            let presentation = DailyActivityPresentation.make(snapshot: snapshot, now: operation.now, rowLimit: 3)
            guard driver.activitiesEnabled,
                  presentation.remainingCount > 0,
                  !presentation.requiresRefresh else {
                await end(descriptors.map(\.id), immediately: true)
                guard operation.generation == dailyGeneration else { return }
                if !driver.activitiesEnabled {
                    status = .unavailable("Live Activities are disabled.")
                } else if snapshot.calendarUnavailable || snapshot.tasksUnavailable {
                    status = .unavailable("Some sources are unavailable. Check access and refresh your day.")
                } else {
                    status = .unavailable("There are no remaining events or tasks today.")
                }
                return
            }
            let matching = descriptors.first { descriptor in
                guard !descriptor.attributes.isLegacy,
                      let end = descriptor.attributes.activityEndsAt,
                      end > operation.now else { return false }
                return descriptor.attributes == TimetableActivityAttributes(
                    snapshot: snapshot, startedAt: descriptor.attributes.activityStartedAt
                )
            }
            // Updating content must not reset the system's eight-hour lifetime.
            let attributes = matching?.attributes ?? TimetableActivityAttributes(
                snapshot: snapshot, startedAt: operation.now
            )
            guard let payload = DailyActivityPayload.make(snapshot: snapshot, attributes: attributes, now: operation.now) else {
                await end(descriptors.map(\.id), immediately: true)
                guard operation.generation == dailyGeneration else { return }
                status = .failed("The daily schedule could not fit in a Live Activity.")
                return
            }
            let state = TimetableActivityAttributes.ContentState(daily: payload)
            let staleDate = min(snapshot.dayEnd, snapshot.generatedAt.addingTimeInterval(TimetableFreshness.defaultThreshold))
            await end(descriptors.filter { $0.id != matching?.id }.map(\.id), immediately: true)
            guard operation.generation == dailyGeneration else { return }
            if let matching {
                await driver.update(id: matching.id, state: state, staleDate: staleDate)
            } else {
                _ = try driver.request(attributes: attributes, state: state, staleDate: staleDate)
            }
            guard operation.generation == dailyGeneration else { return }
            status = .running
        } catch DailyActivitySnapshotCoordinatorError.superseded {
            // A scope/authorization refresh owns the replacement. Never terminate
            // an activity using a rejected, out-of-date snapshot request.
            return
        } catch {
            guard operation.generation == dailyGeneration else { return }
            await end(descriptors.map(\.id), immediately: true)
            guard operation.generation == dailyGeneration else { return }
            status = .failed("The daily schedule could not refresh. Open the app and try again.")
        }
    }
}
