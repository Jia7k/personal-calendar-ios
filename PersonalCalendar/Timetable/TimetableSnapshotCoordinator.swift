import Foundation
import Observation
import WidgetKit

@MainActor
protocol TimetableWidgetReloading: AnyObject {
    func reloadTimetableWidgets()
}

@MainActor
final class SystemTimetableWidgetReloader: TimetableWidgetReloading {
    func reloadTimetableWidgets() {
        WidgetCenter.shared.reloadTimelines(ofKind: "NextClassWidget")
        WidgetCenter.shared.reloadTimelines(ofKind: "WeekTimetableWidget")
    }
}

@MainActor
@Observable
final class TimetableSnapshotCoordinator {
    private enum Destination {
        case legacy(
            settings: AppSettingsStore,
            writer: any TimetableSnapshotWriting
        )
        case catalog(
            profiles: any ProfileRepository,
            writer: any TimetableWidgetCatalogWriting,
            onFailClosed: @MainActor () -> Void
        )
    }

    private(set) var latestSnapshot: TimetableSnapshotV1?
    private(set) var latestCatalog: TimetableWidgetCatalogV1?
    private(set) var errorMessage: String?

    @ObservationIgnored private let calendar: any CalendarServicing
    @ObservationIgnored private let builder: TimetableSnapshotBuilder
    @ObservationIgnored private let destination: Destination
    @ObservationIgnored private let reloader: any TimetableWidgetReloading

    init(
        calendar: any CalendarServicing,
        settings: AppSettingsStore,
        builder: TimetableSnapshotBuilder,
        writer: any TimetableSnapshotWriting,
        reloader: any TimetableWidgetReloading
    ) {
        self.calendar = calendar
        self.builder = builder
        destination = .legacy(settings: settings, writer: writer)
        self.reloader = reloader
    }

    init(
        calendar: any CalendarServicing,
        profiles: any ProfileRepository,
        builder: TimetableSnapshotBuilder,
        writer: any TimetableWidgetCatalogWriting,
        reloader: any TimetableWidgetReloading,
        onFailClosed: @escaping @MainActor () -> Void = {}
    ) {
        self.calendar = calendar
        self.builder = builder
        destination = .catalog(
            profiles: profiles,
            writer: writer,
            onFailClosed: onFailClosed
        )
        self.reloader = reloader
    }

    @discardableResult
    func refresh(now: Date = .now, failClosed: Bool = false) throws -> TimetableSnapshotV1 {
        switch destination {
        case let .legacy(settings, writer):
            return try refreshLegacy(now: now, settings: settings, writer: writer)
        case let .catalog(profiles, writer, onFailClosed):
            return try refreshCatalog(
                now: now,
                profiles: profiles,
                writer: writer,
                failClosed: failClosed,
                onFailClosed: onFailClosed
            )
        }
    }

    private func refreshLegacy(
        now: Date,
        settings: AppSettingsStore,
        writer: any TimetableSnapshotWriting
    ) throws -> TimetableSnapshotV1 {
        do {
            let events: [CalendarEventSnapshot]
            if calendar.accessState == .granted {
                let availableIDs = Set(calendar.calendars().map(\.id))
                let visibleIDs = settings.visibleCalendarIDs(availableIDs: availableIDs)
                events = visibleIDs.isEmpty
                    ? []
                    : try calendar.fetchEvents(
                        in: builder.weekInterval(containing: now),
                        calendarIDs: visibleIDs
                    )
            } else {
                events = []
            }

            let snapshot = builder.makeSnapshot(
                access: calendar.accessState,
                events: events,
                now: now
            )
            try writer.write(snapshot)
            latestSnapshot = snapshot
            latestCatalog = nil
            errorMessage = nil
            reloader.reloadTimetableWidgets()
            return snapshot
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    private func refreshCatalog(
        now: Date,
        profiles repository: any ProfileRepository,
        writer: any TimetableWidgetCatalogWriting,
        failClosed: Bool,
        onFailClosed: @MainActor () -> Void
    ) throws -> TimetableSnapshotV1 {
        let access = calendar.accessState
        var mustFailClosed = failClosed || access != .granted
        do {
            let savedProfiles = try repository.list()
            let assignedIDs = savedProfiles.reduce(into: Set<String>()) {
                $0.formUnion($1.calendarIDs)
            }
            let availableIDs = access == .granted
                ? Set(calendar.calendars().map(\.id))
                : []
            let fetchIDs = assignedIDs.intersection(availableIDs)
            mustFailClosed = mustFailClosed || fetchIDs != assignedIDs
            let events: [CalendarEventSnapshot]
            if access == .granted, !fetchIDs.isEmpty {
                events = try calendar.fetchEvents(
                    in: builder.weekInterval(containing: now),
                    calendarIDs: fetchIDs
                ).filter { fetchIDs.contains($0.calendarID) }
            } else {
                events = []
            }

            let catalog = makeCatalog(
                profiles: savedProfiles,
                access: access,
                events: events,
                now: now
            )
            try writer.write(catalog)
            guard let everything = catalog.snapshot(for: .everything) else {
                throw TimetableSnapshotStoreError.invalidCatalog
            }

            latestCatalog = catalog
            latestSnapshot = everything
            errorMessage = nil
            reloader.reloadTimetableWidgets()
            return everything
        } catch {
            errorMessage = error.localizedDescription
            if mustFailClosed {
                try? writer.delete()
                latestCatalog = nil
                latestSnapshot = nil
                reloader.reloadTimetableWidgets()
                onFailClosed()
            }
            throw error
        }
    }

    private func makeCatalog(
        profiles: [ProfileSnapshot],
        access: AccessState,
        events: [CalendarEventSnapshot],
        now: Date
    ) -> TimetableWidgetCatalogV1 {
        let assignedIDs = profiles.reduce(into: Set<String>()) {
            $0.formUnion($1.calendarIDs)
        }
        let everythingSnapshot = makeSnapshot(
            membership: assignedIDs,
            access: access,
            events: events,
            now: now
        )
        let everything = TimetableWidgetProfile(
            id: .everything,
            name: "Everything",
            colorHex: "#4F6F64",
            symbolName: "rectangle.3.group.fill",
            snapshot: everythingSnapshot
        )
        let saved = profiles.map { profile in
            TimetableWidgetProfile(
                id: .saved(profile.id),
                name: profile.name,
                colorHex: profile.colorHex,
                symbolName: profile.symbolName,
                snapshot: makeSnapshot(
                    membership: profile.calendarIDs,
                    access: access,
                    events: events.filter { profile.calendarIDs.contains($0.calendarID) },
                    now: now
                )
            )
        }

        return TimetableWidgetCatalogV1(
            version: TimetableWidgetCatalogV1.currentVersion,
            generatedAt: now,
            profiles: [everything] + saved
        )
    }

    private func makeSnapshot(
        membership: Set<String>,
        access: AccessState,
        events: [CalendarEventSnapshot],
        now: Date
    ) -> TimetableSnapshotV1 {
        let availability: TimetableAvailability
        if access != .granted {
            availability = .calendarAccessRequired
        } else if membership.isEmpty {
            availability = .emptyProfile
        } else {
            availability = .ready
        }
        return builder.makeSnapshot(
            availability: availability,
            events: events,
            now: now
        )
    }
}
