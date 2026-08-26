import Foundation
import Observation

enum TaskTimeBlockFailure: Equatable, Sendable {
    case profileUnavailable
    case invalidDestination
    case writeFailed
}

enum TaskTimeBlockPhase: Equatable, Sendable {
    case ready
    case awaitingConflictConfirmation
    case saved(id: String?)
    case failed(TaskTimeBlockFailure)
}

@MainActor
@Observable
final class TaskTimeBlockViewModel {
    let task: ReminderSnapshot

    private(set) var creationProfile: CreationProfileContext?
    private(set) var availableCalendars: [CalendarDescriptor] = []
    private(set) var suggestions: [TaskTimeBlockSuggestion] = []
    private(set) var durationMinutes = 60
    private(set) var start: Date
    private(set) var end: Date
    private(set) var destinationCalendarID: String?
    private(set) var conflicts: [String] = []
    private(set) var requiresConflictConfirmation = false
    private(set) var requiresProfileSelection: Bool
    private(set) var phase: TaskTimeBlockPhase = .ready

    var selectedProfileName: String? { creationProfile?.profileName }

    @ObservationIgnored private let calendarService: any CalendarServicing
    @ObservationIgnored private let resolveScope: @MainActor (ProfileIdentity) throws -> ProfileScope
    @ObservationIgnored private let planner: TaskTimeBlockPlanner
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private var scopedEvents: [CalendarEventSnapshot] = []
    @ObservationIgnored private var didSave = false
    @ObservationIgnored private var isSaving = false

    init(
        task: ReminderSnapshot,
        creationProfile: CreationProfileContext?,
        calendarService: any CalendarServicing,
        resolveScope: @escaping @MainActor (ProfileIdentity) throws -> ProfileScope,
        planner: TaskTimeBlockPlanner,
        calendar: Calendar,
        now: @escaping @MainActor () -> Date
    ) {
        let initialStart = now()
        self.task = task
        self.creationProfile = creationProfile
        self.calendarService = calendarService
        self.resolveScope = resolveScope
        self.planner = planner
        self.calendar = calendar
        self.now = now
        start = initialStart
        end = calendar.date(byAdding: .minute, value: 60, to: initialStart) ?? initialStart
        requiresProfileSelection = creationProfile == nil
    }

    func load() async {
        guard !didSave else { return }
        guard let creationProfile else {
            requiresProfileSelection = true
            clearScopedContent()
            phase = .ready
            return
        }

        requiresProfileSelection = false
        let scope: ProfileScope
        do {
            scope = try resolveScope(.saved(creationProfile.profileID))
        } catch {
            failForUnavailableProfile()
            return
        }

        guard scope.identity == .saved(creationProfile.profileID),
              calendarService.accessState == .granted else {
            failForUnavailableProfile()
            return
        }

        let liveCalendars = SourceDescriptorOrdering.calendars(
            calendarService.calendars().filter {
                scope.calendarIDs.contains($0.id) && $0.allowsContentModifications
            }
        )
        availableCalendars = liveCalendars
        destinationCalendarID = preferredDestination(
            existing: destinationCalendarID,
            capturedDefault: creationProfile.defaultCalendarID,
            liveCalendars: liveCalendars
        )

        guard !scope.calendarIDs.isEmpty else {
            scopedEvents = []
            suggestions = []
            conflicts = []
            resetConfirmation()
            return
        }

        guard let interval = candidateDayInterval(reference: now()) else {
            scopedEvents = []
            suggestions = []
            conflicts = []
            resetConfirmation()
            return
        }

        do {
            scopedEvents = try calendarService.fetchEvents(
                in: interval,
                calendarIDs: scope.calendarIDs
            )
            .filter { scope.calendarIDs.contains($0.calendarID) }
            rebuildSuggestions(selectFirst: true)
            resetConfirmation()
        } catch {
            failForUnavailableProfile()
        }
    }

    func chooseProfile(_ context: CreationProfileContext) async {
        guard !didSave else { return }
        creationProfile = context
        destinationCalendarID = nil
        requiresProfileSelection = false
        await load()
    }

    func setDurationMinutes(_ value: Int) {
        guard !didSave, [30, 60, 90].contains(value) else { return }
        durationMinutes = value
        rebuildSuggestions(selectFirst: true)
        resetConfirmation()
    }

    func setInterval(start: Date, end: Date) {
        guard !didSave else { return }
        self.start = start
        self.end = end
        conflicts = currentConflicts()
        resetConfirmation(preservingConflicts: true)
    }

    func selectDestination(calendarID: String?) {
        guard !didSave else { return }
        destinationCalendarID = calendarID
        resetConfirmation()
    }

