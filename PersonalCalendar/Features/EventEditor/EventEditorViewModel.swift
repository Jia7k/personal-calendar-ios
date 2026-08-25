import Foundation
import Observation

enum EventEditorCommit: Equatable {
    case created(id: String?)
    case updated
    case deleted
}

enum EventEditorUnavailableReason: Equatable {
    case accessUnavailable
    case itemGone
    case readOnlySource
    case nonaddressable
    case immutable
}

enum EventEditorError: Equatable {
    case accessUnavailable
    case itemGone
    case immutable
    case invalidDestination
    case validationFailure
    case retryableWriteFailure
}

enum EventEditorAction: Equatable {
    case save
    case delete(scope: RecurrenceEditScope)
}

enum EventEditorPhase: Equatable {
    case idle
    case confirming(action: EventEditorAction)
    case writing(action: EventEditorAction)
    case failed(action: EventEditorAction, error: EventEditorError)
    case created(id: String?)
    case updated
    case deleted
    case unavailable(reason: EventEditorUnavailableReason)
}

@MainActor
@Observable
final class EventEditorViewModel {
    private enum Mode { case create, edit(displayID: String) }
    private enum PendingAction: Equatable {
        case save(scope: RecurrenceEditScope)
        case delete(scope: RecurrenceEditScope)

        var editorAction: EventEditorAction {
            switch self {
            case .save: .save
            case let .delete(scope): .delete(scope: scope)
            }
        }
    }
    private enum ErrorDisposition {
        case unavailable(EventEditorUnavailableReason)
        case failed(EventEditorError)
    }

    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool
    var notes: String?
    var location: String?
    var url: URL?
    var destinationCalendarID: String?
    var categoryID: UUID?
    var alarmIntent: EventAlarmMutationIntent = .preserve
    var recurrenceIntent: RecurrenceMutationIntent = .preserve {
        didSet { scopeExplanation = nil }
    }
    private(set) var alarmDisplay: String?
    private(set) var recurrenceDisplay: String?
    private(set) var currentCalendarID: String?
    private(set) var currentCalendarTitle: String?
    private(set) var alarmSnapshot: EventAlarmSnapshot = .none
    private(set) var recurrenceSnapshot: RecurrenceSnapshot = .none
    private(set) var availableCategories: [CategorySnapshot] = []
    private(set) var categoryWarning: String?
    private(set) var availableSaveScopes: [RecurrenceEditScope] = [.thisOccurrence]
    private(set) var scopeExplanation: String?
    private(set) var phase: EventEditorPhase = .idle
    /// Identifies the confirmation currently rendered by the presentation.
    /// A trailing dismissal write is authoritative only for this generation.
    private(set) var confirmationGeneration = 0

    var unavailableReason: EventEditorUnavailableReason? {
        guard case let .unavailable(reason) = phase else { return nil }
        return reason
    }

    /// A local, side-effect-free preflight for the Save control. Provider
    /// authority (the live item and destination) is deliberately rechecked
    /// only by the mutation path immediately before a write.
    var canSave: Bool {
        acceptsActions && formValidationError() == nil
    }

    /// The exact scope whose consent is currently being requested. Confirmation
    /// copy must read this value rather than an independently mutable Picker.
    var confirmationSaveScope: RecurrenceEditScope? {
        guard case .confirming(action: .save) = phase,
              case let .save(scope)? = pendingConfirmation else { return nil }
        return scope
    }

    var requiresDiscardConfirmation: Bool {
        guard !discardWasConfirmed else { return false }
        switch phase {
        case .created, .updated, .deleted:
            return false
        case .unavailable:
            return formState != cleanBaseline
        case .failed:
            return true
        case .idle, .confirming, .writing:
            return formState != cleanBaseline
        }
    }

    @ObservationIgnored private let mode: Mode
    @ObservationIgnored private let service: any CalendarServicing
    @ObservationIgnored private let categories: (any CategoryRepository)?
    @ObservationIgnored private let onCommitted: @MainActor (EventEditorCommit) -> Void
    @ObservationIgnored private let onReconciliationNeeded: @MainActor () -> Void
    @ObservationIgnored private var cleanBaseline: FormState
    @ObservationIgnored private var didLoad = false
    @ObservationIgnored private var didCommit = false
    @ObservationIgnored private var didRequestReconciliation = false
    @ObservationIgnored private var discardWasConfirmed = false
    /// Scope travels only with the pending or retry action that selected it. It is
    /// never a global editor setting, so a cancelled future action cannot widen a
    /// later "this event" attempt.
    @ObservationIgnored private var pendingConfirmation: PendingAction?
    @ObservationIgnored private var retryAction: PendingAction?

