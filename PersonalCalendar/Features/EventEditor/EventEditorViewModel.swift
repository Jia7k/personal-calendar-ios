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

enum EventEditorSavePreflightIssue: Equatable {
    case titleRequired
    case datesOrAlertsInvalid
    case repeatInvalid
    case destinationRequired
    case detailsInvalid
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
    private enum Mode {
        case create
        case edit(displayID: String, occurrence: EventOccurrenceAddress?)
    }
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
    var start: Date {
        didSet {
            guard start != oldValue, !isApplyingReadableSnapshot else { return }
            guard start.timeIntervalSinceReferenceDate.isFinite,
                  oldValue.timeIntervalSinceReferenceDate.isFinite,
                  end.timeIntervalSinceReferenceDate.isFinite else { return }
            if isAllDay {
                guard end > oldValue else { return }
                let previousStart = calendar.startOfDay(for: oldValue)
                let previousEnd = calendar.startOfDay(for: end)
                let dayCount = max(1, calendar.dateComponents(
                    [.day],
                    from: previousStart,
                    to: previousEnd
                ).day ?? 1)
                guard let shiftedEnd = calendar.date(
                    byAdding: .day,
                    value: dayCount,
                    to: start
                ) else { return }
                end = shiftedEnd
            } else {
                let previousDuration = end.timeIntervalSince(oldValue)
                guard previousDuration > 0 else { return }
                end = start.addingTimeInterval(previousDuration)
            }
        }
    }
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
    private(set) var creationDestinationCalendarIDs: Set<String>?
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

    var canDuplicate: Bool {
        guard case .edit = mode,
              let currentCalendarID,
              duplicateDestinationCalendarIDs?.contains(currentCalendarID) == true,
              let loadedSnapshot,
              Self.supportsFaithfulDuplicate(loadedSnapshot) else { return false }
        switch phase {
        case .idle, .failed:
            return true
        case .confirming, .writing, .created, .updated, .deleted, .unavailable:
            return false
        }
    }

    /// A local, side-effect-free preflight for the Save control. Provider
    /// authority (the live item and destination) is deliberately rechecked
    /// only by the mutation path immediately before a write.
    var canSave: Bool {
        acceptsActions && savePreflightIssue == nil
    }

