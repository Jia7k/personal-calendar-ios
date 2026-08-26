import CoreFoundation
import Darwin
import Foundation

enum AppRouteHandoffStoreError: Error, Equatable, Sendable {
    case containerUnavailable
    case unsupportedRoute
    case invalidQuickEntry
    case payloadTooLarge
}

struct AppRouteHandoffStore: Sendable {
    static let filename = "quick-entry-handoff-v1.json"
    static let arrivalNotificationName = "local.personalcalendar.quick-entry-handoff.arrived"

    private static let currentVersion = 1
    private static let maximumPayloadSize = 64 * 1_024
    private static let claimStaleInterval: TimeInterval = 5 * 60

    let fileURL: URL

    static func appGroup(fileManager: FileManager = .default) throws -> Self {
        guard let directory = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: TimetableSnapshotStore.appGroupIdentifier
        ) else {
            throw AppRouteHandoffStoreError.containerUnavailable
        }
        let store = Self(fileURL: directory.appendingPathComponent(filename, isDirectory: false))
        try store.removeOrphanedClaims()
        return store
    }

    func write(_ route: AppRoute) throws {
        try removeOrphanedClaims()

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

        let envelope = Envelope(
            version: Self.currentVersion,
            route: .quickEntry,
            payload: payload
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(envelope)
        guard data.count <= Self.maximumPayloadSize else {
            throw AppRouteHandoffStoreError.payloadTooLarge
        }

        try data.write(to: fileURL, options: .atomic)
        Self.postArrivalNotification()
    }

    func consume() throws -> AppRoute? {
        try removeOrphanedClaims()
        guard let claimedURL = try claimPayload() else { return nil }
        defer { try? FileManager.default.removeItem(at: claimedURL) }

        let values = try claimedURL.resourceValues(forKeys: [.fileSizeKey])
        guard let fileSize = values.fileSize,
              fileSize <= Self.maximumPayloadSize else {
            return nil
        }

        let data = try Data(contentsOf: claimedURL)
        guard data.count <= Self.maximumPayloadSize,
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              envelope.version == Self.currentVersion,
              envelope.route == .quickEntry,
              Self.containsNonWhitespace(envelope.payload.text),
              envelope.payload.profile != .everything else {
            return nil
        }

        return .quickEntry(
            text: envelope.payload.text,
            profile: envelope.payload.profile
        )
    }

    private func claimPayload() throws -> URL? {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }

        let claimedURL = fileURL.deletingLastPathComponent().appendingPathComponent(
            ".\(fileURL.lastPathComponent).consuming-\(ProcessInfo.processInfo.processIdentifier)-\(UUID().uuidString)",
            isDirectory: false
        )
        do {
            try fileManager.moveItem(at: fileURL, to: claimedURL)
            return claimedURL
        } catch {
            guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
            throw error
        }
    }

    private static func containsNonWhitespace(_ value: String) -> Bool {
        value.unicodeScalars.contains {
            !CharacterSet.whitespacesAndNewlines.contains($0)
        }
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
    struct Envelope: Codable {
        let version: Int
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