    private init(
        mode: Mode,
        service: any CalendarServicing,
        savedDefaultCalendarID: String? = nil,
        initialStart: Date,
        initialEnd: Date,
        initialIsAllDay: Bool,
        categories: (any CategoryRepository)?,
        onCommitted: @escaping @MainActor (EventEditorCommit) -> Void = { _ in },
        onReconciliationNeeded: @escaping @MainActor () -> Void = {}
    ) {
        self.mode = mode
        self.service = service
        self.categories = categories
        self.onCommitted = onCommitted
        self.onReconciliationNeeded = onReconciliationNeeded
        title = ""
        start = initialStart
        end = initialEnd
        isAllDay = initialIsAllDay
        notes = nil
        location = nil
        url = nil
        destinationCalendarID = nil
        categoryID = nil
        availableCategories = categories.flatMap { try? $0.list() } ?? []
        cleanBaseline = .empty(start: initialStart, end: initialEnd, isAllDay: initialIsAllDay)

        if case .create = mode {
            alarmIntent = .clear
            recurrenceIntent = .clear
            if service.accessState == .granted,
               let savedDefaultCalendarID,
               service.calendars().contains(where: { $0.id == savedDefaultCalendarID && $0.allowsContentModifications }) {
                destinationCalendarID = savedDefaultCalendarID
            }
        }
        cleanBaseline = formState
    }

    static func create(
        service: any CalendarServicing,
        savedDefaultCalendarID: String?,
        initialStart: Date = .now,
        initialEnd: Date? = nil,
        isAllDay: Bool = false,
        categories: (any CategoryRepository)? = nil,
        onCommitted: @escaping @MainActor (EventEditorCommit) -> Void = { _ in }
    ) -> EventEditorViewModel {
        EventEditorViewModel(
            mode: .create,
            service: service,
            savedDefaultCalendarID: savedDefaultCalendarID,
            initialStart: initialStart,
            initialEnd: initialEnd ?? initialStart.addingTimeInterval(3_600),
            initialIsAllDay: isAllDay,
            categories: categories,
            onCommitted: onCommitted
        )
    }

    static func edit(
        displayID: String,
        service: any CalendarServicing,
        categories: (any CategoryRepository)? = nil,
        onCommitted: @escaping @MainActor (EventEditorCommit) -> Void = { _ in },
        onReconciliationNeeded: @escaping @MainActor () -> Void = {}
    ) -> EventEditorViewModel {
        let initialStart = Date.now
        return EventEditorViewModel(
            mode: .edit(displayID: displayID),
            service: service,
            initialStart: initialStart,
            initialEnd: initialStart.addingTimeInterval(3_600),
            initialIsAllDay: false,
            categories: categories,
            onCommitted: onCommitted,
            onReconciliationNeeded: onReconciliationNeeded
        )
    }

    func load() async {
        guard case .edit = mode, !didLoad, phase == .idle else { return }
        didLoad = true
        guard service.accessState == .granted else {
            phase = .unavailable(reason: .accessUnavailable)
            return
        }
        guard case let .edit(displayID) = mode, let snapshot = service.event(id: displayID) else {
            becomeItemGone()
            return
        }

        applyReadable(snapshot)
        cleanBaseline = formState
        if snapshot.mutationID == nil {
            phase = .unavailable(reason: .nonaddressable)
        } else if !snapshot.allowsModification {
            phase = .unavailable(reason: .readOnlySource)
        }
    }

