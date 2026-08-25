import Foundation
import Observation

@MainActor
@Observable
final class TasksViewModel {
    struct TaskMutationOperation: Equatable { let id: String; let completed: Bool }
    private(set) var today: [ReminderSnapshot] = []
    private(set) var upcoming: [ReminderSnapshot] = []
    private(set) var completed: [ReminderSnapshot] = []
    private(set) var refreshErrorMessage: String?
    private(set) var mutationErrorMessage: String?
    private(set) var failedMutationOperation: TaskMutationOperation?
    var errorMessage: String? { mutationErrorMessage ?? refreshErrorMessage }
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
              item.isCompleted != operation.completed else {
            clearMutationRecovery(id: operation.id)
            return
        }
        await setCompleted(id: operation.id, completed: operation.completed)
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
            today = []
            upcoming = []
            completed = []
            clearAllMutationRecovery()
            refreshErrorMessage = nil
        } else {
            confirmed.removeAll { !scope.reminderListIDs.contains($0.listID) }
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
            guard identityMatches else { return nil }
        }
        return scope
    }

    private func failClosedForUnknownScope() {
        confirmed = []
        today = []
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
        today = incomplete.filter { item in item.dueDate.map { LocalDay(date: $0, calendar: calendar) <= todayDay } ?? false }.sorted(by: sort)
        upcoming = incomplete.filter { item in item.dueDate.map { LocalDay(date: $0, calendar: calendar) > todayDay } ?? true }.sorted(by: sort)
        completed = visible.filter(\.isCompleted).sorted(by: sort)
    }
    private func reconcileMutationRecovery(authoritativeFetch: Bool, scope: CapturedScope) {
        guard let operation = failedMutationOperation else { return }
        let selected = visibleListIDs(for: scope)
        guard service.accessState == .granted, let item = confirmed.first(where: { $0.id == operation.id }), selected.contains(item.listID), item.allowsModification else { clearMutationRecovery(id: operation.id); return }
        if authoritativeFetch && item.isCompleted == operation.completed { clearMutationRecovery(id: operation.id) }
    }
    private func scopeAllows(_ item: ReminderSnapshot, scope: CapturedScope) -> Bool {
        visibleListIDs(for: scope).contains(item.listID)
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
    private func clearAllMutationRecovery() { failedMutationOperation = nil; mutationErrorMessage = nil }

    private func sort(_ lhs: ReminderSnapshot, _ rhs: ReminderSnapshot) -> Bool {
        switch (lhs.dueDate, rhs.dueDate) { case let (a?, b?): if a != b { return a < b }; case (_?, nil): return true; case (nil, _?): return false; case (nil, nil): break }
        let titleOrder = lhs.title.localizedCaseInsensitiveCompare(rhs.title); return titleOrder == .orderedSame ? lhs.id < rhs.id : titleOrder == .orderedAscending
    }
    private func replacing(_ item: ReminderSnapshot, completed: Bool) -> ReminderSnapshot { item.withCompletion(completed) }
}