    /// Describes only local, side-effect-free save eligibility. Provider
    /// authority remains exclusively owned by the mutation path.
    var savePreflightIssue: EventEditorSavePreflightIssue? {
        guard acceptsActions else { return nil }
        guard hasRequiredCreationDestination,
              hasLocallyAllowedCreationDestination else {
            return .destinationRequired
        }
        guard let error = formValidationError() else { return nil }
        return switch error as? DraftValidationError {
        case .some(.emptyTitle): .titleRequired
        case .some(.invalidDateRange): .datesOrAlertsInvalid
        case .some(.invalidRecurrence): .repeatInvalid
        case .none, .some(.readOnlyDestination), .some(.itemNotFound),
             .some(.invalidDestination), .some(.invalidRecurrenceScope),
             .some(.recurringReminderRequiresDueDate):
            .detailsInvalid
        }
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
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let categories: (any CategoryRepository)?
    @ObservationIgnored private let requiresExplicitCreationDestination: Bool
    @ObservationIgnored private let onCommitted: @MainActor (EventEditorCommit) -> Void
    @ObservationIgnored private let onReconciliationNeeded: @MainActor () -> Void
    @ObservationIgnored private let resolveCreationDestinationCalendarIDs: (@MainActor () throws -> Set<String>)?
    @ObservationIgnored private let duplicateDestinationCalendarIDs: Set<String>?
    @ObservationIgnored private let resolveDuplicateDestinationCalendarIDs: (@MainActor () throws -> Set<String>)?
    @ObservationIgnored private var cleanBaseline: FormState
    @ObservationIgnored private var didLoad = false
    @ObservationIgnored private var isApplyingReadableSnapshot = false
    @ObservationIgnored private var loadedSnapshot: CalendarEventSnapshot?
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
        calendar: Calendar,
        savedDefaultCalendarID: String? = nil,
        requiresExplicitCreationDestination: Bool = false,
        initialStart: Date,
        initialEnd: Date,
        initialIsAllDay: Bool,
        categories: (any CategoryRepository)?,
        creationDestinationCalendarIDs: Set<String>? = nil,
        resolveCreationDestinationCalendarIDs: (@MainActor () throws -> Set<String>)? = nil,
        duplicateDestinationCalendarIDs: Set<String>? = nil,
        resolveDuplicateDestinationCalendarIDs: (@MainActor () throws -> Set<String>)? = nil,
        onCommitted: @escaping @MainActor (EventEditorCommit) -> Void = { _ in },
        onReconciliationNeeded: @escaping @MainActor () -> Void = {}
    ) {
        self.mode = mode
        self.service = service
        self.calendar = calendar
        self.categories = categories
        self.creationDestinationCalendarIDs = creationDestinationCalendarIDs
        self.resolveCreationDestinationCalendarIDs = resolveCreationDestinationCalendarIDs
        self.duplicateDestinationCalendarIDs = duplicateDestinationCalendarIDs
        self.resolveDuplicateDestinationCalendarIDs = resolveDuplicateDestinationCalendarIDs
        self.requiresExplicitCreationDestination = requiresExplicitCreationDestination
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
        calendar: Calendar = .current,
        creationProfile: CreationProfileContext? = nil,
        initialDraft: EventDraft? = nil,
        initialCategoryID: UUID? = nil,
        creationDestinationCalendarIDs: Set<String>? = nil,
        resolveCreationDestinationCalendarIDs: (@MainActor () throws -> Set<String>)? = nil,
        initialStart: Date = .now,
        initialEnd: Date? = nil,
        isAllDay: Bool = false,
        categories: (any CategoryRepository)? = nil,
        onCommitted: @escaping @MainActor (EventEditorCommit) -> Void = { _ in }
    ) -> EventEditorViewModel {
        let preferredDefaultCalendarID: String?
        if let creationProfile {
            preferredDefaultCalendarID = creationProfile.defaultCalendarID
        } else {
            preferredDefaultCalendarID = savedDefaultCalendarID
        }

        let allowedCalendarIDs = creationDestinationCalendarIDs
            ?? creationProfile?.memberCalendarIDs
        let seededStart = initialDraft?.start ?? initialStart
        let seededEnd = initialDraft?.end
            ?? initialEnd
            ?? seededStart.addingTimeInterval(3_600)
        let model = EventEditorViewModel(
            mode: .create,
            service: service,
            calendar: calendar,
            savedDefaultCalendarID: preferredDefaultCalendarID,
            requiresExplicitCreationDestination: initialDraft != nil
                || creationProfile?.requiresExplicitCalendarDestination == true,
            initialStart: seededStart,
            initialEnd: seededEnd,
            initialIsAllDay: initialDraft?.isAllDay ?? isAllDay,
            categories: categories,
            creationDestinationCalendarIDs: allowedCalendarIDs,
            resolveCreationDestinationCalendarIDs: resolveCreationDestinationCalendarIDs,
            onCommitted: onCommitted
        )

        if let initialDraft {
            model.title = initialDraft.title
            model.start = initialDraft.start
            model.end = initialDraft.end
            model.isAllDay = initialDraft.isAllDay
            model.notes = initialDraft.notes
            model.location = initialDraft.location
            model.url = initialDraft.url
            model.alarmIntent = initialDraft.alarms
            model.recurrenceIntent = initialDraft.recurrence
            model.destinationCalendarID = Self.validCreationCalendarID(
                initialDraft.calendarID,
                service: service,
                allowedCalendarIDs: allowedCalendarIDs
            )
            if let initialCategoryID,
               model.availableCategories.contains(where: { $0.id == initialCategoryID }) {
                model.categoryID = initialCategoryID
            }
            model.cleanBaseline = model.formState
        }
        return model
    }

