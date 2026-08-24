import Foundation
import Observation

struct RoutineHistoryDay: Identifiable, Equatable, Sendable { let day: LocalDay; let isScheduled: Bool; let isCompleted: Bool; var id: LocalDay { day } }
struct RoutineRowState: Identifiable, Equatable, Sendable { let routine: RoutineSnapshot; let isCompletedToday: Bool; let streak: Int; let history: [RoutineHistoryDay]; var id: UUID { routine.id } }
enum RoutineEditorOperation: Equatable { case create, update(UUID) }
enum RoutineActionOperation: Equatable { case pause(UUID, Bool), archive(UUID, Bool), completion(UUID, LocalDay, Bool), delete(UUID) }

@MainActor
@Observable
final class RoutinesViewModel {
    private(set) var active: [RoutineRowState] = []
    private(set) var archived: [RoutineRowState] = []
    private(set) var errorMessage: String?
    private(set) var draftOnFailure: RoutineDraft?
    private(set) var failedEditorOperation: RoutineEditorOperation?
    private(set) var failedActionOperation: RoutineActionOperation?
    private(set) var isLoading = false
    private(set) var mutatingIDs: Set<UUID> = []
    private let repository: any RoutineRepository; private let calendar: Calendar; private let now: () -> Date
    private var confirmedCompletedDays: [UUID: Set<LocalDay>] = [:]

