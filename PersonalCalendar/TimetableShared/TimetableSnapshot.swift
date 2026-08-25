import Foundation

enum TimetableAvailability: String, Codable, Hashable, Sendable {
    case ready
    case calendarAccessRequired
}

struct TimetableEntry: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let title: String
    let shortTitle: String
    let start: Date
    let end: Date
    let location: String?
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
    static let currentVersion = 1

    let version: Int
    let availability: TimetableAvailability
    let generatedAt: Date
    let weekStart: Date
    let timeZoneIdentifier: String
    let entries: [TimetableEntry]

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
