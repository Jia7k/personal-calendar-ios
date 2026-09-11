import Foundation
import Observation

@MainActor
@Observable
final class TasksViewModel {
    struct TaskMutationOperation: Equatable { let id: String; let completed: Bool }
    private(set) var overdue: [ReminderSnapshot] = []
    private(set) var today: [ReminderSnapshot] = []
    private(set) var needsScheduling: [ReminderSnapshot] = []
    private(set) var upcoming: [ReminderSnapshot] = []
    private(set) var completed: [ReminderSnapshot] = []
    private(set) var refreshErrorMessage: String?
    private(set) var mutationErrorMessage: String?
    private(set) var failedMutationOperation: TaskMutationOperation?
    private(set) var latestTaskUndo: TaskUndoState?
    private(set) var rescheduleUndo: TaskRescheduleUndo?
    private(set) var rescheduleErrorMessage: String?
    var errorMessage: String? { rescheduleErrorMessage ?? mutationErrorMessage ?? refreshErrorMessage }
    private(set) var isLoading = false
    private(set) var isProfileEmpty = false
    private(set) var mutatingIDs: Set<String> = []

    private let service: any RemindersServicing
    private let settings: AppSettingsStore
    @ObservationIgnored private let currentScope: (@MainActor () throws -> ProfileScope)?
    private let calendar: Calendar
    private let now: () -> Date
    private var confirmed: [ReminderSnapshot] = []
    private var loadGeneration = 0
    private var cachedScopeIdentity: ProfileIdentity?
    private var rescheduleUndoExpectedSchedule: ReminderScheduleValue?
    private var rescheduleUndoExpectedListID: String?

    private struct CapturedScope {
        let identity: ProfileIdentity?
        let reminderListIDs: Set<String>
        let fetchesAllWhenEmpty: Bool

        var isProfileScope: Bool { identity != nil }
    }

    init(service: any RemindersServicing, settings: AppSettingsStore, calendar: Calendar = .current, now: @escaping () -> Date = { .now }) {
        self.service = service
        self.settings = settings
        currentScope = nil
        self.calendar = calendar
        self.now = now
    }

    init(
        service: any RemindersServicing,
        settings: AppSettingsStore,
        currentScope: @escaping @MainActor () throws -> ProfileScope,
        calendar: Calendar = .current,
        now: @escaping () -> Date = { .now }
    ) {
        self.service = service
        self.settings = settings
        self.currentScope = currentScope
        self.calendar = calendar
        self.now = now
    }

    var accessExplanation: String? {
        switch service.accessState {
        case .denied: "Tasks are unavailable because Reminders access is denied."
        case .restricted: "Tasks are unavailable because Reminders access is restricted."
        case .notDetermined: "Allow Reminders access to show your tasks."
        case .granted: nil
        }
    }

    func load() async {
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true
        defer { if generation == loadGeneration { isLoading = false } }

        let scope: CapturedScope
        do {
            scope = try captureScope()
        } catch {
            failClosedForUnknownScope()
            refreshErrorMessage = "Your tasks could not be refreshed. Pull to try again."
            return
        }

        prepareForLoad(scope)

        guard service.accessState == .granted else {
            confirmed = []
            publish(scope: scope)
            reconcileMutationRecovery(authoritativeFetch: true, scope: scope)
            refreshErrorMessage = nil
            return
        }

        guard !scope.reminderListIDs.isEmpty || scope.fetchesAllWhenEmpty else {
            confirmed = []
            publish(scope: scope)
            reconcileMutationRecovery(authoritativeFetch: true, scope: scope)
            refreshErrorMessage = nil
            return
        }

        do {
            let fetched = try await service.fetchReminders(listIDs: scope.reminderListIDs)
            guard generation == loadGeneration else { return }
            confirmed = scope.fetchesAllWhenEmpty
                ? fetched
                : fetched.filter { scope.reminderListIDs.contains($0.listID) }
            refreshErrorMessage = nil
            publish(scope: scope)
            reconcileMutationRecovery(authoritativeFetch: true, scope: scope)
        } catch {
            guard generation == loadGeneration else { return }
            refreshErrorMessage = "Your tasks could not be refreshed. Pull to try again."
            publish(scope: scope)
            reconcileMutationRecovery(authoritativeFetch: false, scope: scope)
        }
    }

