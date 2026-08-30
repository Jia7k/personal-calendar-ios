import CoreFoundation
import Darwin
import Foundation

@_silgen_name("flock")
private func appRouteHandoffFlock(_ descriptor: Int32, _ operation: Int32) -> Int32

enum AppRouteHandoffStoreError: Error, Equatable, Sendable {
    case containerUnavailable
    case unsupportedRoute
    case invalidQuickEntry
    case payloadTooLarge
    case queueFull
}

struct AppRouteHandoffStore: Sendable {
    static let filename = "quick-entry-handoff-v1.json"
    static let arrivalNotificationName = "local.personalcalendar.quick-entry-handoff.arrived"

    private static let currentVersion = 2
    private static let lockFilename = ".quick-entry-handoff.lock"
    private static let maximumItemCount = 16
    private static let maximumPayloadSize = 64 * 1_024
    private static let maximumItemAge: TimeInterval = 24 * 60 * 60
    private static let claimStaleInterval: TimeInterval = 5 * 60

    let fileURL: URL

    static func appGroup(fileManager: FileManager = .default) throws -> Self {
        guard let directory = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: TimetableSnapshotStore.appGroupIdentifier
        ) else {
            throw AppRouteHandoffStoreError.containerUnavailable
        }
        let store = Self(fileURL: directory.appendingPathComponent(filename, isDirectory: false))
        try store.withExclusiveLock {
            try store.removeOrphanedClaims()
        }
        return store
    }

    func write(_ route: AppRoute) throws {
        let payload: QuickEntryPayload
        switch route {
        case let .quickEntry(text, profile):
            guard Self.containsNonWhitespace(text) else {
                throw AppRouteHandoffStoreError.invalidQuickEntry
            }
            if case .everything? = profile {
                throw AppRouteHandoffStoreError.invalidQuickEntry
            }
            payload = QuickEntryPayload(text: text, profile: profile)
        default:
            throw AppRouteHandoffStoreError.unsupportedRoute
        }

        let item = QueuedItem(
            id: UUID(),
            enqueuedAt: Date(),
            route: .quickEntry,
            payload: payload
        )
        guard try Self.encodedQueue([item]).count <= Self.maximumPayloadSize else {
            throw AppRouteHandoffStoreError.payloadTooLarge
        }

        try withExclusiveLock {
            try removeOrphanedClaims()
            var items = try readQueue(now: item.enqueuedAt)
            items = Self.pruned(items, now: item.enqueuedAt)
            guard items.count < Self.maximumItemCount else {
                throw AppRouteHandoffStoreError.queueFull
            }

            items.append(item)
            let data = try Self.encodedQueue(items)
            guard data.count <= Self.maximumPayloadSize else {
                throw AppRouteHandoffStoreError.queueFull
            }
            try data.write(to: fileURL, options: .atomic)
        }
        Self.postArrivalNotification()
    }

    func consume() throws -> AppRoute? {
        try withExclusiveLock {
            try removeOrphanedClaims()
            let now = Date()
            var items = Self.pruned(try readQueue(now: now), now: now)
            guard !items.isEmpty else {
                try removePayloadIfPresent()
                return nil
            }

            let item = items.removeFirst()
            if items.isEmpty {
                try removePayloadIfPresent()
            } else {
                try Self.encodedQueue(items).write(to: fileURL, options: .atomic)
            }

            return .quickEntry(
                text: item.payload.text,
                profile: item.payload.profile
            )
        }
    }

    private func readQueue(now: Date) throws -> [QueuedItem] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: fileURL.path) else { return [] }

        let values = try fileURL.resourceValues(forKeys: [.fileSizeKey])
        guard let fileSize = values.fileSize,
              fileSize <= Self.maximumPayloadSize else {
            try removePayloadIfPresent()
            return []
        }

        let data = try Data(contentsOf: fileURL)
        guard data.count <= Self.maximumPayloadSize,
              let marker = try? JSONDecoder().decode(VersionMarker.self, from: data) else {
            try removePayloadIfPresent()
            return []
        }

        let items: [QueuedItem]
        switch marker.version {
        case 1:
            guard let legacy = try? JSONDecoder().decode(LegacyEnvelope.self, from: data),
                  legacy.version == 1 else {
                try removePayloadIfPresent()
                return []
            }
            items = [
                QueuedItem(
                    id: UUID(),
                    enqueuedAt: now,
                    route: legacy.route,
                    payload: legacy.payload
                )
            ]
        case Self.currentVersion:
            guard let envelope = try? JSONDecoder().decode(QueueEnvelope.self, from: data),
                  envelope.version == Self.currentVersion else {
                try removePayloadIfPresent()
                return []
            }
            items = envelope.items
        default:
            try removePayloadIfPresent()
            return []
        }

        guard Self.isValid(items) else {
            try removePayloadIfPresent()
            return []
        }
        return items
    }

    private static func containsNonWhitespace(_ value: String) -> Bool {
        value.unicodeScalars.contains {
            !CharacterSet.whitespacesAndNewlines.contains($0)
        }
    }

    private static func encodedQueue(_ items: [QueuedItem]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(QueueEnvelope(version: currentVersion, items: items))
    }

    private static func isValid(_ items: [QueuedItem]) -> Bool {
        guard items.count <= maximumItemCount,
              Set(items.map(\.id)).count == items.count else {
            return false
        }
        return items.allSatisfy {
            $0.route == .quickEntry
                && containsNonWhitespace($0.payload.text)
                && $0.payload.profile != .everything
                && $0.enqueuedAt.timeIntervalSinceReferenceDate.isFinite
        }
    }

    private static func pruned(_ items: [QueuedItem], now: Date) -> [QueuedItem] {
        items.filter { now.timeIntervalSince($0.enqueuedAt) <= maximumItemAge }
    }

    private func removePayloadIfPresent(fileManager: FileManager = .default) throws {
        do {
            try fileManager.removeItem(at: fileURL)
        } catch where Self.isMissingFileError(error) {
            return
        }
    }

    private func withExclusiveLock<T>(_ operation: () throws -> T) throws -> T {
        let lockURL = fileURL.deletingLastPathComponent().appendingPathComponent(
            Self.lockFilename,
            isDirectory: false
        )
        let descriptor = lockURL.path.withCString {
            Darwin.open($0, O_CREAT | O_RDWR, mode_t(0o600))
        }
        guard descriptor >= 0 else {
            throw Self.posixError()
        }
        defer { Darwin.close(descriptor) }

        while appRouteHandoffFlock(descriptor, LOCK_EX) != 0 {
            guard errno == EINTR else { throw Self.posixError() }
        }
        defer { _ = appRouteHandoffFlock(descriptor, LOCK_UN) }
        return try operation()
    }

    private static func posixError() -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }

    private func removeOrphanedClaims(
        fileManager: FileManager = .default,
        now: Date = Date()
    ) throws {
        let directory = fileURL.deletingLastPathComponent()
        let prefix = ".\(fileURL.lastPathComponent).consuming-"
        let currentProcessID = Int32(ProcessInfo.processInfo.processIdentifier)
        let candidates = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: []
        )

        for candidate in candidates where candidate.lastPathComponent.hasPrefix(prefix) {
            let suffix = candidate.lastPathComponent.dropFirst(prefix.count)
            let ownerText = suffix.split(separator: "-", maxSplits: 1).first
            let ownerProcessID = ownerText.flatMap { Int32($0) }
            let modifiedAt = try? candidate.resourceValues(
                forKeys: [.contentModificationDateKey]
            ).contentModificationDate
            let isStale = modifiedAt.map { now.timeIntervalSince($0) >= Self.claimStaleInterval } ?? true
            let ownerIsCurrent = ownerProcessID == currentProcessID
            let ownerIsRunning = ownerProcessID.map(Self.processIsRunning) ?? false

            if isStale || (!ownerIsCurrent && !ownerIsRunning) {
                do {
                    try fileManager.removeItem(at: candidate)
                } catch where Self.isMissingFileError(error) {
                    continue
                }
            }
        }
    }

    private static func isMissingFileError(_ error: Error) -> Bool {
        let cocoaError = error as NSError
        if cocoaError.domain == NSCocoaErrorDomain,
           cocoaError.code == NSFileNoSuchFileError {
            return true
        }
        if cocoaError.domain == NSPOSIXErrorDomain,
           cocoaError.code == Int(ENOENT) {
            return true
        }
        guard let underlying = cocoaError.userInfo[NSUnderlyingErrorKey] as? NSError else {
            return false
        }
        return underlying.domain == NSPOSIXErrorDomain && underlying.code == Int(ENOENT)
    }

    private static func processIsRunning(_ processID: Int32) -> Bool {
        guard processID > 0 else { return false }
        errno = 0
        return Darwin.kill(pid_t(processID), 0) == 0 || errno == EPERM
    }

    private static func postArrivalNotification() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(arrivalNotificationName as CFString),
            nil,
            nil,
            true
        )
    }
}

private extension AppRouteHandoffStore {
    struct VersionMarker: Decodable {
        let version: Int
    }

    struct LegacyEnvelope: Codable {
        let version: Int
        let route: RouteKind
        let payload: QuickEntryPayload
    }

    struct QueueEnvelope: Codable {
        let version: Int
        let items: [QueuedItem]
    }

    struct QueuedItem: Codable {
        let id: UUID
        let enqueuedAt: Date
        let route: RouteKind
        let payload: QuickEntryPayload
    }

    enum RouteKind: String, Codable {
        case quickEntry
    }

    struct QuickEntryPayload: Codable {
        let text: String
        let profile: ProfileIdentity?
    }
}
