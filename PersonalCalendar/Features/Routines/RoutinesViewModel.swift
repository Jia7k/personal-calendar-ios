import Foundation
import Observation

struct RoutineHistoryDay: Identifiable, Equatable, Sendable { let day: LocalDay; let isScheduled: Bool; let isCompleted: Bool; var id: LocalDay { day } }
struct RoutineRowState: Identifiable, Equatable, Sendable { let routine: RoutineSnapshot; let isCompletedToday: Bool; let streak: Int; let history: [RoutineHistoryDay]; let representedDay: LocalDay; var id: UUID { routine.id } }
enum RoutineEditorOperation: Equatable { case create, update(UUID) }
enum RoutineActionOperation: Equatable { case pause(UUID, Bool), archive(UUID, Bool), completion(UUID, LocalDay, Bool), delete(UUID) }
struct RoutineActionRecovery: Equatable { let operation: RoutineActionOperation; let message: String; let token: Int }

@MainActor
@Observable
final class RoutinesViewModel {
    private(set) var active: [RoutineRowState] = []
    private(set) var archived: [RoutineRowState] = []
    private(set) var refreshErrorMessage: String?
    private(set) var editorErrorMessage: String?
    private(set) var actionRecovery: RoutineActionRecovery?
    var actionErrorMessage: String? { actionRecovery?.message }
    var errorMessage: String? { actionErrorMessage ?? editorErrorMessage ?? refreshErrorMessage }
    private(set) var draftOnFailure: RoutineDraft?
    private(set) var failedEditorOperation: RoutineEditorOperation?
    var failedActionOperation: RoutineActionOperation? { actionRecovery?.operation }
    var deleteRetryTarget: RoutineRowState? {
        guard case let .delete(id)? = actionRecovery?.operation else { return nil }
        return row(id)
    }
    func resolveDeleteRetryTarget() -> RoutineRowState? {
        guard case let .delete(id)? = actionRecovery?.operation else { return nil }
        guard let target = row(id) else {
            actionRecovery = nil
            refreshErrorMessage = "That routine is no longer available. Refresh routines to continue."
            return nil
        }
        return target
    }
    private(set) var isLoading = false
    private(set) var mutatingIDs: Set<UUID> = []
    private let repository: any RoutineRepository; private let calendar: Calendar; private let now: () -> Date
    private var confirmedCompletedDays: [UUID: Set<LocalDay>] = [:]
    private var actionToken = 0

    init(repository: any RoutineRepository, calendar: Calendar = .current, now: @escaping () -> Date = { .now }) { self.repository = repository; self.calendar = calendar; self.now = now }
    var currentDay: LocalDay { LocalDay(date: now(), calendar: calendar) }
    var weekdayOrder: [Int] { (0..<7).map { ((calendar.firstWeekday - 1 + $0) % 7) + 1 } }
    func weekdayName(_ weekday: Int) -> String { calendar.weekdaySymbols[weekday - 1] }
    func windowName(_ window: RoutineWindow) -> String { switch window { case .morning: "Morning"; case .afternoon: "Afternoon"; case .evening: "Evening"; case .anytime: "Anytime" } }
    func localizedDate(for day: LocalDay) -> String { let formatter = DateFormatter(); formatter.calendar = calendar; formatter.locale = .current; formatter.timeZone = calendar.timeZone; formatter.dateStyle = .medium; formatter.timeStyle = .none; return formatter.string(from: day.startDate(in: calendar)) }
    func historyAccessibilityValue(_ history: [RoutineHistoryDay]) -> String { history.map { "\(localizedDate(for: $0.day)): \($0.isScheduled ? "scheduled" : "not scheduled"), \($0.isCompleted ? "completed" : "not completed")" }.joined(separator: "; ") }
    func reminderComponents(for date: Date) -> DateComponents { calendar.dateComponents([.hour, .minute], from: date) }
    func reminderDate(hour: Int?, minute: Int?) -> Date {
        let components = DateComponents(calendar: calendar, timeZone: calendar.timeZone, year: 2001, month: 1, day: 1, hour: hour ?? 9, minute: minute ?? 0, second: 0)
        return calendar.date(from: components) ?? Date(timeIntervalSinceReferenceDate: 0)
    }
    func isRepresentingCurrentDay(_ row: RoutineRowState) -> Bool { row.representedDay == currentDay }
    func canCompleteToday(_ row: RoutineRowState) -> Bool { isRepresentingCurrentDay(row) && !row.routine.isPaused && !row.routine.isArchived && row.routine.weekdays.contains(weekday(for: currentDay)) }
    func canChangeCompletion(_ row: RoutineRowState) -> Bool { isRepresentingCurrentDay(row) && (row.isCompletedToday || canCompleteToday(row)) }

