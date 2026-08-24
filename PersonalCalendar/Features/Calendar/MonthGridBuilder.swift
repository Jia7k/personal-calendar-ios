import Foundation

struct CalendarCell: Identifiable, Equatable {
    let day: LocalDay
    let belongsToDisplayedMonth: Bool

    var id: LocalDay { day }
}

struct MonthGridBuilder {
    let calendar: Calendar

    func days(containing month: LocalDay) -> [CalendarCell] {
        let first = month.startDate(in: calendar)
        let weekdayOffset = (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7
        let gridStart = calendar.date(byAdding: .day, value: -weekdayOffset, to: first)!

        return (0..<42).map { offset in
            let date = calendar.date(byAdding: .day, value: offset, to: gridStart)!
            let day = LocalDay(date: date, calendar: calendar)
            return CalendarCell(
                day: day,
                belongsToDisplayedMonth: day.month == month.month && day.year == month.year
            )
        }
    }

    func week(containing selectedDay: LocalDay, displayedMonth: LocalDay) -> [CalendarCell] {
        let selectedDate = selectedDay.startDate(in: calendar)
        let weekdayOffset = (calendar.component(.weekday, from: selectedDate) - calendar.firstWeekday + 7) % 7
        let weekStart = calendar.date(byAdding: .day, value: -weekdayOffset, to: selectedDate)!

        return (0..<7).map { offset in
            let date = calendar.date(byAdding: .day, value: offset, to: weekStart)!
            let day = LocalDay(date: date, calendar: calendar)
            return CalendarCell(
                day: day,
                belongsToDisplayedMonth: day.month == displayedMonth.month && day.year == displayedMonth.year
            )
        }
    }
}
