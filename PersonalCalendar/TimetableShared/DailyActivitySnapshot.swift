import Foundation

struct DailyActivityProfile: Codable, Hashable, Sendable {
    let id: ProfileIdentity
    let name: String
    let symbolName: String

    private enum CodingKeys: String, CodingKey {
        case id = "i", name = "n", symbolName = "s"
    }
}

struct DailyActivityItem: Codable, Hashable, Identifiable, Sendable {
    enum Kind: String, Codable, Hashable, Sendable { case event = "e", task = "t" }

    let id: String
    let kind: Kind
    let title: String
    let shortTitle: String
    let start: Date
    let end: Date?
    let isAllDay: Bool
    let location: String?
    let hasAlert: Bool

    init(id: String, kind: Kind, title: String, shortTitle: String, start: Date,
         end: Date? = nil, isAllDay: Bool = false, location: String? = nil,
         hasAlert: Bool = false) {
        self.id = id
        self.kind = kind
        self.title = title
        self.shortTitle = shortTitle
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.location = location
        self.hasAlert = hasAlert
    }

    private enum CodingKeys: String, CodingKey {
        case id = "i", kind = "k", title = "t", shortTitle = "s", start = "b"
        case end = "e", isAllDay = "a", location = "l", hasAlert = "h"
    }

    func isEligible(in snapshot: DailyActivitySnapshot, at now: Date) -> Bool {
        guard !id.isEmpty, start.timeIntervalSinceReferenceDate.isFinite else { return false }
        switch kind {
        case .event:
            guard let end, end.timeIntervalSinceReferenceDate.isFinite,
                  start < end, start < snapshot.dayEnd, end > snapshot.dayStart else { return false }
            return isAllDay || end > now
        case .task:
            return end == nil && start >= snapshot.dayStart && start < snapshot.dayEnd
        }
    }
}

struct DailyActivitySnapshot: Codable, Hashable, Sendable {
    let profile: DailyActivityProfile
    let dayStart: Date
    let dayEnd: Date
    let timeZoneIdentifier: String
    let generatedAt: Date
    let items: [DailyActivityItem]
    var calendarUnavailable: Bool = false
    var tasksUnavailable: Bool = false

    var hasValidDay: Bool {
        guard dayStart.timeIntervalSinceReferenceDate.isFinite,
              dayEnd.timeIntervalSinceReferenceDate.isFinite,
              generatedAt.timeIntervalSinceReferenceDate.isFinite,
              dayStart < dayEnd,
              let zone = TimeZone(identifier: timeZoneIdentifier) else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar.startOfDay(for: dayStart) == dayStart
            && calendar.date(byAdding: .day, value: 1, to: dayStart) == dayEnd
    }

    func replacing(items: [DailyActivityItem], profile: DailyActivityProfile? = nil) -> Self {
        Self(profile: profile ?? self.profile, dayStart: dayStart, dayEnd: dayEnd,
             timeZoneIdentifier: timeZoneIdentifier, generatedAt: generatedAt, items: items,
             calendarUnavailable: calendarUnavailable, tasksUnavailable: tasksUnavailable)
    }

    private enum CodingKeys: String, CodingKey {
        case profile = "p", dayStart = "b", dayEnd = "e", timeZoneIdentifier = "z"
        case generatedAt = "g", items = "i", calendarUnavailable = "c", tasksUnavailable = "t"
    }
}
