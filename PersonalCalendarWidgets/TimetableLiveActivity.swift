import ActivityKit
import SwiftUI
import WidgetKit

struct TimetableLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TimetableActivityAttributes.self) { context in
            TimetableLockScreenView(snapshot: context.state.snapshot)
                .privacySensitive()
                .activityBackgroundTint(.black.opacity(0.82))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    CourseStatusCode(snapshot: context.state.snapshot)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    CourseBoundaryTimer(snapshot: context.state.snapshot)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    CourseStatusDetail(snapshot: context.state.snapshot)
                }
            } compactLeading: {
                CourseStatusCode(snapshot: context.state.snapshot)
            } compactTrailing: {
                CourseBoundaryTimer(snapshot: context.state.snapshot)
            } minimal: {
                Circle()
                    .fill(Color(red: 0.38, green: 0.73, blue: 0.68))
                    .frame(width: 9, height: 9)
            }
            .keylineTint(Color(red: 0.38, green: 0.73, blue: 0.68))
        }
    }
}

private struct TimetableLockScreenView: View {
    let snapshot: TimetableSnapshotV1

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            TimeRailsView(snapshot: snapshot, now: context.date, showsStatusStrip: true)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(height: 148)
        }
    }
}

private struct CourseStatusCode: View {
    let snapshot: TimetableSnapshotV1

    var body: some View {
        Text(moment.entry?.shortTitle ?? "SCHOOL")
            .font(.caption.weight(.heavy))
            .foregroundStyle(.white)
            .privacySensitive()
    }

    private var moment: TimetableMoment {
        snapshot.moment(at: .now, calendar: calendar(for: snapshot))
    }
}

private struct CourseBoundaryTimer: View {
    let snapshot: TimetableSnapshotV1

    var body: some View {
        if let boundary {
            Text(boundary, style: .timer)
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.white)
        } else {
            Text("DONE")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
        }
    }

    private var boundary: Date? {
        switch snapshot.moment(at: .now, calendar: calendar(for: snapshot)) {
        case let .current(entry): entry.end
        case let .next(entry), let .gap(entry): entry.start
        case .none: nil
        }
    }
}

private struct CourseStatusDetail: View {
    let snapshot: TimetableSnapshotV1

    var body: some View {
        if let entry = moment.entry {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(.subheadline.weight(.semibold))
                HStack(spacing: 5) {
                    Text(entry.start, format: .dateTime.hour().minute())
                    Text("–")
                    Text(entry.end, format: .dateTime.hour().minute())
                    if let location = entry.location {
                        Text("·")
                        Text(location)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .privacySensitive()
        } else {
            Text("No more classes today")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var moment: TimetableMoment {
        snapshot.moment(at: .now, calendar: calendar(for: snapshot))
    }
}

private func calendar(for snapshot: TimetableSnapshotV1) -> Calendar {
    var value = Calendar(identifier: .gregorian)
    value.timeZone = TimeZone(identifier: snapshot.timeZoneIdentifier) ?? .current
    return value
}
