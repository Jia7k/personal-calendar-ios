import Foundation
import Observation

struct QuickEntryDestinationOptions: Equatable, Sendable {
    let calendarAccess: AccessState
    let remindersAccess: AccessState
    let calendars: [CalendarDescriptor]
    let reminderLists: [ReminderListDescriptor]
    let defaultCalendarID: String?
    let defaultReminderListID: String?
    let visibleCalendarIDs: Set<String>
    let visibleReminderListIDs: Set<String>

    static let empty = QuickEntryDestinationOptions(
        calendarAccess: .notDetermined,
        remindersAccess: .notDetermined,
        calendars: [],
        reminderLists: [],
        defaultCalendarID: nil,
        defaultReminderListID: nil,
        visibleCalendarIDs: [],
        visibleReminderListIDs: []
    )

    @MainActor
    static func resolve(
        calendar: any CalendarServicing,
        reminders: any RemindersServicing,
        settings: AppSettingsStore
    ) -> QuickEntryDestinationOptions {
        let calendarAccess = calendar.accessState
        let remindersAccess = reminders.accessState
        let allCalendars = calendarAccess == .granted ? calendar.calendars() : []
        let allLists = remindersAccess == .granted ? reminders.lists() : []
        let writableCalendars = SourceDescriptorOrdering.calendars(allCalendars.filter(\.allowsContentModifications))
        let writableLists = SourceDescriptorOrdering.reminderLists(allLists.filter(\.allowsContentModifications))
        let calendarIDs = Set(allCalendars.map(\.id))
        let listIDs = Set(allLists.map(\.id))
        let validCalendarDefault = settings.defaultCalendarID.flatMap { id in writableCalendars.contains(where: { $0.id == id }) ? id : nil }
        let validListDefault = settings.defaultReminderListID.flatMap { id in writableLists.contains(where: { $0.id == id }) ? id : nil }
        return .init(
            calendarAccess: calendarAccess,
            remindersAccess: remindersAccess,
            calendars: writableCalendars,
            reminderLists: writableLists,
            defaultCalendarID: validCalendarDefault,
            defaultReminderListID: validListDefault,
            visibleCalendarIDs: calendarAccess == .granted ? settings.visibleCalendarIDs(availableIDs: calendarIDs) : [],
            visibleReminderListIDs: remindersAccess == .granted ? settings.visibleReminderListIDs(availableIDs: listIDs) : []
        )
    }

    @MainActor
    static func resolve(
        calendar: any CalendarServicing,
        reminders: any RemindersServicing,
        context: CreationProfileContext
    ) -> QuickEntryDestinationOptions {
        let calendarAccess = calendar.accessState
        let remindersAccess = reminders.accessState
        let allCalendars = calendarAccess == .granted ? calendar.calendars() : []
        let allLists = remindersAccess == .granted ? reminders.lists() : []
        let writableCalendars = SourceDescriptorOrdering.calendars(
            allCalendars.filter(\.allowsContentModifications)
        )
        let writableLists = SourceDescriptorOrdering.reminderLists(
            allLists.filter(\.allowsContentModifications)
        )
        let calendarIDs = Set(allCalendars.map(\.id))
        let listIDs = Set(allLists.map(\.id))
        let validCalendarDefault = context.defaultCalendarID.flatMap { id in
            context.memberCalendarIDs.contains(id)
                && writableCalendars.contains(where: { $0.id == id }) ? id : nil
        }
        let validListDefault = context.defaultReminderListID.flatMap { id in
            context.memberReminderListIDs.contains(id)
                && writableLists.contains(where: { $0.id == id }) ? id : nil
        }

        return .init(
            calendarAccess: calendarAccess,
            remindersAccess: remindersAccess,
            calendars: writableCalendars,
            reminderLists: writableLists,
            defaultCalendarID: validCalendarDefault,
            defaultReminderListID: validListDefault,
            visibleCalendarIDs: context.memberCalendarIDs.intersection(calendarIDs),
            visibleReminderListIDs: context.memberReminderListIDs.intersection(listIDs)
        )
    }
}

enum QuickEntryFailure: Equatable, Sendable {
    case validation
    case accessUnavailable
    case systemDefaultUnavailable
    case invalidDestination
    case explicitDestinationRequired
    case writeFailed
}

enum QuickEntryConfirmationState: Equatable, Sendable {
    case ready
    case failed(QuickEntryFailure)
}

enum QuickEntryPhase: Equatable, Sendable {
    case entry(parseError: QuickEntryParseError?)
    case confirmation(QuickEntryConfirmationState)
    case saving(QuickEntryKind)
    case committed(QuickEntrySaveOutcome)
}

