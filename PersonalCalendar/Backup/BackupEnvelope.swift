import Foundation

struct BackupEnvelope: Codable, Equatable, Sendable {
    let version: Int
    let exportedAt: Date
    let routines: [RoutineBackup]
    let completions: [CompletionBackup]
    let categories: [CategorySnapshot]
    let categoryLinks: [CategoryLinkBackup]
    let settings: SettingsBackup
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

struct SettingsBackup: Codable, Equatable, Sendable {
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
}

enum BackupValidator {
    static func validate(_ envelope: BackupEnvelope) throws {
        guard envelope.version == 1 else { throw BackupError.unsupportedVersion(envelope.version) }
        guard Set(envelope.routines.map(\.id)).count == envelope.routines.count else { throw BackupError.invalidData("Routine identifiers must be unique.") }
        guard Set(envelope.categories.map(\.id)).count == envelope.categories.count else { throw BackupError.invalidData("Category identifiers must be unique.") }
        let categoryNames = envelope.categories.map { CategoryRecord.nameKey(for: $0.name.trimmingCharacters(in: .whitespacesAndNewlines)) }
        guard Set(categoryNames).count == envelope.categories.count else { throw BackupError.invalidData("Category names must be unique.") }
        guard Set(envelope.completions.map { RoutineCompletionRecord.key(routineID: $0.routineID, day: $0.day) }).count == envelope.completions.count else { throw BackupError.invalidData("Routine completions must be unique per day.") }
        guard Set(envelope.categoryLinks.map { ExternalCategoryLinkRecord.key(source: $0.source, externalID: $0.externalID) }).count == envelope.categoryLinks.count else { throw BackupError.invalidData("External category links must be unique.") }

        let routineIDs = Set(envelope.routines.map(\.id))
        let categoryIDs = Set(envelope.categories.map(\.id))
        guard envelope.completions.allSatisfy({ routineIDs.contains($0.routineID) }) else { throw BackupError.invalidData("A completion refers to a missing routine.") }
        guard envelope.completions.allSatisfy({ isValid($0.day) }) else { throw BackupError.invalidData("A completion date is invalid.") }
        guard envelope.routines.allSatisfy({ $0.categoryID.map(categoryIDs.contains) ?? true }) else { throw BackupError.invalidData("A routine refers to a missing category.") }
        guard envelope.categoryLinks.allSatisfy({ !$0.externalID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && categoryIDs.contains($0.categoryID) }) else { throw BackupError.invalidData("A category link is invalid.") }
        guard envelope.routines.allSatisfy({ !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !$0.weekdays.isEmpty && $0.weekdays.allSatisfy((1...7).contains) }) else { throw BackupError.invalidData("A routine is invalid.") }
        guard envelope.routines.allSatisfy(validReminderTime) else { throw BackupError.invalidData("A routine reminder time is invalid.") }
        guard envelope.categories.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && isValidColor($0.colorHex) }) else { throw BackupError.invalidData("A category is invalid.") }
        guard Set(envelope.settings.selectedCalendarIDs).count == envelope.settings.selectedCalendarIDs.count,
              Set(envelope.settings.selectedReminderListIDs).count == envelope.settings.selectedReminderListIDs.count else {
            throw BackupError.invalidData("Source selections must not contain duplicates.")
        }
        guard (0...23).contains(envelope.settings.morningSummaryHour), (0...59).contains(envelope.settings.morningSummaryMinute) else { throw BackupError.invalidData("Summary time is invalid.") }
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
}

extension AppSettingsStore {
    var backupValue: SettingsBackup {
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
}
