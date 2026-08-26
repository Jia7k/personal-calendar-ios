import Foundation
import Observation

enum SourceDescriptorOrdering {
    static func calendars(_ values: [CalendarDescriptor]) -> [CalendarDescriptor] { values.sorted(by: areInAscendingOrder) }
    static func reminderLists(_ values: [ReminderListDescriptor]) -> [ReminderListDescriptor] { values.sorted(by: areInAscendingOrder) }

    private static func areInAscendingOrder(id leftID: String, title leftTitle: String, id rightID: String, title rightTitle: String) -> Bool {
        let titleOrder = leftTitle.localizedCaseInsensitiveCompare(rightTitle)
        return titleOrder == .orderedSame ? leftID < rightID : titleOrder == .orderedAscending
    }
    private static func areInAscendingOrder(_ left: CalendarDescriptor, _ right: CalendarDescriptor) -> Bool { areInAscendingOrder(id: left.id, title: left.title, id: right.id, title: right.title) }
    private static func areInAscendingOrder(_ left: ReminderListDescriptor, _ right: ReminderListDescriptor) -> Bool { areInAscendingOrder(id: left.id, title: left.title, id: right.id, title: right.title) }
}

struct LegacyProfileSelectionSnapshot: Equatable, Sendable {
    let calendarIDs: Set<String>
    let reminderListIDs: Set<String>
    let defaultCalendarID: String?
    let defaultReminderListID: String?
    let calendarSelectionWasExplicit: Bool
    let reminderSelectionWasExplicit: Bool
}

enum ProfileMigrationPart: String, CaseIterable, Codable, Hashable, Sendable {
    case records
    case calendar
    case reminders
    case routines
}

@MainActor
@Observable
final class AppSettingsStore {
    private enum Key {
        static let selectedCalendars = "selectedCalendarIDs"
        static let selectedLists = "selectedReminderListIDs"
        static let defaultCalendar = "defaultCalendarID"
        static let defaultList = "defaultReminderListID"
        static let calendarsExplicit = "selectedCalendarIDsAreExplicit"
        static let listsExplicit = "selectedReminderListIDsAreExplicit"
        static let onboarding = "didCompleteOnboarding"
        static let categoriesSeeded = "didSeedCategories"
        static let morningSummaryEnabled = "morningSummaryEnabled"
        static let morningSummaryHour = "morningSummaryHour"
        static let morningSummaryMinute = "morningSummaryMinute"
        static let showNextItemOnLockScreen = "showNextItemOnLockScreen"
        static let classAlertPreferences = "classAlertPreferences"
        static let activeProfile = "activeProfileIdentity"
        static let lastActiveSavedProfile = "lastActiveSavedProfileID"

        static func profileMigration(_ part: ProfileMigrationPart) -> String {
            "profileMigration.\(part.rawValue)"
        }
    }

