import Foundation

struct BackupVersionHeader: Decodable, Sendable {
    let version: Int
}

struct BackupEnvelopeV1: Codable, Equatable, Sendable {
    let version: Int
    let exportedAt: Date
    let routines: [RoutineBackup]
    let completions: [CompletionBackup]
    let categories: [CategorySnapshot]
    let categoryLinks: [CategoryLinkBackup]
    let settings: SettingsBackupV1
}

struct BackupEnvelopeV2: Codable, Equatable, Sendable {
    let version: Int
    let exportedAt: Date
    let routines: [RoutineBackup]
    let completions: [CompletionBackup]
    let categories: [CategorySnapshot]
    let categoryLinks: [CategoryLinkBackup]
    let profiles: [ProfileSnapshot]
    let settings: SettingsBackupV2
}

struct RoutineBackup: Codable, Equatable, Sendable {
    let id: UUID
    let title: String
    let weekdays: [Int]
    let window: RoutineWindow
    let reminderHour: Int?
    let reminderMinute: Int?
    let categoryID: UUID?
    let isPaused: Bool
    let isArchived: Bool
    let createdAt: Date
}

struct CompletionBackup: Codable, Equatable, Sendable {
    let routineID: UUID
    let day: LocalDay
    let completedAt: Date
}

struct CategoryLinkBackup: Codable, Equatable, Sendable {
    let source: ExternalItemSource
    let externalID: String
    let categoryID: UUID
}

struct SettingsBackupV1: Codable, Equatable, Sendable {
    let selectedCalendarIDs: [String]
    let selectedReminderListIDs: [String]
    let defaultCalendarID: String?
    let defaultReminderListID: String?
    let calendarSelectionIsExplicit: Bool
    let reminderSelectionIsExplicit: Bool
    let morningSummaryEnabled: Bool
    let morningSummaryHour: Int
    let morningSummaryMinute: Int
    let showNextItemOnLockScreen: Bool
    let didSeedCategories: Bool
    let didCompleteOnboarding: Bool
}

struct SettingsBackupV2: Codable, Equatable, Sendable {
    let legacy: SettingsBackupV1
    let activeProfileIdentity: ProfileIdentity
    let lastActiveSavedProfileID: UUID?
    let completedProfileMigrationParts: [ProfileMigrationPart]
}

enum BackupError: Error, Equatable {
    case unsupportedVersion(Int)
    case invalidData(String)
    case replacementFailed
}

struct BackupSummary: Equatable, Sendable {
    let routines: Int
    let completions: Int
    let categories: Int
    let categoryLinks: Int
    let profiles: Int
}

enum BackupValidator {
    static func validate(_ envelope: BackupEnvelopeV1) throws {
        guard envelope.version == 1 else { throw BackupError.unsupportedVersion(envelope.version) }
        try validateAppOwnedData(
            routines: envelope.routines,
            completions: envelope.completions,
            categories: envelope.categories,
            categoryLinks: envelope.categoryLinks,
            settings: envelope.settings
        )
    }

    static func validate(_ envelope: BackupEnvelopeV2) throws {
        guard envelope.version == 2 else { throw BackupError.unsupportedVersion(envelope.version) }
        try validateAppOwnedData(
            routines: envelope.routines,
            completions: envelope.completions,
            categories: envelope.categories,
            categoryLinks: envelope.categoryLinks,
            settings: envelope.settings.legacy
        )
        try validateProfiles(envelope.profiles, routineIDs: Set(envelope.routines.map(\.id)))
        guard Set(envelope.settings.completedProfileMigrationParts).count
                == envelope.settings.completedProfileMigrationParts.count else {
            throw BackupError.invalidData("Profile migration markers must be unique.")
        }
    }

