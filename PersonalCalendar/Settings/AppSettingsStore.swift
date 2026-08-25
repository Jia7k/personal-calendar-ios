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
    private(set) var calendarSelectionIsExplicit: Bool
    private(set) var reminderSelectionIsExplicit: Bool

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedCalendarIDs = Set(defaults.stringArray(forKey: Key.selectedCalendars) ?? [])
        let storedReminderListIDs = Set(defaults.stringArray(forKey: Key.selectedLists) ?? [])
        selectedCalendarIDs = storedCalendarIDs
        selectedReminderListIDs = storedReminderListIDs
        defaultCalendarID = defaults.string(forKey: Key.defaultCalendar)
        defaultReminderListID = defaults.string(forKey: Key.defaultList)
        didCompleteOnboarding = defaults.bool(forKey: Key.onboarding)
        didSeedCategories = defaults.bool(forKey: Key.categoriesSeeded)
        morningSummaryEnabled = defaults.bool(forKey: Key.morningSummaryEnabled)
        morningSummaryHour = (defaults.object(forKey: Key.morningSummaryHour) as? Int).flatMap { (0...23).contains($0) ? $0 : nil } ?? 8
        morningSummaryMinute = (defaults.object(forKey: Key.morningSummaryMinute) as? Int).flatMap { (0...59).contains($0) ? $0 : nil } ?? 0
        showNextItemOnLockScreen = defaults.bool(forKey: Key.showNextItemOnLockScreen)
        calendarSelectionIsExplicit = defaults.object(forKey: Key.calendarsExplicit) as? Bool ?? !storedCalendarIDs.isEmpty
        reminderSelectionIsExplicit = defaults.object(forKey: Key.listsExplicit) as? Bool ?? !storedReminderListIDs.isEmpty
        persistSelectionMarkers()
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
        if calendarAccess == .granted, defaultCalendarID.map({ id in !calendars.contains { $0.id == id && $0.allowsContentModifications } }) == true {
            defaultCalendarID = nil
            defaults.removeObject(forKey: Key.defaultCalendar)
        }
        if remindersAccess == .granted, defaultReminderListID.map({ id in !lists.contains { $0.id == id && $0.allowsContentModifications } }) == true {
            defaultReminderListID = nil
            defaults.removeObject(forKey: Key.defaultList)
        }
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
}

extension UserDefaults {
    static var ephemeral: UserDefaults { UserDefaults(suiteName: "PersonalCalendar.\(UUID().uuidString)")! }
}
