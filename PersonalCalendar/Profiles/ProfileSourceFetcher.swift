import Foundation

struct ProfileSourceFetchResult: Equatable, Sendable {
    let events: [CalendarEventSnapshot]
    let reminders: [ReminderSnapshot]
}

@MainActor
struct ProfileSourceFetcher {
    private let calendar: any CalendarServicing
    private let reminders: any RemindersServicing

    init(
        calendar: any CalendarServicing,
        reminders: any RemindersServicing
    ) {
        self.calendar = calendar
        self.reminders = reminders
    }

    func fetch(
        scope: ProfileScope,
        interval: DateInterval
    ) async throws -> ProfileSourceFetchResult {
        let events: [CalendarEventSnapshot]
        if scope.calendarIDs.isEmpty {
            events = []
        } else {
            events = try calendar.fetchEvents(
                in: interval,
                calendarIDs: scope.calendarIDs
            )
        }

        let reminderSnapshots: [ReminderSnapshot]
        if scope.reminderListIDs.isEmpty {
            reminderSnapshots = []
        } else {
            reminderSnapshots = try await reminders.fetchReminders(
                listIDs: scope.reminderListIDs
            )
        }

        return ProfileSourceFetchResult(
            events: events,
            reminders: reminderSnapshots
        )
    }
}