    init(repository: any RoutineRepository, calendar: Calendar = .current, now: @escaping () -> Date = { .now }) { self.repository = repository; self.calendar = calendar; self.now = now }
    var currentDay: LocalDay { LocalDay(date: now(), calendar: calendar) }
    var weekdayOrder: [Int] { (0..<7).map { ((calendar.firstWeekday - 1 + $0) % 7) + 1 } }
    func weekdayName(_ weekday: Int) -> String { calendar.weekdaySymbols[weekday - 1] }
    func reminderComponents(for date: Date) -> DateComponents { calendar.dateComponents([.hour, .minute], from: date) }
    func reminderDate(hour: Int?, minute: Int?) -> Date { calendar.date(bySettingHour: hour ?? 9, minute: minute ?? 0, second: 0, of: now()) ?? now() }
    func canCompleteToday(_ row: RoutineRowState) -> Bool { !row.routine.isPaused && !row.routine.isArchived && row.routine.weekdays.contains(weekday(for: currentDay)) }

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
            active = staged.filter { !$0.routine.isArchived }; archived = staged.filter { $0.routine.isArchived }; errorMessage = nil
        } catch { errorMessage = savedMutation ? "Your routine change was saved, but routines could not be refreshed. Pull to try again." : "Your routines could not be loaded. Pull to try again." }
    }

    func create(_ draft: RoutineDraft) -> Bool {
        guard valid(draft) else { failEditor(.create, draft: draft, message: "Enter a title, choose at least one day, and use a valid reminder time."); return false }
        let clean = normalized(draft)
        do { let id = try repository.create(clean); clearEditorFailure(); insert(rowState(for: .init(id: id, title: clean.title, weekdays: clean.weekdays, window: clean.window, reminderHour: clean.reminderHour, reminderMinute: clean.reminderMinute, isPaused: false, isArchived: false))); reload(savedMutation: true); return true } catch { failEditor(.create, draft: clean, message: "Your routine was not saved. Edit it and try again."); return false }
    }
    func update(id: UUID, draft: RoutineDraft) -> Bool {
        guard valid(draft), let existing = row(id) else { failEditor(.update(id), draft: draft, message: "Enter a title, choose at least one day, and use a valid reminder time."); return false }
        let clean = normalized(draft)
        do { try repository.update(id: id, draft: clean); replace(existing, with: rowState(for: .init(id: id, title: clean.title, weekdays: clean.weekdays, window: clean.window, reminderHour: clean.reminderHour, reminderMinute: clean.reminderMinute, isPaused: existing.routine.isPaused, isArchived: existing.routine.isArchived), completed: confirmedCompletedDays[id] ?? [])); clearEditorFailure(); reload(savedMutation: true); return true } catch { failEditor(.update(id), draft: clean, message: "Your routine was not saved. Edit it and try again."); return false }
    }
    func setCompleted(id: UUID, completed state: Bool) async {
        guard let row = row(id), (row.isCompletedToday || (!row.routine.isPaused && !row.routine.isArchived && row.routine.weekdays.contains(weekday(for: currentDay)))), !mutatingIDs.contains(id) else { return }
        mutate(id, patch: { row in self.completedRow(row, completed: state) }) { try repository.setCompleted(routineID: id, day: currentDay, completed: state) }
    }
    func setPaused(id: UUID, paused: Bool) { mutate(id, operation: .pause(id, paused), patch: { row in self.with(row, paused: paused) }) { try repository.setPaused(id: id, paused: paused) } }
    func setArchived(id: UUID, archived: Bool) { mutate(id, operation: .archive(id, archived), patch: { row in self.with(row, archived: archived) }) { try repository.setArchived(id: id, archived: archived) } }
    func delete(id: UUID) { guard !mutatingIDs.contains(id) else { return }; mutatingIDs.insert(id); defer { mutatingIDs.remove(id) }; do { try repository.delete(id: id); active.removeAll { $0.id == id }; archived.removeAll { $0.id == id }; confirmedCompletedDays[id] = nil; reload(savedMutation: true) } catch { errorMessage = "Your routine was not deleted. Try again." } }
    func retryFailedAction() {
        guard let operation = failedActionOperation else { return }
        failedActionOperation = nil
        switch operation {
        case let .pause(id, value): setPaused(id: id, paused: value)
        case let .archive(id, value): setArchived(id: id, archived: value)
        case .completion, .delete: failedActionOperation = operation
        }
    }

    private func mutateDraft(_ draft: RoutineDraft, action: (RoutineDraft) throws -> Void) -> Bool {
        guard valid(draft) else { draftOnFailure = draft; errorMessage = "Enter a title, choose at least one day, and use a valid reminder time."; return false }
        do { try action(normalized(draft)); draftOnFailure = nil; reload(); return true } catch { draftOnFailure = draft; errorMessage = "Your routine was not saved. Edit it and try again."; return false }
    }
    private func mutate(_ id: UUID, operation: RoutineActionOperation? = nil, patch: (RoutineRowState) -> RoutineRowState, action: () throws -> Void) {
        guard !mutatingIDs.contains(id) else { return }; mutatingIDs.insert(id); defer { mutatingIDs.remove(id) }
        guard let old = row(id) else { return }
        do { try action(); failedActionOperation = nil; replace(old, with: patch(old)); reload(savedMutation: true) } catch { failedActionOperation = operation; errorMessage = "Your routine was not changed. Try again." }
    }
    private func rowState(for routine: RoutineSnapshot, completed: Set<LocalDay>, day today: LocalDay? = nil) -> RoutineRowState {
        let today = today ?? currentDay
        let history = (-13...0).map { offset -> RoutineHistoryDay in let day = localDay(offset: offset, from: today); return .init(day: day, isScheduled: routine.weekdays.contains(weekday(for: day)), isCompleted: completed.contains(day)) }
        return .init(routine: routine, isCompletedToday: completed.contains(today), streak: RoutineStreakCalculator().currentStreak(routine: routine, completedDays: completed, through: today, calendar: calendar), history: history)
    }
    private func row(_ id: UUID) -> RoutineRowState? { (active + archived).first { $0.id == id } }
    func canRetryEditor(_ operation: RoutineEditorOperation) -> Bool { failedEditorOperation == operation }
    private func failEditor(_ operation: RoutineEditorOperation, draft: RoutineDraft, message: String) { failedEditorOperation = operation; draftOnFailure = draft; errorMessage = message }
    private func clearEditorFailure() { failedEditorOperation = nil; draftOnFailure = nil }
    private func insert(_ row: RoutineRowState) { if row.routine.isArchived { archived.append(row) } else { active.append(row) } }
    private func replace(_ old: RoutineRowState, with new: RoutineRowState) { active.removeAll { $0.id == old.id }; archived.removeAll { $0.id == old.id }; insert(new) }
    private func replace(_ old: RoutineRowState, routine: RoutineSnapshot) { replace(old, with: .init(routine: routine, isCompletedToday: old.isCompletedToday, streak: old.streak, history: old.history)) }
    private func with(_ row: RoutineRowState, paused: Bool? = nil, archived: Bool? = nil) -> RoutineRowState { .init(routine: .init(id: row.id, title: row.routine.title, weekdays: row.routine.weekdays, window: row.routine.window, reminderHour: row.routine.reminderHour, reminderMinute: row.routine.reminderMinute, isPaused: paused ?? row.routine.isPaused, isArchived: archived ?? row.routine.isArchived), isCompletedToday: row.isCompletedToday, streak: row.streak, history: row.history) }
    private func completedRow(_ row: RoutineRowState, completed: Bool) -> RoutineRowState { var days = confirmedCompletedDays[row.id] ?? []; if completed { days.insert(currentDay) } else { days.remove(currentDay) }; confirmedCompletedDays[row.id] = days; return rowState(for: row.routine, completed: days) }
    private func rowState(for routine: RoutineSnapshot) -> RoutineRowState { let today = currentDay; let history = (-13...0).map { offset -> RoutineHistoryDay in let day = localDay(offset: offset, from: today); return .init(day: day, isScheduled: routine.weekdays.contains(weekday(for: day)), isCompleted: false) }; return .init(routine: routine, isCompletedToday: false, streak: 0, history: history) }
    private func localDay(offset: Int, from day: LocalDay) -> LocalDay { LocalDay(date: calendar.date(byAdding: .day, value: offset, to: day.startDate(in: calendar))!, calendar: calendar) }
    private func weekday(for day: LocalDay) -> Int { calendar.component(.weekday, from: day.startDate(in: calendar)) }
    private func valid(_ d: RoutineDraft) -> Bool { !d.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !d.weekdays.isEmpty && d.weekdays.allSatisfy { (1...7).contains($0) } && ((d.reminderHour == nil && d.reminderMinute == nil) || ((0...23).contains(d.reminderHour ?? -1) && (0...59).contains(d.reminderMinute ?? -1))) }
    private func normalized(_ d: RoutineDraft) -> RoutineDraft { .init(title: d.title.trimmingCharacters(in: .whitespacesAndNewlines), weekdays: d.weekdays, window: d.window, reminderHour: d.reminderHour, reminderMinute: d.reminderMinute) }
}
