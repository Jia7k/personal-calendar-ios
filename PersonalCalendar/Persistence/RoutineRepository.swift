import Foundation

@MainActor
protocol RoutineRepository: AnyObject {
    func list(includeArchived: Bool) throws -> [RoutineSnapshot]
    func create(_ draft: RoutineDraft) throws -> UUID
    func update(id: UUID, draft: RoutineDraft) throws
    func setPaused(id: UUID, paused: Bool) throws
    func setArchived(id: UUID, archived: Bool) throws
    func delete(id: UUID) throws
    func setCompleted(routineID: UUID, day: LocalDay, completed: Bool) throws
    func isCompleted(routineID: UUID, day: LocalDay) throws -> Bool
    func completedDays(routineID: UUID) throws -> Set<LocalDay>
}

enum RoutineRepositoryError: Error, Equatable {
    case invalidDraft
    case routineNotFound
}

struct RoutineStreakCalculator {
    func currentStreak(
        routine: RoutineSnapshot,
        completedDays: Set<LocalDay>,
        through day: LocalDay,
        calendar: Calendar
    ) -> Int {
        guard !routine.weekdays.isEmpty else { return 0 }

        var cursor = day
        if routine.weekdays.contains(calendar.component(.weekday, from: cursor.startDate(in: calendar))),
           !completedDays.contains(cursor) {
            cursor = previousDay(before: cursor, calendar: calendar)
        }

        var streak = 0
        while true {
            let weekday = calendar.component(.weekday, from: cursor.startDate(in: calendar))
            if routine.weekdays.contains(weekday) {
                guard completedDays.contains(cursor) else { return streak }
                streak += 1
            }
            cursor = previousDay(before: cursor, calendar: calendar)
        }
    }

    private func previousDay(before day: LocalDay, calendar: Calendar) -> LocalDay {
        LocalDay(
            date: calendar.date(byAdding: .day, value: -1, to: day.startDate(in: calendar))!,
            calendar: calendar
        )
    }
}
