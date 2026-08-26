import Foundation

enum TimetableAvailability: String, Codable, Hashable, Sendable {
    case ready
    case calendarAccessRequired
    case emptyProfile
    case noClasses
}

typealias TimetableProfileAvailability = TimetableAvailability

enum TimetableFreshness: Equatable, Sendable {
    case fresh
    case stale

    static let defaultThreshold: TimeInterval = 6 * 60 * 60

    static func generatedAt(
        _ generatedAt: Date,
        now: Date,
        threshold: TimeInterval = defaultThreshold
    ) -> Self {
        now < generatedAt.addingTimeInterval(threshold) ? .fresh : .stale
    }
}

struct TimetableEntry: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let title: String
    let shortTitle: String
    let start: Date
    let end: Date
    let location: String?
    let routeID: String

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
        self.routeID = routeID ?? id
    }
}

enum TimetableMoment: Hashable, Sendable {
    case none
    case next(TimetableEntry)
    case current(TimetableEntry)
    case gap(next: TimetableEntry)

    var entry: TimetableEntry? {
        switch self {
        case .none:
            nil
        case let .next(entry), let .current(entry), let .gap(entry):
            entry
        }
    }
}

struct TimetableSnapshotV1: Codable, Hashable, Sendable {
    static let currentVersion = 2

    let version: Int
    let availability: TimetableAvailability
    let generatedAt: Date
    let weekStart: Date
    let timeZoneIdentifier: String
    let entries: [TimetableEntry]
    let omittedEntryCount: Int

    init(
        version: Int,
        availability: TimetableAvailability,
        generatedAt: Date,
        weekStart: Date,
        timeZoneIdentifier: String,
        entries: [TimetableEntry],
        omittedEntryCount: Int = 0
    ) {
        self.version = version
        self.availability = availability
        self.generatedAt = generatedAt
        self.weekStart = weekStart
        self.timeZoneIdentifier = timeZoneIdentifier
        self.entries = entries
        self.omittedEntryCount = omittedEntryCount
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case availability
        case generatedAt
        case weekStart
        case timeZoneIdentifier
        case entries
        case omittedEntryCount
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .version)
        guard version == Self.currentVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .version,
                in: container,
                debugDescription: "Unsupported timetable snapshot version \(version)."
            )
        }

        let omittedEntryCount = try container.decode(Int.self, forKey: .omittedEntryCount)
        guard omittedEntryCount >= 0 else {
            throw DecodingError.dataCorruptedError(
                forKey: .omittedEntryCount,
                in: container,
                debugDescription: "Omitted entry count cannot be negative."
            )
        }

        self.init(
            version: version,
            availability: try container.decode(TimetableAvailability.self, forKey: .availability),
            generatedAt: try container.decode(Date.self, forKey: .generatedAt),
            weekStart: try container.decode(Date.self, forKey: .weekStart),
            timeZoneIdentifier: try container.decode(String.self, forKey: .timeZoneIdentifier),
            entries: try container.decode([TimetableEntry].self, forKey: .entries),
            omittedEntryCount: omittedEntryCount
        )
    }

    func encode(to encoder: any Encoder) throws {
        guard version == Self.currentVersion else {
            throw EncodingError.invalidValue(
                version,
                .init(
                    codingPath: encoder.codingPath,
                    debugDescription: "Unsupported timetable snapshot version \(version)."
                )
            )
        }

        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(availability, forKey: .availability)
        try container.encode(generatedAt, forKey: .generatedAt)
        try container.encode(weekStart, forKey: .weekStart)
        try container.encode(timeZoneIdentifier, forKey: .timeZoneIdentifier)
        try container.encode(entries, forKey: .entries)
        try container.encode(omittedEntryCount, forKey: .omittedEntryCount)
    }

    func moment(at now: Date, calendar: Calendar) -> TimetableMoment {
        let todaysEntries = entries
            .filter { calendar.isDate($0.start, inSameDayAs: now) }
            .sorted(by: TimetableSnapshotV1.entryOrder)

        guard let first = todaysEntries.first else { return .none }

        if let current = todaysEntries.first(where: { $0.start <= now && now < $0.end }) {
            return .current(current)
        }
        if now < first.start {
            return .next(first)
        }
        if let upcoming = todaysEntries.first(where: { now < $0.start }) {
            return .gap(next: upcoming)
        }
        return .none
    }

    private static func entryOrder(_ left: TimetableEntry, _ right: TimetableEntry) -> Bool {
        if left.start != right.start { return left.start < right.start }
        if left.end != right.end { return left.end < right.end }
        return left.id < right.id
    }
}
