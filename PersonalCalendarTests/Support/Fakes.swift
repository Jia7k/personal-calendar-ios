import Foundation
@testable import PersonalCalendar

@MainActor
final class FakeCalendarService: CalendarServicing {
    var accessState: AccessState
    var requestedAccess: AccessState
    var events: [CalendarEventSnapshot]
    var descriptors: [CalendarDescriptor]
    var createdDrafts: [EventDraft] = []

    init(
        access: AccessState,
        requestedAccess: AccessState? = nil,
        events: [CalendarEventSnapshot] = [],
        descriptors: [CalendarDescriptor] = []
    ) {
        accessState = access
        self.requestedAccess = requestedAccess ?? access
        self.events = events
        self.descriptors = descriptors
    }

    func requestFullAccess() async -> AccessState {
        accessState = requestedAccess
        return accessState
    }

    func calendars() -> [CalendarDescriptor] { descriptors }

    func fetchEvents(in interval: DateInterval, calendarIDs: Set<String>) throws -> [CalendarEventSnapshot] {
        events
    }

    func createEvent(_ draft: EventDraft) throws -> String {
        createdDrafts.append(draft)
        return "created-event"
    }
}

struct CompletionCall: Equatable {
    let id: String
    let completed: Bool
}

@MainActor
final class FakeRemindersService: RemindersServicing {
    var accessState: AccessState
    var requestedAccess: AccessState
    var reminders: [ReminderSnapshot]
    var descriptors: [ReminderListDescriptor]
    var fetchError: Error?
    var createdDrafts: [ReminderDraft] = []
    var completedCalls: [CompletionCall] = []

    init(
        access: AccessState,
        requestedAccess: AccessState? = nil,
        reminders: [ReminderSnapshot] = [],
        descriptors: [ReminderListDescriptor] = [],
        fetchError: Error? = nil
    ) {
        accessState = access
        self.requestedAccess = requestedAccess ?? access
        self.reminders = reminders
        self.descriptors = descriptors
        self.fetchError = fetchError
    }

    func requestFullAccess() async -> AccessState {
        accessState = requestedAccess
        return accessState
    }

    func lists() -> [ReminderListDescriptor] { descriptors }

    func fetchReminders(listIDs: Set<String>) async throws -> [ReminderSnapshot] {
        if let fetchError {
            throw fetchError
        }
        return reminders
    }

    func createReminder(_ draft: ReminderDraft) throws -> String {
        createdDrafts.append(draft)
        return "created-task"
    }

    func setCompleted(id: String, completed: Bool) throws {
        completedCalls.append(.init(id: id, completed: completed))
    }
}

extension ReminderSnapshot {
    static let sampleTask = ReminderSnapshot(
        id: "task",
        title: "Buy milk",
        notes: nil,
        dueDate: nil,
        dueHasTime: false,
        priority: 5,
        listID: "tasks",
        listTitle: "Tasks",
        isCompleted: false,
        allowsModification: true,
        hasRecurrence: false
    )
}

@MainActor
final class FakeNotificationAuthorizer: NotificationAuthorizing {
    private var state: AccessState
    private let requested: AccessState

    init(access: AccessState, requestedAccess: AccessState? = nil) {
        state = access
        requested = requestedAccess ?? access
    }

    var accessState: AccessState {
        get async { state }
    }

    func requestAccess() async -> AccessState {
        state = requested
        return state
    }
}
