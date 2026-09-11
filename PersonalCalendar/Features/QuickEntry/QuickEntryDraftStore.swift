import Foundation

enum QuickEntryDraftPhase: String, Codable, Equatable, Sendable {
    case entry
    case confirmation
}

struct QuickEntryDraftSnapshot: Codable, Equatable, Sendable {
    let profileID: UUID
    var text: String
    var preview: QuickEntryPreview?
    var parseTextMarker: String?
    var eventDestinationID: String?
    var taskDestinationID: String?
    var eventDestinationWasExplicitlySelected: Bool
    var taskDestinationWasExplicitlySelected: Bool
    var intendedPhase: QuickEntryDraftPhase
    var checkpointedAt: Date
}

private struct QuickEntryDraftEnvelope: Codable, Equatable, Sendable {
    static let currentVersion = 1

    let version: Int
    var drafts: [QuickEntryDraftSnapshot]

    init(
        version: Int = Self.currentVersion,
        drafts: [QuickEntryDraftSnapshot] = []
    ) {
        self.version = version
        self.drafts = drafts
    }
}

@MainActor
final class QuickEntryDraftStore {
    static let maximumProfiles = 20
    static let maximumTextCharacters = 4_096
    static let maximumEncodedBytes = 131_072

    private let defaults: UserDefaults
    private let key: String
    private var envelope: QuickEntryDraftEnvelope

    init(defaults: UserDefaults, key: String = "quickEntryDrafts") {
        self.defaults = defaults
        self.key = key
        envelope = Self.load(defaults.data(forKey: key))
    }

    func draft(for profileID: UUID) -> QuickEntryDraftSnapshot? {
        envelope.drafts.first { $0.profileID == profileID }
    }

    @discardableResult
    func save(_ draft: QuickEntryDraftSnapshot) -> Bool {
        guard Self.isValid(draft) else { return false }

        var candidate = envelope
        candidate.drafts.removeAll { $0.profileID == draft.profileID }
        candidate.drafts.append(draft)
        candidate.drafts.sort { lhs, rhs in
            if lhs.checkpointedAt != rhs.checkpointedAt {
                return lhs.checkpointedAt > rhs.checkpointedAt
            }
            return lhs.profileID.uuidString < rhs.profileID.uuidString
        }
        if candidate.drafts.count > Self.maximumProfiles {
            candidate.drafts.removeLast(
                candidate.drafts.count - Self.maximumProfiles
            )
        }
        guard let data = Self.encoded(candidate) else { return false }

        envelope = candidate
        defaults.set(data, forKey: key)
        return true
    }

    func removeDraft(for profileID: UUID) {
        let previousCount = envelope.drafts.count
        envelope.drafts.removeAll { $0.profileID == profileID }
        guard envelope.drafts.count != previousCount else { return }
        persistOrReset()
    }

    func reconcile(validProfileIDs: Set<UUID>) {
        let previousCount = envelope.drafts.count
        envelope.drafts.removeAll { !validProfileIDs.contains($0.profileID) }
        guard envelope.drafts.count != previousCount else { return }
        persistOrReset()
    }

    func reset() {
        envelope = .init()
        defaults.removeObject(forKey: key)
    }

    private func persistOrReset() {
        guard !envelope.drafts.isEmpty else {
            reset()
            return
        }
        guard let data = Self.encoded(envelope) else {
            reset()
            return
        }
        defaults.set(data, forKey: key)
    }

    private static func load(_ data: Data?) -> QuickEntryDraftEnvelope {
        guard let data,
              data.count <= maximumEncodedBytes,
              let decoded = try? JSONDecoder().decode(
                  QuickEntryDraftEnvelope.self,
                  from: data
              ),
              isValid(decoded) else { return .init() }
        return decoded
    }

    private static func encoded(_ envelope: QuickEntryDraftEnvelope) -> Data? {
        guard isValid(envelope) else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(envelope),
              data.count <= maximumEncodedBytes else { return nil }
        return data
    }

    private static func isValid(_ envelope: QuickEntryDraftEnvelope) -> Bool {
        guard envelope.version == QuickEntryDraftEnvelope.currentVersion,
              envelope.drafts.count <= maximumProfiles else { return false }
        var profileIDs = Set<UUID>()
        return envelope.drafts.allSatisfy { draft in
            profileIDs.insert(draft.profileID).inserted && isValid(draft)
        }
    }

    private static func isValid(_ draft: QuickEntryDraftSnapshot) -> Bool {
        guard draft.text.count <= maximumTextCharacters,
              !draft.text.trimmingCharacters(
                  in: .whitespacesAndNewlines
              ).isEmpty,
              draft.checkpointedAt.timeIntervalSinceReferenceDate.isFinite
        else { return false }

        if let marker = draft.parseTextMarker,
           marker.count > maximumTextCharacters {
            return false
        }
        guard let preview = draft.preview else {
            return draft.parseTextMarker == nil
                && draft.intendedPhase == .entry
        }
        return previewHasFiniteDates(preview)
            && preview.title.count <= maximumTextCharacters
    }

    private static func previewHasFiniteDates(_ preview: QuickEntryPreview) -> Bool {
        let dates = [
            preview.startDate,
            preview.endDate,
            preview.dueDate,
            preview.reminderDate,
            preview.recurrence?.endDate
        ].compactMap { $0 }
        return dates.allSatisfy(\.timeIntervalSinceReferenceDate.isFinite)
    }
}
