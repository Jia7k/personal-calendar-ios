import Foundation
import Observation

enum TaskEditorAction: Equatable, Sendable { case save, delete }
enum TaskEditorFailure: Equatable, Sendable { case validation, invalidDestination, retryableWrite }
enum TaskEditorUnavailableReason: Equatable, Sendable { case accessUnavailable, itemGone, readOnlySource }
enum TaskEditorCommit: Equatable, Sendable { case created(id: String?), updated, deleted }
enum TaskEditorDismissalDecision: Equatable, Sendable { case dismiss, confirmDiscard }
enum TaskEditorDestinationSelection: Equatable, Sendable { case nilDestination, explicit(id: String) }
enum TaskEditorDestination: Equatable, Sendable {
    case systemDefault
    case preserveCurrent(id: String, title: String)
    case explicit(id: String, title: String)
}

enum TaskEditorSavePreflightIssue: Equatable, Sendable {
    case titleRequired
    case dueDatePriorityOrAlertInvalid
    case repeatRequiresDueDate
    case repeatInvalid
    case destinationRequired
    case detailsInvalid
}

enum TaskEditorPhase: Equatable, Sendable {
    case idle
    case confirming(TaskEditorAction)
    case writing(TaskEditorAction)
    case failed(TaskEditorAction, TaskEditorFailure)
    case created(id: String?)
    case updated
    case deleted
    case unavailable(TaskEditorUnavailableReason)
}

@MainActor
@Observable
final class TaskEditorViewModel {
    var form: ReminderDraft
    var categoryID: UUID?
    private(set) var destination: TaskEditorDestination
    private(set) var phase: TaskEditorPhase = .idle
    private(set) var providerAlarmSnapshot: ReminderAlarmSnapshot?
    private(set) var providerRecurrenceSnapshot: RecurrenceSnapshot?
    private(set) var providerAlarmSummary: String?
    private(set) var providerRecurrenceSummary: String?
    private(set) var mutationExplanation: String?
    private(set) var availableCategories: [CategorySnapshot] = []
    private(set) var categoryWarning: String?
    private(set) var creationDestinationListIDs: Set<String>?
    /// Identifies the rendered delete confirmation. Passive dismissal is valid
    /// only for the generation that produced the presentation.
    private(set) var deleteConfirmationGeneration = 0

    var recurrenceScopeOptions: [RecurrenceEditScope]? { nil }
    var recurringDetailExplanation: String? {
        currentSnapshot?.hasRecurrence == true
            ? "Only the current incomplete reminder occurrence is shown. Completing it may reveal the next occurrence supplied by Apple Reminders."
            : nil
    }
    var recurringDeleteExplanation: String? {
        currentSnapshot?.hasRecurrence == true ? "Deleting this task removes the repeating reminder." : nil
    }
    var schedulingSnapshot: ReminderSnapshot? { currentSnapshot }
    var canDuplicate: Bool {
        guard case .edit = mode,
              let currentSnapshot,
              currentSnapshot.allowsModification,
              duplicateDestinationListIDs?.contains(currentSnapshot.listID) == true,
              Self.supportsFaithfulDuplicate(currentSnapshot) else { return false }
        switch phase {
        case .idle, .failed:
            return true
        case .confirming, .writing, .created, .updated, .deleted, .unavailable:
            return false
        }
    }
    var canRetry: Bool {
        if case .failed = phase { return true }
        return false
    }
    /// A local, side-effect-free preflight for the Save control. The write path
    /// still reacquires the provider item and destination immediately before it
    /// mutates either one.
    var canSave: Bool {
        acceptsNewAction && savePreflightIssue == nil
    }

    /// Describes only local, side-effect-free save eligibility. Provider
    /// authority remains exclusively owned by the mutation path.
    var savePreflightIssue: TaskEditorSavePreflightIssue? {
        guard acceptsNewAction else { return nil }
        guard hasRequiredCreationDestination,
              hasLocallyAllowedCreationDestination else {
            return .destinationRequired
        }
        guard let error = formValidationError() else { return nil }
        return switch error as? DraftValidationError {
        case .some(.emptyTitle): .titleRequired
        case .some(.invalidDateRange): .dueDatePriorityOrAlertInvalid
        case .some(.recurringReminderRequiresDueDate): .repeatRequiresDueDate
        case .some(.invalidRecurrence): .repeatInvalid
        case .none, .some(.readOnlyDestination), .some(.itemNotFound),
             .some(.invalidDestination), .some(.invalidRecurrenceScope):
            .detailsInvalid
        }
    }
    var requiresDiscardConfirmation: Bool {
        guard !discardWasConfirmed else { return false }
        switch phase {
        case .created, .updated, .deleted: return false
        case .idle, .confirming, .writing, .failed, .unavailable: break
        }
        if case .failed = phase { return true }
        return form != initialForm || categoryID != initialCategoryID
    }

