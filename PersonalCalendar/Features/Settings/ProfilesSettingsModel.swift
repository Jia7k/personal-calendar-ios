import Foundation
import Observation

@MainActor
@Observable
final class ProfileEditorState {
    let profileID: UUID?
    var draft: ProfileDraft
    let calendars: [CalendarDescriptor]
    let reminderLists: [ReminderListDescriptor]
    let routines: [RoutineSnapshot]

    init(
        profileID: UUID?,
        draft: ProfileDraft,
        calendars: [CalendarDescriptor],
        reminderLists: [ReminderListDescriptor],
        routines: [RoutineSnapshot]
    ) {
        self.profileID = profileID
        self.draft = draft
        self.calendars = SourceDescriptorOrdering.calendars(calendars)
        self.reminderLists = SourceDescriptorOrdering.reminderLists(reminderLists)
        self.routines = routines.sorted {
            let titleOrder = $0.title.localizedCaseInsensitiveCompare($1.title)
            return titleOrder == .orderedSame
                ? $0.id.uuidString < $1.id.uuidString
                : titleOrder == .orderedAscending
        }
    }

    var waitingCalendarCount: Int {
        draft.calendarIDs.subtracting(Set(calendars.map(\.id))).count
    }

    var waitingReminderListCount: Int {
        draft.reminderListIDs.subtracting(Set(reminderLists.map(\.id))).count
    }

    var validatedDefaultCalendarID: String? {
        guard let id = draft.defaultCalendarID,
              draft.calendarIDs.contains(id),
              calendars.contains(where: { $0.id == id && $0.allowsContentModifications }) else {
            return nil
        }
        return id
    }

    var validatedDefaultReminderListID: String? {
        guard let id = draft.defaultReminderListID,
              draft.reminderListIDs.contains(id),
              reminderLists.contains(where: { $0.id == id && $0.allowsContentModifications }) else {
            return nil
        }
        return id
    }

    var defaultCalendarChoices: [CalendarDescriptor] {
        calendars.filter {
            $0.allowsContentModifications && draft.calendarIDs.contains($0.id)
        }
    }

    var defaultReminderListChoices: [ReminderListDescriptor] {
        reminderLists.filter {
            $0.allowsContentModifications && draft.reminderListIDs.contains($0.id)
        }
    }

    fileprivate var validatedDraft: ProfileDraft {
        var value = draft
        value.defaultCalendarID = validatedDefaultCalendarID
        value.defaultReminderListID = validatedDefaultReminderListID
        return value
    }
}

@MainActor
@Observable
final class ProfilesSettingsModel {
    private let repository: any ProfileRepository
    private let calendar: any CalendarServicing
    private let reminders: any RemindersServicing
    private let routines: any RoutineRepository
    private let profileDidChange: @MainActor (UUID, Bool, Bool) throws -> Void
    private let profileWasDeleted: @MainActor (UUID) throws -> Void

    private(set) var profiles: [ProfileSnapshot] = []

    init(
        repository: any ProfileRepository,
        calendar: any CalendarServicing,
        reminders: any RemindersServicing,
        routines: any RoutineRepository,
        profileDidChange: @escaping @MainActor (UUID, Bool) throws -> Void,
        profileWasDeleted: @escaping @MainActor (UUID) throws -> Void
    ) {
        self.repository = repository
        self.calendar = calendar
        self.reminders = reminders
        self.routines = routines
        self.profileDidChange = { id, visibilityChanged, _ in
            try profileDidChange(id, visibilityChanged)
        }
        self.profileWasDeleted = profileWasDeleted
    }

    init(
        repository: any ProfileRepository,
        calendar: any CalendarServicing,
        reminders: any RemindersServicing,
        routines: any RoutineRepository,
        profileImpactDidChange: @escaping @MainActor (UUID, Bool, Bool) throws -> Void,
        profileWasDeleted: @escaping @MainActor (UUID) throws -> Void
    ) {
        self.repository = repository
        self.calendar = calendar
        self.reminders = reminders
        self.routines = routines
        profileDidChange = profileImpactDidChange
        self.profileWasDeleted = profileWasDeleted
    }

    func reload() throws {
        profiles = try repository.list()
    }

    func makeEditor(profileID: UUID?) throws -> ProfileEditorState {
        let draft: ProfileDraft
        if let profileID {
            draft = Self.draft(from: try repository.profile(id: profileID))
        } else {
            draft = ProfileDraft(
                name: "",
                colorHex: "#4868A8",
                symbolName: "person.fill",
                calendarIDs: [],
                reminderListIDs: [],
                routineIDs: [],
                defaultCalendarID: nil,
                defaultReminderListID: nil
            )
        }

        return ProfileEditorState(
            profileID: profileID,
            draft: draft,
            calendars: calendar.calendars(),
            reminderLists: reminders.lists(),
            routines: try routines.list(includeArchived: true)
        )
    }

    @discardableResult
    func save(_ editor: ProfileEditorState) throws -> UUID {
        let draft = editor.validatedDraft
        let id: UUID
        let visibilityChanged: Bool
        let removedCalendarMembership: Bool

        if let profileID = editor.profileID {
            let previous = try repository.profile(id: profileID)
            try repository.update(id: profileID, draft: draft)
            id = profileID
            visibilityChanged = Self.membershipChanged(from: previous, to: draft)
            removedCalendarMembership = !previous.calendarIDs.subtracting(draft.calendarIDs).isEmpty
        } else {
            id = try repository.create(draft)
            visibilityChanged = !draft.calendarIDs.isEmpty
                || !draft.reminderListIDs.isEmpty
                || !draft.routineIDs.isEmpty
            removedCalendarMembership = false
        }

        profiles = try repository.list()
        try profileDidChange(id, visibilityChanged, removedCalendarMembership)
        return id
    }

    func reorder(_ ids: [UUID]) throws {
        try repository.reorder(ids)
        profiles = try repository.list()
        if let firstID = ids.first {
            try profileDidChange(firstID, false, false)
        }
    }

    func delete(id: UUID) throws {
        try repository.delete(id: id)
        profiles = try repository.list()
        try profileWasDeleted(id)
    }

    private static func draft(from profile: ProfileSnapshot) -> ProfileDraft {
        ProfileDraft(
            name: profile.name,
            colorHex: profile.colorHex,
            symbolName: profile.symbolName,
            calendarIDs: profile.calendarIDs,
            reminderListIDs: profile.reminderListIDs,
            routineIDs: profile.routineIDs,
            defaultCalendarID: profile.defaultCalendarID,
            defaultReminderListID: profile.defaultReminderListID
        )
    }

    private static func membershipChanged(
        from profile: ProfileSnapshot,
        to draft: ProfileDraft
    ) -> Bool {
        profile.calendarIDs != draft.calendarIDs
            || profile.reminderListIDs != draft.reminderListIDs
            || profile.routineIDs != draft.routineIDs
    }
}
