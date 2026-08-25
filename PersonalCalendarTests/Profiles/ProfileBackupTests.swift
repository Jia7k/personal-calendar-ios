import SwiftData
import XCTest
@testable import PersonalCalendar

@MainActor
final class ProfileBackupTests: XCTestCase {
    fileprivate static let personalID = UUID(uuidString: "C0A10000-0000-4000-8000-000000000011")!
    fileprivate static let schoolID = UUID(uuidString: "C0A10000-0000-4000-8000-000000000012")!
    fileprivate static let workID = UUID(uuidString: "C0A10000-0000-4000-8000-000000000013")!

    func testV2RoundTripPreservesProfilesAndActiveSelection() throws {
        let fixture = try makeFixture()
        try fixture.seedProfiles()
        fixture.settings.setActiveProfile(.saved(Self.schoolID))

        let data = try fixture.backup.exportData()
        try fixture.clearProfiles()
        fixture.settings.setActiveProfile(.everything)

        try fixture.backup.restore(data: data)

        XCTAssertEqual(try fixture.profiles.list().map(\.name), ["Personal", "School", "Work"])
        XCTAssertEqual(try fixture.profiles.profile(id: Self.schoolID).calendarIDs, ["google-school"])
        XCTAssertEqual(fixture.settings.activeProfileIdentity, .saved(Self.schoolID))
    }

    func testV1RestoreUsesDecodedLegacySelectionAsMigrationInput() throws {
        let fixture = try makeFixture()
        try fixture.profileMigration.run()
        fixture.settings.setActiveProfile(.everything)

        try fixture.backup.restore(data: try makeV1Backup(
            selectedCalendarIDs: ["legacy-school"],
            selectedReminderListIDs: ["legacy-assignments"]
        ))

        let personal = try fixture.profiles.profile(id: SeedProfile.personalID)
        XCTAssertEqual(personal.calendarIDs, ["legacy-school"])
        XCTAssertEqual(personal.reminderListIDs, ["legacy-assignments"])
    }

    private func makeFixture() throws -> Fixture {
        let container = try ModelContainer(
            for: RoutineRecord.self,
            RoutineCompletionRecord.self,
            CategoryRecord.self,
            ExternalCategoryLinkRecord.self,
            ProfileRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let settings = AppSettingsStore(defaults: .ephemeral)
        let profiles = SwiftDataProfileRepository(context: context)
        let profileMigration = ProfileMigrationCoordinator(
            profiles: profiles,
            calendar: FakeCalendarService(access: .denied),
            reminders: FakeRemindersService(access: .denied),
            routines: FakeRoutineRepository(),
            settings: settings
        )
        let backup = BackupService(
            context: context,
            settings: settings,
            profileMigration: profileMigration
        )
        return Fixture(
            container: container,
            profiles: profiles,
            settings: settings,
            profileMigration: profileMigration,
            backup: backup
        )
    }

    private func makeV1Backup(
        selectedCalendarIDs: [String],
        selectedReminderListIDs: [String]
    ) throws -> Data {
        let payload = BackupEnvelopeV1Fixture(
            version: 1,
            exportedAt: Date(timeIntervalSince1970: 1_700_000_000),
            routines: [],
            completions: [],
            categories: [],
            categoryLinks: [],
            settings: SettingsBackupV1Fixture(
                selectedCalendarIDs: selectedCalendarIDs,
                selectedReminderListIDs: selectedReminderListIDs,
                defaultCalendarID: nil,
                defaultReminderListID: nil,
                calendarSelectionIsExplicit: true,
                reminderSelectionIsExplicit: true,
                morningSummaryEnabled: false,
                morningSummaryHour: 8,
                morningSummaryMinute: 0,
                showNextItemOnLockScreen: false,
                didSeedCategories: false,
                didCompleteOnboarding: true
            )
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(payload)
    }
}

@MainActor
private struct Fixture {
    let container: ModelContainer
    let profiles: SwiftDataProfileRepository
    let settings: AppSettingsStore
    let profileMigration: ProfileMigrationCoordinator
    let backup: BackupService

    func seedProfiles() throws {
        _ = try profiles.create(
            profileDraft(
                name: "Personal",
                colorHex: "#3A8D7C",
                symbolName: "person.fill",
                calendarIDs: ["home"]
            ),
            id: ProfileBackupTests.personalID
        )
        _ = try profiles.create(
            profileDraft(
                name: "School",
                colorHex: "#4868A8",
                symbolName: "graduationcap.fill",
                calendarIDs: ["google-school"],
                reminderListIDs: ["assignments"],
                defaultCalendarID: "google-school",
                defaultReminderListID: "assignments"
            ),
            id: ProfileBackupTests.schoolID
        )
        _ = try profiles.create(
            profileDraft(
                name: "Work",
                colorHex: "#CB6B4F",
                symbolName: "briefcase.fill",
                calendarIDs: ["work"]
            ),
            id: ProfileBackupTests.workID
        )
    }

    func clearProfiles() throws {
        try container.mainContext.delete(
            model: ProfileRecord.self,
            where: nil,
            includeSubclasses: false
        )
        try container.mainContext.save()
    }

    private func profileDraft(
        name: String,
        colorHex: String,
        symbolName: String,
        calendarIDs: Set<String>,
        reminderListIDs: Set<String> = [],
        defaultCalendarID: String? = nil,
        defaultReminderListID: String? = nil
    ) -> ProfileDraft {
        ProfileDraft(
            name: name,
            colorHex: colorHex,
            symbolName: symbolName,
            calendarIDs: calendarIDs,
            reminderListIDs: reminderListIDs,
            routineIDs: [],
            defaultCalendarID: defaultCalendarID,
            defaultReminderListID: defaultReminderListID
        )
    }
}

private struct BackupEnvelopeV1Fixture: Encodable {
    let version: Int
    let exportedAt: Date
    let routines: [RoutineBackup]
    let completions: [CompletionBackup]
    let categories: [CategorySnapshot]
    let categoryLinks: [CategoryLinkBackup]
    let settings: SettingsBackupV1Fixture
}

private struct SettingsBackupV1Fixture: Encodable {
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
