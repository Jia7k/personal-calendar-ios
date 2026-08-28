import SwiftUI

struct MonthGridActivitySummary: Equatable {
    let markerSources: [AgendaSource]
    let eventCount: Int
    let taskCount: Int
    let routineCount: Int

    init(items: [AgendaItem]) {
        markerSources = [AgendaSource.event, .task, .routine].filter { source in
            items.contains { $0.source == source }
        }
        eventCount = items.count { $0.source == .event }
        taskCount = items.count { $0.source == .task }
        routineCount = items.count { $0.source == .routine }
    }

    var totalCount: Int {
        eventCount + taskCount + routineCount
    }

    var sourceCountDescription: String {
        let parts = [
            Self.countDescription(eventCount, singular: "event"),
            Self.countDescription(taskCount, singular: "task"),
            Self.countDescription(routineCount, singular: "routine")
        ].compactMap { $0 }
        return parts.isEmpty ? "0 items" : parts.joined(separator: ", ")
    }

    private static func countDescription(_ count: Int, singular: String) -> String? {
        guard count > 0 else { return nil }
        return "\(count) \(singular)\(count == 1 ? "" : "s")"
    }
}

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
        let summary = MonthGridActivitySummary(items: items)
        let isSelected = cell.day == selectedDay
        let isToday = cell.day == today
        return Button {
            onSelect(cell.day)
        } label: {
            VStack(spacing: 2) {
                dayTitle(cell.day, isSelected: isSelected)
                if dynamicTypeSize.isAccessibilitySize {
                    if summary.totalCount > 0 {
                        Text(summary.sourceCountDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    HStack(spacing: 4) {
                        ForEach(Array(summary.markerSources.enumerated()), id: \.offset) { _, source in
                            Circle()
                                .fill(CalendarTheme.sourceColor(source))
                                .frame(width: 5, height: 5)
                                .accessibilityHidden(true)
                        }
                    }
                    .frame(minHeight: 12)
                }
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
        .accessibilityValue(accessibilityValue(isToday: isToday, isSelected: isSelected, summary: summary))
    }

    private func items(for day: LocalDay) -> [AgendaItem] {
        guard let agenda = agendaByDay[day] else { return [] }
        return agenda.allDay + agenda.scheduled + agenda.priority
    }

    private func accessibilityDateLabel(for day: LocalDay) -> String {
        day.startDate(in: calendar).formatted(.dateTime.weekday(.wide).month(.wide).day().year())
    }

    private func accessibilityValue(
        isToday: Bool,
        isSelected: Bool,
        summary: MonthGridActivitySummary
    ) -> String {
        var values: [String] = []
        if isToday { values.append("Today") }
        if isSelected { values.append("Selected") }
        values.append(summary.sourceCountDescription)
        return values.joined(separator: ", ")
    }
}
