import SwiftUI
import WidgetKit

struct NextClassWidget: Widget {
    let kind = "NextClassWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TimetableWidgetProvider()) { entry in
            NextClassWidgetView(entry: entry)
                .privacySensitive()
                .redacted(reason: entry.snapshot.generatedAt == .distantPast ? .placeholder : [])
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Next Class")
        .description("See the current or next class on the Lock Screen.")
        .supportedFamilies([.accessoryRectangular])
    }
}

struct NextClassWidgetView: View {
    let entry: TimetableWidgetEntry

    var body: some View {
        if entry.snapshot.availability != .ready {
            VStack(alignment: .leading, spacing: 2) {
                Text("SCHOOL TIMETABLE").font(.caption2.weight(.semibold))
                Text("Open My Calendar to sync").font(.headline)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            content(for: entry.snapshot.moment(at: entry.date, calendar: localCalendar))
        }
    }

    @ViewBuilder
    private func content(for moment: TimetableMoment) -> some View {
        switch moment {
        case .none:
            VStack(alignment: .leading, spacing: 2) {
                Text("SCHOOL DAY").font(.caption2.weight(.semibold))
                Text("No more classes").font(.headline)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case let .current(value):
            classContent(label: "NOW", value: value, showsCountdown: true)
        case let .next(value), let .gap(value):
            classContent(label: "NEXT", value: value, showsCountdown: false)
        }
    }

    private func classContent(label: String, value: TimetableEntry, showsCountdown: Bool) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 5) {
                Text(label).font(.caption2.weight(.bold))
                if showsCountdown {
                    Text(value.end, style: .timer).font(.caption2.monospacedDigit())
                } else {
                    Text(value.start, style: .time).font(.caption2.monospacedDigit())
                }
            }
            Text(value.title).font(.headline).lineLimit(1)
            if let location = value.location {
                Text(location).font(.caption).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var localCalendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: entry.snapshot.timeZoneIdentifier) ?? .current
        return value
    }
}
