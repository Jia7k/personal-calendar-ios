import EventKit

enum ReminderDraftValidator {
    static func validate(_ draft: ReminderDraft) throws {
        guard !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DraftValidationError.emptyTitle
        }
    }
}

@MainActor
final class EventKitRemindersService: RemindersServicing {
    private let store: EKEventStore

    init(store: EKEventStore) {
        self.store = store
    }

    var accessState: AccessState {
        EventKitAccessMapper.map(EKEventStore.authorizationStatus(for: .reminder))
    }

    func requestFullAccess() async -> AccessState {
        do {
            return try await store.requestFullAccessToReminders() ? .granted : .denied
        } catch {
            return .denied
        }
    }

    func lists() -> [ReminderListDescriptor] {
        guard accessState == .granted else { return [] }

        return store.calendars(for: .reminder).map {
            ReminderListDescriptor(
                id: $0.calendarIdentifier,
                title: $0.title,
                colorHex: $0.cgColor.hexRGB,
                allowsContentModifications: $0.allowsContentModifications
            )
        }
    }

    func fetchReminders(listIDs: Set<String>) async throws -> [ReminderSnapshot] {
        guard accessState == .granted else { return [] }

        let selectedLists = store.calendars(for: .reminder).filter {
            listIDs.isEmpty || listIDs.contains($0.calendarIdentifier)
        }
        let predicate = store.predicateForReminders(in: selectedLists)

        return try await withCheckedThrowingContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                Task { @MainActor in
                    guard let reminders else {
                        continuation.resume(throwing: ReminderFetchError.missingResult)
                        return
                    }
                    continuation.resume(returning: reminders.map(ReminderSnapshot.init(reminder:)))
                }
            }
        }
    }

    func createReminder(_ draft: ReminderDraft) throws -> String {
        try ReminderDraftValidator.validate(draft)

        let destination: EKCalendar?
        if let listID = draft.listID {
            destination = store.calendars(for: .reminder).first {
                $0.calendarIdentifier == listID
            }
        } else {
            destination = store.defaultCalendarForNewReminders()
        }
        guard let destination, destination.allowsContentModifications else {
            throw DraftValidationError.readOnlyDestination
        }

        let reminder = EKReminder(eventStore: store)
        reminder.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        reminder.notes = draft.notes
        reminder.priority = draft.priority
        reminder.calendar = destination
        if let dueDate = draft.dueDate {
            let components: Set<Calendar.Component> = draft.dueHasTime
                ? [.year, .month, .day, .hour, .minute]
                : [.year, .month, .day]
            var dueComponents = Calendar.current.dateComponents(components, from: dueDate)
            dueComponents.calendar = .current
            dueComponents.timeZone = .current
            reminder.dueDateComponents = dueComponents
        }

        try store.save(reminder, commit: true)
        return reminder.calendarItemIdentifier
    }

    func setCompleted(id: String, completed: Bool) throws {
        guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder,
              reminder.calendar.allowsContentModifications else {
            throw DraftValidationError.readOnlyDestination
        }

        reminder.isCompleted = completed
        try store.save(reminder, commit: true)
    }
}

private enum ReminderFetchError: Error {
    case missingResult
}
