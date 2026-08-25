import SwiftUI
import WidgetKit

struct WeekTimetableWidget: Widget {
    let kind = "WeekTimetableWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TimetableWidgetProvider()) { entry in
            WeekTimetableWidgetView(entry: entry)
                .privacySensitive()
                .redacted(reason: entry.snapshot.generatedAt == .distantPast ? .placeholder : [])
                .containerBackground(for: .widget) { Color.black }
        }
        .configurationDisplayName("School Week")
        .description("See Monday through Friday at a glance.")
        .supportedFamilies([.systemMedium])
    }
}

struct WeekTimetableWidgetView: View {
    let entry: TimetableWidgetEntry

    var body: some View {
        if entry.snapshot.availability == .ready {
            TimeRailsView(snapshot: entry.snapshot, now: entry.date, showsStatusStrip: false)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text("School Week").font(.headline)
                Text("Open My Calendar to sync your timetable.").font(.caption)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}
