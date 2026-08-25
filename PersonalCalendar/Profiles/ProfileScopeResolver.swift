import Foundation

@MainActor
struct ProfileScopeResolver {
    private let profiles: any ProfileRepository
    private let calendar: any CalendarServicing
    private let reminders: any RemindersServicing

    init(
        profiles: any ProfileRepository,
        calendar: any CalendarServicing,
        reminders: any RemindersServicing
    ) {
        self.profiles = profiles
        self.calendar = calendar
        self.reminders = reminders
    }

    func resolve(_ identity: ProfileIdentity) throws -> ProfileScope {
        let calendarDescriptors = currentCalendarDescriptors()
        let reminderDescriptors = currentReminderDescriptors()
        let availableCalendarIDs = Set(calendarDescriptors.map(\.id))
        let availableReminderListIDs = Set(reminderDescriptors.map(\.id))

        switch identity {
        case .everything:
            let membership = try profiles.unionMembership()
            return ProfileScope(
                identity: .everything,
                calendarIDs: membership.calendarIDs.intersection(availableCalendarIDs),
                reminderListIDs: membership.reminderListIDs.intersection(availableReminderListIDs),
                routineIDs: membership.routineIDs,
                defaultCalendarID: nil,
                defaultReminderListID: nil
            )

        case let .saved(id):
            let profile = try profiles.profile(id: id)
            return ProfileScope(
                identity: identity,
                calendarIDs: profile.calendarIDs.intersection(availableCalendarIDs),
                reminderListIDs: profile.reminderListIDs.intersection(availableReminderListIDs),
                routineIDs: profile.routineIDs,
                defaultCalendarID: validCalendarDefault(
                    profile.defaultCalendarID,
                    membership: profile.calendarIDs,
                    descriptors: calendarDescriptors
                ),
                defaultReminderListID: validReminderDefault(
                    profile.defaultReminderListID,
                    membership: profile.reminderListIDs,
                    descriptors: reminderDescriptors
                )
            )
        }
    }

    private func currentCalendarDescriptors() -> [CalendarDescriptor] {
        guard calendar.accessState == .granted else { return [] }
        return calendar.calendars()
    }

    private func currentReminderDescriptors() -> [ReminderListDescriptor] {
        guard reminders.accessState == .granted else { return [] }
        return reminders.lists()
    }

    private func validCalendarDefault(
        _ id: String?,
        membership: Set<String>,
        descriptors: [CalendarDescriptor]
    ) -> String? {
        guard let id,
              membership.contains(id),
              descriptors.contains(where: {
                  $0.id == id && $0.allowsContentModifications
              }) else {
            return nil
        }
        return id
    }

    private func validReminderDefault(
        _ id: String?,
        membership: Set<String>,
        descriptors: [ReminderListDescriptor]
    ) -> String? {
        guard let id,
              membership.contains(id),
              descriptors.contains(where: {
                  $0.id == id && $0.allowsContentModifications
              }) else {
            return nil
        }
        return id
    }
}
