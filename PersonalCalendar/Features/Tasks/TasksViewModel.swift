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
    private(set) var createErrorMessage: String?
    private(set) var mutationErrorMessage: String?
    private(set) var failedMutationOperation: TaskMutationOperation?
    var errorMessage: String? { mutationErrorMessage ?? createErrorMessage ?? refreshErrorMessage }
    private(set) var draftOnFailure: ReminderDraft?
    private(set) var isLoading = false
    private(set) var isSaving = false
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

    var writableLists: [ReminderListDescriptor] { service.lists().filter(\.allowsContentModifications).sorted { ($0.title, $0.id) < ($1.title, $1.id) } }
    var defaultWritableListID: String? {
        let lists = writableLists
        if let saved = settings.defaultReminderListID, lists.contains(where: { $0.id == saved }) { return saved }
        return lists.first?.id
    }

    func load() async {
        loadGeneration += 1; let generation = loadGeneration
        guard service.accessState == .granted else { confirmed = []; publish(); reconcileMutationRecovery(authoritativeFetch: true); refreshErrorMessage = nil; isLoading = false; return }
        isLoading = true; defer { if generation == loadGeneration { isLoading = false } }
        do {
            let fetched = try await service.fetchReminders(listIDs: settings.selectedReminderListIDs)
            guard generation == loadGeneration else { return }
            confirmed = fetched
            refreshErrorMessage = nil; publish(); reconcileMutationRecovery(authoritativeFetch: true)
        } catch {
            guard generation == loadGeneration else { return }
            refreshErrorMessage = "Your tasks could not be refreshed. Pull to try again."
            publish(); reconcileMutationRecovery(authoritativeFetch: false)
        }
    }

    func create(_ draft: ReminderDraft) async -> Bool {
        guard !isSaving else { return false }
        guard service.accessState == .granted else { createErrorMessage = "Allow Reminders access before creating a task."; return false }
        guard isValid(draft), let listID = resolvedListID(for: draft) else { createErrorMessage = "Enter a title and choose a writable reminder list."; return false }
        isSaving = true; defer { isSaving = false }
        var saved = draft; saved.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines); saved.listID = listID
        if saved.dueDate == nil { saved.dueHasTime = false }
        do {
            _ = try service.createReminder(saved); draftOnFailure = nil; createErrorMessage = nil
            await load()
            if refreshErrorMessage != nil { refreshErrorMessage = "Your task was saved, but tasks could not be refreshed. Pull to try again." }
            return true
        } catch {
            draftOnFailure = saved; createErrorMessage = "Your task was not saved. Edit it and try again."; return false
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
        let selected = settings.selectedReminderListIDs
        let visible = confirmed.filter { selected.isEmpty || selected.contains($0.listID) }
        let incomplete = visible.filter { !$0.isCompleted }
        today = incomplete.filter { item in item.dueDate.map { LocalDay(date: $0, calendar: calendar) <= todayDay } ?? false }.sorted(by: sort)
        upcoming = incomplete.filter { item in item.dueDate.map { LocalDay(date: $0, calendar: calendar) > todayDay } ?? true }.sorted(by: sort)
        completed = visible.filter(\.isCompleted).sorted(by: sort)
    }
    private func reconcileMutationRecovery(authoritativeFetch: Bool) {
        guard let operation = failedMutationOperation else { return }
        let selected = settings.selectedReminderListIDs
        guard service.accessState == .granted, let item = confirmed.first(where: { $0.id == operation.id }), (selected.isEmpty || selected.contains(item.listID)), item.allowsModification else { clearMutationRecovery(id: operation.id); return }
        if authoritativeFetch && item.isCompleted == operation.completed { clearMutationRecovery(id: operation.id) }
    }
    private func isSelected(_ item: ReminderSnapshot) -> Bool { settings.selectedReminderListIDs.isEmpty || settings.selectedReminderListIDs.contains(item.listID) }
    private func clearMutationRecovery(id: String) { guard failedMutationOperation?.id == id else { return }; failedMutationOperation = nil; mutationErrorMessage = nil }

    private func sort(_ lhs: ReminderSnapshot, _ rhs: ReminderSnapshot) -> Bool {
        switch (lhs.dueDate, rhs.dueDate) { case let (a?, b?): if a != b { return a < b }; case (_?, nil): return true; case (nil, _?): return false; case (nil, nil): break }
        let titleOrder = lhs.title.localizedCaseInsensitiveCompare(rhs.title); return titleOrder == .orderedSame ? lhs.id < rhs.id : titleOrder == .orderedAscending
    }
    private func resolvedListID(for draft: ReminderDraft) -> String? {
        if let chosen = draft.listID { return writableLists.contains(where: { $0.id == chosen }) ? chosen : nil }
        return defaultWritableListID
    }
    private func isValid(_ draft: ReminderDraft) -> Bool { !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (0...9).contains(draft.priority) && (draft.dueDate != nil || !draft.dueHasTime) }
    private func replacing(_ item: ReminderSnapshot, completed: Bool) -> ReminderSnapshot { .init(id: item.id, title: item.title, notes: item.notes, dueDate: item.dueDate, dueHasTime: item.dueHasTime, priority: item.priority, listID: item.listID, listTitle: item.listTitle, isCompleted: completed, allowsModification: item.allowsModification, hasRecurrence: item.hasRecurrence) }
}