    func requestSave(scope requestedScope: RecurrenceEditScope = .thisOccurrence) async {
        guard acceptsActions else { return }
        scopeExplanation = nil

        switch mode {
        case .create:
            retryAction = .save(scope: .thisOccurrence)
            guard validateForm(), validateExplicitDestination() else { return }
            writeCreate()
        case .edit:
            guard let current = resolveCurrentForMutation() else { return }
            let scope = current.hasRecurrence ? requestedScope : .thisOccurrence
            let action = PendingAction.save(scope: scope)
            pendingConfirmation = nil
            retryAction = action
            reconcileScopeState(with: current)
            guard validateForm(), validateExplicitDestination() else { return }
            guard validateSaveScope(scope, current: current) else { return }
            if current.hasRecurrence {
                presentConfirmation(for: action)
            } else {
                writeUpdate(scope: scope, hasRecurringConsent: false)
            }
        }
    }

    func requestDelete(scope: RecurrenceEditScope) async {
        guard acceptsActions, case .edit = mode else { return }
        scopeExplanation = nil
        guard let current = resolveCurrentForMutation() else { return }
        let scope = current.hasRecurrence ? scope : .thisOccurrence
        let action = PendingAction.delete(scope: scope)
        pendingConfirmation = nil
        retryAction = action
        reconcileScopeState(with: current)
        guard validateDeleteScope(scope, current: current) else { return }
        presentConfirmation(for: action)
    }

    func confirm() {
        guard case let .confirming(action) = phase,
              let pendingConfirmation,
              pendingConfirmation.editorAction == action else { return }
        // Keep the confirmation state visible while rechecking authority. This
        // avoids exposing an actionable idle state between consent and the write.
        self.pendingConfirmation = nil
        switch pendingConfirmation {
        case let .save(scope):
            guard validateForm(), validateExplicitDestination(), let current = resolveCurrentForMutation() else { return }
            reconcileScopeState(with: current)
            let effectiveScope = current.hasRecurrence ? scope : .thisOccurrence
            retryAction = .save(scope: effectiveScope)
            guard validateSaveScope(effectiveScope, current: current) else { return }
            writeUpdate(scope: effectiveScope, hasRecurringConsent: true, current: current)
        case let .delete(scope):
            guard let current = resolveCurrentForMutation() else { return }
            reconcileScopeState(with: current)
            guard current.hasRecurrence || scope == .thisOccurrence else {
                // A live series may end while its confirmation is open. Replace
                // the stale future operation with a fresh, explicit this-event
                // confirmation without ever reopening an idle action window.
                let recoveredAction = PendingAction.delete(scope: .thisOccurrence)
                retryAction = recoveredAction
                presentConfirmation(for: recoveredAction)
                return
            }
            retryAction = .delete(scope: scope)
            guard validateDeleteScope(scope, current: current) else { return }
            writeDelete(scope: scope, current: current)
        }
    }

    func cancelConfirmation() {
        guard case .confirming = phase else { return }
        pendingConfirmation = nil
        retryAction = nil
        phase = .idle
    }

    /// SwiftUI writes `false` to the presentation binding for a passive system
    /// dismissal. An affirmative action leaves `confirming` synchronously, so
    /// the same write cannot cancel an operation that has already begun.
    func setConfirmationPresented(_ isPresented: Bool, generation: Int) {
        if !isPresented, generation == confirmationGeneration, case .confirming = phase { cancelConfirmation() }
    }

    func retry() async {
        guard case let .failed(action, error) = phase else { return }
        guard error != .itemGone, error != .accessUnavailable, error != .immutable else { return }
        guard let retryAction, retryAction.editorAction == action else { return }
        switch retryAction {
        case let .save(scope):
            await requestSave(scope: scope)
        case let .delete(scope):
            await requestDelete(scope: scope)
        }
    }

    func confirmDiscard() {
        discardWasConfirmed = true
    }

    private var acceptsActions: Bool {
        switch phase {
        case .idle, .failed: true
        case .confirming, .writing, .created, .updated, .deleted, .unavailable: false
        }
    }

    private func resolveCurrentForMutation() -> CalendarEventSnapshot? {
        guard service.accessState == .granted else {
            phase = .unavailable(reason: .accessUnavailable)
            return nil
        }
        guard case let .edit(displayID) = mode else { return nil }
        guard let snapshot = service.event(id: displayID) else {
            becomeItemGone()
            return nil
        }
        guard snapshot.mutationID != nil else {
            phase = .unavailable(reason: .nonaddressable)
            return nil
        }
        guard snapshot.allowsModification else {
            phase = .unavailable(reason: .readOnlySource)
            return nil
        }
        return snapshot
    }

