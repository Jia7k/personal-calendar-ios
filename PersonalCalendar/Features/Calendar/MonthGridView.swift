import SwiftUI

struct MonthGridView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let cells: [CalendarCell]
    let displayedMonth: LocalDay
    let selectedDay: LocalDay
    let today: LocalDay
    let agendaByDay: [LocalDay: DayAgenda]
    let calendar: Calendar
    let onSelect: (LocalDay) -> Void

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                LazyVStack(spacing: 4) {
                    ForEach(cells) { cell in
                        dayButton(cell)
                    }
                }
            } else {
                VStack(spacing: 4) {
                    weekdayHeader
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                        ForEach(cells) { cell in
                            dayButton(cell)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func dayTitle(_ day: LocalDay, isSelected: Bool) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            Text(day.startDate(in: calendar).formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                .font(.body.weight(isSelected ? .bold : .regular))
        } else {
            Text(day.day, format: .number)
                .font(.body.weight(isSelected ? .bold : .regular))
        }
    }

    private var weekdayHeader: some View {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = calendar.locale ?? .current
        let names = formatter.veryShortWeekdaySymbols ?? ["S", "M", "T", "W", "T", "F", "S"]
        let ordered = (0..<7).map { names[(calendar.firstWeekday - 1 + $0) % 7] }
        return HStack {
            ForEach(Array(ordered.enumerated()), id: \.offset) { _, name in
                Text(name).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
            }
        }
    }

    private func dayButton(_ cell: CalendarCell) -> some View {
        let items = items(for: cell.day)
        let itemCount = items.count
        let isSelected = cell.day == selectedDay
        let isToday = cell.day == today
        return Button {
            onSelect(cell.day)
        } label: {
            VStack(spacing: 2) {
                dayTitle(cell.day, isSelected: isSelected)
                HStack(spacing: 3) {
                    ForEach(Array(items.prefix(3))) { item in
                        Image(systemName: indicatorSymbol(for: item))
                            .font(.caption2)
                            .foregroundStyle(CalendarTheme.sourceColor(item.source))
                    }
                    if itemCount > 3 {
                        Text("+\(itemCount - 3)")
                            .font(.caption2)
                            .foregroundStyle(CalendarTheme.accent)
                    }
                }
                .frame(minHeight: 12)
            }
            .frame(maxWidth: .infinity, minHeight: CalendarTheme.minimumTapSize)
            .background(isSelected ? CalendarTheme.selectionFill : Color.clear, in: RoundedRectangle(cornerRadius: 10))
            .overlay { if isToday { RoundedRectangle(cornerRadius: 10).stroke(CalendarTheme.accent, lineWidth: 1.5) } }
            .opacity(cell.belongsToDisplayedMonth ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .id(cell.day)
        .accessibilityIdentifier(cell.day == today ? "calendar-day-today" : "calendar-day-\(cell.day.year)-\(cell.day.month)-\(cell.day.day)")
        .accessibilityLabel(accessibilityDateLabel(for: cell.day))
        .accessibilityValue(accessibilityValue(isToday: isToday, isSelected: isSelected, itemCount: itemCount))
    }

    private func items(for day: LocalDay) -> [AgendaItem] {
        guard let agenda = agendaByDay[day] else { return [] }
        return agenda.allDay + agenda.scheduled + agenda.priority
    }

    private func indicatorSymbol(for item: AgendaItem) -> String {
        switch (item.source, item.placement) {
        case (.event, .allDay): "calendar.badge.clock"
        case (.event, .timed): "calendar"
        case (.task, _): "checkmark.circle"
        case (.routine, .window): "repeat"
        default: "circle"
        }
    }

    private func accessibilityDateLabel(for day: LocalDay) -> String {
        day.startDate(in: calendar).formatted(.dateTime.weekday(.wide).month(.wide).day().year())
    }

    private func accessibilityValue(isToday: Bool, isSelected: Bool, itemCount: Int) -> String {
        var values: [String] = []
        if isToday { values.append("Today") }
        if isSelected { values.append("Selected") }
        values.append("\(itemCount) items")
        return values.joined(separator: ", ")
    }
}
