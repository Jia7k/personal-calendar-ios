import Foundation
import SwiftData

@MainActor
protocol BackupServicing: AnyObject {
    func exportData() throws -> Data
    func restore(data: Data) throws
}

@MainActor
final class BackupService: BackupServicing {
    private enum DecodedBackup {
        case v1(BackupEnvelopeV1)
        case v2(BackupEnvelopeV2)
        case v3(BackupEnvelopeV3)
    }

    private let context: ModelContext
    private let settings: AppSettingsStore
    private let profileMigration: ProfileMigrationCoordinator?
    private let onRestored: @MainActor () -> Void
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        context: ModelContext,
        settings: AppSettingsStore,
        profileMigration: ProfileMigrationCoordinator? = nil,
        onRestored: @escaping @MainActor () -> Void = {}
    ) {
        self.context = context
        self.settings = settings
        self.profileMigration = profileMigration
        self.onRestored = onRestored
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
            .sorted {
                $0.sortOrder == $1.sortOrder
                    ? $0.id.uuidString < $1.id.uuidString
                    : $0.sortOrder < $1.sortOrder
            }
        let links = try context.fetch(FetchDescriptor<ExternalCategoryLinkRecord>())
            .sorted { $0.key < $1.key }
        let profiles = try context.fetch(FetchDescriptor<ProfileRecord>())
            .sorted {
                $0.sortOrder == $1.sortOrder
                    ? $0.id.uuidString < $1.id.uuidString
                    : $0.sortOrder < $1.sortOrder
            }

        let envelope = BackupEnvelopeV3(
            version: 3,
            exportedAt: .now,
            routines: try routines.map(routineBackup),
            completions: completions.map {
                .init(
                    routineID: $0.routineID,
                    day: .init(year: $0.year, month: $0.month, day: $0.day),
                    completedAt: $0.completedAt
                )
            },
            categories: categories.map {
                .init(id: $0.id, name: $0.name, colorHex: $0.colorHex, sortOrder: $0.sortOrder)
            },
            categoryLinks: try links.map(categoryLinkBackup),
            profiles: profiles.map(profileBackup),
            settings: settings.backupValueV3
        )
        try BackupValidator.validate(envelope)
        return try encoder.encode(envelope)
    }

    func summary(data: Data) throws -> BackupSummary {
        switch try decodeAndValidate(data) {
        case let .v1(envelope):
            return .init(
                routines: envelope.routines.count,
                completions: envelope.completions.count,
                categories: envelope.categories.count,
                categoryLinks: envelope.categoryLinks.count,
                profiles: 0
            )
        case let .v2(envelope):
            return .init(
                routines: envelope.routines.count,
                completions: envelope.completions.count,
                categories: envelope.categories.count,
                categoryLinks: envelope.categoryLinks.count,
                profiles: envelope.profiles.count
            )
        case let .v3(envelope):
            return .init(
                routines: envelope.routines.count,
                completions: envelope.completions.count,
                categories: envelope.categories.count,
                categoryLinks: envelope.categoryLinks.count,
                profiles: envelope.profiles.count
            )
        }
    }

    func restore(data: Data) throws {
        switch try decodeAndValidate(data) {
        case let .v1(envelope):
            try restoreV1(envelope)
        case let .v2(envelope):
            try restoreV2(envelope)
        case let .v3(envelope):
            try restoreV3(envelope)
        }
        onRestored()
    }

    private func restoreV1(_ envelope: BackupEnvelopeV1) throws {
        guard let profileMigration else { throw BackupError.replacementFailed }
        try replaceAppOwnedData(
            routines: envelope.routines,
            completions: envelope.completions,
            categories: envelope.categories,
            categoryLinks: envelope.categoryLinks,
            profiles: []
        )

        settings.applyBackupValue(envelope.settings)
        resetSettingsAddedAfterV1()
        let legacy = LegacyProfileSelectionSnapshot(
            calendarIDs: Set(envelope.settings.selectedCalendarIDs),
            reminderListIDs: Set(envelope.settings.selectedReminderListIDs),
            defaultCalendarID: envelope.settings.defaultCalendarID,
            defaultReminderListID: envelope.settings.defaultReminderListID,
            calendarSelectionWasExplicit: envelope.settings.calendarSelectionIsExplicit,
            reminderSelectionWasExplicit: envelope.settings.reminderSelectionIsExplicit
        )
        do {
            try profileMigration.resetAndMigrate(legacy: legacy)
            settings.setActiveProfile(.everything)
        } catch {
            throw BackupError.replacementFailed
        }
    }

    private func restoreV2(_ envelope: BackupEnvelopeV2) throws {
        try replaceAppOwnedData(
            routines: envelope.routines,
            completions: envelope.completions,
            categories: envelope.categories,
            categoryLinks: envelope.categoryLinks,
            profiles: envelope.profiles
        )
        settings.applyBackupValue(
            envelope.settings,
            validProfileIDs: Set(envelope.profiles.map(\.id))
        )
        resetSettingsAddedAfterV1()
    }

    private func restoreV3(_ envelope: BackupEnvelopeV3) throws {
        try replaceAppOwnedData(
            routines: envelope.routines,
            completions: envelope.completions,
            categories: envelope.categories,
            categoryLinks: envelope.categoryLinks,
            profiles: envelope.profiles
        )

        let validProfileIDs = Set(envelope.profiles.map(\.id))
        settings.applyBackupValue(
            envelope.settings.legacy,
            validProfileIDs: validProfileIDs
        )
        settings.reconcileClassAlertPreferences(validProfileIDs: [])
        for record in envelope.settings.classAlertPreferences
            where validProfileIDs.contains(record.profileID) {
            settings.setClassAlertPreference(
                record.preference,
                for: record.profileID
            )
        }
        settings.quickEntryHistory.replace(
            with: envelope.settings.quickEntryMemory,
            validProfileIDs: validProfileIDs
        )
    }

    private func resetSettingsAddedAfterV1() {
        settings.reconcileClassAlertPreferences(validProfileIDs: [])
        settings.quickEntryHistory.reset()
    }

    private func replaceAppOwnedData(
        routines: [RoutineBackup],
        completions: [CompletionBackup],
        categories: [CategorySnapshot],
        categoryLinks: [CategoryLinkBackup],
        profiles: [ProfileSnapshot]
    ) throws {
        let previousAutosave = context.autosaveEnabled
        defer { context.autosaveEnabled = previousAutosave }

        do {
            context.autosaveEnabled = false
            try context.transaction {
                try context.delete(model: ExternalCategoryLinkRecord.self, where: nil, includeSubclasses: false)
                try context.delete(model: RoutineCompletionRecord.self, where: nil, includeSubclasses: false)
                try context.delete(model: RoutineRecord.self, where: nil, includeSubclasses: false)
                try context.delete(model: CategoryRecord.self, where: nil, includeSubclasses: false)
                try context.delete(model: ProfileRecord.self, where: nil, includeSubclasses: false)

                for value in categories {
                    context.insert(CategoryRecord(
                        id: value.id,
                        name: value.name.trimmingCharacters(in: .whitespacesAndNewlines),
                        colorHex: value.colorHex.uppercased(),
                        sortOrder: value.sortOrder
                    ))
                }
                for value in routines {
                    let draft = RoutineDraft(
                        title: value.title.trimmingCharacters(in: .whitespacesAndNewlines),
                        weekdays: Set(value.weekdays),
                        window: value.window,
                        reminderHour: value.reminderHour,
                        reminderMinute: value.reminderMinute,
                        categoryID: value.categoryID
                    )
                    let record = RoutineRecord(id: value.id, draft: draft, createdAt: value.createdAt)
                    record.isPaused = value.isPaused
                    record.isArchived = value.isArchived
                    context.insert(record)
                }
                for value in completions {
                    context.insert(RoutineCompletionRecord(
                        routineID: value.routineID,
                        day: value.day,
                        completedAt: value.completedAt
                    ))
                }
                for value in categoryLinks {
                    context.insert(ExternalCategoryLinkRecord(
                        source: value.source,
                        externalID: value.externalID,
                        categoryID: value.categoryID
                    ))
                }
                for value in profiles {
                    context.insert(ProfileRecord(
                        id: value.id,
                        name: value.name.trimmingCharacters(in: .whitespacesAndNewlines),
                        colorHex: value.colorHex.uppercased(),
                        symbolName: value.symbolName,
                        sortOrder: value.sortOrder,
                        calendarIDs: value.calendarIDs.sorted(),
                        reminderListIDs: value.reminderListIDs.sorted(),
                        routineIDs: value.routineIDs.sorted { $0.uuidString < $1.uuidString },
                        defaultCalendarID: value.defaultCalendarID,
                        defaultReminderListID: value.defaultReminderListID
                    ))
                }
            }
        } catch {
            context.rollback()
            throw BackupError.replacementFailed
        }
    }

    private func decodeAndValidate(_ data: Data) throws -> DecodedBackup {
        let header: BackupVersionHeader
        do {
            header = try decoder.decode(BackupVersionHeader.self, from: data)
        } catch {
            throw BackupError.invalidData("The backup file could not be read.")
        }

        switch header.version {
        case 1:
            let envelope: BackupEnvelopeV1 = try decode(data)
            try BackupValidator.validate(envelope)
            return .v1(envelope)
        case 2:
            let envelope: BackupEnvelopeV2 = try decode(data)
            try BackupValidator.validate(envelope)
            return .v2(envelope)
        case 3:
            let envelope: BackupEnvelopeV3 = try decode(data)
            try BackupValidator.validate(envelope)
            return .v3(envelope)
        default:
            throw BackupError.unsupportedVersion(header.version)
        }
    }

    private func decode<Value: Decodable>(_ data: Data) throws -> Value {
        do {
            return try decoder.decode(Value.self, from: data)
        } catch let error as BackupError {
            throw error
        } catch {
            throw BackupError.invalidData("The backup file could not be read.")
        }
    }

    private func routineBackup(_ record: RoutineRecord) throws -> RoutineBackup {
        guard let window = RoutineWindow(rawValue: record.windowRaw) else {
            throw BackupError.invalidData("A stored routine is invalid.")
        }
        return .init(
            id: record.id,
            title: record.title,
            weekdays: record.weekdays.sorted(),
            window: window,
            reminderHour: record.reminderHour,
            reminderMinute: record.reminderMinute,
            categoryID: record.categoryID,
            isPaused: record.isPaused,
            isArchived: record.isArchived,
            createdAt: record.createdAt
        )
    }

    private func categoryLinkBackup(_ record: ExternalCategoryLinkRecord) throws -> CategoryLinkBackup {
        guard let source = ExternalItemSource(rawValue: record.sourceRaw) else {
            throw BackupError.invalidData("A stored category link is invalid.")
        }
        return .init(source: source, externalID: record.externalID, categoryID: record.categoryID)
    }

    private func profileBackup(_ record: ProfileRecord) -> ProfileSnapshot {
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
}