    private func applyReadable(_ snapshot: CalendarEventSnapshot) {
        title = snapshot.title
        start = snapshot.start
        end = snapshot.end
        isAllDay = snapshot.isAllDay
        notes = snapshot.notes
        location = snapshot.location
        url = snapshot.url
        destinationCalendarID = nil
        currentCalendarID = snapshot.calendarID
        currentCalendarTitle = snapshot.calendarTitle
        alarmSnapshot = snapshot.alarms
        recurrenceSnapshot = snapshot.recurrence
        if let externalID = snapshot.mutationID {
            categoryID = try? categories?.category(for: .event, externalID: externalID)?.id
        }
        alarmIntent = .preserve
        recurrenceIntent = .preserve
        alarmDisplay = unsupportedAlarmSummary(snapshot.alarms)
        recurrenceDisplay = unsupportedRecurrenceSummary(snapshot.recurrence)
        pendingConfirmation = nil
        retryAction = nil
        reconcileScopeState(with: snapshot)
    }

    private func validateForm() -> Bool {
        guard let error = formValidationError() else { return true }
        handle(error, action: .save)
        return false
    }

    private func formValidationError() -> Error? {
        do {
            try EventDraftValidator.validate(materializedDraft())
            return nil
        } catch {
            return error
        }
    }

    private func validateExplicitDestination() -> Bool {
        guard service.accessState == .granted else {
            phase = .unavailable(reason: .accessUnavailable)
            return false
        }
        guard let destinationCalendarID else { return true }
        guard service.calendars().contains(where: { $0.id == destinationCalendarID && $0.allowsContentModifications }) else {
            phase = .failed(action: .save, error: .invalidDestination)
            return false
        }
        return true
    }

    private func validateSaveScope(_ scope: RecurrenceEditScope, current: CalendarEventSnapshot) -> Bool {
        if current.hasRecurrence, recurrenceIntent != .preserve, scope == .thisOccurrence {
            scopeExplanation = "Changes to repeat settings apply to this and future events."
            phase = .failed(action: .save, error: .validationFailure)
            return false
        }
        scopeExplanation = nil
        return true
    }

    private func validateDeleteScope(_ scope: RecurrenceEditScope, current: CalendarEventSnapshot) -> Bool {
        guard current.hasRecurrence || scope == .thisOccurrence else {
            phase = .failed(action: .delete(scope: scope), error: .validationFailure)
            return false
        }
        return true
    }

    private func writeCreate() {
        phase = .writing(action: .save)
        do {
            let identifier = try service.createEvent(materializedDraft())
            if let identifier { assignCategory(to: identifier) }
            phase = .created(id: identifier)
            commit(.created(id: identifier))
        } catch {
            handle(error, action: .save)
        }
    }

    private func writeUpdate(
        scope: RecurrenceEditScope,
        hasRecurringConsent: Bool,
        current suppliedCurrent: CalendarEventSnapshot? = nil
    ) {
        guard let current = suppliedCurrent ?? resolveCurrentForMutation() else { return }
        reconcileScopeState(with: current)
        let effectiveScope = current.hasRecurrence ? scope : .thisOccurrence
        retryAction = .save(scope: effectiveScope)
        guard validateSaveScope(effectiveScope, current: current), validateExplicitDestination() else { return }
        if current.hasRecurrence, !hasRecurringConsent {
            presentConfirmation(for: .save(scope: effectiveScope))
            return
        }
        phase = .writing(action: .save)
        do {
            try service.updateEvent(id: current.mutationID!, draft: materializedDraft(), scope: effectiveScope)
            assignCategory(to: current.mutationID!)
            phase = .updated
            commit(.updated)
        } catch {
            handle(error, action: .save)
        }
    }

    private func writeDelete(scope: RecurrenceEditScope, current suppliedCurrent: CalendarEventSnapshot? = nil) {
        guard let current = suppliedCurrent ?? resolveCurrentForMutation() else { return }
        reconcileScopeState(with: current)
        guard validateDeleteScope(scope, current: current) else { return }
        retryAction = .delete(scope: scope)
        phase = .writing(action: .delete(scope: scope))
        do {
            try service.deleteEvent(id: current.mutationID!, scope: scope)
            phase = .deleted
            commit(.deleted)
        } catch {
            handle(error, action: .delete(scope: scope))
        }
    }