    private enum Mode { case create, edit(reminderID: String) }

    private let mode: Mode
    private let service: any RemindersServicing
    private let categories: (any CategoryRepository)?
    private let requiresExplicitCreationDestination: Bool
    private let onCommitted: (TaskEditorCommit) -> Void
    private let onReconciliationNeeded: () -> Void
    private let initialForm: ReminderDraft
    private let initialCategoryID: UUID?
    private let nilDestination: TaskEditorDestination
    private let resolveCreationDestinationListIDs: (@MainActor () throws -> Set<String>)?
    private let duplicateDestinationListIDs: Set<String>?
    private let resolveDuplicateDestinationListIDs: (@MainActor () throws -> Set<String>)?
    private var didCommit = false
    private var didRequestReconciliation = false
    private var discardWasConfirmed = false
    private var currentSnapshot: ReminderSnapshot?
    private var deleteConsentedHasRecurrence: Bool?

    private init(
        mode: Mode,
        form: ReminderDraft,
        destination: TaskEditorDestination,
        snapshot: ReminderSnapshot?,
        service: any RemindersServicing,
        categories: (any CategoryRepository)?,
        requiresExplicitCreationDestination: Bool = false,
        creationDestinationListIDs: Set<String>? = nil,
        resolveCreationDestinationListIDs: (@MainActor () throws -> Set<String>)? = nil,
        duplicateDestinationListIDs: Set<String>? = nil,
        resolveDuplicateDestinationListIDs: (@MainActor () throws -> Set<String>)? = nil,
        onCommitted: @escaping (TaskEditorCommit) -> Void,
        onReconciliationNeeded: @escaping () -> Void,
        initialCategoryID: UUID? = nil
    ) {
        self.mode = mode
        self.form = form
        self.destination = destination
        self.currentSnapshot = snapshot
        self.service = service
        self.categories = categories
        self.requiresExplicitCreationDestination = requiresExplicitCreationDestination
        self.creationDestinationListIDs = creationDestinationListIDs
        self.resolveCreationDestinationListIDs = resolveCreationDestinationListIDs
        self.duplicateDestinationListIDs = duplicateDestinationListIDs
        self.resolveDuplicateDestinationListIDs = resolveDuplicateDestinationListIDs
        self.onCommitted = onCommitted
        self.onReconciliationNeeded = onReconciliationNeeded
        self.initialForm = form
        availableCategories = categories.flatMap { try? $0.list() } ?? []
        let loadedCategoryID = snapshot.flatMap {
            try? categories?.category(for: .task, externalID: $0.id)?.id
        } ?? initialCategoryID
        categoryID = loadedCategoryID
        self.initialCategoryID = loadedCategoryID
        self.nilDestination = switch mode {
        case .create: .systemDefault
        case .edit: snapshot.map { .preserveCurrent(id: $0.listID, title: $0.listTitle) } ?? destination
        }
        providerAlarmSnapshot = snapshot?.alarm
        providerRecurrenceSnapshot = snapshot?.recurrence
        if case let .unsupported(summary) = snapshot?.alarm { providerAlarmSummary = summary }
        if case let .unsupported(summary) = snapshot?.recurrence { providerRecurrenceSummary = summary }
    }

