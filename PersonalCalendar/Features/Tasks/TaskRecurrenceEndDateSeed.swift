import Foundation

/// Returns a safe initial recurrence end date for a task. A future due date
/// remains the seed; missing or elapsed due dates fall back to `now`.
func taskRecurrenceEndDateSeed(effectiveDueDate: Date?, now: Date) -> Date {
    max(effectiveDueDate ?? now, now)
}
