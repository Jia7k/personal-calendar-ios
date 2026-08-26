import ActivityKit
import SwiftUI
import WidgetKit

struct TimetableLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TimetableActivityAttributes.self) { context in
            TimetableLockScreenView(
                state: context.state,
                attributes: context.attributes
            )
                .privacySensitive()
                .activityBackgroundTint(.black.opacity(0.82))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    CourseStatusCode(
                        state: context.state,
                        profileName: context.attributes.profileName
                    )
                }
                DynamicIslandExpandedRegion(.trailing) {
                    CourseBoundaryTimer(state: context.state)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    CourseStatusDetail(state: context.state)
                }
            } compactLeading: {
                CourseStatusCode(
                    state: context.state,
                    profileName: context.attributes.profileName
                )
            } compactTrailing: {
                CourseBoundaryTimer(state: context.state)
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
    let state: TimetableActivityAttributes.ContentState
    let attributes: TimetableActivityAttributes

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(spacing: 2) {
                TimeRailsView(
                    snapshot: compactSnapshot(state: state, attributes: attributes),
                    now: context.date,
                    showsStatusStrip: true,
                    profileName: attributes.profileName
                )
                ActivityProjectionStatus(
                    state: state,
                    now: context.date,
                    showsOmissions: false
                )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(height: 148)
            .environment(\.timeZone, activityTimeZone)
        }
    }

    private var activityTimeZone: TimeZone {
        TimeZone(identifier: attributes.timeZoneIdentifier) ?? .current
    }
}

private struct CourseStatusCode: View {
    let state: TimetableActivityAttributes.ContentState
    let profileName: String

    var body: some View {
        Text(state.entry(at: .now)?.shortTitle ?? profileName.uppercased())
            .font(.caption.weight(.heavy))
            .foregroundStyle(.white)
            .privacySensitive()
    }
}

private struct CourseBoundaryTimer: View {
    let state: TimetableActivityAttributes.ContentState

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
        let now = Date.now
        guard let entry = state.entry(at: now) else { return nil }
        return entry.start <= now ? entry.end : entry.start
    }
}

private struct CourseStatusDetail: View {
    let state: TimetableActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let entry = state.entry(at: .now) {
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
            } else {
                Text(
                    state.omittedEntryCount > 0 || state.sourceOmittedEntryCount > 0
                        ? "More events may not be shown"
                        : "No more events today"
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ActivityProjectionStatus(state: state, now: .now)
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .privacySensitive()
    }
}

private struct ActivityProjectionStatus: View {
    let state: TimetableActivityAttributes.ContentState
    let now: Date
    var showsOmissions = true

    var body: some View {
        if (showsOmissions && state.omittedEntryCount > 0)
            || state.sourceOmittedEntryCount > 0
            || state.freshness(at: now) == .stale {
            HStack(spacing: 6) {
                if showsOmissions && state.omittedEntryCount > 0 {
                    Text("+\(state.omittedEntryCount) more today")
                }
                if state.sourceOmittedEntryCount > 0 {
                    Text(sourceOmissionText)
                }
                if state.freshness(at: now) == .stale {
                    Text("Open Personal Calendar to refresh")
                }
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .accessibilityElement(children: .combine)
        }
    }

    private var sourceOmissionText: String {
        let noun = state.sourceOmittedEntryCount == 1 ? "event" : "events"
        return "\(state.sourceOmittedEntryCount) weekly \(noun) not shown"
    }
}

private func compactSnapshot(
    state: TimetableActivityAttributes.ContentState,
    attributes: TimetableActivityAttributes
) -> TimetableSnapshotV1 {
    TimetableSnapshotV1(
        version: TimetableSnapshotV1.currentVersion,
        availability: state.entries.isEmpty ? .noClasses : .ready,
        generatedAt: state.generatedAt,
        weekStart: attributes.weekStart,
        timeZoneIdentifier: attributes.timeZoneIdentifier,
        entries: state.entries.map {
            TimetableEntry(
                id: $0.id,
                title: $0.title,
                shortTitle: $0.shortTitle,
                start: $0.start,
                end: $0.end,
                location: $0.location
            )
        },
        omittedEntryCount: state.omittedEntryCount
    )
}