    func reload(savedMutation: Bool = false) {
        isLoading = true; defer { isLoading = false }
        do {
            let reloadDay = currentDay
            let snapshots = try repository.list(includeArchived: true)
            var nextCompleted: [UUID: Set<LocalDay>] = [:]
            let staged = try snapshots.map { routine -> RoutineRowState in
                let completed = try repository.completedDays(routineID: routine.id)
                nextCompleted[routine.id] = completed
                return rowState(for: routine, completed: completed, day: reloadDay)
            }
            confirmedCompletedDays = nextCompleted
            active = staged.filter { !$0.routine.isArchived }; archived = staged.filter { $0.routine.isArchived }; refreshErrorMessage = nil
        } catch { refreshErrorMessage = savedMutation ? "Your routine change was saved, but routines could not be refreshed. Pull to try again." : "Your routines could not be loaded. Pull to try again." }
    }

    func create(_ draft: RoutineDraft) -> Bool {
        guard valid(draft) else { failEditor(.create, draft: draft, message: "Enter a title, choose at least one day, and use a valid reminder time."); return false }
        let clean = normalized(draft)
        do { let id = try repository.create(clean); clearEditorFailure(); insert(rowState(for: .init(id: id, title: clean.title, weekdays: clean.weekdays, window: clean.window, reminderHour: clean.reminderHour, reminderMinute: clean.reminderMinute, isPaused: false, isArchived: false), completed: [], day: currentDay)); reload(savedMutation: true); return true } catch { failEditor(.create, draft: clean, message: "Your routine was not saved. Edit it and try again."); return false }
    }
    func update(id: UUID, draft: RoutineDraft) -> Bool {
        guard valid(draft), let existing = row(id) else { failEditor(.update(id), draft: draft, message: "Enter a title, choose at least one day, and use a valid reminder time."); return false }
        let clean = normalized(draft)
        do { try repository.update(id: id, draft: clean); replace(existing, with: rowState(for: .init(id: id, title: clean.title, weekdays: clean.weekdays, window: clean.window, reminderHour: clean.reminderHour, reminderMinute: clean.reminderMinute, isPaused: existing.routine.isPaused, isArchived: existing.routine.isArchived), completed: confirmedCompletedDays[id] ?? [], day: existing.representedDay)); clearEditorFailure(); reload(savedMutation: true); return true } catch { failEditor(.update(id), draft: clean, message: "Your routine was not saved. Edit it and try again."); return false }
    }
    func setCompleted(id: UUID, completed state: Bool) async {
        let day = currentDay
        guard let row = row(id), row.representedDay == day, (row.isCompletedToday || (!row.routine.isPaused && !row.routine.isArchived && row.routine.weekdays.contains(weekday(for: day)))), !mutatingIDs.contains(id) else { refreshErrorMessage = "Refresh routines before changing completion."; return }
        mutate(id, operation: .completion(id, day, state), patch: { row in self.completedRow(row, day: day, completed: state) }) { try repository.setCompleted(routineID: id, day: day, completed: state) }
    }
    func setPaused(id: UUID, paused: Bool) { mutate(id, operation: .pause(id, paused), patch: { row in self.with(row, paused: paused) }) { try repository.setPaused(id: id, paused: paused) } }
    func setArchived(id: UUID, archived: Bool) { mutate(id, operation: .archive(id, archived), patch: { row in self.with(row, archived: archived) }) { try repository.setArchived(id: id, archived: archived) } }
    @discardableResult func delete(id: UUID) -> Bool {
        guard !mutatingIDs.contains(id), row(id) != nil else { return false }
        mutatingIDs.insert(id); defer { mutatingIDs.remove(id) }
        let operation = RoutineActionOperation.delete(id)
        do {
            try repository.delete(id: id)
            clearActionRecovery(matching: operation)
            active.removeAll { $0.id == id }; archived.removeAll { $0.id == id }; confirmedCompletedDays[id] = nil
            reload(savedMutation: true)
            return true
        } catch { failAction(operation, message: "Your routine was not deleted. Try again."); return false }
    }
    func retryFailedAction() {
        guard let recovery = actionRecovery else { return }
        let operation = recovery.operation
        switch operation {
        case let .pause(id, value): setPaused(id: id, paused: value)
        case let .archive(id, value): setArchived(id: id, archived: value)
        case let .completion(id, day, value): retryCompletion(id: id, day: day, completed: value)
        case .delete: break
        }
    }

