import Foundation

struct CalendarDeepLinkSignal: Equatable, Sendable, Identifiable {
    let id: UUID
    let day: AppRouteDay?
    let entryID: String?
}

enum CalendarDeepLinkResolution: Equatable, Sendable {
    case navigate(day: AppRouteDay?)
    case open(day: AppRouteDay?, event: CalendarEventSnapshot)
    case unavailable
}

struct CalendarDeepLinkResolver {
    private(set) var lastSignalID: UUID?

    mutating func resolve(
        _ signal: CalendarDeepLinkSignal?,
        events: [CalendarEventSnapshot]
    ) -> CalendarDeepLinkResolution? {
        guard let signal, signal.id != lastSignalID else { return nil }
        lastSignalID = signal.id

        guard let entryID = signal.entryID else {
            return .navigate(day: signal.day)
        }
        guard let event = events.first(where: {
            AppRouteEntryIdentity.make(
                displayID: $0.id,
                occurrenceStart: $0.start
            ) == entryID
        }) else {
            return .unavailable
        }
        return .open(day: signal.day, event: event)
    }
}

struct TaskDeepLinkSignal: Equatable, Sendable, Identifiable {
    let id: UUID
    let reminderID: String
}

enum TaskDeepLinkResolution: Equatable, Sendable {
    case open(ReminderSnapshot)
    case unavailable
}

struct TaskDeepLinkResolver {
    private(set) var lastSignalID: UUID?

    mutating func resolve(
        _ signal: TaskDeepLinkSignal?,
        reminders: [ReminderSnapshot]
    ) -> TaskDeepLinkResolution? {
        guard let signal, signal.id != lastSignalID else { return nil }
        lastSignalID = signal.id

        guard let reminder = reminders.first(where: { $0.id == signal.reminderID }) else {
            return .unavailable
        }
        return .open(reminder)
    }
}

enum HostRouteCancellationPolicy {
    static func shouldFinishAsUnavailable(
        taskIsCancelled: Bool,
        signalIsCurrent: Bool,
        localPresentationIsActive: Bool,
        presentationGenerationIsUnchanged: Bool
    ) -> Bool {
        taskIsCancelled
            && signalIsCurrent
            && !localPresentationIsActive
            && presentationGenerationIsUnchanged
    }
}