    func refreshForExternalChange() async {
        await load()
    }

    /// Host-owned post-editor refresh. The editor has already completed its single provider write.
    func refreshAfterEditorCommit(_ commit: TaskEditorCommit) async {
        await load()
        guard refreshErrorMessage != nil else { return }
        refreshErrorMessage = switch commit {
        case .deleted: "Your task was deleted, but tasks could not be refreshed. Pull to try again."
        case .created, .updated: "Your task was saved, but tasks could not be refreshed. Pull to try again."
        }
    }

    /// Host-owned post-Quick-Entry reconciliation. Other committed kinds do not touch Reminders.
    func refreshAfterQuickEntry(_ outcome: QuickEntrySaveOutcome) async {
        guard case .task = outcome else { return }
        await load()
        if refreshErrorMessage != nil {
            refreshErrorMessage = "Your task was saved, but tasks could not be refreshed. Pull to try again."
        }
    }

    func setCompleted(id: String, completed state: Bool) async {
        guard let scope = scopeForMutation() else { clearMutationRecovery(id: id); return }
        reconcileMutationRecovery(authoritativeFetch: false, scope: scope)
        guard service.accessState == .granted else { clearMutationRecovery(id: id); return }
        guard let item = confirmed.first(where: { $0.id == id }),
              item.allowsModification,
              scopeAllows(item, scope: scope),
              !mutatingIDs.contains(id) else {
            clearMutationRecovery(id: id)
            return
        }
        mutatingIDs.insert(id); defer { mutatingIDs.remove(id) }
        do {
            try service.setCompleted(id: id, completed: state)
            confirmed = confirmed.map { $0.id == id ? replacing($0, completed: state) : $0 }
            if state {
                latestTaskUndo = TaskUndoState(
                    generation: UUID(),
                    title: item.title,
                    rawID: id,
                    snapshot: item
                )
            } else {
                clearCompletionUndo(for: id)
            }
            publish(scope: scope)
            let operation = TaskMutationOperation(id: id, completed: state)
            if failedMutationOperation?.id == operation.id {
                failedMutationOperation = nil
                mutationErrorMessage = nil
            }
            await load()
            if refreshErrorMessage != nil { refreshErrorMessage = "Your task change was saved, but tasks could not be refreshed. Pull to try again." }
        } catch { failedMutationOperation = .init(id: id, completed: state); mutationErrorMessage = "Your task was not changed. Try again." }
    }
    func retryFailedMutation() async {
        guard let operation = failedMutationOperation else { return }
        guard let scope = scopeForMutation() else { clearMutationRecovery(id: operation.id); return }
        reconcileMutationRecovery(authoritativeFetch: false, scope: scope)
        guard service.accessState == .granted, failedMutationOperation == operation else { clearMutationRecovery(id: operation.id); return }
        guard let item = confirmed.first(where: { $0.id == operation.id }),
              item.allowsModification,
              scopeAllows(item, scope: scope),
              item.isCompleted != operation.completed,
              let live = service.reminder(id: operation.id),
              live.listID == item.listID,
              live.allowsModification,
              scopeAllows(live, scope: scope),
              live.isCompleted != operation.completed,
              listAllowsContentModifications(live.listID, scope: scope) else {
            clearMutationRecovery(id: operation.id)
            return
        }
        await setCompleted(id: operation.id, completed: operation.completed)
    }

