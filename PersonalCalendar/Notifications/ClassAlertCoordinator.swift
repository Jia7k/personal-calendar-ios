import Foundation

struct ClassAlertPreference: Codable, Equatable, Sendable {
    static let allowedLeadMinutes: Set<Int> = [5, 10, 15, 20, 30]

    var enabled: Bool
    var leadMinutes: Int
}

struct ClassAlertCoordinator: Sendable {
    let calendar: Calendar
    let horizonDays: Int
    let maximumRequests: Int

    init(
        calendar: Calendar,
        horizonDays: Int = 14,
        maximumRequests: Int = 12
    ) {
        self.calendar = calendar
        self.horizonDays = max(0, horizonDays)
        self.maximumRequests = max(0, maximumRequests)
    }

    func requests(
        profiles: [ProfileSnapshot],
        preferences: [UUID: ClassAlertPreference],
        events: [CalendarEventSnapshot],
        now: Date
    ) -> [LocalNotificationRequest] {
        guard maximumRequests > 0,
              let horizonEnd = calendar.date(
                  byAdding: .day,
                  value: horizonDays,
                  to: now
              ) else { return [] }

        var requestsByIdentifier: [String: LocalNotificationRequest] = [:]
        for profile in profiles.sorted(by: profileOrder) {
            guard let preference = preferences[profile.id],
                  preference.enabled,
                  ClassAlertPreference.allowedLeadMinutes.contains(
                      preference.leadMinutes
                  ) else { continue }

            for event in events where profile.calendarIDs.contains(event.calendarID) {
                guard !event.isAllDay,
                      event.start.timeIntervalSinceReferenceDate.isFinite,
                      event.end.timeIntervalSinceReferenceDate.isFinite,
                      event.end > event.start,
                      event.start > now,
                      let fireDate = calendar.date(
                          byAdding: .minute,
                          value: -preference.leadMinutes,
                          to: event.start
                      ),
                      fireDate > now,
                      fireDate <= horizonEnd
                else { continue }

                let entryID = AppRouteEntryIdentity.make(
                    displayID: event.id,
                    occurrenceStart: event.start
                )
                let day = LocalDay(date: event.start, calendar: calendar)
                let route = AppRoute.calendar(
                    day: .init(year: day.year, month: day.month, day: day.day),
                    profile: .saved(profile.id),
                    entryID: entryID
                )
                guard let routeURL = try? AppRouteCodec().url(for: route) else {
                    continue
                }

                let identifier = "class|\(profile.id.uuidString.lowercased())|\(entryID)"
                requestsByIdentifier[identifier] = .init(
                    identifier: identifier,
                    title: event.title,
                    body: classAlertBody(
                        event: event,
                        leadMinutes: preference.leadMinutes
                    ),
                    fireDate: fireDate,
                    categoryIdentifier: NotificationCategoryIdentifier.classAlert,
                    userInfo: [
                        NotificationPayloadKey.route: routeURL.absoluteString
                    ]
                )
            }
        }

        return Array(requestsByIdentifier.values)
            .sorted {
                $0.fireDate == $1.fireDate
                    ? $0.identifier < $1.identifier
                    : $0.fireDate < $1.fireDate
            }
            .prefix(maximumRequests)
            .map { $0 }
    }

    private func profileOrder(_ left: ProfileSnapshot, _ right: ProfileSnapshot) -> Bool {
        if left.sortOrder != right.sortOrder {
            return left.sortOrder < right.sortOrder
        }
        return left.id.uuidString < right.id.uuidString
    }

    private func classAlertBody(
        event: CalendarEventSnapshot,
        leadMinutes: Int
    ) -> String {
        let location = event.location?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let location, !location.isEmpty {
            return "Starts in \(leadMinutes) minutes · \(location)"
        }
        return "Starts in \(leadMinutes) minutes."
    }
}