    private static func validateAppOwnedData(
        routines: [RoutineBackup],
        completions: [CompletionBackup],
        categories: [CategorySnapshot],
        categoryLinks: [CategoryLinkBackup],
        settings: SettingsBackupV1
    ) throws {
        guard Set(routines.map(\.id)).count == routines.count else {
            throw BackupError.invalidData("Routine identifiers must be unique.")
        }
        guard Set(categories.map(\.id)).count == categories.count else {
            throw BackupError.invalidData("Category identifiers must be unique.")
        }
        let categoryNames = categories.map {
            ProfileRecord.nameKey(for: $0.name.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        guard Set(categoryNames).count == categories.count else {
            throw BackupError.invalidData("Category names must be unique.")
        }
        guard Set(completions.map {
            RoutineCompletionRecord.key(routineID: $0.routineID, day: $0.day)
        }).count == completions.count else {
            throw BackupError.invalidData("Routine completions must be unique per day.")
        }
        guard Set(categoryLinks.map {
            ExternalCategoryLinkRecord.key(source: $0.source, externalID: $0.externalID)
        }).count == categoryLinks.count else {
            throw BackupError.invalidData("External category links must be unique.")
        }

        let routineIDs = Set(routines.map(\.id))
        let categoryIDs = Set(categories.map(\.id))
        guard completions.allSatisfy({ routineIDs.contains($0.routineID) }) else {
            throw BackupError.invalidData("A completion refers to a missing routine.")
        }
        guard completions.allSatisfy({ isValid($0.day) }) else {
            throw BackupError.invalidData("A completion date is invalid.")
        }
        guard routines.allSatisfy({ $0.categoryID.map(categoryIDs.contains) ?? true }) else {
            throw BackupError.invalidData("A routine refers to a missing category.")
        }
        guard categoryLinks.allSatisfy({
            !$0.externalID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && categoryIDs.contains($0.categoryID)
        }) else {
            throw BackupError.invalidData("A category link is invalid.")
        }
        guard routines.allSatisfy({
            !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !$0.weekdays.isEmpty
                && $0.weekdays.allSatisfy((1...7).contains)
                && Set($0.weekdays).count == $0.weekdays.count
        }) else {
            throw BackupError.invalidData("A routine is invalid.")
        }
        guard routines.allSatisfy(validReminderTime) else {
            throw BackupError.invalidData("A routine reminder time is invalid.")
        }
        guard categories.allSatisfy({
            !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && isValidColor($0.colorHex)
        }) else {
            throw BackupError.invalidData("A category is invalid.")
        }
        guard Set(settings.selectedCalendarIDs).count == settings.selectedCalendarIDs.count,
              Set(settings.selectedReminderListIDs).count == settings.selectedReminderListIDs.count else {
            throw BackupError.invalidData("Source selections must not contain duplicates.")
        }
        guard settings.selectedCalendarIDs.allSatisfy(isValidExternalID),
              settings.selectedReminderListIDs.allSatisfy(isValidExternalID) else {
            throw BackupError.invalidData("Source selections contain an invalid identifier.")
        }
        guard (0...23).contains(settings.morningSummaryHour),
              (0...59).contains(settings.morningSummaryMinute) else {
            throw BackupError.invalidData("Summary time is invalid.")
        }
    }

    private static func validateProfiles(
        _ profiles: [ProfileSnapshot],
        routineIDs: Set<UUID>
    ) throws {
        guard !profiles.isEmpty else {
            throw BackupError.invalidData("A backup must contain at least one saved profile.")
        }
        guard Set(profiles.map(\.id)).count == profiles.count else {
            throw BackupError.invalidData("Profile identifiers must be unique.")
        }
        let names = profiles.map {
            ProfileRecord.nameKey(for: $0.name.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        guard Set(names).count == profiles.count else {
            throw BackupError.invalidData("Profile names must be unique.")
        }
        guard Set(profiles.map(\.sortOrder)) == Set(0..<profiles.count) else {
            throw BackupError.invalidData("Profile order is invalid.")
        }
        guard profiles.allSatisfy({ profile in
            !profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && isValidColor(profile.colorHex)
                && ProfileSymbols.allowed.contains(profile.symbolName)
                && profile.calendarIDs.allSatisfy(isValidExternalID)
                && profile.reminderListIDs.allSatisfy(isValidExternalID)
                && profile.routineIDs.isSubset(of: routineIDs)
                && profile.defaultCalendarID.map(profile.calendarIDs.contains) ?? true
                && profile.defaultReminderListID.map(profile.reminderListIDs.contains) ?? true
        }) else {
            throw BackupError.invalidData("A saved profile is invalid.")
        }
    }

    private static func isValid(_ day: LocalDay) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = DateComponents(year: day.year, month: day.month, day: day.day)
        guard let date = calendar.date(from: components) else { return false }
        return calendar.dateComponents([.year, .month, .day], from: date) == components
    }

    private static func validReminderTime(_ value: RoutineBackup) -> Bool {
        switch (value.reminderHour, value.reminderMinute) {
        case (nil, nil): true
        case let (hour?, minute?): (0...23).contains(hour) && (0...59).contains(minute)
        default: false
        }
    }

    private static func isValidColor(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        return bytes.count == 7 && bytes.first == 35 && bytes.dropFirst().allSatisfy { byte in
            (48...57).contains(byte) || (65...70).contains(byte) || (97...102).contains(byte)
        }
    }

    private static func isValidExternalID(_ value: String) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

extension AppSettingsStore {
    var backupValueV1: SettingsBackupV1 {
        .init(
            selectedCalendarIDs: selectedCalendarIDs.sorted(),
            selectedReminderListIDs: selectedReminderListIDs.sorted(),
            defaultCalendarID: defaultCalendarID,
            defaultReminderListID: defaultReminderListID,
            calendarSelectionIsExplicit: calendarSelectionIsExplicit,
            reminderSelectionIsExplicit: reminderSelectionIsExplicit,
            morningSummaryEnabled: morningSummaryEnabled,
            morningSummaryHour: morningSummaryHour,
            morningSummaryMinute: morningSummaryMinute,
            showNextItemOnLockScreen: showNextItemOnLockScreen,
            didSeedCategories: didSeedCategories,
            didCompleteOnboarding: didCompleteOnboarding
        )
    }

    var backupValueV2: SettingsBackupV2 {
        .init(
            legacy: backupValueV1,
            activeProfileIdentity: activeProfileIdentity,
            lastActiveSavedProfileID: lastActiveSavedProfileID,
            completedProfileMigrationParts: completedProfileMigrationParts.sorted {
                $0.rawValue < $1.rawValue
            }
        )
    }
}

typealias BackupEnvelope = BackupEnvelopeV1
typealias SettingsBackup = SettingsBackupV1
