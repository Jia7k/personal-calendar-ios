import Foundation

struct QuickEntryHistoryItem: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let text: String
    let profileIdentity: ProfileIdentity
    let lastUsedAt: Date
}

struct QuickEntryRememberedChoices: Codable, Equatable, Sendable {
    var durationMinutes: Int?
    var categoryID: UUID?
    var destinationID: String?
}

struct QuickEntryPreferenceRecord: Codable, Equatable, Sendable {
    let profileID: UUID
    let kind: QuickEntryKind
    var choices: QuickEntryRememberedChoices
}

struct QuickEntryMemoryV1: Codable, Equatable, Sendable {
    static let currentVersion = 1

    let version: Int
    var history: [QuickEntryHistoryItem]
    var preferences: [QuickEntryPreferenceRecord]

    init(
        version: Int = Self.currentVersion,
        history: [QuickEntryHistoryItem] = [],
        preferences: [QuickEntryPreferenceRecord] = []
    ) {
        self.version = version
        self.history = history
        self.preferences = preferences
    }
}

@MainActor
final class QuickEntryHistoryStore {
    static let maximumHistoryItems = 10

    private struct HistoryKey: Hashable {
        let profileID: UUID
        let normalizedText: String
    }

    private struct PreferenceKey: Hashable {
        let profileID: UUID
        let kind: String
    }

    private let defaults: UserDefaults
    private let key: String
    private var memory: QuickEntryMemoryV1

    init(defaults: UserDefaults, key: String = "quickEntryMemory") {
        self.defaults = defaults
        self.key = key
        memory = Self.load(defaults.data(forKey: key))
    }

    var backupValue: QuickEntryMemoryV1 {
        Self.canonicalized(memory)
    }

    func items(for identity: ProfileIdentity) -> [QuickEntryHistoryItem] {
        guard case let .saved(profileID) = identity else { return [] }
        return memory.history.filter { item in
            guard case let .saved(itemProfileID) = item.profileIdentity else {
                return false
            }
            return itemProfileID == profileID
        }
    }

    func record(
        text: String,
        profileIdentity: ProfileIdentity,
        at date: Date
    ) {
        guard case let .saved(profileID) = profileIdentity,
              date.timeIntervalSinceReferenceDate.isFinite else { return }
        let trimmedText = Self.trimmed(text)
        guard !trimmedText.isEmpty else { return }

        let key = HistoryKey(
            profileID: profileID,
            normalizedText: Self.normalized(trimmedText)
        )
        let existingID = memory.history.first(where: {
            Self.historyKey(for: $0) == key
        })?.id
        memory.history.removeAll { Self.historyKey(for: $0) == key }
        memory.history.append(
            .init(
                id: existingID ?? UUID(),
                text: trimmedText,
                profileIdentity: profileIdentity,
                lastUsedAt: date
            )
        )
        memory = Self.canonicalized(memory)
        persist()
    }

    func clearHistory(for identity: ProfileIdentity) {
        guard case let .saved(profileID) = identity else { return }
        let previousCount = memory.history.count
        memory.history.removeAll {
            guard case let .saved(itemProfileID) = $0.profileIdentity else {
                return false
            }
            return itemProfileID == profileID
        }
        guard memory.history.count != previousCount else { return }
        persist()
    }

    func preference(
        profileID: UUID,
        kind: QuickEntryKind
    ) -> QuickEntryRememberedChoices? {
        memory.preferences.first {
            $0.profileID == profileID && $0.kind.rawValue == kind.rawValue
        }?.choices
    }

    func setPreference(
        _ choices: QuickEntryRememberedChoices,
        profileID: UUID,
        kind: QuickEntryKind
    ) {
        var safeChoices = choices
        if let duration = safeChoices.durationMinutes,
           !(1...1_440).contains(duration) {
            safeChoices.durationMinutes = nil
        }

        memory.preferences.removeAll {
            $0.profileID == profileID && $0.kind.rawValue == kind.rawValue
        }
        memory.preferences.append(
            .init(profileID: profileID, kind: kind, choices: safeChoices)
        )
        memory = Self.canonicalized(memory)
        persist()
    }

