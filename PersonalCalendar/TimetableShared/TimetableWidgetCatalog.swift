import Foundation

struct TimetableWidgetProfile: Codable, Hashable, Identifiable, Sendable {
    let id: ProfileIdentity
    let name: String
    let colorHex: String
    let symbolName: String
    let snapshot: TimetableSnapshotV1
}

struct TimetableWidgetCatalogV1: Codable, Hashable, Sendable {
    static let currentVersion = 1

    let version: Int
    let generatedAt: Date
    let profiles: [TimetableWidgetProfile]

    func profile(for identity: ProfileIdentity) -> TimetableWidgetProfile? {
        profiles.first { $0.id == identity }
    }

    func snapshot(for identity: ProfileIdentity) -> TimetableSnapshotV1? {
        profile(for: identity)?.snapshot
    }
}