    static func creating(
        service: any RemindersServicing,
        savedDefaultListID: String? = nil,
        creationProfile: CreationProfileContext? = nil,
        initialDraft: ReminderDraft? = nil,
        initialCategoryID: UUID? = nil,
        creationDestinationListIDs: Set<String>? = nil,
        resolveCreationDestinationListIDs: (@MainActor () throws -> Set<String>)? = nil,
        categories: (any CategoryRepository)? = nil,
        onCommitted: @escaping (TaskEditorCommit) -> Void = { _ in }
    ) -> TaskEditorViewModel {
        let preferredDefaultListID: String?
        if let creationProfile {
            preferredDefaultListID = creationProfile.defaultReminderListID
        } else {
            preferredDefaultListID = savedDefaultListID
        }
        let allowedListIDs = creationDestinationListIDs
            ?? creationProfile?.memberReminderListIDs
        let selected = service.accessState == .granted
            ? service.lists().first {
                $0.id == preferredDefaultListID
                    && $0.allowsContentModifications
                    && (allowedListIDs?.contains($0.id) ?? true)
            }
            : nil
        var seededForm = initialDraft
            ?? .init(
                title: "",
                notes: nil,
                dueDate: nil,
                priority: 0,
                listID: selected?.id
            )
        if initialDraft != nil {
            seededForm.listID = validCreationListID(
                seededForm.listID,
                service: service,
                allowedListIDs: allowedListIDs
            )
        }
        let seededDestination = service.lists().first {
            $0.id == seededForm.listID && $0.allowsContentModifications
        }
        return .init(
            mode: .create,
            form: seededForm,
            destination: seededDestination.map {
                .explicit(id: $0.id, title: $0.title)
            } ?? .systemDefault,
            snapshot: nil,
            service: service,
            categories: categories,
            requiresExplicitCreationDestination: initialDraft != nil
                || creationProfile?.requiresExplicitReminderDestination == true,
            creationDestinationListIDs: allowedListIDs,
            resolveCreationDestinationListIDs: resolveCreationDestinationListIDs,
            onCommitted: onCommitted,
            onReconciliationNeeded: {},
            initialCategoryID: initialCategoryID
        )
    }

    static func duplicateDraft(
        from snapshot: ReminderSnapshot,
        destinationListID: String,
        creationProfile: CreationProfileContext,
        availableLists: [ReminderListDescriptor]
    ) -> ReminderDraft? {
        guard creationProfile.memberReminderListIDs.contains(destinationListID),
              supportsFaithfulDuplicate(snapshot),
              availableLists.contains(where: {
                  $0.id == destinationListID && $0.allowsContentModifications
              }) else {
            return nil
        }

        return ReminderDraft(
            title: snapshot.title,
            notes: snapshot.notes,
            dueDate: snapshot.dueDate,
            dueHasTime: snapshot.dueHasTime,
            priority: snapshot.priority,
            listID: destinationListID,
            alarm: duplicateAlarmIntent(snapshot.alarm),
            recurrence: duplicateRecurrenceIntent(snapshot.recurrence)
        )
    }

    func makeDuplicate(
        onCommitted duplicateCommitted: @escaping (TaskEditorCommit) -> Void
    ) -> TaskEditorViewModel? {
        guard canDuplicate,
              service.accessState == .granted,
              case let .edit(reminderID) = mode,
              let snapshot = service.reminder(id: reminderID),
              snapshot.allowsModification,
              Self.supportsFaithfulDuplicate(snapshot),
              service.lists().contains(where: {
                  $0.id == snapshot.listID && $0.allowsContentModifications
              }) else {
            return nil
        }
        let allowedListIDs: Set<String>?
        do {
            allowedListIDs = try liveDuplicateDestinationListIDs()
        } catch {
            return nil
        }
        guard allowedListIDs?.contains(snapshot.listID) ?? true else {
            return nil
        }

        let draft = ReminderDraft(
            title: snapshot.title,
            notes: snapshot.notes,
            dueDate: snapshot.dueDate,
            dueHasTime: snapshot.dueHasTime,
            priority: snapshot.priority,
            listID: snapshot.listID,
            alarm: Self.duplicateAlarmIntent(snapshot.alarm),
            recurrence: Self.duplicateRecurrenceIntent(snapshot.recurrence)
        )
        let copiedCategoryID: UUID?
        do {
            if let categories {
                _ = try categories.list()
                copiedCategoryID = try categories.category(
                    for: .task,
                    externalID: snapshot.id
                )?.id
            } else {
                copiedCategoryID = nil
            }
        } catch {
            return nil
        }
        return Self.creating(
            service: service,
            initialDraft: draft,
            initialCategoryID: copiedCategoryID,
            creationDestinationListIDs: allowedListIDs,
            resolveCreationDestinationListIDs: resolveDuplicateDestinationListIDs,
            categories: categories,
            onCommitted: duplicateCommitted
        )
    }

    func finishDuplicateCommit(_ commit: TaskEditorCommit) {
        onCommitted(commit)
    }