    func undoLastTaskCompletion() async {
        guard let capturedUndo = latestTaskUndo,
              !capturedUndo.isPending,
              !mutatingIDs.contains(capturedUndo.rawID),
              let scope = scopeForMutation()
        else { return }
        reconcileMutationRecovery(authoritativeFetch: false, scope: scope)
        guard var undo = latestTaskUndo,
              undo.generation == capturedUndo.generation,
              completionUndoIsEligible(undo, scope: scope)
        else {
            clearCompletionUndo(for: capturedUndo.rawID)
            return
        }

        let generation = undo.generation
        mutatingIDs.insert(undo.rawID)
        defer { mutatingIDs.remove(undo.rawID) }
        undo.isPending = true
        if latestTaskUndo?.generation == generation { latestTaskUndo = undo }

        do {
            try service.setCompleted(id: undo.rawID, completed: false)
            let restored = undo.snapshot.withCompletion(false)
            confirmed = confirmed.map { item in
                item.id == undo.rawID ? restored : item
            }
            if !confirmed.contains(where: { $0.id == undo.rawID }) {
                confirmed.append(restored)
            }
            publish(scope: scope)
            await load()
            if refreshErrorMessage != nil {
                refreshErrorMessage = "Your task change was saved, but tasks could not be refreshed. Pull to try again."
            }
            if failedMutationOperation?.id == undo.rawID {
                failedMutationOperation = nil
                mutationErrorMessage = nil
            }
            if latestTaskUndo?.generation == generation { latestTaskUndo = nil }
        } catch {
            undo.isPending = false
            if latestTaskUndo?.generation == generation { latestTaskUndo = undo }
            failedMutationOperation = .init(id: undo.rawID, completed: false)
            mutationErrorMessage = "Your task was not changed. Try again."
        }
    }

    func quickReschedule(id: String, command: TaskQuickReschedule) async {
        guard let scope = scopeForMutation() else { return }
        guard service.accessState == .granted,
              confirmed.contains(where: { $0.id == id }),
              let item = service.reminder(id: id),
              !item.isCompleted,
              item.allowsModification,
              !item.hasRecurrence,
              scopeAllows(item, scope: scope),
              !mutatingIDs.contains(id)
        else {
            clearRescheduleUndo(for: id)
            return
        }

        let projected: ReminderScheduleValue
        do {
            projected = try TaskQuickReschedulePlanner(calendar: calendar).schedule(
                for: item,
                command: command,
                now: now()
            )
        } catch {
            return
        }

        let previous = item.dueDate.map {
            ReminderScheduleValue(date: $0, hasTime: item.dueHasTime)
        }
        var draft = ReminderDraft(
            title: item.title,
            notes: item.notes,
            dueDate: item.dueDate,
            dueHasTime: item.dueHasTime,
            priority: item.priority,
            listID: nil,
            alarm: .preserve,
            recurrence: .preserve
        )
        draft.schedule = .replace(projected)

        mutatingIDs.insert(id)
        defer { mutatingIDs.remove(id) }
        do {
            try service.updateReminder(id: id, draft: draft)
            replaceConfirmedSchedule(id: id, with: projected)
            publish(scope: scope)
            rescheduleUndo = .init(reminderID: id, previousSchedule: previous)
            rescheduleUndoExpectedSchedule = projected
            rescheduleUndoExpectedListID = item.listID
            rescheduleErrorMessage = nil
            await load()
            if refreshErrorMessage != nil {
                refreshErrorMessage = "Your task was rescheduled, but tasks could not be refreshed. Pull to try again."
            }
        } catch {
            rescheduleErrorMessage = "Your task was not rescheduled. Try again."
        }
    }

