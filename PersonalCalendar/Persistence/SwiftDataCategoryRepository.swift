import Foundation
import SwiftData

@MainActor
final class SwiftDataCategoryRepository: CategoryRepository {
    private struct NormalizedCategory {
        let name: String
        let nameKey: String
        let colorHex: String
    }

    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func list() throws -> [CategorySnapshot] {
        try categoryRecords().map(Self.snapshot)
    }

    func create(name: String, colorHex: String) throws -> UUID {
        let normalized = try normalized(name: name, colorHex: colorHex)
        let records = try categoryRecords()
        guard !records.contains(where: { $0.nameKey == normalized.nameKey }) else {
            throw CategoryRepositoryError.duplicateName
        }

        let record = CategoryRecord(
            name: normalized.name,
            colorHex: normalized.colorHex,
            sortOrder: records.count
        )
        try context.transaction {
            context.insert(record)
            try context.save()
        }
        return record.id
    }

    func update(id: UUID, name: String, colorHex: String) throws {
        let normalized = try normalized(name: name, colorHex: colorHex)
        let records = try categoryRecords()
        guard let record = records.first(where: { $0.id == id }) else {
            throw CategoryRepositoryError.categoryNotFound
        }
        guard !records.contains(where: { $0.id != id && $0.nameKey == normalized.nameKey }) else {
            throw CategoryRepositoryError.duplicateName
        }

        try context.transaction {
            record.name = normalized.name
            record.nameKey = normalized.nameKey
            record.colorHex = normalized.colorHex
            try context.save()
        }
    }