    static func duplicateDraft(
        from snapshot: CalendarEventSnapshot,
        confirmedStart: Date,
        destinationCalendarID: String?,
        calendar: Calendar = .current
    ) -> EventDraft {
        precondition(
            supportsFaithfulDuplicate(snapshot),
            "Unsupported provider metadata must not be silently discarded."
        )
        let copiedStart: Date
        let copiedEnd: Date
        if snapshot.isAllDay {
            let sourceStart = calendar.startOfDay(for: snapshot.start)
            let sourceEnd = calendar.startOfDay(for: snapshot.end)
            let dayCount = max(
                1,
                calendar.dateComponents(
                    [.day],
                    from: sourceStart,
                    to: sourceEnd
                ).day ?? 1
            )
            copiedStart = calendar.startOfDay(for: confirmedStart)
            copiedEnd = calendar.date(
                byAdding: .day,
                value: dayCount,
                to: copiedStart
            ) ?? copiedStart.addingTimeInterval(TimeInterval(dayCount * 86_400))
        } else {
            let duration = max(0, snapshot.end.timeIntervalSince(snapshot.start))
            copiedStart = confirmedStart
            copiedEnd = confirmedStart.addingTimeInterval(duration)
        }
        return EventDraft(
            title: snapshot.title,
            start: copiedStart,
            end: copiedEnd,
            isAllDay: snapshot.isAllDay,
            calendarID: destinationCalendarID,
            notes: snapshot.notes,
            location: snapshot.location,
            url: snapshot.url,
            alarms: duplicateAlarmIntent(snapshot.alarms),
            recurrence: duplicateRecurrenceIntent(
                snapshot.recurrence,
                sourceStart: snapshot.start,
                confirmedStart: copiedStart,
                calendar: calendar
            )
        )
    }

    func makeDuplicate(
        confirmedStart: Date,
        onCommitted duplicateCommitted: @escaping @MainActor (EventEditorCommit) -> Void
    ) -> EventEditorViewModel? {
        guard canDuplicate,
              service.accessState == .granted,
              case let .edit(displayID, occurrence) = mode,
              let snapshot = service.event(
                  id: displayID,
                  occurrence: occurrence
              ),
              snapshot.allowsModification,
              snapshot.mutationID != nil,
              Self.supportsFaithfulDuplicate(snapshot),
              service.calendars().contains(where: {
                  $0.id == snapshot.calendarID && $0.allowsContentModifications
              }) else {
            return nil
        }
        let allowedCalendarIDs: Set<String>?
        do {
            allowedCalendarIDs = try liveDuplicateDestinationCalendarIDs()
        } catch {
            return nil
        }
        guard allowedCalendarIDs?.contains(snapshot.calendarID) ?? true else {
            return nil
        }

        let copiedCategoryID: UUID?
        do {
            if let categories, let externalID = snapshot.mutationID {
                _ = try categories.list()
                copiedCategoryID = try categories.category(
                    for: .event,
                    externalID: externalID
                )?.id
            } else {
                copiedCategoryID = nil
            }
        } catch {
            return nil
        }
        return Self.create(
            service: service,
            savedDefaultCalendarID: nil,
            initialDraft: Self.duplicateDraft(
                from: snapshot,
                confirmedStart: confirmedStart,
                destinationCalendarID: snapshot.calendarID
            ),
            initialCategoryID: copiedCategoryID,
            creationDestinationCalendarIDs: allowedCalendarIDs,
            resolveCreationDestinationCalendarIDs:
                resolveDuplicateDestinationCalendarIDs,
            categories: categories,
            onCommitted: duplicateCommitted
        )
    }

    func finishDuplicateCommit(_ commit: EventEditorCommit) {
        onCommitted(commit)
    }

    private static func validCreationCalendarID(
        _ id: String?,
        service: any CalendarServicing,
        allowedCalendarIDs: Set<String>?
    ) -> String? {
        guard let id,
              service.accessState == .granted,
              service.calendars().contains(where: {
                  $0.id == id && $0.allowsContentModifications
              }),
              allowedCalendarIDs?.contains(id) ?? true else {
            return nil
        }
        return id
    }

    private static func duplicateAlarmIntent(
        _ snapshot: EventAlarmSnapshot
    ) -> EventAlarmMutationIntent {
        switch snapshot {
        case .none, .unsupported:
            return .clear
        case let .editable(offsets):
            return .replace(offsets)
        }
    }

    private static func duplicateRecurrenceIntent(
        _ snapshot: RecurrenceSnapshot,
        sourceStart: Date,
        confirmedStart: Date,
        calendar: Calendar
    ) -> RecurrenceMutationIntent {
        switch snapshot {
        case .none, .unsupported:
            return .clear
        case .editable(var rule):
            if let endDate = rule.endDate {
                let sourceDay = calendar.startOfDay(for: sourceStart)
                let confirmedDay = calendar.startOfDay(for: confirmedStart)
                let dayDelta = calendar.dateComponents(
                    [.day],
                    from: sourceDay,
                    to: confirmedDay
                ).day ?? 0
                rule.endDate = calendar.date(
                    byAdding: .day,
                    value: dayDelta,
                    to: endDate
                )
            }
            return .replace(rule)
        }
    }

