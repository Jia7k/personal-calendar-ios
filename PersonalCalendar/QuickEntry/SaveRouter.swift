import Foundation

enum QuickEntrySaveOutcome: Equatable, Sendable {
    case event(id: String?)
    case task(id: String?)
    case routine(id: UUID)
}

struct QuickEntryRefreshSignal: Equatable, Sendable {
    let id: UUID
    let outcome: QuickEntrySaveOutcome
}

enum QuickEntrySaveError: Error, Equatable, Sendable {
    case invalidTitle
    case invalidEventSchedule
    case invalidTaskSchedule
    case invalidRoutineSchedule
    case invalidRecurrence
    case unsupportedCategory
    case accessUnavailable
    case systemDefaultUnavailable
    case destinationMissing
    case destinationReadOnly
}

@MainActor
protocol QuickEntrySaving {
    func save(_ preview: QuickEntryPreview) throws -> QuickEntrySaveOutcome
}

@MainActor
struct SaveRouter: QuickEntrySaving {
    private let calendar: any CalendarServicing
    private let reminders: any RemindersServicing
    private let routines: any RoutineRepository
    private let categories: (any CategoryRepository)?
    private let localCalendar: Calendar

    init(
        calendar: any CalendarServicing,
        reminders: any RemindersServicing,
        routines: any RoutineRepository,
        categories: (any CategoryRepository)? = nil,
        localCalendar: Calendar
    ) {
        self.calendar = calendar
        self.reminders = reminders
        self.routines = routines
        self.categories = categories
        self.localCalendar = localCalendar
    }

    func save(_ preview: QuickEntryPreview) throws -> QuickEntrySaveOutcome {
        try validateCommonFields(in: preview)

        switch preview.kind {
        case .event:
            let draft = try eventDraft(from: preview)
            try validateEventAuthority(destinationID: draft.calendarID)
            let id = try calendar.createEvent(draft)
            assign(preview.categoryID, to: .event, externalID: id)
            return .event(id: id)

        case .task:
            let draft = try reminderDraft(from: preview)
            try validateTaskAuthority(destinationID: draft.listID)
            let id = try reminders.createReminder(draft)
            assign(preview.categoryID, to: .task, externalID: id)
            return .task(id: id)

        case .routine:
            let draft = try routineDraft(from: preview)
            return .routine(id: try routines.create(draft))
        }
    }

