import EventKit

/// Validates a complete value patch before asking the EventKit driver to mutate
/// a live object.  This keeps validation failures atomic and makes the policy
/// testable without an EventKit database.
@MainActor
final class SystemEventKitMutationBacking: EventKitMutationBacking {
    private let driver: any EventKitStoreDriving

    init(store: EKEventStore, driver: (any EventKitStoreDriving)? = nil) {
        self.driver = driver ?? SystemEventKitStoreDriver(store: store)
    }

    init(driver: any EventKitStoreDriving) {
        self.driver = driver
    }

    func createEvent(_ request: EventCreateRequest) throws -> String? {
        try requireEventAccess()
        try validate(request.draft)
        let destinationID = try driver.resolveEventDestination(request.destination)
        let handle = driver.newEvent()
        do { try handle.apply(.init(draft: request.draft, destinationID: destinationID)) }
        catch {
            handle.discardNewItem()
            throw mappedApplyError(error)
        }
        do { try handle.save(scope: .thisOccurrence, commit: true) }
        catch {
            handle.discardNewItem()
            throw mappedSaveError(error)
        }
        guard let identifier = handle.savedIdentifier,
              !identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return identifier
    }

    func updateEvent(id: String, request: EventUpdateRequest) throws {
        try updateEvent(id: id, occurrence: nil, request: request)
    }

    func updateEvent(
        id: String,
        occurrence: EventOccurrenceAddress?,
        request: EventUpdateRequest
    ) throws {
        try requireEventAccess()
        guard let handle = driver.event(id: id, occurrence: occurrence) else {
            throw EventKitMutationError.itemNotFound
        }
        guard handle.allowsModification else { throw EventKitMutationError.itemReadOnly }
        try validate(request.draft)
        try validateEventScope(handle: handle, request: request)
        let destinationID = try driver.resolveEventDestination(request.destination)
        do { try handle.apply(.init(draft: request.draft, destinationID: destinationID)) }
        catch {
            handle.reset()
            throw mappedApplyError(error)
        }
        do { try handle.save(scope: request.scope, commit: true) }
        catch {
            handle.reset()
            throw mappedSaveError(error)
        }
    }

    func removeEvent(id: String, span: RecurrenceEditScope) throws {
        try removeEvent(id: id, occurrence: nil, span: span)
    }

    func removeEvent(
        id: String,
        occurrence: EventOccurrenceAddress?,
        span: RecurrenceEditScope
    ) throws {
        try requireEventAccess()
        guard let handle = driver.event(id: id, occurrence: occurrence) else {
            throw EventKitMutationError.itemNotFound
        }
        guard handle.allowsModification else { throw EventKitMutationError.itemReadOnly }
        guard handle.hasRecurrence || span == .thisOccurrence else { throw EventKitMutationError.invalidRecurrenceScope }
        do { try handle.remove(scope: span, commit: true) }
        catch { throw EventKitMutationError.removeFailed }
    }

    func createReminder(_ request: ReminderCreateRequest) throws -> String? {
        try requireReminderAccess()
        if case .preserve = request.draft.schedule { throw EventKitMutationError.invalidDraft }
        try validate(request.draft, effectiveSchedule: scheduleForCreate(request.draft))
        let destinationID = try driver.resolveReminderDestination(request.destination)
        let handle = driver.newReminder()
        do { try handle.apply(.init(draft: request.draft, destinationID: destinationID, schedule: scheduleForCreate(request.draft))) }
        catch {
            handle.discardNewItem()
            throw mappedApplyError(error)
        }
        do { try handle.save(commit: true) }
        catch {
            handle.discardNewItem()
            throw mappedSaveError(error)
        }
        guard let identifier = handle.savedIdentifier,
              !identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return identifier
    }

    func updateReminder(id: String, request: ReminderUpdateRequest) throws {
        try requireReminderAccess()
        guard let handle = driver.reminder(id: id) else { throw EventKitMutationError.itemNotFound }
        guard handle.allowsModification else { throw EventKitMutationError.itemReadOnly }
        let schedule = try scheduleForUpdate(request.draft, currentDue: handle.currentSchedule, currentStart: handle.currentStartSchedule, hasRecurrence: handle.hasRecurrence)
        try validate(
            request.draft,
            effectiveSchedule: schedule,
            preservedDue: handle.currentSchedule,
            preservedStart: handle.currentStartSchedule
        )
        let destinationID = try driver.resolveReminderDestination(request.destination)
        do { try handle.apply(.init(draft: request.draft, destinationID: destinationID, schedule: schedule)) }
        catch {
            handle.reset()
            throw mappedApplyError(error)
        }
        do { try handle.save(commit: true) }
        catch {
            handle.reset()
            throw mappedSaveError(error)
        }
    }

    func removeReminder(id: String) throws {
        try requireReminderAccess()
        guard let handle = driver.reminder(id: id) else { throw EventKitMutationError.itemNotFound }
        guard handle.allowsModification else { throw EventKitMutationError.itemReadOnly }
        do { try handle.remove(commit: true) }
        catch { throw EventKitMutationError.removeFailed }
    }

    func setReminderCompleted(id: String, completed: Bool) throws {
        try requireReminderAccess()
        guard let handle = driver.reminder(id: id) else { throw EventKitMutationError.itemNotFound }
        guard handle.allowsModification else { throw EventKitMutationError.itemReadOnly }
        do { try handle.setCompleted(completed) }
        catch {
            handle.reset()
            throw mappedApplyError(error)
        }
        do { try handle.save(commit: true) }
        catch {
            handle.reset()
            throw mappedSaveError(error)
        }
    }