    private static func validCreationListID(
        _ id: String?,
        service: any RemindersServicing,
        allowedListIDs: Set<String>?
    ) -> String? {
        guard let id,
              service.accessState == .granted,
              service.lists().contains(where: {
                  $0.id == id && $0.allowsContentModifications
              }),
              allowedListIDs?.contains(id) ?? true else {
            return nil
        }
        return id
    }

    private static func duplicateAlarmIntent(
        _ snapshot: ReminderAlarmSnapshot
    ) -> ReminderAlarmMutationIntent {
        switch snapshot {
        case .none, .unsupported:
            .clear
        case let .editable(date):
            .replace(date)
        }
    }

    private static func duplicateRecurrenceIntent(
        _ snapshot: RecurrenceSnapshot
    ) -> RecurrenceMutationIntent {
        switch snapshot {
        case .none, .unsupported:
            .clear
        case let .editable(rule):
            .replace(rule)
        }
    }

    private static func supportsFaithfulDuplicate(
        _ snapshot: ReminderSnapshot
    ) -> Bool {
        if case .unsupported = snapshot.alarm { return false }
        if case .unsupported = snapshot.recurrence { return false }
        return true
    }

    static func editing(
        reminderID: String,
        service: any RemindersServicing,
        categories: (any CategoryRepository)? = nil,
        duplicateDestinationListIDs: Set<String>? = nil,
        resolveDuplicateDestinationListIDs: (@MainActor () throws -> Set<String>)? = nil,
        onCommitted: @escaping (TaskEditorCommit) -> Void = { _ in },
        onReconciliationNeeded: @escaping () -> Void = {}
    ) -> TaskEditorViewModel {
        let snapshot = service.accessState == .granted ? service.reminder(id: reminderID) : nil
        var form = ReminderDraft(
            title: snapshot?.title ?? "",
            notes: snapshot?.notes,
            dueDate: nil,
            priority: snapshot?.priority ?? 0,
            listID: nil,
            alarm: .preserve,
            recurrence: .preserve
        )
        form.schedule = .preserve(current: snapshot.flatMap { item in
            item.dueDate.map { .init(date: $0, hasTime: item.dueHasTime) }
        })
        let destination: TaskEditorDestination = snapshot.map { .preserveCurrent(id: $0.listID, title: $0.listTitle) } ?? .systemDefault
        let model = TaskEditorViewModel(
            mode: .edit(reminderID: reminderID),
            form: form,
            destination: destination,
            snapshot: snapshot,
            service: service,
            categories: categories,
            duplicateDestinationListIDs: duplicateDestinationListIDs,
            resolveDuplicateDestinationListIDs: resolveDuplicateDestinationListIDs,
            onCommitted: onCommitted,
            onReconciliationNeeded: onReconciliationNeeded
        )
        if service.accessState != .granted { model.becomeUnavailable(.accessUnavailable) }
        else if snapshot == nil { model.becomeUnavailable(.itemGone) }
        else if snapshot?.allowsModification == false { model.becomeUnavailable(.readOnlySource) }
        return model
    }

    func selectDestination(_ selection: TaskEditorDestinationSelection) {
        guard acceptsNewAction else { return }
        switch selection {
        case .nilDestination:
            form.listID = nil
            destination = nilDestination
        case let .explicit(id):
            guard creationDestinationListIDs?.contains(id) ?? true,
                  let descriptor = service.lists().first(where: { $0.id == id }) else { return }
            form.listID = descriptor.id
            destination = .explicit(id: descriptor.id, title: descriptor.title)
        }
    }

    func requestDismissal() -> TaskEditorDismissalDecision {
        requiresDiscardConfirmation ? .confirmDiscard : .dismiss
    }

    func confirmDiscard() -> TaskEditorDismissalDecision {
        discardWasConfirmed = true
        return .dismiss
    }

    func requestSave() async {
        guard acceptsNewAction else { return }
        performSave()
    }

    func requestDelete() {
        guard acceptsNewAction, case .edit = mode else { return }
        guard let current = resolveEditableReminder() else { return }
        presentDeleteConfirmation(consentingTo: current.hasRecurrence)
    }

    func cancelConfirmation() {
        guard case .confirming = phase else { return }
        deleteConsentedHasRecurrence = nil
        phase = .idle
    }