    private let defaults: UserDefaults
    private(set) var selectedCalendarIDs: Set<String>
    private(set) var selectedReminderListIDs: Set<String>
    private(set) var defaultCalendarID: String?
    private(set) var defaultReminderListID: String?
    var didCompleteOnboarding: Bool { didSet { defaults.set(didCompleteOnboarding, forKey: Key.onboarding) } }
    var didSeedCategories: Bool { didSet { defaults.set(didSeedCategories, forKey: Key.categoriesSeeded) } }
    var morningSummaryEnabled: Bool { didSet { defaults.set(morningSummaryEnabled, forKey: Key.morningSummaryEnabled) } }
    var morningSummaryHour: Int { didSet { defaults.set(morningSummaryHour, forKey: Key.morningSummaryHour) } }
    var morningSummaryMinute: Int { didSet { defaults.set(morningSummaryMinute, forKey: Key.morningSummaryMinute) } }
    var showNextItemOnLockScreen: Bool { didSet { defaults.set(showNextItemOnLockScreen, forKey: Key.showNextItemOnLockScreen) } }
    private(set) var classAlertPreferences: [UUID: ClassAlertPreference]
    private(set) var calendarSelectionIsExplicit: Bool
    private(set) var reminderSelectionIsExplicit: Bool
    private(set) var legacyProfileSelection: LegacyProfileSelectionSnapshot
    private(set) var activeProfileIdentity: ProfileIdentity
    private(set) var lastActiveSavedProfileID: UUID?
    private(set) var completedProfileMigrationParts: Set<ProfileMigrationPart>

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedCalendarIDs = Set(defaults.stringArray(forKey: Key.selectedCalendars) ?? [])
        let storedReminderListIDs = Set(defaults.stringArray(forKey: Key.selectedLists) ?? [])
        let storedDefaultCalendarID = defaults.string(forKey: Key.defaultCalendar)
        let storedDefaultReminderListID = defaults.string(forKey: Key.defaultList)
        let storedCalendarSelectionIsExplicit = defaults.object(forKey: Key.calendarsExplicit) as? Bool ?? !storedCalendarIDs.isEmpty
        let storedReminderSelectionIsExplicit = defaults.object(forKey: Key.listsExplicit) as? Bool ?? !storedReminderListIDs.isEmpty
        selectedCalendarIDs = storedCalendarIDs
        selectedReminderListIDs = storedReminderListIDs
        defaultCalendarID = storedDefaultCalendarID
        defaultReminderListID = storedDefaultReminderListID
        didCompleteOnboarding = defaults.bool(forKey: Key.onboarding)
        didSeedCategories = defaults.bool(forKey: Key.categoriesSeeded)
        morningSummaryEnabled = defaults.bool(forKey: Key.morningSummaryEnabled)
        morningSummaryHour = (defaults.object(forKey: Key.morningSummaryHour) as? Int).flatMap { (0...23).contains($0) ? $0 : nil } ?? 8
        morningSummaryMinute = (defaults.object(forKey: Key.morningSummaryMinute) as? Int).flatMap { (0...59).contains($0) ? $0 : nil } ?? 0
        showNextItemOnLockScreen = defaults.bool(forKey: Key.showNextItemOnLockScreen)
        classAlertPreferences = Self.decodeClassAlertPreferences(
            defaults.data(forKey: Key.classAlertPreferences)
        )
        calendarSelectionIsExplicit = storedCalendarSelectionIsExplicit
        reminderSelectionIsExplicit = storedReminderSelectionIsExplicit
        legacyProfileSelection = LegacyProfileSelectionSnapshot(
            calendarIDs: storedCalendarIDs,
            reminderListIDs: storedReminderListIDs,
            defaultCalendarID: storedDefaultCalendarID,
            defaultReminderListID: storedDefaultReminderListID,
            calendarSelectionWasExplicit: storedCalendarSelectionIsExplicit,
            reminderSelectionWasExplicit: storedReminderSelectionIsExplicit
        )
        activeProfileIdentity = defaults.string(forKey: Key.activeProfile)
            .flatMap(ProfileIdentity.init(storageKey:)) ?? .everything
        lastActiveSavedProfileID = defaults.string(forKey: Key.lastActiveSavedProfile)
            .flatMap(UUID.init(uuidString:))
        completedProfileMigrationParts = Set(ProfileMigrationPart.allCases.filter {
            defaults.bool(forKey: Key.profileMigration($0))
        })
        persistSelectionMarkers()
        persistProfileSelection()
    }

    func classAlertPreference(for profileID: UUID) -> ClassAlertPreference {
        classAlertPreferences[profileID]
            ?? .init(enabled: false, leadMinutes: 10)
    }

    func setClassAlertPreference(
        _ preference: ClassAlertPreference,
        for profileID: UUID
    ) {
        guard ClassAlertPreference.allowedLeadMinutes.contains(
            preference.leadMinutes
        ) else { return }
        classAlertPreferences[profileID] = preference
        persistClassAlertPreferences()
    }

    func reconcileClassAlertPreferences(validProfileIDs: Set<UUID>) {
        let reconciled = classAlertPreferences.filter {
            validProfileIDs.contains($0.key)
        }
        guard reconciled != classAlertPreferences else { return }
        classAlertPreferences = reconciled
        persistClassAlertPreferences()
    }

    func setActiveProfile(_ identity: ProfileIdentity) {
        activeProfileIdentity = identity
        if case let .saved(id) = identity {
            lastActiveSavedProfileID = id
        }
        persistProfileSelection()
    }

    func markProfileMigrationComplete(_ part: ProfileMigrationPart) {
        completedProfileMigrationParts.insert(part)
        defaults.set(true, forKey: Key.profileMigration(part))
    }

    func didMigrateProfilePart(_ part: ProfileMigrationPart) -> Bool {
        completedProfileMigrationParts.contains(part)
    }

    func resetProfileMigration(legacy: LegacyProfileSelectionSnapshot) {
        legacyProfileSelection = legacy
        selectedCalendarIDs = legacy.calendarIDs
        selectedReminderListIDs = legacy.reminderListIDs
        defaultCalendarID = legacy.defaultCalendarID
        defaultReminderListID = legacy.defaultReminderListID
        calendarSelectionIsExplicit = legacy.calendarSelectionWasExplicit
        reminderSelectionIsExplicit = legacy.reminderSelectionWasExplicit
        completedProfileMigrationParts.removeAll()
        for part in ProfileMigrationPart.allCases {
            defaults.set(false, forKey: Key.profileMigration(part))
        }
        persistCalendarSelection()
        persistReminderSelection()
        defaults.set(defaultCalendarID, forKey: Key.defaultCalendar)
        defaults.set(defaultReminderListID, forKey: Key.defaultList)
    }

    func toggleCalendar(id: String, availableIDs: Set<String>) {
        toggle(id: id, selection: &selectedCalendarIDs, explicit: &calendarSelectionIsExplicit, availableIDs: availableIDs)
        persistCalendarSelection()
    }

    func toggleReminderList(id: String, availableIDs: Set<String>) {
        toggle(id: id, selection: &selectedReminderListIDs, explicit: &reminderSelectionIsExplicit, availableIDs: availableIDs)
        persistReminderSelection()
    }

    func replaceSelectedCalendarIDs(_ ids: Set<String>, availableIDs: Set<String>) {
        guard replace(ids, selection: &selectedCalendarIDs, explicit: &calendarSelectionIsExplicit, availableIDs: availableIDs) else { return }
        persistCalendarSelection()
    }

    func replaceSelectedReminderListIDs(_ ids: Set<String>, availableIDs: Set<String>) {
        guard replace(ids, selection: &selectedReminderListIDs, explicit: &reminderSelectionIsExplicit, availableIDs: availableIDs) else { return }
        persistReminderSelection()
    }

    func visibleCalendarIDs(availableIDs: Set<String>) -> Set<String> { calendarSelectionIsExplicit ? selectedCalendarIDs.intersection(availableIDs) : availableIDs }
    func visibleReminderListIDs(availableIDs: Set<String>) -> Set<String> { reminderSelectionIsExplicit ? selectedReminderListIDs.intersection(availableIDs) : availableIDs }

    func setDefaultCalendarID(_ id: String?, descriptors: [CalendarDescriptor], access: AccessState) {
        guard access == .granted else { return }
        defaultCalendarID = id.flatMap { candidate in descriptors.contains { $0.id == candidate && $0.allowsContentModifications } ? candidate : nil }
        defaults.set(defaultCalendarID, forKey: Key.defaultCalendar)
    }

    func setDefaultReminderListID(_ id: String?, descriptors: [ReminderListDescriptor], access: AccessState) {
        guard access == .granted else { return }
        defaultReminderListID = id.flatMap { candidate in descriptors.contains { $0.id == candidate && $0.allowsContentModifications } ? candidate : nil }
        defaults.set(defaultReminderListID, forKey: Key.defaultList)
    }

    func validateDefaults(calendarAccess: AccessState, calendars: [CalendarDescriptor], remindersAccess: AccessState, lists: [ReminderListDescriptor]) {
        if !didMigrateProfilePart(.calendar),
           calendarAccess == .granted,
           defaultCalendarID.map({ id in !calendars.contains { $0.id == id && $0.allowsContentModifications } }) == true {
            defaultCalendarID = nil
            defaults.removeObject(forKey: Key.defaultCalendar)
        }
        if !didMigrateProfilePart(.reminders),
           remindersAccess == .granted,
           defaultReminderListID.map({ id in !lists.contains { $0.id == id && $0.allowsContentModifications } }) == true {
            defaultReminderListID = nil
            defaults.removeObject(forKey: Key.defaultList)
        }
    }

    /// Reconciles persisted source preferences after EventKit reports a changed source list.
    /// A vanished explicit selection falls back to every currently available source.
    func reconcileSources(
        calendarAccess: AccessState,
        calendars: [CalendarDescriptor],
        remindersAccess: AccessState,
        lists: [ReminderListDescriptor]
    ) {
        if calendarAccess == .granted, !didMigrateProfilePart(.calendar) {
            reconcileSelection(
                selection: &selectedCalendarIDs,
                explicit: &calendarSelectionIsExplicit,
                availableIDs: Set(calendars.map(\.id))
            )
            persistCalendarSelection()
        }
        if remindersAccess == .granted, !didMigrateProfilePart(.reminders) {
            reconcileSelection(
                selection: &selectedReminderListIDs,
                explicit: &reminderSelectionIsExplicit,
                availableIDs: Set(lists.map(\.id))
            )
            persistReminderSelection()
        }
        validateDefaults(
            calendarAccess: calendarAccess,
            calendars: calendars,
            remindersAccess: remindersAccess,
            lists: lists
        )
    }

    func applyBackupValue(_ value: SettingsBackupV1) {
        selectedCalendarIDs = Set(value.selectedCalendarIDs)
        selectedReminderListIDs = Set(value.selectedReminderListIDs)
        defaultCalendarID = value.defaultCalendarID
        defaultReminderListID = value.defaultReminderListID
        calendarSelectionIsExplicit = value.calendarSelectionIsExplicit
        reminderSelectionIsExplicit = value.reminderSelectionIsExplicit
        legacyProfileSelection = LegacyProfileSelectionSnapshot(
            calendarIDs: selectedCalendarIDs,
            reminderListIDs: selectedReminderListIDs,
            defaultCalendarID: defaultCalendarID,
            defaultReminderListID: defaultReminderListID,
            calendarSelectionWasExplicit: calendarSelectionIsExplicit,
            reminderSelectionWasExplicit: reminderSelectionIsExplicit
        )
        morningSummaryEnabled = value.morningSummaryEnabled
        morningSummaryHour = value.morningSummaryHour
        morningSummaryMinute = value.morningSummaryMinute
        showNextItemOnLockScreen = value.showNextItemOnLockScreen
        didSeedCategories = value.didSeedCategories
        didCompleteOnboarding = value.didCompleteOnboarding
        persistCalendarSelection()
        persistReminderSelection()
        defaults.set(defaultCalendarID, forKey: Key.defaultCalendar)
        defaults.set(defaultReminderListID, forKey: Key.defaultList)
    }

    func applyBackupValue(_ value: SettingsBackupV2, validProfileIDs: Set<UUID>) {
        applyBackupValue(value.legacy)

        activeProfileIdentity = switch value.activeProfileIdentity {
        case .everything:
            .everything
        case let .saved(id) where validProfileIDs.contains(id):
            .saved(id)
        case .saved:
            .everything
        }
        lastActiveSavedProfileID = value.lastActiveSavedProfileID.flatMap {
            validProfileIDs.contains($0) ? $0 : nil
        }
        if case let .saved(id) = activeProfileIdentity {
            lastActiveSavedProfileID = id
        }

        completedProfileMigrationParts = Set(value.completedProfileMigrationParts)
        for part in ProfileMigrationPart.allCases {
            defaults.set(completedProfileMigrationParts.contains(part), forKey: Key.profileMigration(part))
        }
        persistProfileSelection()
    }

    private func toggle(id: String, selection: inout Set<String>, explicit: inout Bool, availableIDs: Set<String>) {
        guard availableIDs.contains(id) else { return }
        if !explicit { selection = availableIDs; explicit = true }
        if selection.contains(id) {
            guard selection.intersection(availableIDs).count > 1 else { return }
            selection.remove(id)
        } else {
            selection.insert(id)
        }
    }

    private func replace(_ ids: Set<String>, selection: inout Set<String>, explicit: inout Bool, availableIDs: Set<String>) -> Bool {
        let replacement = ids.intersection(availableIDs)
        guard !replacement.isEmpty else { return false }
        selection = replacement
        explicit = true
        return true
    }

    private func reconcileSelection(
        selection: inout Set<String>,
        explicit: inout Bool,
        availableIDs: Set<String>
    ) {
        let hadSelection = !selection.isEmpty
        selection.formIntersection(availableIDs)
        guard explicit, hadSelection, selection.isEmpty else { return }
        selection = availableIDs
        explicit = !availableIDs.isEmpty
    }

    private func persistCalendarSelection() {
        defaults.set(selectedCalendarIDs.sorted(), forKey: Key.selectedCalendars)
        defaults.set(calendarSelectionIsExplicit, forKey: Key.calendarsExplicit)
    }
    private func persistReminderSelection() {
        defaults.set(selectedReminderListIDs.sorted(), forKey: Key.selectedLists)
        defaults.set(reminderSelectionIsExplicit, forKey: Key.listsExplicit)
    }
    private func persistSelectionMarkers() {
        defaults.set(calendarSelectionIsExplicit, forKey: Key.calendarsExplicit)
        defaults.set(reminderSelectionIsExplicit, forKey: Key.listsExplicit)
    }
    private func persistProfileSelection() {
        defaults.set(activeProfileIdentity.storageKey, forKey: Key.activeProfile)
        defaults.set(lastActiveSavedProfileID?.uuidString, forKey: Key.lastActiveSavedProfile)
    }

    private func persistClassAlertPreferences() {
        let serialized = Dictionary(uniqueKeysWithValues: classAlertPreferences.map {
            ($0.key.uuidString, $0.value)
        })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        defaults.set(try? encoder.encode(serialized), forKey: Key.classAlertPreferences)
    }

    private static func decodeClassAlertPreferences(
        _ data: Data?
    ) -> [UUID: ClassAlertPreference] {
        guard let data,
              let stored = try? JSONDecoder().decode(
                  [String: ClassAlertPreference].self,
                  from: data
              ) else { return [:] }
        return stored.reduce(into: [:]) { result, pair in
            guard let id = UUID(uuidString: pair.key),
                  ClassAlertPreference.allowedLeadMinutes.contains(
                      pair.value.leadMinutes
                  ) else { return }
            result[id] = pair.value
        }
    }
}

extension UserDefaults {
    static var ephemeral: UserDefaults { UserDefaults(suiteName: "PersonalCalendar.\(UUID().uuidString)")! }
}