    private func requireEventAccess() throws { guard driver.eventAccessGranted() else { throw EventKitMutationError.accessUnavailable } }
    private func requireReminderAccess() throws { guard driver.reminderAccessGranted() else { throw EventKitMutationError.accessUnavailable } }

    private func validate(_ draft: EventDraft) throws {
        do {
            try EventDraftValidator.validate(draft)
            if case let .replace(offsets) = draft.alarms, !offsets.allSatisfy(\.isFinite) { throw EventKitMutationError.invalidDraft }
        } catch let error as DraftValidationError {
            if error == .invalidRecurrence { throw EventKitMutationError.invalidRecurrence }
            throw EventKitMutationError.invalidDraft
        } catch { throw EventKitMutationError.invalidDraft }
    }

    private func validate(
        _ draft: ReminderDraft,
        effectiveSchedule: PreparedReminderSchedule,
        preservedDue: ReminderScheduleValue? = nil,
        preservedStart: ReminderScheduleValue? = nil
    ) throws {
        do {
            guard !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw EventKitMutationError.invalidDraft
            }
            guard !draft.hasInvalidLegacyDueTimeWithoutDate else { throw EventKitMutationError.invalidDraft }
            guard (0...9).contains(draft.priority) else { throw EventKitMutationError.invalidDraft }
            try validateFiniteSchedule(effectiveSchedule, preservedDue: preservedDue, preservedStart: preservedStart)
            if case let .replace(alarmDate) = draft.alarm, !alarmDate.timeIntervalSinceReferenceDate.isFinite {
                throw EventKitMutationError.invalidDraft
            }
            if case let .replace(rule) = draft.recurrence {
                guard let date = dueDate(in: effectiveSchedule) ?? preservedDue?.date else { throw EventKitMutationError.invalidDraft }
                try EventKitRecurrenceMapper.validate(rule, startsAt: date)
            }
        } catch let error as DraftValidationError {
            if error == .invalidRecurrence { throw EventKitMutationError.invalidRecurrence }
            throw EventKitMutationError.invalidDraft
        } catch { throw EventKitMutationError.invalidDraft }
    }

    private func validateFiniteSchedule(
        _ schedule: PreparedReminderSchedule,
        preservedDue: ReminderScheduleValue?,
        preservedStart: ReminderScheduleValue?
    ) throws {
        let values: [ReminderScheduleValue]
        switch schedule {
        case .clear:
            values = []
        case .preserve:
            values = [preservedDue, preservedStart].compactMap { $0 }
        case let .replace(due, start):
            values = [due] + [start].compactMap { $0 }
        }
        guard values.allSatisfy({ $0.date.timeIntervalSinceReferenceDate.isFinite }) else {
            throw EventKitMutationError.invalidDraft
        }
    }

    private func validateEventScope(handle: any EventMutationHandling, request: EventUpdateRequest) throws {
        if handle.hasRecurrence {
            do { try request.draft.recurrence.validate(scope: request.scope) }
            catch { throw EventKitMutationError.invalidRecurrenceScope }
        } else {
            guard request.scope == .thisOccurrence else { throw EventKitMutationError.invalidRecurrenceScope }
        }
    }

    private func scheduleForCreate(_ draft: ReminderDraft) -> PreparedReminderSchedule {
        switch draft.schedule {
        case .preserve: return .preserve
        case .clear: return .clear
        case let .replace(value): return .replace(due: value, start: value)
        }
    }

    private func scheduleForUpdate(
        _ draft: ReminderDraft,
        currentDue: ReminderScheduleValue?,
        currentStart: ReminderScheduleValue?,
        hasRecurrence: Bool
    ) throws -> PreparedReminderSchedule {
        switch draft.schedule {
        case .preserve:
            if hasRecurrence, currentDue == nil, draft.recurrence == .preserve {
                throw EventKitMutationError.invalidDraft
            }
            return .preserve
        case .clear:
            if hasRecurrence, draft.recurrence == .preserve { throw EventKitMutationError.invalidDraft }
            if case .replace = draft.recurrence { throw EventKitMutationError.invalidDraft }
            return .clear
        case let .replace(value):
            guard value.date.timeIntervalSinceReferenceDate.isFinite else {
                throw EventKitMutationError.invalidDraft
            }
            // Keeping an unchanged due date must not overwrite a distinct start
            // date; moving the due date deliberately aligns both components.
            let start = sameGregorianMinute(currentDue, value) ? (currentStart ?? value) : value
            return .replace(due: value, start: start)
        }
    }

    private func dueDate(in schedule: PreparedReminderSchedule) -> Date? {
        switch schedule {
        case .preserve: return nil
        case .clear: return nil
        case let .replace(due, _): return due.date
        }
    }

    private func mappedSaveError(_ error: Error) -> EventKitMutationError {
        if let mutationError = error as? EventKitMutationError { return mutationError }
        return .saveFailed
    }

    private func mappedApplyError(_ error: Error) -> EventKitMutationError {
        if let mutationError = error as? EventKitMutationError { return mutationError }
        if let draftError = error as? DraftValidationError, draftError == .invalidRecurrence { return .invalidRecurrence }
        return .invalidDraft
    }

    private func sameGregorianMinute(_ lhs: ReminderScheduleValue?, _ rhs: ReminderScheduleValue) -> Bool {
        guard let lhs else { return false }
        guard lhs.date.timeIntervalSinceReferenceDate.isFinite,
              rhs.date.timeIntervalSinceReferenceDate.isFinite else { return false }
        guard lhs.hasTime == rhs.hasTime else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        let fields: Set<Calendar.Component> = lhs.hasTime || rhs.hasTime ? [.year, .month, .day, .hour, .minute] : [.year, .month, .day]
        return calendar.dateComponents(fields, from: lhs.date) == calendar.dateComponents(fields, from: rhs.date)
    }
}
