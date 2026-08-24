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

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        selectedCalendarIDs = Set(defaults.stringArray(forKey: Key.selectedCalendars) ?? [])
        selectedReminderListIDs = Set(defaults.stringArray(forKey: Key.selectedLists) ?? [])
        defaultCalendarID = defaults.string(forKey: Key.defaultCalendar)
        defaultReminderListID = defaults.string(forKey: Key.defaultList)
    }
}

extension UserDefaults {
    static var ephemeral: UserDefaults {
        UserDefaults(suiteName: "PersonalCalendar.\(UUID().uuidString)")!
    }
}
