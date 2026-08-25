import ActivityKit
import Foundation

struct TimetableActivityAttributes: ActivityAttributes, Equatable, Sendable {
    private static let currentSchemaVersion = 2
    private static let legacyProfileID = UUID(
        uuidString: "00000000-0000-0000-0000-000000000000"
    )!

    struct ContentState: Codable, Hashable, Sendable {
        let snapshot: TimetableSnapshotV1
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
