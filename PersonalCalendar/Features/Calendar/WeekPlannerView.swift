import SwiftUI

struct WeekPlannerView: View {
    private struct SelectedItem: Identifiable {
        let id: String
        let item: AgendaItem
    }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var selectedItem: SelectedItem?

    let snapshot: WeekPlannerSnapshot
    let selectedDay: LocalDay
    let now: Date
    let calendar: Calendar
    let onSelectDay: (LocalDay) -> Void
    let onOpenItem: (AgendaItemOrigin) -> Void

    init(
        snapshot: WeekPlannerSnapshot,
        selectedDay: LocalDay,
        now: Date,
        calendar: Calendar,
        onSelectDay: @escaping (LocalDay) -> Void,
        onOpenItem: @escaping (AgendaItemOrigin) -> Void
    ) {
        self.snapshot = snapshot
        self.selectedDay = selectedDay
        self.now = now
        self.calendar = calendar
        self.onSelectDay = onSelectDay
        self.onOpenItem = onOpenItem
    }

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            accessibleAgenda
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("week-planner")
        } else {
            sevenDayTimeline
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("week-planner")
        }
    }

    private var sevenDayTimeline: some View {
        VStack(alignment: .leading, spacing: 12) {
            allDayStrip
            dayHeaders
            timeline
            selectedDetail
            laterStrip
        }
    }

    @ViewBuilder
    private var allDayStrip: some View {
        if !snapshot.allDayItems.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(snapshot.days, id: \.self) { day in
                        let items = snapshot.allDayItems.filter { $0.day == day }
                        if !items.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(day.startDate(in: calendar), format: .dateTime.weekday(.narrow))
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(day == selectedDay ? CalendarTheme.accent : .secondary)
                                ForEach(items) { value in
                                    Button {
                                        select(day: day, item: value.item, identifier: value.id)
                                    } label: {
                                        Text(value.item.title)
                                            .font(.caption)
                                            .lineLimit(1)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 6)
                                            .background(itemColor(value.item).opacity(0.14), in: Capsule())
                                    }
                                    .buttonStyle(.plain)
                                    .frame(minHeight: CalendarTheme.minimumTapSize)
                                    .accessibilityLabel("All day, \(value.item.title), \(dayLabel(day))")
                                }
                            }
                            .frame(minWidth: 82, alignment: .leading)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var dayHeaders: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: timeGutterWidth)
            ForEach(snapshot.days, id: \.self) { day in
                Button { onSelectDay(day) } label: {
                    VStack(spacing: 2) {
                        Text(day.startDate(in: calendar), format: .dateTime.weekday(.narrow))
                            .font(.caption.weight(.semibold))
                        Text(day.startDate(in: calendar), format: .dateTime.day())
                            .font(.caption2.weight(day == selectedDay ? .bold : .regular))
                    }
                    .foregroundStyle(day == selectedDay ? CalendarTheme.accent : .primary)
                    .frame(maxWidth: .infinity, minHeight: CalendarTheme.minimumTapSize)
                    .background(
                        day == selectedDay ? CalendarTheme.selectionFill.opacity(0.45) : .clear,
                        in: RoundedRectangle(cornerRadius: 8)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(dayLabel(day))
                .accessibilityValue(day == selectedDay ? "Selected day" : "")
            }
        }
    }

    private var timeline: some View {
        ScrollView(.vertical, showsIndicators: true) {
            GeometryReader { proxy in
                let dayWidth = max(1, (proxy.size.width - timeGutterWidth) / CGFloat(max(1, snapshot.days.count)))
                ZStack(alignment: .topLeading) {
                    hourRules(width: proxy.size.width)
                    dayDividers(dayWidth: dayWidth)
                    currentTimeLine(dayWidth: dayWidth)
                    ForEach(snapshot.timedItems) { value in
                        timedItem(value, dayWidth: dayWidth)
                    }
                }
            }
            .frame(height: timelineHeight)
        }
        .frame(maxHeight: min(timelineHeight, 440))
        .background(CalendarTheme.surface, in: RoundedRectangle(cornerRadius: CalendarTheme.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: CalendarTheme.cornerRadius)
                .stroke(CalendarTheme.accent.opacity(0.12), lineWidth: 1)
        }
    }

    private func hourRules(width: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(snapshot.startHour...snapshot.endHour, id: \.self) { hour in
                let y = CGFloat(hour - snapshot.startHour) * pointsPerHour
                Path { path in
                    path.move(to: CGPoint(x: timeGutterWidth, y: y))
                    path.addLine(to: CGPoint(x: width, y: y))
                }
                .stroke(.secondary.opacity(0.18), lineWidth: 1)

                if hour < snapshot.endHour {
                    Text(hourLabel(hour))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: timeGutterWidth - 6, alignment: .trailing)
                        .offset(y: y - 7)
                }
            }
        }
    }

    private func dayDividers(dayWidth: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(0...snapshot.days.count, id: \.self) { index in
                Rectangle()
                    .fill(.secondary.opacity(0.12))
                    .frame(width: 1, height: timelineHeight)
                    .offset(x: timeGutterWidth + CGFloat(index) * dayWidth)
            }
        }
    }

    @ViewBuilder
    private func currentTimeLine(dayWidth: CGFloat) -> some View {
        let today = LocalDay(date: now, calendar: calendar)
        if let index = snapshot.days.firstIndex(of: today),
           let offset = minuteOffset(for: now, on: today),
           offset >= 0, offset <= timelineHeight {
            Rectangle()
                .fill(CalendarTheme.accent)
                .frame(width: dayWidth, height: 2)
                .offset(x: timeGutterWidth + CGFloat(index) * dayWidth, y: offset)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func timedItem(_ value: WeekPlannerTimedItem, dayWidth: CGFloat) -> some View {
        if let dayIndex = snapshot.days.firstIndex(of: value.day),
           let y = minuteOffset(for: value.start, on: value.day) {
            let x = itemX(value, dayIndex: dayIndex, dayWidth: dayWidth)

            switch value.kind {
            case .event:
                let end = value.end ?? value.start
                let height = max(28, (minuteOffset(for: end, on: value.day) ?? y) - y)
                Button {
                    select(day: value.day, item: value.item, identifier: value.id)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(value.item.title)
                            .font(.caption2.weight(.semibold))
                            .lineLimit(2)
                        Text(timeRange(start: value.start, end: end))
                            .font(.caption2)
                            .lineLimit(1)
                    }
                    .foregroundStyle(.primary)
                    .padding(5)
                    .frame(maxWidth: .infinity, minHeight: height, alignment: .topLeading)
                    .background(itemColor(value.item).opacity(0.22), in: RoundedRectangle(cornerRadius: 7))
                    .overlay {
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(itemColor(value.item).opacity(0.7), lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .frame(width: eventWidth(value, dayWidth: dayWidth), height: height, alignment: .topLeading)
                .offset(x: x, y: y)
                .accessibilityIdentifier("week-event-\(originIdentifier(value.item.origin) ?? value.item.id)")
                .accessibilityLabel("Event, \(value.item.title), \(timeRange(start: value.start, end: end)), \(dayLabel(value.day))")
            case .taskDue:
                Button {
                    select(day: value.day, item: value.item, identifier: value.id)
                } label: {
                    HStack(spacing: 5) {
                        Diamond()
                            .fill(itemColor(value.item))
                            .frame(width: 11, height: 11)
                        Text(value.item.title)
                            .font(.caption2.weight(.medium))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 5)
                    .frame(maxWidth: .infinity, minHeight: CalendarTheme.minimumTapSize, alignment: .leading)
                    .background(CalendarTheme.surface.opacity(0.94), in: Capsule())
                }
                .buttonStyle(.plain)
                .frame(width: max(28, dayWidth - 6), height: CalendarTheme.minimumTapSize, alignment: .leading)
                .offset(x: timeGutterWidth + CGFloat(dayIndex) * dayWidth + 3, y: y - CalendarTheme.minimumTapSize / 2)
                .accessibilityIdentifier("week-task-\(originIdentifier(value.item.origin) ?? value.item.id)")
                .accessibilityLabel("Task due, \(value.item.title), \(value.start.formatted(date: .omitted, time: .shortened)), \(dayLabel(value.day))")
            }
        }
    }

    @ViewBuilder
    private var selectedDetail: some View {
        if let selectedItem {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedItem.item.title)
                        .font(.subheadline.weight(.semibold))
                    Text(AgendaAccessibilityDescription.scheduleDescription(selectedItem.item.placement))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if canOpen(selectedItem.item.origin) {
                    Button("Open") { onOpenItem(selectedItem.item.origin) }
                        .frame(minWidth: CalendarTheme.minimumTapSize, minHeight: CalendarTheme.minimumTapSize)
                        .accessibilityIdentifier("week-open-selected-item")
                }
            }
            .padding(12)
            .background(CalendarTheme.selectionFill.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    @ViewBuilder
    private var laterStrip: some View {
        if !snapshot.laterItems.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Later")
                    .font(.headline)
                ForEach(snapshot.laterItems) { item in
                    Button { onOpenItem(item.origin) } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "repeat")
                                .foregroundStyle(itemColor(item))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                Text(AgendaAccessibilityDescription.scheduleDescription(item.placement))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, minHeight: CalendarTheme.minimumTapSize, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Routine, \(AgendaAccessibilityDescription.build(for: item))")
                }
            }
            .padding(12)
            .background(CalendarTheme.surface, in: RoundedRectangle(cornerRadius: CalendarTheme.cornerRadius))
        }
    }

    private var accessibleAgenda: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(snapshot.days, id: \.self) { day in
                let allDay = snapshot.allDayItems.filter { $0.day == day }.map(\.item)
                let timed = snapshot.timedItems.filter { $0.day == day }.sorted { $0.start < $1.start }
                let routines = day == selectedDay ? snapshot.laterItems : []
                VStack(alignment: .leading, spacing: 6) {
                    Button { onSelectDay(day) } label: {
                        Text(dayLabel(day))
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: CalendarTheme.minimumTapSize, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(day == selectedDay ? .isSelected : [])

                    ForEach(allDay) { item in
                        accessibleRow(item, prefix: "All day")
                    }
                    ForEach(timed) { value in
                        accessibleRow(
                            value.item,
                            prefix: value.kind == .event
                                ? "Event, \(timeRange(start: value.start, end: value.end ?? value.start))"
                                : "Task due, \(value.start.formatted(date: .omitted, time: .shortened))"
                        )
                    }
                    ForEach(routines) { item in
                        accessibleRow(item, prefix: "Later routine")
                    }
                    if allDay.isEmpty && timed.isEmpty && routines.isEmpty {
                        Text("Nothing planned")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .background(CalendarTheme.surface, in: RoundedRectangle(cornerRadius: CalendarTheme.cornerRadius))
            }
        }
    }

    private func accessibleRow(_ item: AgendaItem, prefix: String) -> some View {
        Button {
            onOpenItem(item.origin)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: symbol(for: item.source))
                    .foregroundStyle(itemColor(item))
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                    Text(prefix)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, minHeight: CalendarTheme.minimumTapSize, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(prefix), \(AgendaAccessibilityDescription.build(for: item))")
    }

    private let timeGutterWidth: CGFloat = 40
    private let pointsPerHour: CGFloat = 52

    private var timelineHeight: CGFloat {
        CGFloat(max(1, snapshot.endHour - snapshot.startHour)) * pointsPerHour
    }

    private func minuteOffset(for date: Date, on day: LocalDay) -> CGFloat? {
        let start = day.startDate(in: calendar)
        guard let minutes = calendar.dateComponents([.minute], from: start, to: date).minute else {
            return nil
        }
        return CGFloat(minutes - snapshot.startHour * 60) / 60 * pointsPerHour
    }

    private func itemX(_ value: WeekPlannerTimedItem, dayIndex: Int, dayWidth: CGFloat) -> CGFloat {
        let columnWidth = eventWidth(value, dayWidth: dayWidth)
        return timeGutterWidth + CGFloat(dayIndex) * dayWidth + 3 + CGFloat(value.overlapColumn) * columnWidth
    }

    private func eventWidth(_ value: WeekPlannerTimedItem, dayWidth: CGFloat) -> CGFloat {
        max(18, (dayWidth - 6) / CGFloat(max(1, value.overlapColumnCount)))
    }

    private func select(day: LocalDay, item: AgendaItem, identifier: String) {
        onSelectDay(day)
        selectedItem = .init(id: identifier, item: item)
    }

    private func canOpen(_ origin: AgendaItemOrigin) -> Bool {
        switch origin {
        case .event, .reminder, .routine: true
        case .synthetic: false
        }
    }

    private func originIdentifier(_ origin: AgendaItemOrigin) -> String? {
        switch origin {
        case let .event(id), let .reminder(id): id
        case let .routine(id, _): id.uuidString
        case .synthetic: nil
        }
    }

    private func itemColor(_ item: AgendaItem) -> Color {
        item.category.flatMap { CalendarTheme.color(hex: $0.colorHex) }
            ?? CalendarTheme.sourceColor(item.source)
    }

    private func symbol(for source: AgendaSource) -> String {
        switch source {
        case .event: "calendar"
        case .task: "checkmark.circle"
        case .routine: "repeat"
        }
    }

    private func hourLabel(_ hour: Int) -> String {
        let date = calendar.date(bySettingHour: hour % 24, minute: 0, second: 0, of: now)
        return date?.formatted(date: .omitted, time: .shortened) ?? "\(hour):00"
    }

    private func timeRange(start: Date, end: Date) -> String {
        "\(start.formatted(date: .omitted, time: .shortened))–\(end.formatted(date: .omitted, time: .shortened))"
    }

    private func dayLabel(_ day: LocalDay) -> String {
        day.startDate(in: calendar).formatted(.dateTime.weekday(.wide).month(.wide).day())
    }
}

private struct Diamond: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.closeSubpath()
        return path
    }
}
