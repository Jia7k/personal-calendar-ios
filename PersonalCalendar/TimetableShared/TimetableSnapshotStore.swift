import Foundation

protocol TimetableSnapshotReading {
    func read() throws -> TimetableSnapshotV1
}

protocol TimetableSnapshotWriting {
    func write(_ value: TimetableSnapshotV1) throws
}

enum TimetableSnapshotStoreError: Error, Equatable {
    case containerUnavailable
}

struct TimetableSnapshotStore: TimetableSnapshotReading, TimetableSnapshotWriting, Sendable {
    static let appGroupIdentifier = "group.local.personalcalendar.shared"
    static let filename = "timetable-v1.json"

    let fileURL: URL

    static func appGroup(fileManager: FileManager = .default) throws -> Self {
        guard let directory = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else {
            throw TimetableSnapshotStoreError.containerUnavailable
        }
        return Self(fileURL: directory.appendingPathComponent(filename, isDirectory: false))
    }

    func read() throws -> TimetableSnapshotV1 {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(TimetableSnapshotV1.self, from: Data(contentsOf: fileURL))
    }

    func write(_ value: TimetableSnapshotV1) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(value).write(to: fileURL, options: .atomic)
    }
}
