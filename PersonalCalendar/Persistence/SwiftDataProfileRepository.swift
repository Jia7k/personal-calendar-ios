import Foundation
import SwiftData

@MainActor
final class SwiftDataProfileRepository: ProfileRepository {
    private struct NormalizedProfile {
        let name: String
        let nameKey: String
        let colorHex: String
        let symbolName: String
        let calendarIDs: [String]
        let reminderListIDs: [String]
        let routineIDs: [UUID]
        let defaultCalendarID: String?
        let defaultReminderListID: String?
    }

    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func list() throws -> [ProfileSnapshot] {
        try records().map(Self.snapshot)
    }

    func profile(id: UUID) throws -> ProfileSnapshot {
        guard let record = try records().first(where: { $0.id == id }) else {
            throw ProfileRepositoryError.profileNotFound
        }
        return Self.snapshot(record)
    }

    func create(_ draft: ProfileDraft, id requestedID: UUID?) throws -> UUID {
        let normalized = try normalize(draft)
        let stored = try records()
        guard !stored.contains(where: { ProfileRecord.nameKey(for: $0.name) == normalized.nameKey }) else {
            throw ProfileRepositoryError.duplicateName
        }
        let id = requestedID ?? UUID()
        guard !stored.contains(where: { $0.id == id }) else {
            throw ProfileRepositoryError.duplicateIdentifier
        }
        let record = makeRecord(id: id, normalized: normalized, sortOrder: stored.count)
        try context.transaction {
            context.insert(record)
            try context.save()
        }
        return id
    }

    func update(id: UUID, draft: ProfileDraft) throws {
        let normalized = try normalize(draft)
        let stored = try records()
        guard let record = stored.first(where: { $0.id == id }) else {
            throw ProfileRepositoryError.profileNotFound
        }
        guard !stored.contains(where: {
            $0.id != id && ProfileRecord.nameKey(for: $0.name) == normalized.nameKey
        }) else {
            throw ProfileRepositoryError.duplicateName
        }

        try context.transaction {
            record.name = normalized.name
            record.colorHex = normalized.colorHex
            record.symbolName = normalized.symbolName
            record.calendarIDs = normalized.calendarIDs
            record.reminderListIDs = normalized.reminderListIDs
            record.routineIDs = normalized.routineIDs
            record.defaultCalendarID = normalized.defaultCalendarID
            record.defaultReminderListID = normalized.defaultReminderListID
            try context.save()
        }
    }

    func reorder(_ ids: [UUID]) throws {
        let stored = try records()
        guard ids.count == stored.count,
              Set(ids).count == ids.count,
              Set(ids) == Set(stored.map(\.id)) else {
            throw ProfileRepositoryError.invalidReorder
        }
        let byID = Dictionary(uniqueKeysWithValues: stored.map { ($0.id, $0) })
        try context.transaction {
            for (order, id) in ids.enumerated() {
                byID[id]?.sortOrder = order
            }
            try context.save()
        }
    }

    func delete(id: UUID) throws {
        let stored = try records()
        guard let record = stored.first(where: { $0.id == id }) else {
            throw ProfileRepositoryError.profileNotFound
        }
        guard stored.count > 1 else {
            throw ProfileRepositoryError.cannotDeleteLastProfile
        }
        let remaining = stored.filter { $0.id != id }
        try context.transaction {
            context.delete(record)
            for (order, value) in remaining.enumerated() {
                value.sortOrder = order
            }
            try context.save()
        }
    }

    func removeRoutineID(_ id: UUID) throws {
        let affected = try records().filter { $0.routineIDs.contains(id) }
        guard !affected.isEmpty else { return }
        try context.transaction {
            for record in affected {
                record.routineIDs.removeAll { $0 == id }
            }
            try context.save()
        }
    }

    func unionMembership() throws -> ProfileMembership {
        let stored = try records()
        return ProfileMembership(
            calendarIDs: stored.reduce(into: Set<String>()) { $0.formUnion($1.calendarIDs) },
            reminderListIDs: stored.reduce(into: Set<String>()) { $0.formUnion($1.reminderListIDs) },
            routineIDs: stored.reduce(into: Set<UUID>()) { $0.formUnion($1.routineIDs) }
        )
    }

    private func records() throws -> [ProfileRecord] {
        try context.fetch(FetchDescriptor<ProfileRecord>()).sorted {
            if $0.sortOrder == $1.sortOrder {
                return $0.id.uuidString < $1.id.uuidString
            }
            return $0.sortOrder < $1.sortOrder
        }
    }

    private func normalize(_ draft: ProfileDraft) throws -> NormalizedProfile {
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw ProfileRepositoryError.invalidName }
        guard Self.isValidColor(draft.colorHex) else { throw ProfileRepositoryError.invalidColor }
        guard ProfileSymbols.allowed.contains(draft.symbolName) else {
            throw ProfileRepositoryError.invalidSymbol
        }
        guard draft.calendarIDs.allSatisfy(Self.isValidExternalID),
              draft.reminderListIDs.allSatisfy(Self.isValidExternalID) else {
            throw ProfileRepositoryError.invalidExternalIdentifier
        }
        if let defaultCalendarID = draft.defaultCalendarID,
           !draft.calendarIDs.contains(defaultCalendarID) {
            throw ProfileRepositoryError.defaultCalendarNotMember
        }
        if let defaultReminderListID = draft.defaultReminderListID,
           !draft.reminderListIDs.contains(defaultReminderListID) {
            throw ProfileRepositoryError.defaultReminderListNotMember
        }

        return NormalizedProfile(
            name: name,
            nameKey: ProfileRecord.nameKey(for: name),
            colorHex: draft.colorHex.uppercased(),
            symbolName: draft.symbolName,
            calendarIDs: draft.calendarIDs.sorted(),
            reminderListIDs: draft.reminderListIDs.sorted(),
            routineIDs: draft.routineIDs.sorted { $0.uuidString < $1.uuidString },
            defaultCalendarID: draft.defaultCalendarID,
            defaultReminderListID: draft.defaultReminderListID
        )
    }

    private func makeRecord(
        id: UUID,
        normalized: NormalizedProfile,
        sortOrder: Int
    ) -> ProfileRecord {
        ProfileRecord(
            id: id,
            name: normalized.name,
            colorHex: normalized.colorHex,
            symbolName: normalized.symbolName,
            sortOrder: sortOrder,
            calendarIDs: normalized.calendarIDs,
            reminderListIDs: normalized.reminderListIDs,
            routineIDs: normalized.routineIDs,
            defaultCalendarID: normalized.defaultCalendarID,
            defaultReminderListID: normalized.defaultReminderListID
        )
    }

    private static func snapshot(_ record: ProfileRecord) -> ProfileSnapshot {
        ProfileSnapshot(
            id: record.id,
            name: record.name,
            colorHex: record.colorHex,
            symbolName: record.symbolName,
            sortOrder: record.sortOrder,
            calendarIDs: Set(record.calendarIDs),
            reminderListIDs: Set(record.reminderListIDs),
            routineIDs: Set(record.routineIDs),
            defaultCalendarID: record.defaultCalendarID,
            defaultReminderListID: record.defaultReminderListID
        )
    }

    private static func isValidColor(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        return bytes.count == 7 && bytes.first == 35 && bytes.dropFirst().allSatisfy {
            (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0)
        }
    }

    private static func isValidExternalID(_ value: String) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