enum QuickEntryDismissalDecision: Equatable, Sendable {
    case dismiss
    case confirmDiscard
    case blocked
}

enum QuickEntrySourceAction: Equatable, Sendable {
    case requestAccess
    case openSettings
    case none
}

enum QuickEntryCaptureSource: Equatable, Sendable {
    case inApp
    case shortcut
}

@MainActor
@Observable
final class QuickEntryViewModel {
    var text = ""
    var preview: QuickEntryPreview?
    private(set) var phase: QuickEntryPhase = .entry(parseError: nil)
    private(set) var destinations: QuickEntryDestinationOptions
    private(set) var categories: [CategorySnapshot]
    private(set) var transformationNotice: String?
    private(set) var recentEntries: [QuickEntryHistoryItem]
    let captureSource: QuickEntryCaptureSource

    @ObservationIgnored private let parser: any QuickEntryParsing
    @ObservationIgnored private let saver: any QuickEntrySaving
    @ObservationIgnored private let context: QuickEntryParseContext
    @ObservationIgnored private let creationProfile: CreationProfileContext?
    @ObservationIgnored private let historyStore: QuickEntryHistoryStore?
    @ObservationIgnored private let historyNow: @MainActor () -> Date
    @ObservationIgnored private let onCommitted: @MainActor (QuickEntrySaveOutcome) -> Void
    @ObservationIgnored private var didCommit = false
    @ObservationIgnored private var discardWasConfirmed = false
    @ObservationIgnored private var eventDestinationID: String?
    @ObservationIgnored private var taskDestinationID: String?
    @ObservationIgnored private var eventDestinationWasExplicitlySelected = false
    @ObservationIgnored private var taskDestinationWasExplicitlySelected = false

    init(
        parser: any QuickEntryParsing,
        saver: any QuickEntrySaving,
        context: QuickEntryParseContext,
        destinations: QuickEntryDestinationOptions = .empty,
        categories: [CategorySnapshot] = [],
        creationProfile: CreationProfileContext? = nil,
        historyStore: QuickEntryHistoryStore? = nil,
        historyNow: @escaping @MainActor () -> Date = Date.init,
        captureSource: QuickEntryCaptureSource = .inApp,
        onCommitted: @escaping @MainActor (QuickEntrySaveOutcome) -> Void = { _ in }
    ) {
        self.parser = parser
        self.saver = saver
        self.context = context
        self.destinations = destinations
        self.categories = categories.sorted { $0.sortOrder < $1.sortOrder }
        self.creationProfile = creationProfile
        self.historyStore = historyStore
        self.historyNow = historyNow
        if let creationProfile, let historyStore {
            recentEntries = historyStore.items(for: .saved(creationProfile.profileID))
        } else {
            recentEntries = []
        }
        self.captureSource = captureSource
        self.onCommitted = onCommitted
        eventDestinationID = destinations.defaultCalendarID
        taskDestinationID = destinations.defaultReminderListID
    }

    var canSave: Bool {
        guard case .confirmation = phase, let preview else { return false }
        return localFailure(for: preview) == nil
    }

    var errorMessage: String? {
        switch phase {
        case let .entry(parseError?): parseMessage(parseError)
        case let .confirmation(.failed(failure)): saveMessage(failure)
        case .entry(parseError: nil), .confirmation(.ready), .saving, .committed: nil
        }
    }

    var warningMessage: String? {
        guard let preview else { return nil }
        switch preview.kind {
        case .event:
            guard let start = preview.startDate, start < context.now else { return nil }
            return "This event is scheduled in the past."
        case .task:
            guard let due = preview.dueDate,
                  context.calendar.startOfDay(for: due) < context.calendar.startOfDay(for: context.now) else { return nil }
            return "This task is scheduled in the past."
        case .routine:
            guard let reminder = preview.reminderDate, reminder < context.now else { return nil }
            return "This routine reminder is scheduled in the past."
        }
    }

    var destinationVisibilityHint: String? {
        guard let preview, let id = preview.destinationID else { return nil }
        if let creationProfile {
            let isOutsideProfile = switch preview.kind {
            case .event: !creationProfile.memberCalendarIDs.contains(id)
            case .task: !creationProfile.memberReminderListIDs.contains(id)
            case .routine: false
            }
            return isOutsideProfile ? "Outside \(creationProfile.profileName)" : nil
        }
        switch preview.kind {
        case .event where !destinations.visibleCalendarIDs.contains(id):
            return "Items saved in this calendar may be hidden from combined views."
        case .task where !destinations.visibleReminderListIDs.contains(id):
            return "Items saved in this list may be hidden from combined views."
        case .event, .task, .routine:
            return nil
        }
    }