    func save(confirmingConflicts: Bool = false) async {
        guard !didSave, !isSaving else { return }
        guard let creationProfile else {
            requiresProfileSelection = true
            phase = .failed(.profileUnavailable)
            return
        }
        guard let destinationCalendarID,
              let selectedInterval = validInterval else {
            phase = .failed(.invalidDestination)
            return
        }

        let liveScope: ProfileScope
        do {
            liveScope = try resolveScope(.saved(creationProfile.profileID))
        } catch {
            phase = .failed(.profileUnavailable)
            return
        }

        guard liveScope.identity == .saved(creationProfile.profileID) else {
            phase = .failed(.profileUnavailable)
            return
        }
        guard calendarService.accessState == .granted,
              liveScope.calendarIDs.contains(destinationCalendarID) else {
            phase = .failed(.invalidDestination)
            return
        }

        let liveCalendars = SourceDescriptorOrdering.calendars(
            calendarService.calendars().filter {
                liveScope.calendarIDs.contains($0.id) && $0.allowsContentModifications
            }
        )
        availableCalendars = liveCalendars
        guard liveCalendars.contains(where: { $0.id == destinationCalendarID }) else {
            phase = .failed(.invalidDestination)
            return
        }

        guard let fetchInterval = dayInterval(containing: selectedInterval) else {
            phase = .failed(.invalidDestination)
            return
        }
        do {
            scopedEvents = try calendarService.fetchEvents(
                in: fetchInterval,
                calendarIDs: liveScope.calendarIDs
            )
            .filter { liveScope.calendarIDs.contains($0.calendarID) }
        } catch {
            phase = .failed(.writeFailed)
            return
        }

        conflicts = currentConflicts()
        if !conflicts.isEmpty && !confirmingConflicts {
            requiresConflictConfirmation = true
            phase = .awaitingConflictConfirmation
            return
        }
        requiresConflictConfirmation = false

        let draft = EventDraft(
            title: task.title,
            start: start,
            end: end,
            isAllDay: false,
            calendarID: destinationCalendarID,
            notes: "personalcalendar-task:v1:\(Self.percentEncodeRFC3986(task.id))",
            alarms: .clear,
            recurrence: .clear
        )

        isSaving = true
        defer { isSaving = false }
        do {
            let id = try calendarService.createEvent(draft)
            didSave = true
            phase = .saved(id: id)
        } catch {
            requiresConflictConfirmation = !conflicts.isEmpty
            phase = .failed(.writeFailed)
        }
    }

    private var validInterval: DateInterval? {
        guard start.timeIntervalSinceReferenceDate.isFinite,
              end.timeIntervalSinceReferenceDate.isFinite,
              start < end else {
            return nil
        }
        return DateInterval(start: start, end: end)
    }

    private func candidateDayInterval(reference: Date) -> DateInterval? {
        guard reference.timeIntervalSinceReferenceDate.isFinite else { return nil }
        let today = calendar.startOfDay(for: reference)
        let day: Date
        if let due = task.dueDate,
           due.timeIntervalSinceReferenceDate.isFinite,
           calendar.startOfDay(for: due) >= today {
            day = calendar.startOfDay(for: due)
        } else {
            day = today
        }
        guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day),
              day < nextDay else {
            return nil
        }
        return DateInterval(start: day, end: nextDay)
    }

    private func dayInterval(containing interval: DateInterval) -> DateInterval? {
        let firstDay = calendar.startOfDay(for: interval.start)
        let endDay = calendar.startOfDay(for: interval.end)
        let exclusiveEnd: Date
        if interval.end == endDay {
            exclusiveEnd = endDay
        } else {
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: endDay) else {
                return nil
            }
            exclusiveEnd = nextDay
        }
        guard firstDay < exclusiveEnd else { return nil }
        return DateInterval(start: firstDay, end: exclusiveEnd)
    }

    private func preferredDestination(
        existing: String?,
        capturedDefault: String?,
        liveCalendars: [CalendarDescriptor]
    ) -> String? {
        if let existing,
           liveCalendars.contains(where: { $0.id == existing }) {
            return existing
        }
        guard let capturedDefault,
              liveCalendars.contains(where: { $0.id == capturedDefault }) else {
            return nil
        }
        return capturedDefault
    }

    private func rebuildSuggestions(selectFirst: Bool) {
        suggestions = planner.suggestions(
            task: task,
            durationMinutes: durationMinutes,
            events: scopedEvents,
            now: now()
        )
        if selectFirst, let first = suggestions.first {
            start = first.interval.start
            end = first.interval.end
        }
        conflicts = currentConflicts()
    }

    private func currentConflicts() -> [String] {
        guard let interval = validInterval else { return [] }
        return planner.conflicts(for: interval, events: scopedEvents)
    }

    private func resetConfirmation(preservingConflicts: Bool = false) {
        requiresConflictConfirmation = false
        if !preservingConflicts {
            conflicts = currentConflicts()
        }
        phase = .ready
    }

    private func clearScopedContent() {
        availableCalendars = []
        destinationCalendarID = nil
        scopedEvents = []
        suggestions = []
        conflicts = []
        requiresConflictConfirmation = false
    }

    private func failForUnavailableProfile() {
        clearScopedContent()
        phase = .failed(.profileUnavailable)
    }

    private static func percentEncodeRFC3986(_ value: String) -> String {
        value.utf8.map { byte in
            switch byte {
            case 65...90, 97...122, 48...57, 45, 46, 95, 126:
                String(UnicodeScalar(byte))
            default:
                String(format: "%%%02X", byte)
            }
        }
        .joined()
    }
}