    func reorder(ids: [UUID]) throws {
        let records = try categoryRecords()
        let storedIDs = Set(records.map(\.id))
        guard ids.count == records.count,
              Set(ids).count == ids.count,
              Set(ids) == storedIDs else {
            throw CategoryRepositoryError.invalidReorder
        }
        let recordsByID = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })

        try context.transaction {
            for (sortOrder, id) in ids.enumerated() {
                recordsByID[id]?.sortOrder = sortOrder
            }
            try context.save()
        }
    }

    func delete(id: UUID, reassignedTo replacementID: UUID?) throws {
        let records = try categoryRecords()
        guard let deleted = records.first(where: { $0.id == id }) else {
            throw CategoryRepositoryError.categoryNotFound
        }

        var replacement: CategoryRecord?
        if let replacementID {
            guard replacementID != id else {
                throw CategoryRepositoryError.replacementMatchesDeletedCategory
            }
            guard let record = records.first(where: { $0.id == replacementID }) else {
                throw CategoryRepositoryError.replacementCategoryNotFound
            }
            replacement = record
        }

        let routines = try context.fetch(FetchDescriptor<RoutineRecord>())
            .filter { $0.categoryID == id }
        let links = try context.fetch(FetchDescriptor<ExternalCategoryLinkRecord>())
            .filter { $0.categoryID == id }
        let remaining = records.filter { $0.id != id }

        try context.transaction {
            if let replacement {
                for routine in routines {
                    routine.categoryID = replacement.id
                }
                for link in links {
                    link.categoryID = replacement.id
                }
            } else {
                for routine in routines {
                    routine.categoryID = nil
                }
                for link in links {
                    context.delete(link)
                }
            }

            context.delete(deleted)
            for (sortOrder, record) in remaining.enumerated() {
                record.sortOrder = sortOrder
            }
            try context.save()
        }
    }

    func assign(
        categoryID: UUID?,
        to source: ExternalItemSource,
        externalID: String
    ) throws {
        try validateExternalID(externalID)
        if let categoryID {
            guard try categoryRecords().contains(where: { $0.id == categoryID }) else {
                throw CategoryRepositoryError.categoryNotFound
            }
        }

        let linkKey = ExternalCategoryLinkRecord.key(source: source, externalID: externalID)
        let links = try context.fetch(FetchDescriptor<ExternalCategoryLinkRecord>())
        let existing = links.first(where: { $0.key == linkKey })

        guard categoryID != nil || existing != nil else { return }
        try context.transaction {
            if let categoryID {
                if let existing {
                    existing.categoryID = categoryID
                } else {
                    context.insert(
                        ExternalCategoryLinkRecord(
                            source: source,
                            externalID: externalID,
                            categoryID: categoryID
                        )
                    )
                }
            } else if let existing {
                context.delete(existing)
            }
            try context.save()
        }
    }

    func category(
        for source: ExternalItemSource,
        externalID: String
    ) throws -> CategorySnapshot? {
        try validateExternalID(externalID)
        let linkKey = ExternalCategoryLinkRecord.key(source: source, externalID: externalID)
        guard let link = try context.fetch(FetchDescriptor<ExternalCategoryLinkRecord>())
            .first(where: { $0.key == linkKey }) else {
            return nil
        }
        guard let record = try categoryRecords().first(where: { $0.id == link.categoryID }) else {
            return nil
        }
        return Self.snapshot(from: record)
    }

    func removeUnresolvedLinks(
        for source: ExternalItemSource,
        validExternalIDs: Set<String>
    ) throws {
        for externalID in validExternalIDs {
            try validateExternalID(externalID)
        }
        let staleLinks = try context.fetch(FetchDescriptor<ExternalCategoryLinkRecord>())
            .filter { $0.sourceRaw == source.rawValue && !validExternalIDs.contains($0.externalID) }
        guard !staleLinks.isEmpty else { return }

        try context.transaction {
            for link in staleLinks {
                context.delete(link)
            }
            try context.save()
        }
    }

    func seedDefaultsIfNeeded(settings: AppSettingsStore) throws {
        guard !settings.didSeedCategories else { return }

        let seeds = [
            ("Work", "#CB6B4F"),
            ("Personal", "#3A8D7C"),
            ("Health", "#4868A8"),
            ("Errands", "#8A63B8")
        ]
        let normalizedSeeds = try seeds.map { try normalized(name: $0.0, colorHex: $0.1) }
        let existing = try categoryRecords()
        let existingNameKeys = Set(existing.map(\.nameKey))
        let nextSortOrder = (existing.map(\.sortOrder).max() ?? -1) + 1
        let missingSeeds = normalizedSeeds.filter { !existingNameKeys.contains($0.nameKey) }
        let records = missingSeeds.enumerated().map { offset, value in
            CategoryRecord(
                name: value.name,
                colorHex: value.colorHex,
                sortOrder: nextSortOrder + offset
            )
        }

        if !records.isEmpty {
            try context.transaction {
                for record in records {
                    context.insert(record)
                }
                try context.save()
            }
        }
        settings.didSeedCategories = true
    }

    private func categoryRecords() throws -> [CategoryRecord] {
        try context.fetch(FetchDescriptor<CategoryRecord>()).sorted {
            if $0.sortOrder == $1.sortOrder {
                return $0.id.uuidString < $1.id.uuidString
            }
            return $0.sortOrder < $1.sortOrder
        }
    }

    private func normalized(name: String, colorHex: String) throws -> NormalizedCategory {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else {
            throw CategoryRepositoryError.invalidName
        }

        let bytes = Array(colorHex.utf8)
        guard bytes.count == 7,
              bytes.first == 35,
              bytes.dropFirst().allSatisfy(Self.isASCIIHexDigit) else {
            throw CategoryRepositoryError.invalidColor
        }

        return NormalizedCategory(
            name: normalizedName,
            nameKey: CategoryRecord.nameKey(for: normalizedName),
            colorHex: colorHex.uppercased()
        )
    }

    private func validateExternalID(_ externalID: String) throws {
        guard !externalID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CategoryRepositoryError.invalidExternalIdentifier
        }
    }

    private static func isASCIIHexDigit(_ value: UInt8) -> Bool {
        (48...57).contains(value) || (65...70).contains(value) || (97...102).contains(value)
    }

    private static func snapshot(from record: CategoryRecord) -> CategorySnapshot {
        CategorySnapshot(
            id: record.id,
            name: record.name,
            colorHex: record.colorHex,
            sortOrder: record.sortOrder
        )
    }
}