    var sourceAction: QuickEntrySourceAction {
        guard let preview else { return .none }
        return switch access(for: preview.kind) {
        case .notDetermined: .requestAccess
        case .denied: .openSettings
        case .granted, .restricted: .none
        }
    }

    func systemDefaultIsAvailable(for kind: QuickEntryKind) -> Bool {
        switch kind {
        case .event:
            guard !requiresExplicitDestination(for: kind) else { return false }
            return destinations.calendarAccess == .granted && !destinations.calendars.isEmpty
        case .task:
            guard !requiresExplicitDestination(for: kind) else { return false }
            return destinations.remindersAccess == .granted && !destinations.reminderLists.isEmpty
        case .routine:
            return false
        }
    }

    var sourceExplanation: String? {
        guard let preview, preview.kind != .routine else { return nil }
        let source = preview.kind == .event ? "Calendar" : "Reminders"
        let alternatives = preview.kind == .event ? "Task or Routine" : "Event or Routine"
        return switch access(for: preview.kind) {
        case .notDetermined: "Allow \(source) access to save this item."
        case .denied: "\(source) access is unavailable. Choose \(alternatives), or enable \(source) access in Settings."
        case .restricted: "\(source) access is restricted by your device or account. Choose \(alternatives)."
        case .granted where writableDestinations(for: preview.kind).isEmpty: "No writable \(source.lowercased()) destination is available."
        case .granted: nil
        }
    }

    var weekdayOrder: [Int] {
        let first = context.calendar.firstWeekday
        return (0..<7).map { ((first - 1 + $0) % 7) + 1 }
    }

    func weekdayName(_ weekday: Int) -> String {
        guard (1...7).contains(weekday) else { return "" }
        let formatter = DateFormatter()
        formatter.calendar = context.calendar
        formatter.locale = context.locale
        formatter.timeZone = context.timeZone
        return formatter.shortWeekdaySymbols[weekday - 1]
    }

    func parse() {
        guard case .entry = phase else { return }
        do {
            var parsed = try parser.parse(text, context: context)
            let parserSuppliedDestination = parsed.destinationID != nil
            eventDestinationID = destinations.defaultCalendarID
            taskDestinationID = destinations.defaultReminderListID
            eventDestinationWasExplicitlySelected = false
            taskDestinationWasExplicitlySelected = false
            let rememberedDestinationApplied = applyRememberedChoices(to: &parsed)
            switch parsed.kind {
            case .event:
                if !parserSuppliedDestination,
                   !rememberedDestinationApplied,
                   parsed.destinationID == nil {
                    parsed.destinationID = eventDestinationID
                }
                eventDestinationID = parsed.destinationID
                eventDestinationWasExplicitlySelected = rememberedDestinationApplied
            case .task:
                if !parserSuppliedDestination,
                   !rememberedDestinationApplied,
                   parsed.destinationID == nil {
                    parsed.destinationID = taskDestinationID
                }
                taskDestinationID = parsed.destinationID
                taskDestinationWasExplicitlySelected = rememberedDestinationApplied
            case .routine:
                parsed.destinationID = nil
            }
            preview = parsed
            transformationNotice = nil
            discardWasConfirmed = false
            phase = .confirmation(.ready)
        } catch let error as QuickEntryParseError {
            preview = nil
            transformationNotice = nil
            phase = .entry(parseError: error)
        } catch {
            preview = nil
            transformationNotice = nil
            phase = .entry(parseError: .ambiguousExpression)
        }
    }

    func returnToEntry() {
        guard case .confirmation = phase else { return }
        phase = .entry(parseError: nil)
    }

    func selectRecent(id: UUID) {
        guard case .entry = phase,
              let item = recentEntries.first(where: { $0.id == id }) else { return }
        text = item.text
        preview = nil
        transformationNotice = nil
        discardWasConfirmed = false
        phase = .entry(parseError: nil)
    }

    func clearRecent() {
        guard let creationProfile, let historyStore else { return }
        historyStore.clearHistory(for: .saved(creationProfile.profileID))
        recentEntries = historyStore.items(for: .saved(creationProfile.profileID))
    }

