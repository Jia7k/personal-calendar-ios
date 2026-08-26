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

struct BackupEnvelopeV3: Codable, Equatable, Sendable {
    let version: Int
    let exportedAt: Date
    let routines: [RoutineBackup]
    let completions: [CompletionBackup]
    let categories: [CategorySnapshot]
    let categoryLinks: [CategoryLinkBackup]
    let profiles: [ProfileSnapshot]
    let settings: SettingsBackupV3
}

struct BackupEnvelopeV4: Codable, Equatable, Sendable {
    let version: Int
    let exportedAt: Date
    let routines: [RoutineBackup]
    let completions: [CompletionBackup]
    let categories: [CategorySnapshot]
    let categoryLinks: [CategoryLinkBackup]
    let profiles: [ProfileSnapshot]
    let settings: SettingsBackupV4
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

struct ClassAlertPreferenceBackup: Codable, Equatable, Sendable {
    let profileID: UUID
    let preference: ClassAlertPreference
}

struct SettingsBackupV3: Codable, Equatable, Sendable {
    let legacy: SettingsBackupV2
    let classAlertPreferences: [ClassAlertPreferenceBackup]
    let quickEntryMemory: QuickEntryMemoryV1
}

struct SettingsBackupV4: Codable, Equatable, Sendable {
    let legacy: SettingsBackupV3
    let preferredLiveActivityProfile: ProfileIdentity?
    let automaticallyStartsLiveActivityOnForeground: Bool
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

    static func validate(_ envelope: BackupEnvelopeV3) throws {
        guard envelope.version == 3 else {
            throw BackupError.unsupportedVersion(envelope.version)
        }
        try validateAppOwnedData(
            routines: envelope.routines,
            completions: envelope.completions,
            categories: envelope.categories,
            categoryLinks: envelope.categoryLinks,
            settings: envelope.settings.legacy.legacy
        )
        try validateProfiles(
            envelope.profiles,
            routineIDs: Set(envelope.routines.map(\.id))
        )
        guard Set(envelope.settings.legacy.completedProfileMigrationParts).count
                == envelope.settings.legacy.completedProfileMigrationParts.count else {
            throw BackupError.invalidData("Profile migration markers must be unique.")
        }
        try validateClassAlertPreferences(
            envelope.settings.classAlertPreferences
        )
        try validateQuickEntryMemory(envelope.settings.quickEntryMemory)
    }

    static func validate(_ envelope: BackupEnvelopeV4) throws {
        guard envelope.version == 4 else {
            throw BackupError.unsupportedVersion(envelope.version)
        }
        try validate(BackupEnvelopeV3(
            version: 3,
            exportedAt: envelope.exportedAt,
            routines: envelope.routines,
            completions: envelope.completions,
            categories: envelope.categories,
            categoryLinks: envelope.categoryLinks,
            profiles: envelope.profiles,
            settings: envelope.settings.legacy
        ))

        let validProfileIDs = Set(envelope.profiles.map(\.id))
        if case let .saved(id)? =
            envelope.settings.preferredLiveActivityProfile,
            !validProfileIDs.contains(id) {
            throw BackupError.invalidData(
                "The preferred Live Activity profile is missing."
            )
        }
        if envelope.settings.automaticallyStartsLiveActivityOnForeground,
           envelope.settings.preferredLiveActivityProfile == nil {
            throw BackupError.invalidData(
                "Automatic Live Activity start requires a profile."
            )
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

    private static func validateClassAlertPreferences(
        _ records: [ClassAlertPreferenceBackup]
    ) throws {
        guard Set(records.map(\.profileID)).count == records.count else {
            throw BackupError.invalidData(
                "Class alert preferences must be unique per profile."
            )
        }
        guard records.allSatisfy({
            ClassAlertPreference.allowedLeadMinutes.contains(
                $0.preference.leadMinutes
            )
        }) else {
            throw BackupError.invalidData(
                "A class alert preference is invalid."
            )
        }
    }

    private static func validateQuickEntryMemory(
        _ memory: QuickEntryMemoryV1
    ) throws {
        guard memory.version == QuickEntryMemoryV1.currentVersion else {
            throw BackupError.invalidData(
                "The Quick Entry memory version is unsupported."
            )
        }
        guard memory.history.count <= 10 else {
            throw BackupError.invalidData(
                "Quick Entry history contains too many items."
            )
        }
        guard Set(memory.history.map(\.id)).count == memory.history.count else {
            throw BackupError.invalidData(
                "Quick Entry history identifiers must be unique."
            )
        }

        var historyKeys = Set<String>()
        for item in memory.history {
            guard case let .saved(profileID) = item.profileIdentity,
                  item.text == item.text.trimmingCharacters(
                    in: .whitespacesAndNewlines
                  ),
                  !item.text.isEmpty,
                  item.lastUsedAt.timeIntervalSinceReferenceDate.isFinite else {
                throw BackupError.invalidData(
                    "A Quick Entry history item is invalid."
                )
            }
            let key = profileID.uuidString.lowercased()
                + "|" + normalizedQuickEntryText(item.text)
            guard historyKeys.insert(key).inserted else {
                throw BackupError.invalidData(
                    "Quick Entry history must be unique per profile."
                )
            }
        }

        var preferenceKeys = Set<String>()
        for record in memory.preferences {
            if let duration = record.choices.durationMinutes,
               !(1...1_440).contains(duration) {
                throw BackupError.invalidData(
                    "A Quick Entry duration is invalid."
                )
            }
            let key = record.profileID.uuidString.lowercased()
                + "|" + record.kind.rawValue
            guard preferenceKeys.insert(key).inserted else {
                throw BackupError.invalidData(
                    "Quick Entry preferences must be unique per profile and kind."
                )
            }
        }
    }

    private static func normalizedQuickEntryText(_ value: String) -> String {
        let locale = Locale(identifier: "en_US_POSIX")
        return value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(
                options: [
                    .caseInsensitive,
                    .diacriticInsensitive,
                    .widthInsensitive
                ],
                locale: locale
            )
            .lowercased(with: locale)
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

    var backupValueV3: SettingsBackupV3 {
        .init(
            legacy: backupValueV2,
            classAlertPreferences: classAlertPreferences
                .map { profileID, preference in
                    .init(profileID: profileID, preference: preference)
                }
                .sorted {
                    $0.profileID.uuidString.lowercased()
                        < $1.profileID.uuidString.lowercased()
                },
            quickEntryMemory: quickEntryHistory.backupValue
        )
    }

    var backupValueV4: SettingsBackupV4 {
        .init(
            legacy: backupValueV3,
            preferredLiveActivityProfile: preferredLiveActivityProfile,
            automaticallyStartsLiveActivityOnForeground:
                automaticallyStartsLiveActivityOnForeground
        )
    }
}

typealias BackupEnvelope = BackupEnvelopeV1
typealias SettingsBackup = SettingsBackupV1