    func undoQuickReschedule() async {
        guard let undo = rescheduleUndo else { return }
        guard let scope = scopeForMutation(),
              service.accessState == .granted,
              confirmed.contains(where: { $0.id == undo.reminderID }),
              let item = service.reminder(id: undo.reminderID),
              !item.isCompleted,
              !item.hasRecurrence,
              item.allowsModification,
              scopeAllows(item, scope: scope),
              item.listID == rescheduleUndoExpectedListID,
              schedulesMatch(currentSchedule(of: item), rescheduleUndoExpectedSchedule),
              !mutatingIDs.contains(item.id)
        else {
            clearRescheduleUndo(for: undo.reminderID)
            return
        }

        var draft = ReminderDraft(
            title: item.title,
            notes: item.notes,
            dueDate: item.dueDate,
            dueHasTime: item.dueHasTime,
            priority: item.priority,
            listID: nil,
            alarm: .preserve,
            recurrence: .preserve
        )
        if let previous = undo.previousSchedule {
            draft.schedule = .replace(previous)
        } else {
            draft.schedule = .clear
        }

        mutatingIDs.insert(item.id)
        defer { mutatingIDs.remove(item.id) }
        do {
            try service.updateReminder(id: item.id, draft: draft)
            replaceConfirmedSchedule(id: item.id, with: undo.previousSchedule)
            publish(scope: scope)
            if rescheduleUndo == undo { clearRescheduleUndo() }
            rescheduleErrorMessage = nil
            await load()
            if refreshErrorMessage != nil {
                refreshErrorMessage = "Your task schedule was restored, but tasks could not be refreshed. Pull to try again."
            }
        } catch {
            rescheduleErrorMessage = "Your task schedule was not restored. Try again."
        }
    }

    private func captureScope() throws -> CapturedScope {
        if let currentScope {
            let scope = try currentScope()
            return CapturedScope(
                identity: scope.identity,
                reminderListIDs: scope.reminderListIDs,
                fetchesAllWhenEmpty: false
            )
        }

        let descriptorIDs = Set(service.lists().map(\.id))
        let visibleIDs = descriptorIDs.isEmpty
            ? settings.selectedReminderListIDs
            : settings.visibleReminderListIDs(availableIDs: descriptorIDs)
        return CapturedScope(
            identity: nil,
            reminderListIDs: visibleIDs,
            fetchesAllWhenEmpty: !settings.reminderSelectionIsExplicit && visibleIDs.isEmpty
        )
    }

    private func prepareForLoad(_ scope: CapturedScope) {
        guard scope.isProfileScope else {
            isProfileEmpty = false
            return
        }

        isProfileEmpty = scope.reminderListIDs.isEmpty
        if cachedScopeIdentity != scope.identity {
            confirmed = []
            overdue = []
            today = []
            needsScheduling = []
            upcoming = []
            completed = []
            clearAllMutationRecovery()
            refreshErrorMessage = nil
        } else {
            confirmed.removeAll { !scope.reminderListIDs.contains($0.listID) }
            if let undo = latestTaskUndo,
               !scope.reminderListIDs.contains(undo.snapshot.listID) {
                latestTaskUndo = nil
            }
            publish(scope: scope)
        }
        cachedScopeIdentity = scope.identity
    }

    private func scopeForMutation() -> CapturedScope? {
        let scope: CapturedScope
        do {
            scope = try captureScope()
        } catch {
            failClosedForUnknownScope()
            refreshErrorMessage = "Your tasks could not be refreshed. Pull to try again."
            return nil
        }

        if scope.isProfileScope {
            let identityMatches = cachedScopeIdentity == scope.identity
            prepareForLoad(scope)
            reconcileMutationRecovery(authoritativeFetch: false, scope: scope)
            guard identityMatches else { return nil }
        }
        return scope
    }

    private func failClosedForUnknownScope() {
        confirmed = []
        overdue = []
        today = []
        needsScheduling = []
        upcoming = []
        completed = []
        cachedScopeIdentity = nil
        isProfileEmpty = false
        clearAllMutationRecovery()
    }