    func updateDestinationOptions(_ options: QuickEntryDestinationOptions) {
        guard !isTerminal else { return }
        destinations = options
        guard case .confirmation = phase, var updated = preview else { return }
        switch updated.kind {
        case .event:
            guard updated.destinationID == nil,
                  !eventDestinationWasExplicitlySelected,
                  options.calendarAccess == .granted,
                  let defaultID = options.defaultCalendarID,
                  options.calendars.contains(where: { $0.id == defaultID && $0.allowsContentModifications }) else { return }
            updated.destinationID = defaultID
            eventDestinationID = defaultID
        case .task:
            guard updated.destinationID == nil,
                  !taskDestinationWasExplicitlySelected,
                  options.remindersAccess == .granted,
                  let defaultID = options.defaultReminderListID,
                  options.reminderLists.contains(where: { $0.id == defaultID && $0.allowsContentModifications }) else { return }
            updated.destinationID = defaultID
            taskDestinationID = defaultID
        case .routine:
            return
        }
        preview = updated
    }

    func selectDestination(_ id: String?) {
        guard case .confirmation = phase, var updated = preview else { return }
        switch updated.kind {
        case .event:
            eventDestinationWasExplicitlySelected = true
            eventDestinationID = id
        case .task:
            taskDestinationWasExplicitlySelected = true
            taskDestinationID = id
        case .routine:
            return
        }
        updated.destinationID = id
        preview = updated
        phase = .confirmation(.ready)
        discardWasConfirmed = false
    }

    func setTaskDueEnabled(_ isEnabled: Bool) {
        mutatePreview { preview in
            guard preview.kind == .task else { return }
            if isEnabled {
                if preview.dueDate == nil {
                    preview.dueDate = nextWholeHour(after: context.now)
                    preview.dueHasTime = true
                }
            } else {
                preview.dueDate = nil
                preview.dueHasTime = false
                preview.recurrence = nil
            }
        }
    }

    func setReminderEnabled(_ isEnabled: Bool) {
        mutatePreview { preview in
            guard isEnabled else {
                preview.reminderDate = nil
                return
            }
            guard preview.reminderDate == nil else { return }
            switch preview.kind {
            case .event:
                preview.reminderDate = (preview.startDate ?? nextWholeHour(after: context.now)).addingTimeInterval(-600)
            case .task:
                preview.reminderDate = preview.dueDate ?? nextWholeHour(after: context.now)
            case .routine:
                preview.reminderDate = nextRoutineOccurrence(
                    days: validDays(preview.weekdays),
                    window: preview.routineWindow ?? .anytime
                )
            }
        }
    }

    func setRecurrenceEnabled(_ isEnabled: Bool) {
        mutatePreview { preview in
            guard preview.kind != .routine else { return }
            guard isEnabled else {
                preview.recurrence = nil
                return
            }
            if preview.kind == .task, preview.dueDate == nil {
                preview.dueDate = nextWholeHour(after: context.now)
                preview.dueHasTime = true
            }
            if preview.recurrence == nil {
                preview.recurrence = .init(frequency: .daily, interval: 1, weekdays: [], endDate: nil)
            }
        }
    }

    func setRecurrenceEndEnabled(_ isEnabled: Bool) {
        mutatePreview { preview in
            guard preview.kind != .routine else { return }
            if !isEnabled {
                preview.recurrence?.endDate = nil
                return
            }
            if preview.recurrence == nil {
                if preview.kind == .task, preview.dueDate == nil {
                    preview.dueDate = nextWholeHour(after: context.now)
                    preview.dueHasTime = true
                }
                preview.recurrence = .init(frequency: .daily, interval: 1, weekdays: [], endDate: nil)
            }
            guard preview.recurrence?.endDate == nil else { return }
            let start = preview.kind == .event
                ? preview.startDate ?? context.now
                : preview.dueDate ?? context.now
            preview.recurrence?.endDate = context.calendar.date(byAdding: .month, value: 1, to: start)
        }
    }

    func confirmSave() {
        guard case .confirmation = phase, let preview else { return }
        if let failure = localFailure(for: preview) {
            phase = .confirmation(.failed(failure))
            return
        }
        phase = .saving(preview.kind)
        do {
            let outcome = try saver.save(preview)
            phase = .committed(outcome)
            guard !didCommit else { return }
            didCommit = true
            rememberSuccessfulCommit(preview)
            onCommitted(outcome)
        } catch {
            phase = .confirmation(.failed(mappedFailure(error)))
        }
    }

    func selectKind(_ kind: QuickEntryKind) {
        guard case .confirmation = phase, var next = preview, next.kind != kind else { return }
        captureDestination(next.destinationID, for: next.kind)
        transformationNotice = nil
        switch (next.kind, kind) {
        case (.event, .task): eventToTask(&next)
        case (.event, .routine): eventToRoutine(&next)
        case (.task, .event): taskToEvent(&next)
        case (.task, .routine): taskToRoutine(&next)
        case (.routine, .event): routineToEvent(&next)
        case (.routine, .task): routineToTask(&next)
        case (.event, .event), (.task, .task), (.routine, .routine): break
        }
        next.kind = kind
        applyRememberedChoices(to: &next, destinationMayOverride: true)
        preview = next
        phase = .confirmation(.ready)
    }