    /// Handles passive dismissal of the system confirmation presentation.
    /// Confirmed operations leave `confirming` synchronously and are therefore
    /// immune to the presentation's trailing `false` write.
    func setDeleteConfirmationPresented(_ isPresented: Bool, generation: Int) {
        if !isPresented, generation == deleteConfirmationGeneration, case .confirming(.delete) = phase { cancelConfirmation() }
    }

    func confirm() {
        guard case .confirming(.delete) = phase,
              let consentedHasRecurrence = deleteConsentedHasRecurrence,
              let current = resolveEditableReminder() else { return }
        guard current.hasRecurrence == consentedHasRecurrence else {
            presentDeleteConfirmation(consentingTo: current.hasRecurrence)
            return
        }
        deleteConsentedHasRecurrence = nil
        performDelete(current: current)
    }

    func retry() async {
        guard case let .failed(action, _) = phase else { return }
        switch action {
        case .save: performSave()
        case .delete:
            guard let current = resolveEditableReminder() else { return }
            presentDeleteConfirmation(consentingTo: current.hasRecurrence)
        }
    }

    private var acceptsNewAction: Bool {
        switch phase {
        case .idle: true
        case .failed: true
        case .confirming, .writing, .created, .updated, .deleted, .unavailable: false
        }
    }

    private var hasRequiredCreationDestination: Bool {
        guard case .create = mode, requiresExplicitCreationDestination else { return true }
        return form.listID != nil
    }

    private var hasLocallyAllowedCreationDestination: Bool {
        guard case .create = mode,
              let creationDestinationListIDs,
              let listID = form.listID else { return true }
        return creationDestinationListIDs.contains(listID)
    }

    private func liveDuplicateDestinationListIDs() throws -> Set<String>? {
        if let resolveDuplicateDestinationListIDs {
            return try resolveDuplicateDestinationListIDs()
        }
        return duplicateDestinationListIDs
    }

    private func performSave() {
        guard acceptsNewAction else { return }
        guard service.accessState == .granted else { becomeUnavailable(.accessUnavailable); return }
        switch mode {
        case .create:
            guard validateForm(), validateExplicitDestination() else { return }
            phase = .writing(.save)
            do {
                let identifier = try service.createReminder(form)
                if let identifier { assignCategory(to: identifier) }
                phase = .created(id: identifier)
                commit(.created(id: identifier))
            } catch {
                handleWriteError(error, action: .save)
            }
        case let .edit(reminderID):
            guard resolveEditableReminder() != nil else { return }
            guard validateForm(), validateExplicitDestination() else { return }
            // Reacquire once more immediately before the synchronous provider
            // write, then revalidate every authority derived from that snapshot.
            guard resolveEditableReminder() != nil else { return }
            guard validateForm(), validateExplicitDestination() else { return }
            phase = .writing(.save)
            do {
                try service.updateReminder(id: reminderID, draft: form)
                assignCategory(to: reminderID)
                phase = .updated
                commit(.updated)
            } catch {
                handleWriteError(error, action: .save)
            }
        }
    }

    private func performDelete(current: ReminderSnapshot) {
        guard case let .edit(reminderID) = mode else { return }
        guard service.accessState == .granted else { becomeUnavailable(.accessUnavailable); return }
        do {
            guard let finalCurrent = resolveEditableReminder() else { return }
            guard finalCurrent.hasRecurrence == current.hasRecurrence else {
                presentDeleteConfirmation(consentingTo: finalCurrent.hasRecurrence)
                return
            }
            phase = .writing(.delete)
            try service.deleteReminder(id: reminderID)
            phase = .deleted
            commit(.deleted)
        } catch {
            handleWriteError(error, action: .delete)
        }
    }

    private func resolveEditableReminder() -> ReminderSnapshot? {
        guard service.accessState == .granted else { becomeUnavailable(.accessUnavailable); return nil }
        guard case let .edit(reminderID) = mode else { return currentSnapshot }
        guard let snapshot = service.reminder(id: reminderID) else { becomeUnavailable(.itemGone); return nil }
        currentSnapshot = snapshot
        guard snapshot.allowsModification else { becomeUnavailable(.readOnlySource); return nil }
        return snapshot
    }

    private func presentDeleteConfirmation(consentingTo hasRecurrence: Bool) {
        deleteConfirmationGeneration += 1
        deleteConsentedHasRecurrence = hasRecurrence
        phase = .confirming(.delete)
    }