    private func publish(scope: CapturedScope) {
        let todayDay = LocalDay(date: now(), calendar: calendar)
        let selected = visibleListIDs(for: scope)
        let visible = confirmed.filter { selected.contains($0.listID) }
        let incomplete = visible.filter { !$0.isCompleted }
        overdue = incomplete.filter { item in item.dueDate.map { LocalDay(date: $0, calendar: calendar) < todayDay } ?? false }.sorted(by: sort)
        today = incomplete.filter { item in item.dueDate.map { LocalDay(date: $0, calendar: calendar) == todayDay } ?? false }.sorted(by: sort)
        needsScheduling = incomplete.filter { $0.dueDate == nil }.sorted(by: sort)
        upcoming = incomplete.filter { item in
            item.dueDate.map { LocalDay(date: $0, calendar: calendar) > todayDay } ?? false
        }.sorted(by: sort)
        completed = visible.filter(\.isCompleted).sorted(by: sort)
    }
    private func reconcileMutationRecovery(authoritativeFetch: Bool, scope: CapturedScope) {
        let selected = visibleListIDs(for: scope)
        if let operation = failedMutationOperation {
            guard service.accessState == .granted,
                  let item = confirmed.first(where: { $0.id == operation.id }),
                  selected.contains(item.listID),
                  item.allowsModification else {
                clearMutationRecovery(id: operation.id)
                reconcileCompletionUndo(scope: scope)
                reconcileRescheduleUndo(authoritativeFetch: authoritativeFetch, selectedListIDs: selected)
                return
            }
            if authoritativeFetch && item.isCompleted == operation.completed {
                clearMutationRecovery(id: operation.id)
            }
        }
        reconcileCompletionUndo(scope: scope)
        reconcileRescheduleUndo(authoritativeFetch: authoritativeFetch, selectedListIDs: selected)
    }
    private func scopeAllows(_ item: ReminderSnapshot, scope: CapturedScope) -> Bool {
        visibleListIDs(for: scope).contains(item.listID)
    }
    private func listAllowsContentModifications(
        _ listID: String,
        scope: CapturedScope
    ) -> Bool {
        let descriptors = service.lists()
        if descriptors.isEmpty { return !scope.isProfileScope }
        return descriptors.contains {
            $0.id == listID && $0.allowsContentModifications
        }
    }
    private func visibleListIDs(for scope: CapturedScope) -> Set<String> {
        if scope.isProfileScope { return scope.reminderListIDs }
        return settings.visibleReminderListIDs(availableIDs: availableListIDs)
    }
    private var availableListIDs: Set<String> {
        let descriptorIDs = Set(service.lists().map(\.id))
        return descriptorIDs.isEmpty ? Set(confirmed.map(\.listID)) : descriptorIDs
    }
    private func clearMutationRecovery(id: String) { guard failedMutationOperation?.id == id else { return }; failedMutationOperation = nil; mutationErrorMessage = nil }
    private func clearAllMutationRecovery() {
        failedMutationOperation = nil
        mutationErrorMessage = nil
        latestTaskUndo = nil
        clearRescheduleUndo()
        rescheduleErrorMessage = nil
    }

    private func reconcileCompletionUndo(scope: CapturedScope) {
        guard let undo = latestTaskUndo,
              completionUndoIsEligible(undo, scope: scope) else {
            latestTaskUndo = nil
            return
        }
    }

    private func completionUndoIsEligible(
        _ undo: TaskUndoState,
        scope: CapturedScope
    ) -> Bool {
        let descriptors = service.lists()
        let descriptorIDs = Set(descriptors.map(\.id))
        let writableDescriptorIDs = Set(
            descriptors.filter(\.allowsContentModifications).map(\.id)
        )
        guard service.accessState == .granted,
              undo.snapshot.allowsModification,
              visibleListIDs(for: scope).contains(undo.snapshot.listID),
              descriptorIDs.contains(undo.snapshot.listID),
              writableDescriptorIDs.contains(undo.snapshot.listID)
        else { return false }

        guard let authoritative = service.reminder(id: undo.rawID) else { return false }
        return authoritative.listID == undo.snapshot.listID
            && authoritative.allowsModification
            && (authoritative.isCompleted || undo.isPending)
    }

