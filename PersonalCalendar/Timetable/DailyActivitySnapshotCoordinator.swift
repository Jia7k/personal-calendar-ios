import Foundation
import Observation

@MainActor
protocol DailyActivitySnapshotProviding: AnyObject {
    func snapshot(
        for profile: ProfileIdentity,
        now: Date
    ) async throws -> DailyActivitySnapshot

    func invalidate()
}

enum DailyActivitySnapshotCoordinatorError: Error, Equatable, Sendable {
    case invalidDate
    case superseded
}

@MainActor
@Observable
final class DailyActivitySnapshotCoordinator: DailyActivitySnapshotProviding {
    private struct SourceContext: Equatable {
        let profile: DailyActivityProfile
        let configuredCalendarIDs: Set<String>
        let configuredReminderListIDs: Set<String>
        let scope: ProfileScope
        let calendarAccess: AccessState
        let reminderAccess: AccessState
        let calendarUnavailable: Bool
        let tasksUnavailable: Bool
    }

    private struct CacheKey: Hashable {
        let profile: ProfileIdentity
        let dayStart: Date
        let dayEnd: Date
        let timeZoneIdentifier: String
    }

    private struct CacheEntry {
        let context: SourceContext
        let requestSequence: UInt64
        let snapshot: DailyActivitySnapshot
    }

    private let profiles: any ProfileRepository
    private let calendar: any CalendarServicing
    private let reminders: any RemindersServicing
    private let localCalendar: Calendar
    private let calendarProvider: (@MainActor () -> Calendar)?

    private var cache: [CacheKey: CacheEntry] = [:]
    private var requestSequences: [CacheKey: UInt64] = [:]
    private var observedTimeZoneIdentifier: String?

    private(set) var revision = 0

    init(
        profiles: any ProfileRepository,
        calendar: any CalendarServicing,
        reminders: any RemindersServicing,
        localCalendar: Calendar,
        calendarProvider: (@MainActor () -> Calendar)? = nil
    ) {
        self.profiles = profiles
        self.calendar = calendar
        self.reminders = reminders
        self.localCalendar = localCalendar
        self.calendarProvider = calendarProvider
    }

    func snapshot(
        for profileIdentity: ProfileIdentity,
        now: Date
    ) async throws -> DailyActivitySnapshot {
        let requestCalendar = capturedCalendar()
        guard now.timeIntervalSinceReferenceDate.isFinite,
              let cacheKey = cacheKey(
                for: profileIdentity,
                now: now,
                calendar: requestCalendar
              ) else {
            invalidate()
            throw DailyActivitySnapshotCoordinatorError.invalidDate
        }
        observe(timeZoneIdentifier: cacheKey.timeZoneIdentifier)

        let startingContext: SourceContext
        do {
            startingContext = try sourceContext(for: profileIdentity)
        } catch {
            invalidate()
            throw error
        }
        if let cached = cache[cacheKey], cached.context == startingContext {
            return cached.snapshot
        }
        cache[cacheKey] = nil

        let startingRevision = revision
        let requestSequence = nextRequestSequence(for: cacheKey)

        let fetchedEvents: [CalendarEventSnapshot]
        let fetchedReminders: [ReminderSnapshot]
        do {
            if startingContext.scope.calendarIDs.isEmpty {
                fetchedEvents = []
            } else {
                fetchedEvents = try calendar.fetchEvents(
                    in: DateInterval(start: cacheKey.dayStart, end: cacheKey.dayEnd),
                    calendarIDs: startingContext.scope.calendarIDs
                )
            }

            if startingContext.scope.reminderListIDs.isEmpty {
                fetchedReminders = []
            } else {
                fetchedReminders = try await reminders.fetchReminders(
                    listIDs: startingContext.scope.reminderListIDs
                )
            }
        } catch {
            guard revision == startingRevision else {
                throw DailyActivitySnapshotCoordinatorError.superseded
            }
            invalidate()
            throw error
        }

        guard revision == startingRevision else {
            throw DailyActivitySnapshotCoordinatorError.superseded
        }

        let validationCalendar = capturedCalendar()
        guard self.cacheKey(
            for: profileIdentity,
            now: now,
            calendar: validationCalendar
        ) == cacheKey else {
            invalidate()
            observedTimeZoneIdentifier = validationCalendar.timeZone.identifier
            throw DailyActivitySnapshotCoordinatorError.superseded
        }

        let currentContext: SourceContext
        do {
            currentContext = try sourceContext(for: profileIdentity)
        } catch {
            invalidate()
            throw error
        }
        guard currentContext == startingContext else {
            throw DailyActivitySnapshotCoordinatorError.superseded
        }

        let scopedEvents = fetchedEvents.filter {
            currentContext.scope.calendarIDs.contains($0.calendarID)
        }
        let scopedReminders = fetchedReminders.filter {
            currentContext.scope.reminderListIDs.contains($0.listID)
        }
        let value = DailyActivitySnapshotBuilder(calendar: requestCalendar).makeSnapshot(
            profile: currentContext.profile,
            scope: currentContext.scope,
            events: scopedEvents,
            reminders: scopedReminders,
            now: now,
            calendarUnavailable: currentContext.calendarUnavailable,
            tasksUnavailable: currentContext.tasksUnavailable
        )

        guard revision == startingRevision else {
            throw DailyActivitySnapshotCoordinatorError.superseded
        }
        if let winner = cache[cacheKey],
           winner.context == currentContext,
           winner.requestSequence > requestSequence {
            return winner.snapshot
        }
        cache[cacheKey] = CacheEntry(
            context: currentContext,
            requestSequence: requestSequence,
            snapshot: value
        )
        return value
    }

