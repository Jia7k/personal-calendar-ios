import Foundation
import WidgetKit

struct TimetableWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: TimetableSnapshotV1
}

struct TimetableWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> TimetableWidgetEntry {
        let now = Date()
        return TimetableWidgetEntry(date: now, snapshot: placeholderSnapshot(now: now))
    }

    func getSnapshot(in context: Context, completion: @escaping (TimetableWidgetEntry) -> Void) {
        let now = Date()
        completion(TimetableWidgetEntry(date: now, snapshot: loadSnapshot(now: now, placeholder: context.isPreview)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TimetableWidgetEntry>) -> Void) {
        let now = Date()
        let snapshot = loadSnapshot(now: now, placeholder: false)
        let calendar = calendar(for: snapshot)
        let dates = TimetableTimelineBuilder(calendar: calendar).refreshDates(snapshot: snapshot, now: now)
        completion(Timeline(entries: dates.map { TimetableWidgetEntry(date: $0, snapshot: snapshot) }, policy: .atEnd))
    }

    private func loadSnapshot(now: Date, placeholder: Bool) -> TimetableSnapshotV1 {
        if placeholder { return placeholderSnapshot(now: now) }
        return (try? TimetableSnapshotStore.appGroup().read()) ?? unavailableSnapshot(now: now)
    }

    private func calendar(for snapshot: TimetableSnapshotV1) -> Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: snapshot.timeZoneIdentifier) ?? .current
        return value
    }

    private func unavailableSnapshot(now: Date) -> TimetableSnapshotV1 {
        let calendar = Calendar.current
        return TimetableSnapshotV1(
            version: TimetableSnapshotV1.currentVersion,
            availability: .calendarAccessRequired,
            generatedAt: now,
            weekStart: calendar.startOfDay(for: now),
            timeZoneIdentifier: calendar.timeZone.identifier,
            entries: []
        )
    }

    private func placeholderSnapshot(now: Date) -> TimetableSnapshotV1 {
        let end = now.addingTimeInterval(90 * 60)
        return TimetableSnapshotV1(
            version: TimetableSnapshotV1.currentVersion,
            availability: .ready,
            generatedAt: .distantPast,
            weekStart: Calendar.current.startOfDay(for: now),
            timeZoneIdentifier: TimeZone.current.identifier,
            entries: [
                TimetableEntry(
                    id: "placeholder",
                    title: "INF 2003 Lecture",
                    shortTitle: "I03",
                    start: now.addingTimeInterval(-30 * 60),
                    end: end,
                    location: "Online"
                )
            ]
        )
    }
}