    private func clearCompletionUndo(for id: String? = nil) {
        if let id, latestTaskUndo?.rawID != id { return }
        latestTaskUndo = nil
    }

    private func reconcileRescheduleUndo(
        authoritativeFetch: Bool,
        selectedListIDs: Set<String>
    ) {
        guard let undo = rescheduleUndo else {
            rescheduleUndoExpectedSchedule = nil
            rescheduleUndoExpectedListID = nil
            return
        }
        guard service.accessState == .granted,
              let expectedListID = rescheduleUndoExpectedListID,
              selectedListIDs.contains(expectedListID) else {
            clearRescheduleUndo()
            return
        }
        guard let item = confirmed.first(where: { $0.id == undo.reminderID }) else {
            if authoritativeFetch { clearRescheduleUndo() }
            return
        }
        guard item.listID == expectedListID,
              item.allowsModification,
              !item.isCompleted,
              !item.hasRecurrence else {
            clearRescheduleUndo()
            return
        }
        if authoritativeFetch,
           !schedulesMatch(currentSchedule(of: item), rescheduleUndoExpectedSchedule) {
            clearRescheduleUndo()
        }
    }

    private func clearRescheduleUndo(for reminderID: String? = nil) {
        if let reminderID, rescheduleUndo?.reminderID != reminderID { return }
        rescheduleUndo = nil
        rescheduleUndoExpectedSchedule = nil
        rescheduleUndoExpectedListID = nil
    }

    private func currentSchedule(of item: ReminderSnapshot) -> ReminderScheduleValue? {
        item.dueDate.map { ReminderScheduleValue(date: $0, hasTime: item.dueHasTime) }
    }

    private func schedulesMatch(
        _ lhs: ReminderScheduleValue?,
        _ rhs: ReminderScheduleValue?
    ) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case let (lhs?, rhs?):
            guard lhs.hasTime == rhs.hasTime,
                  lhs.date.timeIntervalSinceReferenceDate.isFinite,
                  rhs.date.timeIntervalSinceReferenceDate.isFinite else { return false }
            let components: Set<Calendar.Component> = lhs.hasTime
                ? [.year, .month, .day, .hour, .minute]
                : [.year, .month, .day]
            return calendar.dateComponents(components, from: lhs.date)
                == calendar.dateComponents(components, from: rhs.date)
        case (.none, .some), (.some, .none):
            return false
        }
    }

    private func replaceConfirmedSchedule(id: String, with schedule: ReminderScheduleValue?) {
        confirmed = confirmed.map { item in
            guard item.id == id else { return item }
            return ReminderSnapshot(
                id: item.id,
                title: item.title,
                notes: item.notes,
                dueDate: schedule?.date,
                dueHasTime: schedule?.hasTime ?? false,
                priority: item.priority,
                listID: item.listID,
                listTitle: item.listTitle,
                isCompleted: item.isCompleted,
                allowsModification: item.allowsModification,
                hasRecurrence: item.hasRecurrence,
                alarm: item.alarm,
                recurrence: item.recurrence
            )
        }
    }

    private func sort(_ lhs: ReminderSnapshot, _ rhs: ReminderSnapshot) -> Bool {
        switch (lhs.dueDate, rhs.dueDate) { case let (a?, b?): if a != b { return a < b }; case (_?, nil): return true; case (nil, _?): return false; case (nil, nil): break }
        let titleOrder = lhs.title.localizedCaseInsensitiveCompare(rhs.title); return titleOrder == .orderedSame ? lhs.id < rhs.id : titleOrder == .orderedAscending
    }
    private func replacing(_ item: ReminderSnapshot, completed: Bool) -> ReminderSnapshot { item.withCompletion(completed) }
}
