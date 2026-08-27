import ActivityKit
import Foundation

struct TimetableActivityAttributes: ActivityAttributes, Equatable, Sendable {
    private static let currentSchemaVersion = 2
    private static let legacyProfileID = UUID(
        uuidString: "00000000-0000-0000-0000-000000000000"
    )!

    struct ContentState: Codable, Hashable, Sendable {
        static let maximumEncodedBytes = 3_500

        struct Entry: Codable, Hashable, Identifiable, Sendable {
            let id: String
            let title: String
            let shortTitle: String
            let start: Date
            let end: Date
            let location: String?
            let routeID: String?

            init(
                id: String,
                title: String,
                shortTitle: String,
                start: Date,
                end: Date,
                location: String?,
                routeID: String? = nil
            ) {
                self.id = id
                self.title = title
                self.shortTitle = shortTitle
                self.start = start
                self.end = end
                self.location = location
                self.routeID = routeID
            }

            fileprivate init(_ entry: TimetableEntry) {
                id = entry.id
                title = String(entry.title.prefix(48))
                shortTitle = String(entry.shortTitle.prefix(8))
                start = entry.start
                end = entry.end
                location = entry.location.map { String($0.prefix(64)) }
                routeID = entry.routeID
            }

            private enum CodingKeys: String, CodingKey {
                case id = "i"
                case title = "t"
                case shortTitle = "s"
                case start = "b"
                case end = "e"
                case location = "l"
                case routeID = "r"
            }

            init(from decoder: any Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                id = try container.decode(String.self, forKey: .id)
                title = try container.decode(String.self, forKey: .title)
                shortTitle = try container.decode(String.self, forKey: .shortTitle)
                start = try container.decode(Date.self, forKey: .start)
                end = try container.decode(Date.self, forKey: .end)
                location = try container.decodeIfPresent(String.self, forKey: .location)
                routeID = try container.decodeIfPresent(String.self, forKey: .routeID)
            }

            func encode(to encoder: any Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(id, forKey: .id)
                try container.encode(title, forKey: .title)
                try container.encode(shortTitle, forKey: .shortTitle)
                try container.encode(start, forKey: .start)
                try container.encode(end, forKey: .end)
                try container.encodeIfPresent(location, forKey: .location)
                try container.encodeIfPresent(routeID, forKey: .routeID)
            }
        }

        let generatedAt: Date
        let entries: [Entry]
        let omittedEntryCount: Int
        let sourceOmittedEntryCount: Int

        static func projecting(
            snapshot: TimetableSnapshotV1,
            now: Date,
            calendar: Calendar
        ) -> Self? {
            var localCalendar = calendar
            localCalendar.timeZone = TimeZone(identifier: snapshot.timeZoneIdentifier)
                ?? calendar.timeZone
            let candidates = snapshot.entries
                .filter {
                    ($0.start <= now && now < $0.end)
                        || (localCalendar.isDate($0.start, inSameDayAs: now) && $0.start > now)
                }
                .sorted(by: entryOrder)
                .map(Entry.init)
            var retainedEntries = candidates

            while true {
                let state = Self(
                    generatedAt: snapshot.generatedAt,
                    entries: retainedEntries,
                    omittedEntryCount: candidates.count - retainedEntries.count,
                    sourceOmittedEntryCount: snapshot.omittedEntryCount
                )
                guard let encodedSize = state.encodedSize else { return nil }
                if encodedSize <= maximumEncodedBytes {
                    return state
                }
                guard !retainedEntries.isEmpty else { return nil }
                retainedEntries.removeLast()
            }
        }

        func freshness(at now: Date) -> TimetableFreshness {
            TimetableFreshness.generatedAt(generatedAt, now: now)
        }

        func entry(at now: Date) -> Entry? {
            entries.first(where: { $0.start <= now && now < $0.end })
                ?? entries.first(where: { $0.start > now })
        }

        func nextBoundary(after now: Date) -> Date? {
            let freshnessBoundary = generatedAt.addingTimeInterval(
                TimetableFreshness.defaultThreshold
            )
            let eventBoundaries = entries
                .flatMap { [$0.start, $0.end] }
                .filter { $0 > now }
            let freshnessBoundaries = freshnessBoundary > now ? [freshnessBoundary] : []
            return (eventBoundaries + freshnessBoundaries).min()
        }

        private var encodedSize: Int? {
            try? JSONEncoder().encode(self).count
        }

        private static func entryOrder(_ left: TimetableEntry, _ right: TimetableEntry) -> Bool {
            if left.start != right.start { return left.start < right.start }
            if left.end != right.end { return left.end < right.end }
            if left.title != right.title { return left.title < right.title }
            return left.id < right.id
        }

        private enum CodingKeys: String, CodingKey {
            case generatedAt = "g"
            case entries = "e"
            case omittedEntryCount = "o"
            case sourceOmittedEntryCount = "u"
        }
    }

    private let schemaVersion: Int
    let profileIdentity: ProfileIdentity
    let profileName: String
    let weekStart: Date
    let timeZoneIdentifier: String

    var isLegacy: Bool { schemaVersion < Self.currentSchemaVersion }

    init(
        profileIdentity: ProfileIdentity,
        profileName: String,
        weekStart: Date,
        timeZoneIdentifier: String
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.profileIdentity = profileIdentity
        self.profileName = profileName
        self.weekStart = weekStart
        self.timeZoneIdentifier = timeZoneIdentifier
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case profileIdentity
        case profileName
        case weekStart
        case timeZoneIdentifier
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        profileIdentity = try container.decodeIfPresent(
            ProfileIdentity.self,
            forKey: .profileIdentity
        ) ?? .saved(Self.legacyProfileID)
        profileName = try container.decodeIfPresent(String.self, forKey: .profileName) ?? "Timetable"
        weekStart = try container.decode(Date.self, forKey: .weekStart)
        timeZoneIdentifier = try container.decode(String.self, forKey: .timeZoneIdentifier)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(profileIdentity, forKey: .profileIdentity)
        try container.encode(profileName, forKey: .profileName)
        try container.encode(weekStart, forKey: .weekStart)
        try container.encode(timeZoneIdentifier, forKey: .timeZoneIdentifier)
    }
}