    private func presentConfirmation(for action: PendingAction) {
        confirmationGeneration += 1
        pendingConfirmation = action
        phase = .confirming(action: action.editorAction)
    }

    private func materializedDraft() -> EventDraft {
        EventDraft(
            title: title,
            start: start,
            end: end,
            isAllDay: isAllDay,
            calendarID: destinationCalendarID,
            notes: notes,
            location: location,
            url: url,
            alarms: alarmIntent,
            recurrence: recurrenceIntent
        )
    }

    private func assignCategory(to externalID: String) {
        guard let categories else { return }
        do {
            try categories.assign(categoryID: categoryID, to: .event, externalID: externalID)
            categoryWarning = nil
        } catch {
            categoryWarning = "The item was saved, but its app color was not applied."
        }
    }

    private func handle(_ error: Error, action: EventEditorAction) {
        switch disposition(for: error) {
        case .unavailable(.itemGone):
            becomeItemGone()
        case let .unavailable(reason):
            phase = .unavailable(reason: reason)
        case let .failed(error):
            phase = .failed(action: action, error: error)
        }
    }

    private func disposition(for error: Error) -> ErrorDisposition {
        if let error = error as? EventKitMutationError {
            return switch error {
            case .accessUnavailable: .unavailable(.accessUnavailable)
            case .itemNotFound: .unavailable(.itemGone)
            case .itemReadOnly: .unavailable(.readOnlySource)
            case .defaultUnavailable, .destinationMissing, .destinationReadOnly: .failed(.invalidDestination)
            case .invalidDraft, .invalidRecurrence, .invalidRecurrenceScope: .failed(.validationFailure)
            case .saveFailed, .removeFailed: .failed(.retryableWriteFailure)
            }
        }
        if let error = error as? DraftValidationError {
            return switch error {
            case .itemNotFound: .unavailable(.itemGone)
            case .readOnlyDestination, .invalidDestination: .failed(.invalidDestination)
            case .emptyTitle, .invalidDateRange, .invalidRecurrence, .invalidRecurrenceScope, .recurringReminderRequiresDueDate: .failed(.validationFailure)
            }
        }
        return .failed(.retryableWriteFailure)
    }

    private func becomeItemGone() {
        pendingConfirmation = nil
        retryAction = nil
        phase = .unavailable(reason: .itemGone)
        guard !didRequestReconciliation else { return }
        didRequestReconciliation = true
        onReconciliationNeeded()
    }

    private func commit(_ result: EventEditorCommit) {
        guard !didCommit else { return }
        didCommit = true
        onCommitted(result)
    }

    private func unsupportedAlarmSummary(_ value: EventAlarmSnapshot) -> String? {
        if case let .unsupported(summary) = value { return summary }
        return nil
    }

    private func unsupportedRecurrenceSummary(_ value: RecurrenceSnapshot) -> String? {
        if case let .unsupported(summary) = value { return summary }
        return nil
    }

    private func reconcileScopeState(with snapshot: CalendarEventSnapshot) {
        availableSaveScopes = snapshot.hasRecurrence
            ? [.thisOccurrence, .futureOccurrences]
            : [.thisOccurrence]
        if !snapshot.hasRecurrence {
            scopeExplanation = nil
        }
    }

    private var formState: FormState {
        FormState(
            title: title,
            start: start,
            end: end,
            isAllDay: isAllDay,
            notes: notes,
            location: location,
            url: url,
            destinationCalendarID: destinationCalendarID,
            categoryID: categoryID,
            alarmIntent: alarmIntent,
            recurrenceIntent: recurrenceIntent
        )
    }
}

private struct FormState: Equatable {
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let notes: String?
    let location: String?
    let url: URL?
    let destinationCalendarID: String?
    let categoryID: UUID?
    let alarmIntent: EventAlarmMutationIntent
    let recurrenceIntent: RecurrenceMutationIntent

    static func empty(start: Date, end: Date, isAllDay: Bool) -> FormState {
        FormState(title: "", start: start, end: end, isAllDay: isAllDay, notes: nil, location: nil, url: nil, destinationCalendarID: nil, categoryID: nil, alarmIntent: .preserve, recurrenceIntent: .preserve)
    }
}
