import Foundation

struct TimetableActivityRouteResolver: Sendable {
    private let routeBuilder: TimetableSurfaceRouteBuilder

    init(routeBuilder: TimetableSurfaceRouteBuilder = .init()) {
        self.routeBuilder = routeBuilder
    }

    func url(
        attributes: TimetableActivityAttributes,
        state: TimetableActivityAttributes.ContentState,
        now: Date
    ) -> URL? {
        let entry = state.entry(at: now)
        let routeID = entry?.routeID
        let hasNonblankRouteID = routeID?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty == false

        return try? routeBuilder.url(
            profile: attributes.profileIdentity,
            date: hasNonblankRouteID ? entry?.start ?? now : now,
            timeZoneIdentifier: attributes.timeZoneIdentifier,
            entryRouteID: routeID
        )
    }
}
