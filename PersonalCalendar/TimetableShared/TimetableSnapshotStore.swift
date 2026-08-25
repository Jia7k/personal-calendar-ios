import Foundation

protocol TimetableSnapshotReading {
    func read() throws -> TimetableSnapshotV1
}

protocol TimetableSnapshotWriting {
    func write(_ value: TimetableSnapshotV1) throws
}

protocol TimetableWidgetCatalogReading {
    func read() throws -> TimetableWidgetCatalogV1
}

protocol TimetableWidgetCatalogWriting {
    func write(_ value: TimetableWidgetCatalogV1) throws
    func delete() throws
}

enum TimetableSnapshotStoreError: Error, Equatable {
    case containerUnavailable
    case unsupportedVersion(Int)
    case invalidCatalog
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

struct TimetableWidgetCatalogStore: TimetableWidgetCatalogReading, TimetableWidgetCatalogWriting, Sendable {
    static let appGroupIdentifier = TimetableSnapshotStore.appGroupIdentifier
    static let filename = "timetable-catalog-v1.json"

    let fileURL: URL

    static func appGroup(fileManager: FileManager = .default) throws -> Self {
        guard let directory = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else {
            throw TimetableSnapshotStoreError.containerUnavailable
        }
        return Self(fileURL: directory.appendingPathComponent(filename, isDirectory: false))
    }

    func read() throws -> TimetableWidgetCatalogV1 {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let value = try decoder.decode(
            TimetableWidgetCatalogV1.self,
            from: Data(contentsOf: fileURL)
        )
        guard value.version == TimetableWidgetCatalogV1.currentVersion else {
            throw TimetableSnapshotStoreError.unsupportedVersion(value.version)
        }
        return value
    }

    func write(_ value: TimetableWidgetCatalogV1) throws {
        guard value.version == TimetableWidgetCatalogV1.currentVersion else {
            throw TimetableSnapshotStoreError.unsupportedVersion(value.version)
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(value).write(to: fileURL, options: .atomic)
        if let legacyFileURL {
            try deleteIfPresent(legacyFileURL)
        }
    }

    func delete() throws {
        var firstError: Error?
        for target in [fileURL, legacyFileURL].compactMap({ $0 }) {
            do {
                try deleteIfPresent(target)
            } catch {
                if firstError == nil { firstError = error }
            }
        }
        if let firstError { throw firstError }
    }

    private var legacyFileURL: URL? {
        guard fileURL.lastPathComponent == Self.filename else { return nil }
        return fileURL.deletingLastPathComponent().appendingPathComponent(
            TimetableSnapshotStore.filename,
            isDirectory: false
        )
    }

    private func deleteIfPresent(_ target: URL) throws {
        guard FileManager.default.fileExists(atPath: target.path) else { return }
        try FileManager.default.removeItem(at: target)
    }
}