    private func validateCommonFields(in preview: QuickEntryPreview) throws {
        guard !preview.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw QuickEntrySaveError.invalidTitle
        }
    }

    private func eventDraft(from preview: QuickEntryPreview) throws -> EventDraft {
        guard let start = preview.startDate,
              let end = preview.endDate,
              start.timeIntervalSinceReferenceDate.isFinite,
              end.timeIntervalSinceReferenceDate.isFinite,
              end > start else {
            throw QuickEntrySaveError.invalidEventSchedule
        }

        let alarms: EventAlarmMutationIntent
        if let reminderDate = preview.reminderDate {
            let offset = reminderDate.timeIntervalSince(start)
            guard reminderDate.timeIntervalSinceReferenceDate.isFinite,
                  offset.isFinite else {
                throw QuickEntrySaveError.invalidEventSchedule
            }
            alarms = .replace([offset])
        } else {
            alarms = .clear
        }

        let recurrence = try recurrenceIntent(
            from: preview.recurrence,
            startsAt: start
        )
        let draft = EventDraft(
            title: preview.title,
            start: start,
            end: end,
            isAllDay: preview.isAllDay,
            calendarID: preview.destinationID,
            alarms: alarms,
            recurrence: recurrence
        )

        do {
            try EventDraftValidator.validate(draft)
        } catch DraftValidationError.invalidRecurrence {
            throw QuickEntrySaveError.invalidRecurrence
        } catch {
            throw QuickEntrySaveError.invalidEventSchedule
        }
        return draft
    }

    private func reminderDraft(from preview: QuickEntryPreview) throws -> ReminderDraft {
        if preview.dueHasTime, preview.dueDate == nil {
            throw QuickEntrySaveError.invalidTaskSchedule
        }
        if let dueDate = preview.dueDate,
           !dueDate.timeIntervalSinceReferenceDate.isFinite {
            throw QuickEntrySaveError.invalidTaskSchedule
        }
        if let reminderDate = preview.reminderDate,
           !reminderDate.timeIntervalSinceReferenceDate.isFinite {
            throw QuickEntrySaveError.invalidTaskSchedule
        }
        if preview.recurrence != nil, preview.dueDate == nil {
            throw QuickEntrySaveError.invalidTaskSchedule
        }

        let recurrence = try recurrenceIntent(
            from: preview.recurrence,
            startsAt: preview.dueDate
        )
        let draft = ReminderDraft(
            title: preview.title,
            notes: nil,
            dueDate: preview.dueDate,
            dueHasTime: preview.dueHasTime,
            priority: 0,
            listID: preview.destinationID,
            alarm: preview.reminderDate.map(ReminderAlarmMutationIntent.replace) ?? .clear,
            recurrence: recurrence
        )

        do {
            try ReminderDraftValidator.validate(draft)
        } catch DraftValidationError.invalidRecurrence {
            throw QuickEntrySaveError.invalidRecurrence
        } catch {
            throw QuickEntrySaveError.invalidTaskSchedule
        }
        return draft
    }

    private func routineDraft(from preview: QuickEntryPreview) throws -> RoutineDraft {
        guard let window = preview.routineWindow,
              !preview.weekdays.isEmpty,
              preview.weekdays.allSatisfy({ (1...7).contains($0) }) else {
            throw QuickEntrySaveError.invalidRoutineSchedule
        }

        _ = try recurrenceIntent(from: preview.recurrence, startsAt: nil)

        let reminderComponents: (hour: Int?, minute: Int?)
        if let reminderDate = preview.reminderDate {
            guard reminderDate.timeIntervalSinceReferenceDate.isFinite else {
                throw QuickEntrySaveError.invalidRoutineSchedule
            }
            let components = localCalendar.dateComponents([.hour, .minute], from: reminderDate)
            guard let hour = components.hour,
                  let minute = components.minute,
                  (0...23).contains(hour),
                  (0...59).contains(minute) else {
                throw QuickEntrySaveError.invalidRoutineSchedule
            }
            reminderComponents = (hour, minute)
        } else {
            reminderComponents = (nil, nil)
        }

        return RoutineDraft(
            title: preview.title.trimmingCharacters(in: .whitespacesAndNewlines),
            weekdays: preview.weekdays,
            window: window,
            reminderHour: reminderComponents.hour,
            reminderMinute: reminderComponents.minute,
            categoryID: preview.categoryID
        )
    }

    private func assign(
        _ categoryID: UUID?,
        to source: ExternalItemSource,
        externalID: String?
    ) {
        guard let categories,
              let externalID,
              !externalID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        try? categories.assign(categoryID: categoryID, to: source, externalID: externalID)
    }

    private func recurrenceIntent(
        from recurrence: RecurrenceRuleDraft?,
        startsAt: Date?
    ) throws -> RecurrenceMutationIntent {
        guard let recurrence else { return .clear }
        do {
            try EventKitRecurrenceMapper.validate(recurrence, startsAt: startsAt)
        } catch {
            throw QuickEntrySaveError.invalidRecurrence
        }
        return .replace(recurrence)
    }

    private func validateEventAuthority(destinationID: String?) throws {
        guard calendar.accessState == .granted else {
            throw QuickEntrySaveError.accessUnavailable
        }
        let descriptors = calendar.calendars()
        try validateDestination(
            id: destinationID,
            matching: descriptors.map { ($0.id, $0.allowsContentModifications) }
        )
    }

    private func validateTaskAuthority(destinationID: String?) throws {
        guard reminders.accessState == .granted else {
            throw QuickEntrySaveError.accessUnavailable
        }
        let descriptors = reminders.lists()
        try validateDestination(
            id: destinationID,
            matching: descriptors.map { ($0.id, $0.allowsContentModifications) }
        )
    }

    private func validateDestination(
        id: String?,
        matching descriptors: [(id: String, isWritable: Bool)]
    ) throws {
        guard let id else {
            guard descriptors.contains(where: { $0.isWritable }) else {
                throw QuickEntrySaveError.systemDefaultUnavailable
            }
            return
        }

        let matches = descriptors.filter { $0.id == id }
        guard !matches.isEmpty else {
            throw QuickEntrySaveError.destinationMissing
        }
        guard matches.contains(where: { $0.isWritable }) else {
            throw QuickEntrySaveError.destinationReadOnly
        }
    }
}