    private static func supportsFaithfulDuplicate(
        _ snapshot: CalendarEventSnapshot
    ) -> Bool {
        if case .unsupported = snapshot.alarms { return false }
        if case .unsupported = snapshot.recurrence { return false }
        return true
    }

    static func edit(
        displayID: String,
        occurrence: EventOccurrenceAddress? = nil,
        service: any CalendarServicing,
        calendar: Calendar = .current,
        categories: (any CategoryRepository)? = nil,
        duplicateDestinationCalendarIDs: Set<String>? = nil,
        resolveDuplicateDestinationCalendarIDs: (@MainActor () throws -> Set<String>)? = nil,
        onCommitted: @escaping @MainActor (EventEditorCommit) -> Void = { _ in },
        onReconciliationNeeded: @escaping @MainActor () -> Void = {}
    ) -> EventEditorViewModel {
        let initialStart = Date.now
        return EventEditorViewModel(
            mode: .edit(
                displayID: displayID,
                occurrence: occurrence
            ),
            service: service,
            calendar: calendar,
            initialStart: initialStart,
            initialEnd: initialStart.addingTimeInterval(3_600),
            initialIsAllDay: false,
            categories: categories,
            duplicateDestinationCalendarIDs: duplicateDestinationCalendarIDs,
            resolveDuplicateDestinationCalendarIDs:
                resolveDuplicateDestinationCalendarIDs,
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
        guard case let .edit(displayID, occurrence) = mode,
              let snapshot = service.event(
                  id: displayID,
                  occurrence: occurrence
              ) else {
            becomeItemGone()
            return
        }

        loadedSnapshot = snapshot
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

    private var hasRequiredCreationDestination: Bool {
        guard case .create = mode, requiresExplicitCreationDestination else { return true }
        return destinationCalendarID != nil
    }

    private var hasLocallyAllowedCreationDestination: Bool {
        guard case .create = mode,
              let creationDestinationCalendarIDs,
              let destinationCalendarID else { return true }
        return creationDestinationCalendarIDs.contains(destinationCalendarID)
    }

    private func liveDuplicateDestinationCalendarIDs() throws -> Set<String>? {
        if let resolveDuplicateDestinationCalendarIDs {
            return try resolveDuplicateDestinationCalendarIDs()
        }
        return duplicateDestinationCalendarIDs
    }

    private func resolveCurrentForMutation() -> CalendarEventSnapshot? {
        guard service.accessState == .granted else {
            phase = .unavailable(reason: .accessUnavailable)
            return nil
        }
        guard case let .edit(displayID, occurrence) = mode else {
            return nil
        }
        guard let snapshot = service.event(
            id: displayID,
            occurrence: occurrence
        ) else {
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
        loadedSnapshot = snapshot
        return snapshot
    }

    private func applyReadable(_ snapshot: CalendarEventSnapshot) {
        isApplyingReadableSnapshot = true
        defer { isApplyingReadableSnapshot = false }
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
        if case .create = mode,
           requiresExplicitCreationDestination,
           destinationCalendarID == nil {
            phase = .failed(action: .save, error: .invalidDestination)
            return false
        }
        guard let destinationCalendarID else { return true }
        guard service.calendars().contains(where: { $0.id == destinationCalendarID && $0.allowsContentModifications }) else {
            phase = .failed(action: .save, error: .invalidDestination)
            return false
        }
        if case .create = mode,
           let creationDestinationCalendarIDs,
           !creationDestinationCalendarIDs.contains(destinationCalendarID) {
            phase = .failed(action: .save, error: .invalidDestination)
            return false
        }
        if case .create = mode,
           let resolveCreationDestinationCalendarIDs {
            do {
                guard try resolveCreationDestinationCalendarIDs()
                    .contains(destinationCalendarID) else {
                    phase = .failed(action: .save, error: .invalidDestination)
                    return false
                }
            } catch {
                phase = .failed(action: .save, error: .invalidDestination)
                return false
            }
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
            try service.updateEvent(
                id: current.mutationID!,
                occurrence: editOccurrence,
                draft: materializedDraft(),
                scope: effectiveScope
            )
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
            try service.deleteEvent(
                id: current.mutationID!,
                occurrence: editOccurrence,
                scope: scope
            )
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

    private var editOccurrence: EventOccurrenceAddress? {
        guard case let .edit(_, occurrence) = mode else { return nil }
        return occurrence
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
        loadedSnapshot = nil
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
