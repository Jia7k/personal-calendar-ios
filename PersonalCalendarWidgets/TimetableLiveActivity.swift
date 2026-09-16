import ActivityKit
import SwiftUI
import WidgetKit

struct TimetableLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TimetableActivityAttributes.self) { context in
            TimelineView(.periodic(from: .now, by: 30)) { timeline in
                DailyActivityView(
                    state: context.state,
                    attributes: context.attributes,
                    now: timeline.date,
                    isSystemStale: context.isStale,
                    hasEnded: activityHasEnded(context.attributes, at: timeline.date)
                )
                .environment(\.timeZone, activityTimeZone(context.attributes))
                .widgetURL(routeURL(context: context, now: timeline.date))
            }
            .privacySensitive()
            .activityBackgroundTint(DailyActivityColors.surface)
            .activitySystemActionForegroundColor(DailyActivityColors.primaryText)
        } dynamicIsland: { context in
            let route = routeURL(context: context, now: .now)

            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    TimelineView(.periodic(from: .now, by: 30)) { timeline in
                        DailyActivityIslandLeadingView(
                            state: context.state,
                            attributes: context.attributes,
                            now: timeline.date,
                            isSystemStale: context.isStale,
                            hasEnded: activityHasEnded(context.attributes, at: timeline.date)
                        )
                        .environment(\.timeZone, activityTimeZone(context.attributes))
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    TimelineView(.periodic(from: .now, by: 30)) { timeline in
                        DailyActivityIslandTrailingView(
                            state: context.state,
                            now: timeline.date,
                            isSystemStale: context.isStale,
                            hasEnded: activityHasEnded(context.attributes, at: timeline.date)
                        )
                        .environment(\.timeZone, activityTimeZone(context.attributes))
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    TimelineView(.periodic(from: .now, by: 30)) { timeline in
                        DailyActivityExpandedView(
                            state: context.state,
                            attributes: context.attributes,
                            now: timeline.date,
                            isSystemStale: context.isStale,
                            hasEnded: activityHasEnded(context.attributes, at: timeline.date)
                        )
                        .environment(\.timeZone, activityTimeZone(context.attributes))
                    }
                }
            } compactLeading: {
                TimelineView(.periodic(from: .now, by: 30)) { timeline in
                    DailyActivityCompactLeadingView(
                        state: context.state,
                        now: timeline.date,
                        isSystemStale: context.isStale,
                        hasEnded: activityHasEnded(context.attributes, at: timeline.date)
                    )
                    .environment(\.timeZone, activityTimeZone(context.attributes))
                }
            } compactTrailing: {
                TimelineView(.periodic(from: .now, by: 30)) { timeline in
                    DailyActivityCompactTrailingView(
                        state: context.state,
                        now: timeline.date,
                        isSystemStale: context.isStale,
                        hasEnded: activityHasEnded(context.attributes, at: timeline.date)
                    )
                    .environment(\.timeZone, activityTimeZone(context.attributes))
                }
            } minimal: {
                TimelineView(.periodic(from: .now, by: 30)) { timeline in
                    DailyActivityMinimalView(
                        state: context.state,
                        now: timeline.date,
                        isSystemStale: context.isStale,
                        hasEnded: activityHasEnded(context.attributes, at: timeline.date)
                    )
                    .environment(\.timeZone, activityTimeZone(context.attributes))
                }
            }
            .widgetURL(route)
            .keylineTint(DailyActivityColors.eventAccent)
        }
    }

    private func routeURL(
        context: ActivityViewContext<TimetableActivityAttributes>,
        now: Date
    ) -> URL? {
        TimetableActivityRouteResolver().url(
            attributes: context.attributes,
            state: context.state,
            now: now
        )
    }

    private func activityTimeZone(_ attributes: TimetableActivityAttributes) -> TimeZone {
        TimeZone(identifier: attributes.timeZoneIdentifier) ?? .current
    }

    private func activityHasEnded(
        _ attributes: TimetableActivityAttributes,
        at now: Date
    ) -> Bool {
        attributes.activityEndsAt.map { now >= $0 } ?? false
    }
}
