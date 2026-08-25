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
    private(set) var latestSnapshot: TimetableSnapshotV1?
    private(set) var errorMessage: String?

    @ObservationIgnored private let calendar: any CalendarServicing
    @ObservationIgnored private let settings: AppSettingsStore
    @ObservationIgnored private let builder: TimetableSnapshotBuilder
    @ObservationIgnored private let writer: any TimetableSnapshotWriting
    @ObservationIgnored private let reloader: any TimetableWidgetReloading

    init(
        calendar: any CalendarServicing,
        settings: AppSettingsStore,
        builder: TimetableSnapshotBuilder,
        writer: any TimetableSnapshotWriting,
        reloader: any TimetableWidgetReloading
    ) {
        self.calendar = calendar
        self.settings = settings
        self.builder = builder
        self.writer = writer
        self.reloader = reloader
    }

    @discardableResult
    func refresh(now: Date = .now) throws -> TimetableSnapshotV1 {
        do {
            let events: [CalendarEventSnapshot]
            if calendar.accessState == .granted {
                let descriptors = calendar.calendars()
                let availableIDs = Set(descriptors.map(\.id))
                let visibleIDs = settings.visibleCalendarIDs(availableIDs: availableIDs)
                events = try calendar.fetchEvents(
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
            errorMessage = nil
            reloader.reloadTimetableWidgets()
            return snapshot
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }
}
