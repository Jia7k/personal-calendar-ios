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
    private(set) var mutatingIDs: Set<String> = []

    private let service: any RemindersServicing
    private let settings: AppSettingsStore
    private let calendar: Calendar
    private let now: () -> Date
    private var confirmed: [ReminderSnapshot] = []
    private var loadGeneration = 0

    init(service: any RemindersServicing, settings: AppSettingsStore, calendar: Calendar = .current, now: @escaping () -> Date = { .now }) {
        self.service = service; self.settings = settings; self.calendar = calendar; self.now = now
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
        loadGeneration += 1; let generation = loadGeneration
        guard service.accessState == .granted else { confirmed = []; publish(); reconcileMutationRecovery(authoritativeFetch: true); refreshErrorMessage = nil; isLoading = false; return }
        isLoading = true; defer { if generation == loadGeneration { isLoading = false } }
        do {
            let descriptorIDs = Set(service.lists().map(\.id))
            let visibleIDs = descriptorIDs.isEmpty ? settings.selectedReminderListIDs : settings.visibleReminderListIDs(availableIDs: descriptorIDs)
            let fetched = settings.reminderSelectionIsExplicit && visibleIDs.isEmpty ? [] : try await service.fetchReminders(listIDs: visibleIDs)
            guard generation == loadGeneration else { return }
            confirmed = fetched
            refreshErrorMessage = nil; publish(); reconcileMutationRecovery(authoritativeFetch: true)
        } catch {
            guard generation == loadGeneration else { return }
            refreshErrorMessage = "Your tasks could not be refreshed. Pull to try again."
            publish(); reconcileMutationRecovery(authoritativeFetch: false)
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
        reconcileMutationRecovery(authoritativeFetch: false)
        guard service.accessState == .granted else { clearMutationRecovery(id: id); return }
        guard let item = confirmed.first(where: { $0.id == id }), item.allowsModification, isSelected(item), !mutatingIDs.contains(id) else { clearMutationRecovery(id: id); return }
        mutatingIDs.insert(id); defer { mutatingIDs.remove(id) }
        do {
            try service.setCompleted(id: id, completed: state)
            confirmed = confirmed.map { $0.id == id ? replacing($0, completed: state) : $0 }
            publish()
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
        reconcileMutationRecovery(authoritativeFetch: false)
        guard service.accessState == .granted, failedMutationOperation == operation else { clearMutationRecovery(id: operation.id); return }
        guard let item = confirmed.first(where: { $0.id == operation.id }), item.allowsModification, isSelected(item), item.isCompleted != operation.completed else { clearMutationRecovery(id: operation.id); return }
        await setCompleted(id: operation.id, completed: operation.completed)
    }

    private func publish() {
        let todayDay = LocalDay(date: now(), calendar: calendar)
        let selected = settings.visibleReminderListIDs(availableIDs: availableListIDs)
        let visible = confirmed.filter { selected.contains($0.listID) }
        let incomplete = visible.filter { !$0.isCompleted }
        today = incomplete.filter { item in item.dueDate.map { LocalDay(date: $0, calendar: calendar) <= todayDay } ?? false }.sorted(by: sort)
        upcoming = incomplete.filter { item in item.dueDate.map { LocalDay(date: $0, calendar: calendar) > todayDay } ?? true }.sorted(by: sort)
        completed = visible.filter(\.isCompleted).sorted(by: sort)
    }
    private func reconcileMutationRecovery(authoritativeFetch: Bool) {
        guard let operation = failedMutationOperation else { return }
        let selected = settings.visibleReminderListIDs(availableIDs: availableListIDs)
        guard service.accessState == .granted, let item = confirmed.first(where: { $0.id == operation.id }), selected.contains(item.listID), item.allowsModification else { clearMutationRecovery(id: operation.id); return }
        if authoritativeFetch && item.isCompleted == operation.completed { clearMutationRecovery(id: operation.id) }
    }
    private func isSelected(_ item: ReminderSnapshot) -> Bool { settings.visibleReminderListIDs(availableIDs: availableListIDs).contains(item.listID) }
    private var availableListIDs: Set<String> {
        let descriptorIDs = Set(service.lists().map(\.id))
        return descriptorIDs.isEmpty ? Set(confirmed.map(\.listID)) : descriptorIDs
    }
    private func clearMutationRecovery(id: String) { guard failedMutationOperation?.id == id else { return }; failedMutationOperation = nil; mutationErrorMessage = nil }

    private func sort(_ lhs: ReminderSnapshot, _ rhs: ReminderSnapshot) -> Bool {
        switch (lhs.dueDate, rhs.dueDate) { case let (a?, b?): if a != b { return a < b }; case (_?, nil): return true; case (nil, _?): return false; case (nil, nil): break }
        let titleOrder = lhs.title.localizedCaseInsensitiveCompare(rhs.title); return titleOrder == .orderedSame ? lhs.id < rhs.id : titleOrder == .orderedAscending
    }
    private func replacing(_ item: ReminderSnapshot, completed: Bool) -> ReminderSnapshot { item.withCompletion(completed) }
}
