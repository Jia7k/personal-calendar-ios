import Foundation

enum TaskQuickReschedule: Equatable, Sendable {
    case laterToday
    case tomorrow
    case nextWeek
    case pick(Date, hasTime: Bool)
}

enum TaskQuickRescheduleError: Error, Equatable, Sendable {
    case recurringTaskRequiresEditor
    case invalidDate
}

struct TaskRescheduleUndo: Equatable, Sendable {
    let reminderID: String
    let previousSchedule: ReminderScheduleValue?
}

struct TaskQuickReschedulePlanner: Sendable {
    let calendar: Calendar

    func schedule(
        for reminder: ReminderSnapshot,
        command: TaskQuickReschedule,
        now: Date
    ) throws -> ReminderScheduleValue {
        guard !reminder.hasRecurrence else {
            throw TaskQuickRescheduleError.recurringTaskRequiresEditor
        }
        guard now.timeIntervalSinceReferenceDate.isFinite else {
            throw TaskQuickRescheduleError.invalidDate
        }

        let result: ReminderScheduleValue
        switch command {
        case .laterToday:
            if reminder.dueHasTime,
               let dueDate = reminder.dueDate,
               calendar.isDate(dueDate, inSameDayAs: now),
               dueDate > now {
                result = .init(date: dueDate, hasTime: true)
                break
            }
            guard let sixPM = calendar.date(
                bySettingHour: 18,
                minute: 0,
                second: 0,
                of: now
            ),
            let minimum = calendar.date(byAdding: .minute, value: 15, to: now)
            else {
                throw TaskQuickRescheduleError.invalidDate
            }
            result = .init(date: max(sixPM, minimum), hasTime: true)

        case .tomorrow:
            result = try moving(reminder, daysFromNow: 1, now: now)

        case .nextWeek:
            result = try moving(reminder, daysFromNow: 7, now: now)

        case let .pick(date, hasTime):
            result = .init(date: date, hasTime: hasTime)
        }

        guard result.date.timeIntervalSinceReferenceDate.isFinite else {
            throw TaskQuickRescheduleError.invalidDate
        }
        return result
    }

    private func moving(
        _ reminder: ReminderSnapshot,
        daysFromNow dayOffset: Int,
        now: Date
    ) throws -> ReminderScheduleValue {
        let today = calendar.startOfDay(for: now)
        guard let targetDay = calendar.date(byAdding: .day, value: dayOffset, to: today) else {
            throw TaskQuickRescheduleError.invalidDate
        }

        guard reminder.dueHasTime else {
            return .init(date: targetDay, hasTime: false)
        }

        let source = reminder.dueDate ?? now
        let components = calendar.dateComponents([.hour, .minute, .second], from: source)
        guard let target = calendar.date(
            bySettingHour: components.hour ?? 0,
            minute: components.minute ?? 0,
            second: components.second ?? 0,
            of: targetDay
        ) else {
            throw TaskQuickRescheduleError.invalidDate
        }
        return .init(date: target, hasTime: true)
    }
}