    func replace(
        with replacement: QuickEntryMemoryV1,
        validProfileIDs: Set<UUID>
    ) {
        guard Self.isStructurallyValid(replacement) else {
            reset()
            return
        }

        var filtered = replacement
        filtered.history = filtered.history.filter {
            guard case let .saved(profileID) = $0.profileIdentity else {
                return false
            }
            return validProfileIDs.contains(profileID)
        }
        filtered.preferences = filtered.preferences.filter {
            validProfileIDs.contains($0.profileID)
        }
        memory = Self.canonicalized(filtered)
        persist()
    }

    func reconcile(validProfileIDs: Set<UUID>) {
        let previous = memory
        memory.history.removeAll {
            guard case let .saved(profileID) = $0.profileIdentity else {
                return true
            }
            return !validProfileIDs.contains(profileID)
        }
        memory.preferences.removeAll {
            !validProfileIDs.contains($0.profileID)
        }
        guard memory != previous else { return }
        memory = Self.canonicalized(memory)
        persist()
    }

    func reset() {
        memory = .init()
        defaults.removeObject(forKey: key)
    }

    private func persist() {
        let canonical = Self.canonicalized(memory)
        guard Self.isStructurallyValid(canonical) else {
            reset()
            return
        }
        memory = canonical
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(canonical) else {
            reset()
            return
        }
        defaults.set(data, forKey: key)
    }

    private static func load(_ data: Data?) -> QuickEntryMemoryV1 {
        guard let data,
              let decoded = try? JSONDecoder().decode(
                  QuickEntryMemoryV1.self,
                  from: data
              ),
              isStructurallyValid(decoded) else { return .init() }
        return canonicalized(decoded)
    }

    private static func isStructurallyValid(
        _ value: QuickEntryMemoryV1
    ) -> Bool {
        guard value.version == QuickEntryMemoryV1.currentVersion,
              value.history.count <= maximumHistoryItems else { return false }

        var itemIDs = Set<UUID>()
        var historyKeys = Set<HistoryKey>()
        for item in value.history {
            guard case .saved = item.profileIdentity,
                  itemIDs.insert(item.id).inserted,
                  item.text == trimmed(item.text),
                  !item.text.isEmpty,
                  item.lastUsedAt.timeIntervalSinceReferenceDate.isFinite,
                  let key = historyKey(for: item),
                  historyKeys.insert(key).inserted else { return false }
        }

        var preferenceKeys = Set<PreferenceKey>()
        for preference in value.preferences {
            if let duration = preference.choices.durationMinutes,
               !(1...1_440).contains(duration) {
                return false
            }
            let key = PreferenceKey(
                profileID: preference.profileID,
                kind: preference.kind.rawValue
            )
            guard preferenceKeys.insert(key).inserted else { return false }
        }
        return true
    }

    private static func canonicalized(
        _ value: QuickEntryMemoryV1
    ) -> QuickEntryMemoryV1 {
        var result = value
        result.history.sort(by: historyComesFirst)
        if result.history.count > maximumHistoryItems {
            result.history.removeLast(result.history.count - maximumHistoryItems)
        }
        result.preferences.sort(by: preferenceComesFirst)
        return result
    }

    private static func historyComesFirst(
        _ left: QuickEntryHistoryItem,
        _ right: QuickEntryHistoryItem
    ) -> Bool {
        if left.lastUsedAt != right.lastUsedAt {
            return left.lastUsedAt > right.lastUsedAt
        }
        if left.profileIdentity.storageKey != right.profileIdentity.storageKey {
            return left.profileIdentity.storageKey < right.profileIdentity.storageKey
        }
        let leftText = normalized(left.text)
        let rightText = normalized(right.text)
        if leftText != rightText { return leftText < rightText }
        return left.id.uuidString.lowercased() < right.id.uuidString.lowercased()
    }

    private static func preferenceComesFirst(
        _ left: QuickEntryPreferenceRecord,
        _ right: QuickEntryPreferenceRecord
    ) -> Bool {
        let leftID = left.profileID.uuidString.lowercased()
        let rightID = right.profileID.uuidString.lowercased()
        if leftID != rightID { return leftID < rightID }
        return left.kind.rawValue < right.kind.rawValue
    }

    private static func historyKey(for item: QuickEntryHistoryItem) -> HistoryKey? {
        guard case let .saved(profileID) = item.profileIdentity else {
            return nil
        }
        return .init(
            profileID: profileID,
            normalizedText: normalized(item.text)
        )
    }

    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalized(_ text: String) -> String {
        let locale = Locale(identifier: "en_US_POSIX")
        return trimmed(text)
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: locale
            )
            .lowercased(with: locale)
    }
}
