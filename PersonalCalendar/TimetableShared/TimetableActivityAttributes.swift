import ActivityKit
import Foundation

struct TimetableActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable, Sendable {
        let snapshot: TimetableSnapshotV1
    }

    let weekStart: Date
    let timeZoneIdentifier: String
}
