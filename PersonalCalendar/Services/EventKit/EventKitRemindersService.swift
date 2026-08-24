import EventKit

@MainActor
enum ReminderDraftValidator {
    static func validate(_ draft: ReminderDraft) throws {
        guard !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DraftValidationError.emptyTitle
        }
        guard !draft.hasInvalidLegacyDueTimeWithoutDate else {
            throw DraftValidationError.recurringReminderRequiresDueDate
        }
        guard (0...9).contains(draft.priority) else {
            throw DraftValidationError.invalidDateRange
        }
        guard draft.dueDate?.timeIntervalSinceReferenceDate.isFinite ?? true else {
            throw DraftValidationError.invalidDateRange
        }
        if case let .replace(date) = draft.alarm,
           !date.timeIntervalSinceReferenceDate.isFinite {
            throw DraftValidationError.invalidDateRange
        }
        if case let .replace(rule) = draft.recurrence { guard let due = draft.dueDate else { throw DraftValidationError.recurringReminderRequiresDueDate }; try EventKitRecurrenceMapper.validate(rule, startsAt: due) }
    }
}

@MainActor
final class EventKitRemindersService: RemindersServicing {
    private let store: EKEventStore
    private let mutations: any EventKitMutationBacking

    init(store: EKEventStore, mutations: (any EventKitMutationBacking)? = nil) {
        self.store = store
        self.mutations = mutations ?? SystemEventKitMutationBacking(store: store)
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
                    let occurrences = reminders.map(ReminderOccurrenceInput.init(reminder:))
                    continuation.resume(returning: ReminderSnapshotMapper.snapshots(from: occurrences))
                }
            }
        }
    }

    func createReminder(_ draft: ReminderDraft) throws -> String? {
        try mutations.createReminder(.init(draft: draft, destination: draft.listID.map(CreateDestination.explicit) ?? .defaultWritable))
    }

    func setCompleted(id: String, completed: Bool) throws {
        try mutations.setReminderCompleted(id: id, completed: completed)
    }
    func reminder(id: String) -> ReminderSnapshot? { guard accessState == .granted, let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else { return nil }; return ReminderSnapshotMapper.snapshot(from: .init(reminder: reminder)) }
    func updateReminder(id: String, draft: ReminderDraft) throws { try mutations.updateReminder(id: id, request: .init(draft: draft, destination: draft.listID.map(UpdateDestination.explicit) ?? .preserveCurrent)) }
    func deleteReminder(id: String) throws { try mutations.removeReminder(id: id) }
}


private enum ReminderFetchError: Error {
    case missingResult
}

enum ReminderDueComponentBuilder {
    static func components(
        for dueDate: Date,
        dueHasTime: Bool,
        preferredCalendar: Calendar
    ) -> DateComponents {
        var gregorianCalendar = Calendar(identifier: .gregorian)
        gregorianCalendar.timeZone = preferredCalendar.timeZone
        let requestedComponents: Set<Calendar.Component> = dueHasTime
            ? [.year, .month, .day, .hour, .minute]
            : [.year, .month, .day]
        var components = gregorianCalendar.dateComponents(requestedComponents, from: dueDate)
        components.calendar = gregorianCalendar
        components.timeZone = preferredCalendar.timeZone
        return components
    }
}
