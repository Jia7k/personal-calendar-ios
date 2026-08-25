import Foundation

enum SeedProfile {
    static let personalID = UUID(uuidString: "C0A10000-0000-4000-8000-000000000001")!
    static let schoolID = UUID(uuidString: "C0A10000-0000-4000-8000-000000000002")!
    static let workID = UUID(uuidString: "C0A10000-0000-4000-8000-000000000003")!

    fileprivate static let values: [(id: UUID, draft: ProfileDraft)] = [
        (
            personalID,
            ProfileDraft(
                name: "Personal",
                colorHex: "#3A8D7C",
                symbolName: "person.fill",
                calendarIDs: [],
                reminderListIDs: [],
                routineIDs: [],
                defaultCalendarID: nil,
                defaultReminderListID: nil
            )
        ),
        (
            schoolID,
            ProfileDraft(
                name: "School",
                colorHex: "#4868A8",
                symbolName: "graduationcap.fill",
                calendarIDs: [],
                reminderListIDs: [],
                routineIDs: [],
                defaultCalendarID: nil,
                defaultReminderListID: nil
            )
        ),
        (
            workID,
            ProfileDraft(
                name: "Work",
                colorHex: "#CB6B4F",
                symbolName: "briefcase.fill",
                calendarIDs: [],
                reminderListIDs: [],
                routineIDs: [],
                defaultCalendarID: nil,
                defaultReminderListID: nil
            )
        )
    ]
}

@MainActor
final class ProfileMigrationCoordinator {
    private let profiles: any ProfileRepository
    private let calendar: any CalendarServicing
    private let reminders: any RemindersServicing
    private let routines: any RoutineRepository
    private let settings: AppSettingsStore

    init(
        profiles: any ProfileRepository,
        calendar: any CalendarServicing,
        reminders: any RemindersServicing,
        routines: any RoutineRepository,
        settings: AppSettingsStore
    ) {
        self.profiles = profiles
        self.calendar = calendar
        self.reminders = reminders
        self.routines = routines
        self.settings = settings
    }

    func run() throws {
        try seedRecordsIfNeeded()
        try migrateRoutinesIfNeeded()
        try migrateCalendarsIfReady()
        try migrateRemindersIfReady()
    }

    func resetAndMigrate(legacy: LegacyProfileSelectionSnapshot) throws {
        settings.resetProfileMigration(legacy: legacy)
        try run()
    }

    private func seedRecordsIfNeeded() throws {
        guard !settings.didMigrateProfilePart(.records) else { return }

        var existingIDs = Set(try profiles.list().map(\.id))
        for seed in SeedProfile.values where !existingIDs.contains(seed.id) {
            _ = try profiles.create(seed.draft, id: seed.id)
            existingIDs.insert(seed.id)
        }

        settings.setActiveProfile(.saved(SeedProfile.personalID))
        settings.markProfileMigrationComplete(.records)
    }

    private func migrateRoutinesIfNeeded() throws {
        guard !settings.didMigrateProfilePart(.routines) else { return }
        let routineIDs = Set(try routines.list(includeArchived: false).map(\.id))
        try updatePersonal { $0.routineIDs = routineIDs }
        settings.markProfileMigrationComplete(.routines)
    }

    private func migrateCalendarsIfReady() throws {
        guard !settings.didMigrateProfilePart(.calendar) else { return }
        let legacy = settings.legacyProfileSelection
        let descriptors = calendar.calendars()
        guard let ids = migratedIDs(
            stored: legacy.calendarIDs,
            wasExplicit: legacy.calendarSelectionWasExplicit,
            access: calendar.accessState,
            current: Set(descriptors.map(\.id))
        ) else { return }

        let defaultID = legacy.defaultCalendarID.flatMap { candidate in
            ids.contains(candidate) && descriptors.contains {
                $0.id == candidate && $0.allowsContentModifications
            } ? candidate : nil
        }
        try updatePersonal {
            $0.calendarIDs = ids
            $0.defaultCalendarID = defaultID
        }
        settings.markProfileMigrationComplete(.calendar)
    }

    private func migrateRemindersIfReady() throws {
        guard !settings.didMigrateProfilePart(.reminders) else { return }
        let legacy = settings.legacyProfileSelection
        let descriptors = reminders.lists()
        guard let ids = migratedIDs(
            stored: legacy.reminderListIDs,
            wasExplicit: legacy.reminderSelectionWasExplicit,
            access: reminders.accessState,
            current: Set(descriptors.map(\.id))
        ) else { return }

        let defaultID = legacy.defaultReminderListID.flatMap { candidate in
            ids.contains(candidate) && descriptors.contains {
                $0.id == candidate && $0.allowsContentModifications
            } ? candidate : nil
        }
        try updatePersonal {
            $0.reminderListIDs = ids
            $0.defaultReminderListID = defaultID
        }
        settings.markProfileMigrationComplete(.reminders)
    }

    private func migratedIDs(
        stored: Set<String>,
        wasExplicit: Bool,
        access: AccessState,
        current: Set<String>
    ) -> Set<String>? {
        if wasExplicit, !stored.isEmpty {
            return stored
        }
        guard access == .granted else { return nil }
        return current
    }

    private func updatePersonal(_ update: (inout ProfileDraft) -> Void) throws {
        let snapshot = try profiles.profile(id: SeedProfile.personalID)
        var draft = ProfileDraft(
            name: snapshot.name,
            colorHex: snapshot.colorHex,
            symbolName: snapshot.symbolName,
            calendarIDs: snapshot.calendarIDs,
            reminderListIDs: snapshot.reminderListIDs,
            routineIDs: snapshot.routineIDs,
            defaultCalendarID: snapshot.defaultCalendarID,
            defaultReminderListID: snapshot.defaultReminderListID
        )
        update(&draft)
        try profiles.update(id: SeedProfile.personalID, draft: draft)
    }
}
