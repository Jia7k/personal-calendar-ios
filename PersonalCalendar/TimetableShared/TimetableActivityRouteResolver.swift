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
        if let daily = state.daily {
            let snapshot = daily.snapshot
            guard !attributes.isLegacy, snapshot.hasValidDay,
                  snapshot.profile.id == attributes.profileIdentity,
                  snapshot.timeZoneIdentifier == attributes.timeZoneIdentifier,
                  snapshot.dayStart == attributes.dayStart,
                  snapshot.dayEnd == attributes.dayEnd else { return nil }
            return try? routeBuilder.url(profile: snapshot.profile.id, date: snapshot.dayStart,
                timeZoneIdentifier: snapshot.timeZoneIdentifier, entryRouteID: nil)
        }
        guard attributes.dayStart == nil, attributes.dayEnd == nil else { return nil }
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