    func requestDismissal() -> QuickEntryDismissalDecision {
        if case .saving = phase { return .blocked }
        if case .committed = phase { return .dismiss }
        if discardWasConfirmed { return .dismiss }
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || preview != nil {
            return .confirmDiscard
        }
        return .dismiss
    }

    func confirmDiscard() { discardWasConfirmed = true }

    private var isTerminal: Bool { if case .committed = phase { return true }; return false }

    @discardableResult
    private func applyRememberedChoices(
        to preview: inout QuickEntryPreview,
        destinationMayOverride: Bool = false
    ) -> Bool {
        guard let creationProfile,
              let choices = historyStore?.preference(
                  profileID: creationProfile.profileID,
                  kind: preview.kind
              ) else { return false }

        if let categoryID = choices.categoryID,
           categories.contains(where: { $0.id == categoryID }) {
            preview.categoryID = categoryID
        }

        if preview.kind == .event,
           !preview.isAllDay,
           let duration = choices.durationMinutes,
           (1...1_440).contains(duration),
           let start = preview.startDate,
           let end = context.calendar.date(byAdding: .minute, value: duration, to: start) {
            preview.endDate = end
        }

        guard (preview.destinationID == nil || destinationMayOverride),
              preview.kind != .routine else {
            return false
        }
        switch preview.kind {
        case .event:
            guard let destinationID = choices.destinationID else {
                guard !requiresExplicitDestination(for: .event) else {
                    return false
                }
                preview.destinationID = nil
                eventDestinationWasExplicitlySelected = true
                return true
            }
            guard creationProfile.memberCalendarIDs.contains(destinationID),
                  destinations.calendars.contains(where: {
                      $0.id == destinationID && $0.allowsContentModifications
                  }) else { return false }
            preview.destinationID = destinationID
            eventDestinationWasExplicitlySelected = true
            return true
        case .task:
            guard let destinationID = choices.destinationID else {
                guard !requiresExplicitDestination(for: .task) else {
                    return false
                }
                preview.destinationID = nil
                taskDestinationWasExplicitlySelected = true
                return true
            }
            guard creationProfile.memberReminderListIDs.contains(destinationID),
                  destinations.reminderLists.contains(where: {
                      $0.id == destinationID && $0.allowsContentModifications
                  }) else { return false }
            preview.destinationID = destinationID
            taskDestinationWasExplicitlySelected = true
            return true
        case .routine:
            return false
        }
    }

    private func rememberSuccessfulCommit(_ preview: QuickEntryPreview) {
        guard let creationProfile, let historyStore else { return }
        let profileIdentity = ProfileIdentity.saved(creationProfile.profileID)
        historyStore.record(
            text: text,
            profileIdentity: profileIdentity,
            at: historyNow()
        )

        let existingChoices = historyStore.preference(
            profileID: creationProfile.profileID,
            kind: preview.kind
        )
        let measuredDuration: Int? = if preview.kind == .event,
                                       !preview.isAllDay,
                                       let start = preview.startDate,
                                       let end = preview.endDate {
            validDurationMinutes(start: start, end: end)
        } else {
            nil
        }
        let durationMinutes = measuredDuration
            ?? (preview.kind == .event ? existingChoices?.durationMinutes : nil)
        historyStore.setPreference(
            QuickEntryRememberedChoices(
                durationMinutes: durationMinutes,
                categoryID: preview.categoryID,
                destinationID: rememberedDestination(
                    preview.destinationID,
                    kind: preview.kind,
                    profile: creationProfile
                )
            ),
            profileID: creationProfile.profileID,
            kind: preview.kind
        )
        recentEntries = historyStore.items(for: profileIdentity)
    }

    private func validDurationMinutes(start: Date, end: Date) -> Int? {
        let seconds = end.timeIntervalSince(start)
        guard seconds.isFinite, seconds > 0 else { return nil }
        let minutes = Int((seconds / 60).rounded())
        return (1...1_440).contains(minutes) ? minutes : nil
    }

    private func rememberedDestination(
        _ destinationID: String?,
        kind: QuickEntryKind,
        profile: CreationProfileContext
    ) -> String? {
        guard let destinationID else { return nil }
        switch kind {
        case .event:
            return profile.memberCalendarIDs.contains(destinationID)
                && destinations.calendars.contains(where: {
                    $0.id == destinationID && $0.allowsContentModifications
                }) ? destinationID : nil
        case .task:
            return profile.memberReminderListIDs.contains(destinationID)
                && destinations.reminderLists.contains(where: {
                    $0.id == destinationID && $0.allowsContentModifications
                }) ? destinationID : nil
        case .routine:
            return nil
        }
    }