    private func validateForm() -> Bool {
        guard formValidationError() == nil else {
            phase = .failed(.save, .validation)
            return false
        }
        return true
    }

    private func formValidationError() -> Error? {
        do {
            var validationDraft = form
            if case .preserve = form.schedule {
                validationDraft.schedule = currentSnapshot?.dueDate.map {
                    .replace(.init(date: $0, hasTime: currentSnapshot?.dueHasTime ?? false))
                } ?? .clear
            }
            let hasEffectiveRecurrence: Bool = switch form.recurrence {
            case .preserve: currentSnapshot?.hasRecurrence == true
            case .clear: false
            case .replace: true
            }
            if hasEffectiveRecurrence, validationDraft.dueDate == nil {
                throw DraftValidationError.recurringReminderRequiresDueDate
            }
            try ReminderDraftValidator.validate(validationDraft)
            return nil
        } catch {
            return error
        }
    }

    private func validateExplicitDestination() -> Bool {
        if case .create = mode,
           requiresExplicitCreationDestination,
           form.listID == nil {
            phase = .failed(.save, .invalidDestination)
            return false
        }
        guard let id = form.listID else { return true }
        guard service.lists().contains(where: { $0.id == id && $0.allowsContentModifications }) else {
            phase = .failed(.save, .invalidDestination)
            return false
        }
        if case .create = mode,
           let creationDestinationListIDs,
           !creationDestinationListIDs.contains(id) {
            phase = .failed(.save, .invalidDestination)
            return false
        }
        if case .create = mode,
           let resolveCreationDestinationListIDs {
            do {
                guard try resolveCreationDestinationListIDs().contains(id) else {
                    phase = .failed(.save, .invalidDestination)
                    return false
                }
            } catch {
                phase = .failed(.save, .invalidDestination)
                return false
            }
        }
        return true
    }

    private func assignCategory(to externalID: String) {
        guard let categories else { return }
        do {
            try categories.assign(categoryID: categoryID, to: .task, externalID: externalID)
            categoryWarning = nil
        } catch {
            categoryWarning = "The item was saved, but its app color was not applied."
        }
    }

    private func failure(for error: Error) -> TaskEditorFailure {
        switch error {
        case DraftValidationError.emptyTitle, DraftValidationError.invalidDateRange, DraftValidationError.invalidRecurrence, DraftValidationError.invalidRecurrenceScope, DraftValidationError.recurringReminderRequiresDueDate:
            .validation
        case DraftValidationError.invalidDestination, DraftValidationError.readOnlyDestination:
            .invalidDestination
        case EventKitMutationError.destinationMissing, EventKitMutationError.destinationReadOnly, EventKitMutationError.defaultUnavailable:
            .invalidDestination
        case EventKitMutationError.invalidDraft, EventKitMutationError.invalidRecurrence, EventKitMutationError.invalidRecurrenceScope:
            .validation
        case EventKitMutationError.saveFailed, EventKitMutationError.removeFailed:
            .retryableWrite
        default:
            .retryableWrite
        }
    }

    private func handleWriteError(_ error: Error, action: TaskEditorAction) {
        switch error {
        case DraftValidationError.itemNotFound, EventKitMutationError.itemNotFound:
            becomeUnavailable(.itemGone)
        case DraftValidationError.readOnlyDestination where action == .delete:
            becomeUnavailable(.readOnlySource)
        case EventKitMutationError.accessUnavailable:
            becomeUnavailable(.accessUnavailable)
        case EventKitMutationError.itemReadOnly:
            becomeUnavailable(.readOnlySource)
        default:
            phase = .failed(action, failure(for: error))
        }
    }

    private func becomeUnavailable(_ reason: TaskEditorUnavailableReason) {
        deleteConsentedHasRecurrence = nil
        phase = .unavailable(reason)
        mutationExplanation = switch reason {
        case .accessUnavailable: "Reminders access is unavailable."
        case .itemGone: "This task is no longer available."
        case .readOnlySource: "This task belongs to a read-only reminders list."
        }
        if reason == .itemGone, !didRequestReconciliation {
            didRequestReconciliation = true
            onReconciliationNeeded()
        }
    }

    private func commit(_ result: TaskEditorCommit) {
        guard !didCommit else { return }
        didCommit = true
        onCommitted(result)
    }
}
