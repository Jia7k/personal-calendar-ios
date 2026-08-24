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
        didSet { defaults.set(selectedCalendarIDs.sorted(), forKey: Key.selectedCalendars); calendarSelectionIsExplicit = true }
    }

    var selectedReminderListIDs: Set<String> {
        didSet { defaults.set(selectedReminderListIDs.sorted(), forKey: Key.selectedLists); reminderSelectionIsExplicit = true }
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
        let inferredCalendarExplicit = defaults.object(forKey: Key.calendarsExplicit) as? Bool ?? !storedCalendars.isEmpty
        let inferredListExplicit = defaults.object(forKey: Key.listsExplicit) as? Bool ?? !storedLists.isEmpty
        calendarSelectionIsExplicit = inferredCalendarExplicit
        reminderSelectionIsExplicit = inferredListExplicit
        // Persist migration so a future empty persisted set is never mistaken for implicit-all.
        defaults.set(inferredCalendarExplicit, forKey: Key.calendarsExplicit)
        defaults.set(inferredListExplicit, forKey: Key.listsExplicit)
    }

    func toggleCalendar(id: String, availableIDs: Set<String>) { toggle(id: id, selection: &selectedCalendarIDs, explicit: &calendarSelectionIsExplicit, availableIDs: availableIDs) }
    func toggleReminderList(id: String, availableIDs: Set<String>) { toggle(id: id, selection: &selectedReminderListIDs, explicit: &reminderSelectionIsExplicit, availableIDs: availableIDs) }
    func visibleCalendarIDs(availableIDs: Set<String>) -> Set<String> { calendarSelectionIsExplicit ? selectedCalendarIDs.intersection(availableIDs) : availableIDs }
    func visibleReminderListIDs(availableIDs: Set<String>) -> Set<String> { reminderSelectionIsExplicit ? selectedReminderListIDs.intersection(availableIDs) : availableIDs }
    func setSelectedCalendarsForTesting(_ ids: Set<String>, explicit: Bool) { selectedCalendarIDs = ids; calendarSelectionIsExplicit = explicit }
    func setSelectedReminderListsForTesting(_ ids: Set<String>, explicit: Bool) { selectedReminderListIDs = ids; reminderSelectionIsExplicit = explicit }

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