    private func mutatePreview(_ mutation: (inout QuickEntryPreview) -> Void) {
        guard case .confirmation = phase, var updated = preview else { return }
        mutation(&updated)
        preview = updated
        phase = .confirmation(.ready)
        discardWasConfirmed = false
    }

    private func access(for kind: QuickEntryKind) -> AccessState {
        switch kind {
        case .event: destinations.calendarAccess
        case .task: destinations.remindersAccess
        case .routine: .granted
        }
    }

    private func writableDestinations(for kind: QuickEntryKind) -> [String] {
        switch kind {
        case .event: destinations.calendars.map(\.id)
        case .task: destinations.reminderLists.map(\.id)
        case .routine: []
        }
    }

    private func localFailure(for preview: QuickEntryPreview) -> QuickEntryFailure? {
        guard !preview.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .validation }
        switch preview.kind {
        case .event:
            guard destinations.calendarAccess == .granted else { return .accessUnavailable }
            if let id = preview.destinationID {
                guard destinations.calendars.contains(where: { $0.id == id }) else { return .invalidDestination }
            } else if requiresExplicitDestination(for: preview.kind) {
                return .explicitDestinationRequired
            } else if destinations.calendars.isEmpty { return .systemDefaultUnavailable }
            guard let start = preview.startDate, let end = preview.endDate,
                  start.timeIntervalSinceReferenceDate.isFinite,
                  end.timeIntervalSinceReferenceDate.isFinite, end > start else { return .validation }
            guard preview.reminderDate?.timeIntervalSinceReferenceDate.isFinite ?? true else { return .validation }
            if let recurrence = preview.recurrence {
                do { try EventKitRecurrenceMapper.validate(recurrence, startsAt: start) }
                catch { return .validation }
            }
        case .task:
            guard destinations.remindersAccess == .granted else { return .accessUnavailable }
            if let id = preview.destinationID {
                guard destinations.reminderLists.contains(where: { $0.id == id }) else { return .invalidDestination }
            } else if requiresExplicitDestination(for: preview.kind) {
                return .explicitDestinationRequired
            } else if destinations.reminderLists.isEmpty { return .systemDefaultUnavailable }
            guard !(preview.dueDate == nil && preview.dueHasTime),
                  preview.dueDate?.timeIntervalSinceReferenceDate.isFinite ?? true,
                  preview.reminderDate?.timeIntervalSinceReferenceDate.isFinite ?? true else { return .validation }
            if let recurrence = preview.recurrence {
                guard let due = preview.dueDate else { return .validation }
                do { try EventKitRecurrenceMapper.validate(recurrence, startsAt: due) }
                catch { return .validation }
            }
        case .routine:
            guard preview.routineWindow != nil,
                  !preview.weekdays.isEmpty,
                  preview.weekdays.allSatisfy({ (1...7).contains($0) }),
                  preview.reminderDate?.timeIntervalSinceReferenceDate.isFinite ?? true else { return .validation }
        }
        return nil
    }

    private func mappedFailure(_ error: Error) -> QuickEntryFailure {
        guard let error = error as? QuickEntrySaveError else { return .writeFailed }
        return switch error {
        case .invalidTitle, .invalidEventSchedule, .invalidTaskSchedule, .invalidRoutineSchedule, .invalidRecurrence, .unsupportedCategory:
            .validation
        case .accessUnavailable:
            .accessUnavailable
        case .systemDefaultUnavailable:
            .systemDefaultUnavailable
        case .destinationMissing, .destinationReadOnly:
            .invalidDestination
        case .explicitDestinationRequired:
            .explicitDestinationRequired
        }
    }

    private func requiresExplicitDestination(for kind: QuickEntryKind) -> Bool {
        guard let creationProfile else { return false }
        return switch kind {
        case .event:
            creationProfile.requiresExplicitCalendarDestination
                || destinations.defaultCalendarID == nil
        case .task:
            creationProfile.requiresExplicitReminderDestination
                || destinations.defaultReminderListID == nil
        case .routine:
            false
        }
    }

    private func parseMessage(_ error: QuickEntryParseError) -> String {
        switch error {
        case .emptyInput: "Enter something to add."
        case .noUsableTitle: "Add a title and try again."
        case .invalidClock: "Enter a valid time."
        case .invalidDate: "Check the date and try again."
        case .nonexistentLocalTime: "That local time does not exist. Choose another time."
        case .ambiguousExpression: "Use one clear date and time, then try again."
        }
    }

    private func saveMessage(_ failure: QuickEntryFailure) -> String {
        switch failure {
        case .validation: "Check the highlighted details and try again."
        case .accessUnavailable: sourceExplanation ?? "This source is unavailable."
        case .systemDefaultUnavailable: "No writable System Default destination is available. Choose another type or destination."
        case .invalidDestination: "The selected destination is no longer writable. Choose another destination."
        case .explicitDestinationRequired:
            preview?.kind == .event
                ? "Choose a calendar before saving."
                : "Choose a reminder list before saving."
        case .writeFailed:
            switch preview?.kind {
            case .event: "Your event was not saved. Edit it and try again."
            case .task: "Your task was not saved. Edit it and try again."
            case .routine: "Your routine was not saved. Edit it and try again."
            case nil: "Nothing was saved. Your edits are still here; try again."
            }
        }
    }

    private func captureDestination(_ id: String?, for kind: QuickEntryKind) {
        switch kind {
        case .event: eventDestinationID = id
        case .task: taskDestinationID = id
        case .routine: break
        }
    }

    private func eventToTask(_ preview: inout QuickEntryPreview) {
        preview.dueDate = preview.startDate
        preview.dueHasTime = !preview.isAllDay
        preview.startDate = nil
        preview.endDate = nil
        preview.isAllDay = false
        preview.routineWindow = nil
        preview.weekdays = []
        preview.destinationID = taskDestinationID
    }

    private func eventToRoutine(_ preview: inout QuickEntryPreview) {
        let start = preview.startDate ?? context.now
        let mapping = routineSchedule(recurrence: preview.recurrence, fallbackDate: start)
        preview.weekdays = mapping.days
        preview.routineWindow = preview.isAllDay ? .anytime : window(for: start)
        if mapping.transformed { transformationNotice = "This repeat pattern was converted to a weekday routine schedule." }
        preview.startDate = nil
        preview.endDate = nil
        preview.isAllDay = false
        preview.dueDate = nil
        preview.dueHasTime = false
        preview.recurrence = nil
        preview.destinationID = nil
    }

    private func taskToEvent(_ preview: inout QuickEntryPreview) {
        let start: Date
        let end: Date
        if let due = preview.dueDate, preview.dueHasTime {
            start = due
            end = due.addingTimeInterval(3_600)
            preview.isAllDay = false
        } else if let due = preview.dueDate {
            start = context.calendar.startOfDay(for: due)
            end = context.calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(3_600)
            preview.isAllDay = true
        } else {
            start = nextWholeHour(after: context.now)
            end = start.addingTimeInterval(3_600)
            preview.isAllDay = false
        }
        preview.startDate = start
        preview.endDate = end
        preview.dueDate = nil
        preview.dueHasTime = false
        preview.routineWindow = nil
        preview.weekdays = []
        preview.destinationID = eventDestinationID
    }

    private func taskToRoutine(_ preview: inout QuickEntryPreview) {
        let fallback = preview.dueDate
        let mapping = routineSchedule(recurrence: preview.recurrence, fallbackDate: fallback)
        preview.weekdays = mapping.days
        if let due = preview.dueDate, preview.dueHasTime { preview.routineWindow = window(for: due) }
        else { preview.routineWindow = .anytime }
        if mapping.transformed { transformationNotice = "This repeat pattern was converted to a weekday routine schedule." }
        preview.startDate = nil
        preview.endDate = nil
        preview.isAllDay = false
        preview.dueDate = nil
        preview.dueHasTime = false
        preview.recurrence = nil
        preview.destinationID = nil
    }

    private func routineToEvent(_ preview: inout QuickEntryPreview) {
        let days = validDays(preview.weekdays)
        let start = nextRoutineOccurrence(days: days, window: preview.routineWindow ?? .anytime)
        preview.startDate = start
        preview.endDate = start.addingTimeInterval(3_600)
        preview.isAllDay = false
        preview.dueDate = nil
        preview.dueHasTime = false
        preview.reminderDate = mappedReminder(preview.reminderDate, onto: start)
        preview.recurrence = canonicalRecurrence(days)
        preview.routineWindow = nil
        preview.weekdays = []
        preview.destinationID = eventDestinationID
    }

    private func routineToTask(_ preview: inout QuickEntryPreview) {
        let days = validDays(preview.weekdays)
        let window = preview.routineWindow ?? .anytime
        let day = nextEligibleDay(days: days)
        let due: Date
        if window == .anytime {
            due = day
            preview.dueHasTime = false
        } else {
            due = localTime(on: day, hour: window.anchorHour ?? 9, minute: 0) ?? day
            preview.dueHasTime = true
        }
        preview.dueDate = due
        preview.reminderDate = mappedReminder(preview.reminderDate, onto: day)
        preview.recurrence = canonicalRecurrence(days)
        preview.startDate = nil
        preview.endDate = nil
        preview.isAllDay = false
        preview.routineWindow = nil
        preview.weekdays = []
        preview.destinationID = taskDestinationID
    }

    private func routineSchedule(recurrence: RecurrenceRuleDraft?, fallbackDate: Date?) -> (days: Set<Int>, transformed: Bool) {
        guard let recurrence else {
            guard let fallbackDate else { return (Set(1...7), false) }
            return (Set([context.calendar.component(.weekday, from: fallbackDate)]), false)
        }
        let transformed = recurrence.interval != 1 || recurrence.endDate != nil || recurrence.frequency == .monthly || recurrence.frequency == .yearly
        switch recurrence.frequency {
        case .daily:
            return (Set(1...7), transformed)
        case .weekly:
            let fallbackDay = fallbackDate.map { context.calendar.component(.weekday, from: $0) }
            let days = recurrence.weekdays.isEmpty
                ? fallbackDay.map { Set([$0]) } ?? Set(1...7)
                : recurrence.weekdays
            return (days, transformed || recurrence.weekdays.isEmpty)
        case .monthly, .yearly:
            let day = fallbackDate.map { context.calendar.component(.weekday, from: $0) }
            return (day.map { Set([$0]) } ?? Set(1...7), true)
        }
    }

    private func window(for date: Date) -> RoutineWindow {
        switch context.calendar.component(.hour, from: date) {
        case 5...11: .morning
        case 12...16: .afternoon
        default: .evening
        }
    }

    private func validDays(_ days: Set<Int>) -> Set<Int> {
        let valid = days.filter { (1...7).contains($0) }
        return valid.isEmpty ? Set(1...7) : valid
    }

    private func canonicalRecurrence(_ days: Set<Int>) -> RecurrenceRuleDraft {
        days == Set(1...7)
            ? .init(frequency: .daily, interval: 1, weekdays: [], endDate: nil)
            : .init(frequency: .weekly, interval: 1, weekdays: days, endDate: nil)
    }

    private func nextWholeHour(after date: Date) -> Date {
        if let interval = context.calendar.dateInterval(of: .hour, for: date), interval.end > date { return interval.end }
        return context.calendar.date(byAdding: .hour, value: 1, to: date) ?? date.addingTimeInterval(3_600)
    }

    private func nextEligibleDay(days: Set<Int>) -> Date {
        let today = context.calendar.startOfDay(for: context.now)
        for offset in 0...7 {
            guard let day = context.calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            if days.contains(context.calendar.component(.weekday, from: day)) { return day }
        }
        return today
    }

    private func nextRoutineOccurrence(days: Set<Int>, window: RoutineWindow) -> Date {
        let today = context.calendar.startOfDay(for: context.now)
        let anytimeHour = context.calendar.component(.hour, from: nextWholeHour(after: context.now))
        for offset in 0...7 {
            guard let day = context.calendar.date(byAdding: .day, value: offset, to: today),
                  days.contains(context.calendar.component(.weekday, from: day)) else { continue }
            let candidate = localTime(on: day, hour: window.anchorHour ?? anytimeHour, minute: 0)
            if let candidate, candidate > context.now { return candidate }
        }
        return nextWholeHour(after: context.now)
    }

    private func mappedReminder(_ reminder: Date?, onto day: Date) -> Date? {
        guard let reminder else { return nil }
        let components = context.calendar.dateComponents([.hour, .minute], from: reminder)
        return localTime(on: day, hour: components.hour ?? 9, minute: components.minute ?? 0)
    }

    private func localTime(on day: Date, hour: Int, minute: Int) -> Date? {
        let dayParts = context.calendar.dateComponents([.year, .month, .day], from: day)
        guard let start = context.calendar.date(from: DateComponents(timeZone: context.timeZone, year: dayParts.year, month: dayParts.month, day: dayParts.day)) else { return nil }
        let wanted = DateComponents(timeZone: context.timeZone, hour: hour, minute: minute, second: 0)
        guard let candidate = context.calendar.nextDate(after: start.addingTimeInterval(-1), matching: wanted, matchingPolicy: .strict, repeatedTimePolicy: .first, direction: .forward) else { return nil }
        let actual = context.calendar.dateComponents([.year, .month, .day, .hour, .minute], from: candidate)
        guard actual.year == dayParts.year, actual.month == dayParts.month, actual.day == dayParts.day, actual.hour == hour, actual.minute == minute else { return nil }
        return candidate
    }
}