    private func mutateDraft(_ draft: RoutineDraft, action: (RoutineDraft) throws -> Void) -> Bool {
        guard valid(draft) else { draftOnFailure = draft; editorErrorMessage = "Enter a title, choose at least one day, and use a valid reminder time."; return false }
        do { try action(normalized(draft)); draftOnFailure = nil; reload(); return true } catch { draftOnFailure = draft; editorErrorMessage = "Your routine was not saved. Edit it and try again."; return false }
    }
    private func mutate(_ id: UUID, operation: RoutineActionOperation? = nil, patch: (RoutineRowState) -> RoutineRowState, action: () throws -> Void) {
        guard !mutatingIDs.contains(id) else { return }; mutatingIDs.insert(id); defer { mutatingIDs.remove(id) }
        guard let old = row(id) else { return }
        do { try action(); if let operation { clearActionRecovery(matching: operation) }; replace(old, with: patch(old)); reload(savedMutation: true) } catch { if let operation { failAction(operation, message: "Your routine was not changed. Try again.") } }
    }
    private func rowState(for routine: RoutineSnapshot, completed: Set<LocalDay>, day today: LocalDay) -> RoutineRowState {
        let history = (-13...0).map { offset -> RoutineHistoryDay in let day = localDay(offset: offset, from: today); return .init(day: day, isScheduled: routine.weekdays.contains(weekday(for: day)), isCompleted: completed.contains(day)) }
        return .init(routine: routine, isCompletedToday: completed.contains(today), streak: RoutineStreakCalculator().currentStreak(routine: routine, completedDays: completed, through: today, calendar: calendar), history: history, representedDay: today)
    }
    private func row(_ id: UUID) -> RoutineRowState? { (active + archived).first { $0.id == id } }
    func canRetryEditor(_ operation: RoutineEditorOperation) -> Bool { failedEditorOperation == operation }
    func failedDraft(for operation: RoutineEditorOperation) -> RoutineDraft? { canRetryEditor(operation) ? draftOnFailure : nil }
    private func failEditor(_ operation: RoutineEditorOperation, draft: RoutineDraft, message: String) { failedEditorOperation = operation; draftOnFailure = draft; editorErrorMessage = message }
    private func clearEditorFailure() { failedEditorOperation = nil; draftOnFailure = nil; editorErrorMessage = nil }
    private func failAction(_ operation: RoutineActionOperation, message: String) { actionToken += 1; actionRecovery = .init(operation: operation, message: message, token: actionToken) }
    private func clearActionRecovery(matching operation: RoutineActionOperation) { guard actionRecovery?.operation == operation else { return }; actionRecovery = nil }
    func deleteErrorMessage(for id: UUID) -> String? { guard case let .delete(failedID)? = actionRecovery?.operation, failedID == id else { return nil }; return actionRecovery?.message }
    private func insert(_ row: RoutineRowState) { if row.routine.isArchived { archived.append(row) } else { active.append(row) } }
    private func replace(_ old: RoutineRowState, with new: RoutineRowState) { active.removeAll { $0.id == old.id }; archived.removeAll { $0.id == old.id }; insert(new) }
    private func replace(_ old: RoutineRowState, routine: RoutineSnapshot) { replace(old, with: .init(routine: routine, isCompletedToday: old.isCompletedToday, streak: old.streak, history: old.history, representedDay: old.representedDay)) }
    private func with(_ row: RoutineRowState, paused: Bool? = nil, archived: Bool? = nil) -> RoutineRowState { .init(routine: .init(id: row.id, title: row.routine.title, weekdays: row.routine.weekdays, window: row.routine.window, reminderHour: row.routine.reminderHour, reminderMinute: row.routine.reminderMinute, isPaused: paused ?? row.routine.isPaused, isArchived: archived ?? row.routine.isArchived), isCompletedToday: row.isCompletedToday, streak: row.streak, history: row.history, representedDay: row.representedDay) }
    private func retryCompletion(id: UUID, day: LocalDay, completed: Bool) { mutate(id, operation: .completion(id, day, completed), patch: { row in self.completedRow(row, day: day, completed: completed) }) { try repository.setCompleted(routineID: id, day: day, completed: completed) } }
    private func completedRow(_ row: RoutineRowState, day: LocalDay, completed: Bool) -> RoutineRowState { var days = confirmedCompletedDays[row.id] ?? []; if completed { days.insert(day) } else { days.remove(day) }; confirmedCompletedDays[row.id] = days; return rowState(for: row.routine, completed: days, day: row.representedDay) }
    private func localDay(offset: Int, from day: LocalDay) -> LocalDay { LocalDay(date: calendar.date(byAdding: .day, value: offset, to: day.startDate(in: calendar))!, calendar: calendar) }
    private func weekday(for day: LocalDay) -> Int { calendar.component(.weekday, from: day.startDate(in: calendar)) }
    private func valid(_ d: RoutineDraft) -> Bool { !d.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !d.weekdays.isEmpty && d.weekdays.allSatisfy { (1...7).contains($0) } && ((d.reminderHour == nil && d.reminderMinute == nil) || ((0...23).contains(d.reminderHour ?? -1) && (0...59).contains(d.reminderMinute ?? -1))) }
    private func normalized(_ d: RoutineDraft) -> RoutineDraft { .init(title: d.title.trimmingCharacters(in: .whitespacesAndNewlines), weekdays: d.weekdays, window: d.window, reminderHour: d.reminderHour, reminderMinute: d.reminderMinute) }
}
