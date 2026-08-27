import AppIntents
import SwiftUI
import WidgetKit

struct NextClassWidget: Widget {
    let kind = "NextClassWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: TimetableWidgetConfigurationIntent.self,
            provider: TimetableWidgetProvider()
        ) { entry in
            NextClassWidgetView(entry: entry)
                .privacySensitive(entry.containsPrivateData)
                .redacted(reason: entry.isPlaceholder ? .placeholder : [])
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Next Class")
        .description("See the current or next class on the Lock Screen.")
        .supportedFamilies([.accessoryRectangular])
    }
}

struct NextClassWidgetView: View {
    let entry: TimetableWidgetEntry

    @ViewBuilder
    var body: some View {
        let routeURL = TimetableWidgetRouteResolver().nextClassURL(
            content: entry.content,
            date: entry.date
        )
        Group {
            switch entry.content {
            case .chooseProfile:
                message(title: "TIMETABLE", detail: "Choose a profile")
            case .profileDeleted:
                message(title: "TIMETABLE", detail: "Choose another profile")
            case let .calendarAccessRequired(profileName):
                message(title: profileName, detail: "Allow Calendar access")
            case let .emptyProfile(profileName):
                message(title: profileName, detail: "No calendars in this profile")
            case let .noClasses(profileName):
                message(title: profileName, detail: "No classes this week")
            case let .ready(_, profileName, snapshot):
                content(
                    for: snapshot.moment(at: entry.date, calendar: calendar(for: snapshot)),
                    profileName: profileName
                )
            }
        }
        .widgetURL(routeURL)
        .accessibilityHint(routeURL == nil ? "" : "Opens this timetable in My Calendar")
    }

    @ViewBuilder
    private func content(for moment: TimetableMoment, profileName: String) -> some View {
        switch moment {
        case .none:
            message(title: profileName, detail: "No more classes")
        case let .current(value):
            classContent(
                profileName: profileName,
                label: "NOW",
                value: value,
                showsCountdown: true
            )
        case let .next(value), let .gap(value):
            classContent(
                profileName: profileName,
                label: "NEXT",
                value: value,
                showsCountdown: false
            )
        }
    }

    private func classContent(
        profileName: String,
        label: String,
        value: TimetableEntry,
        showsCountdown: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 5) {
                Text(profileName.uppercased())
                    .lineLimit(1)
                Spacer(minLength: 2)
                Text(label)
                if showsCountdown {
                    Text(value.end, style: .timer).monospacedDigit()
                } else {
                    Text(value.start, style: .time).monospacedDigit()
                }
            }
            .font(.caption2.weight(.bold))
            Text(value.title).font(.headline).lineLimit(1)
            if let location = value.location {
                Text(location).font(.caption).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func message(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
            Text(detail)
                .font(.headline)
                .minimumScaleFactor(0.8)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func calendar(for snapshot: TimetableSnapshotV1) -> Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: snapshot.timeZoneIdentifier) ?? .current
        return value
    }
}
