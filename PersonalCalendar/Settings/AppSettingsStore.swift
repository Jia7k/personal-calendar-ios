import Foundation
import Observation

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
    }

    private let defaults: UserDefaults

    var selectedCalendarIDs: Set<String> {
        didSet { defaults.set(selectedCalendarIDs.sorted(), forKey: Key.selectedCalendars) }
    }

    var selectedReminderListIDs: Set<String> {
        didSet { defaults.set(selectedReminderListIDs.sorted(), forKey: Key.selectedLists) }
    }

    var defaultCalendarID: String? {
        didSet { defaults.set(defaultCalendarID, forKey: Key.defaultCalendar) }
    }

    var defaultReminderListID: String? {
        didSet { defaults.set(defaultReminderListID, forKey: Key.defaultList) }
    }
    var didCompleteOnboarding: Bool { didSet { defaults.set(didCompleteOnboarding, forKey: Key.onboarding) } }
    private(set) var calendarSelectionIsExplicit: Bool { didSet { defaults.set(calendarSelectionIsExplicit, forKey: Key.calendarsExplicit) } }
    private(set) var reminderSelectionIsExplicit: Bool { didSet { defaults.set(reminderSelectionIsExplicit, forKey: Key.listsExplicit) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedCalendars = Set(defaults.stringArray(forKey: Key.selectedCalendars) ?? [])
        let storedLists = Set(defaults.stringArray(forKey: Key.selectedLists) ?? [])
        selectedCalendarIDs = storedCalendars
        selectedReminderListIDs = storedLists
        defaultCalendarID = defaults.string(forKey: Key.defaultCalendar)
        defaultReminderListID = defaults.string(forKey: Key.defaultList)
        didCompleteOnboarding = defaults.bool(forKey: Key.onboarding)
        // Older non-empty selections are intentional; an absent marker with an empty set remains implicit-all.
        calendarSelectionIsExplicit = defaults.object(forKey: Key.calendarsExplicit) as? Bool ?? !storedCalendars.isEmpty
        reminderSelectionIsExplicit = defaults.object(forKey: Key.listsExplicit) as? Bool ?? !storedLists.isEmpty
    }

    func toggleCalendar(id: String, availableIDs: Set<String>) { toggle(id: id, selection: &selectedCalendarIDs, explicit: &calendarSelectionIsExplicit, availableIDs: availableIDs) }
    func toggleReminderList(id: String, availableIDs: Set<String>) { toggle(id: id, selection: &selectedReminderListIDs, explicit: &reminderSelectionIsExplicit, availableIDs: availableIDs) }
    func visibleCalendarIDs(availableIDs: Set<String>) -> Set<String> { calendarSelectionIsExplicit ? selectedCalendarIDs.intersection(availableIDs) : availableIDs }
    func visibleReminderListIDs(availableIDs: Set<String>) -> Set<String> { reminderSelectionIsExplicit ? selectedReminderListIDs.intersection(availableIDs) : availableIDs }

    private func toggle(id: String, selection: inout Set<String>, explicit: inout Bool, availableIDs: Set<String>) {
        guard availableIDs.contains(id) else { return }
        if !explicit { selection = availableIDs; explicit = true }
        if selection.contains(id) {
            guard selection.intersection(availableIDs).count > 1 else { return }
            selection.remove(id)
        } else { selection.insert(id) }
    }
}

extension UserDefaults {
    static var ephemeral: UserDefaults {
        UserDefaults(suiteName: "PersonalCalendar.\(UUID().uuidString)")!
    }
}
