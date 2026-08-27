import Foundation

enum TimetableWidgetContent: Hashable, Sendable {
    case chooseProfile
    case profileDeleted
    case calendarAccessRequired(profileName: String)
    case emptyProfile(profileName: String)
    case noClasses(profileName: String)
    case ready(
        profile: ProfileIdentity,
        profileName: String,
        snapshot: TimetableSnapshotV1
    )
}

struct TimetableWidgetRouteResolver: Sendable {
    private let routeBuilder: TimetableSurfaceRouteBuilder

    init(routeBuilder: TimetableSurfaceRouteBuilder = .init()) {
        self.routeBuilder = routeBuilder
    }

    func nextClassURL(content: TimetableWidgetContent, date: Date) -> URL? {
        guard let context = readyContext(content) else { return nil }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = context.timeZone
        let entry = context.snapshot.moment(at: date, calendar: calendar).entry

        return try? routeBuilder.url(
            profile: context.profile,
            date: entry?.start ?? date,
            timeZoneIdentifier: context.snapshot.timeZoneIdentifier,
            entryRouteID: entry?.routeID
        )
    }

    func weekURL(content: TimetableWidgetContent, date: Date) -> URL? {
        guard let context = readyContext(content) else { return nil }

        return try? routeBuilder.url(
            profile: context.profile,
            date: date,
            timeZoneIdentifier: context.snapshot.timeZoneIdentifier,
            entryRouteID: nil
        )
    }

    private func readyContext(
        _ content: TimetableWidgetContent
    ) -> (profile: ProfileIdentity, snapshot: TimetableSnapshotV1, timeZone: TimeZone)? {
        guard case let .ready(profile, _, snapshot) = content,
              snapshot.availability == .ready,
              let timeZone = TimeZone(identifier: snapshot.timeZoneIdentifier) else {
            return nil
        }
        return (profile, snapshot, timeZone)
    }
}
