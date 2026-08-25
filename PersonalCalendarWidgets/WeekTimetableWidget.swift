import AppIntents
import SwiftUI
import WidgetKit

struct WeekTimetableWidget: Widget {
    let kind = "WeekTimetableWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: TimetableWidgetConfigurationIntent.self,
            provider: TimetableWidgetProvider()
        ) { entry in
            WeekTimetableWidgetView(entry: entry)
                .privacySensitive(entry.containsPrivateData)
                .redacted(reason: entry.isPlaceholder ? .placeholder : [])
                .containerBackground(for: .widget) { Color.black }
        }
        .configurationDisplayName("Weekly Timetable")
        .description("Choose a profile and see Monday through Friday at a glance.")
        .supportedFamilies([.systemMedium])
    }
}

struct WeekTimetableWidgetView: View {
    let entry: TimetableWidgetEntry

    @ViewBuilder
    var body: some View {
        switch entry.content {
        case .chooseProfile:
            message(title: "Timetable", detail: "Choose a profile")
        case .profileDeleted:
            message(title: "Timetable", detail: "Choose another profile")
        case let .calendarAccessRequired(profileName):
            message(title: profileName, detail: "Allow Calendar access in My Calendar")
        case let .emptyProfile(profileName):
            message(title: profileName, detail: "No calendars in this profile")
        case let .noClasses(profileName):
            message(title: profileName, detail: "No classes this week")
        case let .ready(profileName, snapshot):
            TimeRailsView(
                snapshot: snapshot,
                now: entry.date,
                showsStatusStrip: false,
                profileName: profileName
            )
        }
    }

    private func message(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
                .lineLimit(1)
            Text(detail)
                .font(.caption)
                .lineLimit(2)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}
