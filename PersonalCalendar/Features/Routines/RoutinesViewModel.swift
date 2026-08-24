import Foundation
import Observation

struct RoutineHistoryDay: Identifiable, Equatable, Sendable { let day: LocalDay; let isScheduled: Bool; let isCompleted: Bool; var id: LocalDay { day } }
struct RoutineRowState: Identifiable, Equatable, Sendable { let routine: RoutineSnapshot; let isCompletedToday: Bool; let streak: Int; let history: [RoutineHistoryDay]; var id: UUID { routine.id } }

@MainActor
@Observable
final class RoutinesViewModel {
    private(set) var active: [RoutineRowState] = []
    private(set) var archived: [RoutineRowState] = []
    private(set) var errorMessage: String?
    private(set) var draftOnFailure: RoutineDraft?
    private(set) var isLoading = false
    private(set) var mutatingIDs: Set<UUID> = []
    private let repository: any RoutineRepository; private let calendar: Calendar; private let now: () -> Date

    init(repository: any RoutineRepository, calendar: Calendar = .current, now: @escaping () -> Date = { .now }) { self.repository = repository; self.calendar = calendar; self.now = now }
    var currentDay: LocalDay { LocalDay(date: now(), calendar: calendar) }
    var weekdayOrder: [Int] { (0..<7).map { ((calendar.firstWeekday - 1 + $0) % 7) + 1 } }
    func weekdayName(_ weekday: Int) -> String { calendar.weekdaySymbols[weekday - 1] }

    func reload() {
        isLoading = true; defer { isLoading = false }
        do {
            let snapshots = try repository.list(includeArchived: true)
            let staged = try snapshots.map(makeRow)
            active = staged.filter { !$0.routine.isArchived }; archived = staged.filter { $0.routine.isArchived }; errorMessage = nil
        } catch { errorMessage = "Your routines could not be loaded. Pull to try again." }
    }

    func create(_ draft: RoutineDraft) -> Bool { mutateDraft(draft) { _ = try repository.create($0) } }
    func update(id: UUID, draft: RoutineDraft) -> Bool { mutateDraft(draft) { try repository.update(id: id, draft: $0) } }
    func setCompleted(id: UUID, completed state: Bool) async {
        guard let row = row(id), (row.isCompletedToday || (!row.routine.isPaused && !row.routine.isArchived && row.routine.weekdays.contains(weekday(for: currentDay)))), !mutatingIDs.contains(id) else { return }
        mutate(id) { try repository.setCompleted(routineID: id, day: currentDay, completed: state) }
    }
    func setPaused(id: UUID, paused: Bool) { mutate(id) { try repository.setPaused(id: id, paused: paused) } }
    func setArchived(id: UUID, archived: Bool) { mutate(id) { try repository.setArchived(id: id, archived: archived) } }
    func delete(id: UUID) { mutate(id) { try repository.delete(id: id) } }

    private func mutateDraft(_ draft: RoutineDraft, action: (RoutineDraft) throws -> Void) -> Bool {
        guard valid(draft) else { draftOnFailure = draft; errorMessage = "Enter a title, choose at least one day, and use a valid reminder time."; return false }
        do { try action(normalized(draft)); draftOnFailure = nil; reload(); return true } catch { draftOnFailure = draft; errorMessage = "Your routine was not saved. Edit it and try again."; return false }
    }
    private func mutate(_ id: UUID, action: () throws -> Void) {
        guard !mutatingIDs.contains(id) else { return }; mutatingIDs.insert(id); defer { mutatingIDs.remove(id) }
        do { try action(); reload() } catch { errorMessage = "Your routine was not changed. Try again." }
    }
    private func makeRow(_ routine: RoutineSnapshot) throws -> RoutineRowState {
        let completed = try repository.completedDays(routineID: routine.id); let today = currentDay
        let history = (-13...0).map { offset -> RoutineHistoryDay in let day = localDay(offset: offset, from: today); return .init(day: day, isScheduled: routine.weekdays.contains(weekday(for: day)), isCompleted: completed.contains(day)) }
        return .init(routine: routine, isCompletedToday: completed.contains(today), streak: RoutineStreakCalculator().currentStreak(routine: routine, completedDays: completed, through: today, calendar: calendar), history: history)
    }
    private func row(_ id: UUID) -> RoutineRowState? { (active + archived).first { $0.id == id } }
    private func localDay(offset: Int, from day: LocalDay) -> LocalDay { LocalDay(date: calendar.date(byAdding: .day, value: offset, to: day.startDate(in: calendar))!, calendar: calendar) }
    private func weekday(for day: LocalDay) -> Int { calendar.component(.weekday, from: day.startDate(in: calendar)) }
    private func valid(_ d: RoutineDraft) -> Bool { !d.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !d.weekdays.isEmpty && d.weekdays.allSatisfy { (1...7).contains($0) } && ((d.reminderHour == nil && d.reminderMinute == nil) || ((0...23).contains(d.reminderHour ?? -1) && (0...59).contains(d.reminderMinute ?? -1))) }
    private func normalized(_ d: RoutineDraft) -> RoutineDraft { .init(title: d.title.trimmingCharacters(in: .whitespacesAndNewlines), weekdays: d.weekdays, window: d.window, reminderHour: d.reminderHour, reminderMinute: d.reminderMinute) }
}