    func invalidate() {
        revision &+= 1
        cache.removeAll(keepingCapacity: true)
        requestSequences.removeAll(keepingCapacity: true)
    }

    private func sourceContext(
        for identity: ProfileIdentity
    ) throws -> SourceContext {
        let activityProfile: DailyActivityProfile
        let membership: ProfileMembership
        switch identity {
        case .everything:
            activityProfile = DailyActivityProfile(
                id: .everything,
                name: "Everything",
                symbolName: "rectangle.3.group.fill"
            )
            membership = try profiles.unionMembership()

        case let .saved(id):
            let profile = try profiles.profile(id: id)
            activityProfile = DailyActivityProfile(
                id: identity,
                name: profile.name,
                symbolName: profile.symbolName
            )
            membership = ProfileMembership(
                calendarIDs: profile.calendarIDs,
                reminderListIDs: profile.reminderListIDs,
                routineIDs: profile.routineIDs
            )
        }

        let calendarAccess = calendar.accessState
        let reminderAccess = reminders.accessState
        let availableCalendarIDs = calendarAccess == .granted
            ? Set(calendar.calendars().map(\.id))
            : []
        let availableReminderListIDs = reminderAccess == .granted
            ? Set(reminders.lists().map(\.id))
            : []
        let resolvedCalendarIDs = membership.calendarIDs.intersection(availableCalendarIDs)
        let resolvedReminderListIDs = membership.reminderListIDs.intersection(
            availableReminderListIDs
        )
        let scope = ProfileScope(
            identity: identity,
            calendarIDs: resolvedCalendarIDs,
            reminderListIDs: resolvedReminderListIDs,
            routineIDs: membership.routineIDs,
            defaultCalendarID: nil,
            defaultReminderListID: nil
        )

        return SourceContext(
            profile: activityProfile,
            configuredCalendarIDs: membership.calendarIDs,
            configuredReminderListIDs: membership.reminderListIDs,
            scope: scope,
            calendarAccess: calendarAccess,
            reminderAccess: reminderAccess,
            calendarUnavailable: sourceIsUnavailable(
                configured: membership.calendarIDs,
                available: availableCalendarIDs,
                access: calendarAccess
            ),
            tasksUnavailable: sourceIsUnavailable(
                configured: membership.reminderListIDs,
                available: availableReminderListIDs,
                access: reminderAccess
            )
        )
    }

    private func sourceIsUnavailable(
        configured: Set<String>,
        available: Set<String>,
        access: AccessState
    ) -> Bool {
        guard !configured.isEmpty else { return false }
        return access != .granted || !configured.subtracting(available).isEmpty
    }

    private func cacheKey(
        for profile: ProfileIdentity,
        now: Date,
        calendar: Calendar
    ) -> CacheKey? {
        let dayStart = calendar.startOfDay(for: now)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        guard dayStart.timeIntervalSinceReferenceDate.isFinite,
              dayEnd.timeIntervalSinceReferenceDate.isFinite,
              dayEnd > dayStart else { return nil }
        return CacheKey(
            profile: profile,
            dayStart: dayStart,
            dayEnd: dayEnd,
            timeZoneIdentifier: calendar.timeZone.identifier
        )
    }

    private func observe(timeZoneIdentifier: String) {
        if let observedTimeZoneIdentifier,
           observedTimeZoneIdentifier != timeZoneIdentifier {
            invalidate()
        }
        observedTimeZoneIdentifier = timeZoneIdentifier
    }

    private func capturedCalendar() -> Calendar {
        var calendar = calendarProvider?() ?? localCalendar
        let timeZoneIdentifier = calendar.timeZone.identifier
        if let capturedTimeZone = TimeZone(identifier: timeZoneIdentifier) {
            calendar.timeZone = capturedTimeZone
        }
        return calendar
    }

    private func nextRequestSequence(for key: CacheKey) -> UInt64 {
        let next = (requestSequences[key] ?? 0) &+ 1
        requestSequences[key] = next
        return next
    }

}
