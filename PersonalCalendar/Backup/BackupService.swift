import Foundation
import SwiftData

@MainActor
protocol BackupServicing: AnyObject {
    func exportData() throws -> Data
    func restore(data: Data) throws
}

@MainActor
final class BackupService: BackupServicing {
    private let context: ModelContext
    private let settings: AppSettingsStore
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(context: ModelContext, settings: AppSettingsStore) {
        self.context = context
        self.settings = settings
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func exportData() throws -> Data {
        let routines = try context.fetch(FetchDescriptor<RoutineRecord>())
            .sorted { $0.id.uuidString < $1.id.uuidString }
        let completions = try context.fetch(FetchDescriptor<RoutineCompletionRecord>())
            .sorted { $0.key < $1.key }
        let categories = try context.fetch(FetchDescriptor<CategoryRecord>())
            .sorted { $0.sortOrder == $1.sortOrder ? $0.id.uuidString < $1.id.uuidString : $0.sortOrder < $1.sortOrder }
        let links = try context.fetch(FetchDescriptor<ExternalCategoryLinkRecord>())
            .sorted { $0.key < $1.key }

        let envelope = BackupEnvelope(
            version: 1,
            exportedAt: .now,
            routines: try routines.map(routineBackup),
            completions: completions.map { .init(routineID: $0.routineID, day: .init(year: $0.year, month: $0.month, day: $0.day), completedAt: $0.completedAt) },
            categories: categories.map { .init(id: $0.id, name: $0.name, colorHex: $0.colorHex, sortOrder: $0.sortOrder) },
            categoryLinks: try links.map(categoryLinkBackup),
            settings: settings.backupValue
        )
        return try encoder.encode(envelope)
    }

    func summary(data: Data) throws -> BackupSummary {
        let envelope = try decodeAndValidate(data)
        return .init(routines: envelope.routines.count, completions: envelope.completions.count, categories: envelope.categories.count, categoryLinks: envelope.categoryLinks.count)
    }

    func restore(data: Data) throws {
        let envelope = try decodeAndValidate(data)
        let previousAutosave = context.autosaveEnabled
        defer { context.autosaveEnabled = previousAutosave }

        do {
            context.autosaveEnabled = false
            try context.transaction {
                try context.delete(model: ExternalCategoryLinkRecord.self, where: nil, includeSubclasses: false)
                try context.delete(model: RoutineCompletionRecord.self, where: nil, includeSubclasses: false)
                try context.delete(model: RoutineRecord.self, where: nil, includeSubclasses: false)
                try context.delete(model: CategoryRecord.self, where: nil, includeSubclasses: false)

                for value in envelope.categories {
                    context.insert(CategoryRecord(id: value.id, name: value.name.trimmingCharacters(in: .whitespacesAndNewlines), colorHex: value.colorHex.uppercased(), sortOrder: value.sortOrder))
                }
                for value in envelope.routines {
                    let draft = RoutineDraft(title: value.title.trimmingCharacters(in: .whitespacesAndNewlines), weekdays: Set(value.weekdays), window: value.window, reminderHour: value.reminderHour, reminderMinute: value.reminderMinute, categoryID: value.categoryID)
                    let record = RoutineRecord(id: value.id, draft: draft, createdAt: value.createdAt)
                    record.isPaused = value.isPaused
                    record.isArchived = value.isArchived
                    context.insert(record)
                }
                for value in envelope.completions {
                    context.insert(RoutineCompletionRecord(routineID: value.routineID, day: value.day, completedAt: value.completedAt))
                }
                for value in envelope.categoryLinks {
                    context.insert(ExternalCategoryLinkRecord(source: value.source, externalID: value.externalID, categoryID: value.categoryID))
                }
                try context.save()
            }
        } catch {
            context.rollback()
            throw BackupError.replacementFailed
        }

        settings.applyBackupValue(envelope.settings)
    }

    private func decodeAndValidate(_ data: Data) throws -> BackupEnvelope {
        let envelope: BackupEnvelope
        do {
            envelope = try decoder.decode(BackupEnvelope.self, from: data)
        } catch {
            throw BackupError.invalidData("The backup file could not be read.")
        }
        try BackupValidator.validate(envelope)
        return envelope
    }

    private func routineBackup(_ record: RoutineRecord) throws -> RoutineBackup {
        guard let window = RoutineWindow(rawValue: record.windowRaw) else {
            throw BackupError.invalidData("A stored routine is invalid.")
        }
        return .init(id: record.id, title: record.title, weekdays: record.weekdays.sorted(), window: window, reminderHour: record.reminderHour, reminderMinute: record.reminderMinute, categoryID: record.categoryID, isPaused: record.isPaused, isArchived: record.isArchived, createdAt: record.createdAt)
    }

    private func categoryLinkBackup(_ record: ExternalCategoryLinkRecord) throws -> CategoryLinkBackup {
        guard let source = ExternalItemSource(rawValue: record.sourceRaw) else {
            throw BackupError.invalidData("A stored category link is invalid.")
        }
        return .init(source: source, externalID: record.externalID, categoryID: record.categoryID)
    }
}
