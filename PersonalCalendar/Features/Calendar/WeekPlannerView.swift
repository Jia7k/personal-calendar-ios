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
    let onSetTaskCompleted: (String, Bool) -> Void
    let onScheduleTaskTime: ((String) -> Void)?
    let onOpenEvent: ((CalendarEventSnapshot) -> Void)?

    init(
        snapshot: WeekPlannerSnapshot,
        selectedDay: LocalDay,
        now: Date,
        calendar: Calendar,
        onSelectDay: @escaping (LocalDay) -> Void,
        onOpenItem: @escaping (AgendaItemOrigin) -> Void,
        onSetTaskCompleted: @escaping (String, Bool) -> Void = { _, _ in },
        onScheduleTaskTime: ((String) -> Void)? = nil,
        onOpenEvent: ((CalendarEventSnapshot) -> Void)? = nil
    ) {
        self.snapshot = snapshot
        self.selectedDay = selectedDay
        self.now = now
        self.calendar = calendar
        self.onSelectDay = onSelectDay
        self.onOpenItem = onOpenItem
        self.onSetTaskCompleted = onSetTaskCompleted
        self.onScheduleTaskTime = onScheduleTaskTime
        self.onOpenEvent = onOpenEvent
    }

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            ScrollView {
                accessibleAgenda
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }
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
        GeometryReader { proxy in
            let dayWidth = WeekPlannerTimelineMetrics.dayWidth(
                availableWidth: proxy.size.width,
                timeGutterWidth: timeGutterWidth,
                dayCount: snapshot.days.count,
                maximumOverlapCount: maximumOverlapCount
            )
            let contentWidth = timeGutterWidth + dayWidth * CGFloat(snapshot.days.count)
            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                ZStack(alignment: .topLeading) {
                    hourRules(width: contentWidth)
                    dayDividers(dayWidth: dayWidth)
                    currentTimeLine(dayWidth: dayWidth)
                    ForEach(snapshot.timedItems) { value in
                        timedItem(value, dayWidth: dayWidth)
                    }
                }
                .frame(width: contentWidth, height: timelineHeight, alignment: .topLeading)
            }
        }
        .frame(height: min(timelineHeight, 440))
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
                let height = max(CalendarTheme.minimumTapSize, (minuteOffset(for: end, on: value.day) ?? y) - y)
                let width = eventWidth(value, dayWidth: dayWidth)
                Button {
                    selectEvent(item: value.item, identifier: value.id)
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
                .frame(width: width, height: height, alignment: .topLeading)
                .popover(
                    isPresented: eventPopoverBinding(
                        identifier: value.id,
                        item: value.item
                    ),
                    attachmentAnchor: .rect(.bounds),
                    arrowEdge: .top
                ) {
                    if let event = eventDetails(for: value.item) {
                        WeekEventDetailCard(
                            event: event,
                            calendar: calendar,
                            onClose: { selectedItem = nil },
                            onOpen: { openEvent(event) }
                        )
                        .presentationCompactAdaptation(.popover)
                    }
                }
                .alignmentGuide(.leading) { dimensions in
                    dimensions[.leading] - x
                }
                .alignmentGuide(.top) { dimensions in
                    dimensions[.top] - y
                }
                .accessibilityIdentifier("week-event-\(originIdentifier(value.item.origin) ?? value.item.id)")
                .accessibilityLabel("Event, \(value.item.title), \(timeRange(start: value.start, end: end)), \(dayLabel(value.day))")
                .accessibilityValue(selectedItem?.id == value.id ? "Expanded" : "Collapsed")
                .accessibilityHint("Shows full event details before opening the event.")
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
                .frame(width: WeekPlannerTimelineMetrics.taskWidth(dayWidth: dayWidth), height: CalendarTheme.minimumTapSize, alignment: .leading)
                .offset(x: timeGutterWidth + CGFloat(dayIndex) * dayWidth + 3, y: y - CalendarTheme.minimumTapSize / 2)
                .accessibilityIdentifier("week-task-\(originIdentifier(value.item.origin) ?? value.item.id)")
                .accessibilityLabel("Task due, \(value.item.title), \(value.start.formatted(date: .omitted, time: .shortened)), \(dayLabel(value.day))")
            }
        }
    }

    @ViewBuilder
    private var selectedDetail: some View {
        if let selectedItem, eventDetails(for: selectedItem.item) == nil {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedItem.item.title)
                        .font(.subheadline.weight(.semibold))
                    Text(AgendaAccessibilityDescription.scheduleDescription(selectedItem.item.placement))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let reminderID = reminderID(for: selectedItem.item),
                   selectedItem.item.allowsModification,
                   !selectedItem.item.isCompleted {
                    if let onScheduleTaskTime {
                        Button("Schedule") {
                            onScheduleTaskTime(reminderID)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .frame(
                            minWidth: CalendarTheme.minimumTapSize,
                            minHeight: CalendarTheme.minimumTapSize
                        )
                        .accessibilityIdentifier("week-task-schedule-\(reminderID)")
                        .accessibilityLabel("Schedule time for \(selectedItem.item.title)")
                        .accessibilityHint("Creates a separate calendar event and leaves the reminder unchanged.")
                    }
                    Button("Complete") {
                        self.selectedItem = nil
                        onSetTaskCompleted(reminderID, true)
                    }
                    .frame(minWidth: CalendarTheme.minimumTapSize, minHeight: CalendarTheme.minimumTapSize)
                    .accessibilityIdentifier("week-task-complete-\(reminderID)")
                }
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

                    ForEach(snapshot.allDayItems.filter { $0.day == day }) { value in
                        accessibleRow(
                            value.item,
                            day: day,
                            identifier: value.id,
                            prefix: "All day"
                        )
                    }
                    ForEach(timed) { value in
                        accessibleRow(
                            value.item,
                            day: day,
                            identifier: value.id,
                            prefix: value.kind == .event
                                ? "Event, \(timeRange(start: value.start, end: value.end ?? value.start))"
                                : "Task due, \(value.start.formatted(date: .omitted, time: .shortened))"
                        )
                    }
                    ForEach(routines) { item in
                        accessibleRow(
                            item,
                            day: day,
                            identifier: item.id,
                            prefix: "Later routine"
                        )
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

    private func accessibleRow(
        _ item: AgendaItem,
        day: LocalDay,
        identifier: String,
        prefix: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                if eventDetails(for: item) != nil {
                    selectEvent(item: item, identifier: identifier)
                } else {
                    onOpenItem(item.origin)
                }
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
            .accessibilityIdentifier(accessibilityIdentifier(for: item))
            .accessibilityLabel("\(prefix), \(AgendaAccessibilityDescription.build(for: item))")
            .accessibilityValue(
                eventDetails(for: item) == nil
                    ? ""
                    : (selectedItem?.id == identifier ? "Expanded" : "Collapsed")
            )
            .accessibilityHint(
                eventDetails(for: item) == nil
                    ? "Opens the item."
                    : "Shows full event details before opening the event."
            )

            if selectedItem?.id == identifier,
               let event = eventDetails(for: item) {
                WeekEventDetailCard(
                    event: event,
                    calendar: calendar,
                    isInline: true,
                    containerIdentifier: "week-event-detail-inline",
                    onClose: { selectedItem = nil },
                    onOpen: { openEvent(event) }
                )
            }

            if let reminderID = reminderID(for: item),
               item.allowsModification,
               !item.isCompleted {
                HStack(spacing: 8) {
                    if let onScheduleTaskTime {
                        Button("Schedule") {
                            onScheduleTaskTime(reminderID)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .frame(
                            minWidth: CalendarTheme.minimumTapSize,
                            minHeight: CalendarTheme.minimumTapSize
                        )
                        .accessibilityIdentifier("week-task-schedule-\(reminderID)")
                        .accessibilityLabel("Schedule time for \(item.title)")
                        .accessibilityHint("Creates a separate calendar event and leaves the reminder unchanged.")
                    }
                    Button("Complete") {
                        onSetTaskCompleted(reminderID, true)
                    }
                    .frame(
                        minWidth: CalendarTheme.minimumTapSize,
                        minHeight: CalendarTheme.minimumTapSize
                    )
                    .accessibilityIdentifier("week-task-complete-\(reminderID)")
                }
            }
        }
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
        WeekPlannerTimelineMetrics.eventWidth(
            dayWidth: dayWidth,
            overlapCount: value.overlapColumnCount
        )
    }

    private var maximumOverlapCount: Int {
        snapshot.timedItems
            .filter { $0.kind == .event }
            .map(\.overlapColumnCount)
            .max() ?? 1
    }

    private func select(day: LocalDay, item: AgendaItem, identifier: String) {
        onSelectDay(day)
        selectedItem = .init(id: identifier, item: item)
    }

    private func selectEvent(item: AgendaItem, identifier: String) {
        selectedItem = .init(id: identifier, item: item)
    }

    private func eventPopoverBinding(
        identifier: String,
        item: AgendaItem
    ) -> Binding<Bool> {
        Binding(
            get: {
                selectedItem?.id == identifier && eventDetails(for: item) != nil
            },
            set: { isPresented in
                if !isPresented, selectedItem?.id == identifier {
                    selectedItem = nil
                }
            }
        )
    }

    private func accessibilityIdentifier(for item: AgendaItem) -> String {
        let identifier = originIdentifier(item.origin) ?? item.id
        return switch item.source {
        case .event: "week-event-\(identifier)"
        case .task: "week-task-\(identifier)"
        case .routine: "week-routine-\(identifier)"
        }
    }

    private func eventDetails(for item: AgendaItem) -> CalendarEventSnapshot? {
        guard let key = WeekPlannerEventOccurrenceKey(item: item) else { return nil }
        return snapshot.eventDetailsByOccurrence[key]
    }

    private func openEvent(_ event: CalendarEventSnapshot) {
        selectedItem = nil
        Task { @MainActor in
            await Task.yield()
            if let onOpenEvent {
                onOpenEvent(event)
            } else {
                onOpenItem(.event(id: event.id))
            }
        }
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

    private func reminderID(for item: AgendaItem) -> String? {
        guard case let .reminder(id) = item.origin else { return nil }
        return id
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

private struct WeekEventDetailCard: View {
    let event: CalendarEventSnapshot
    let calendar: Calendar
    var isInline = false
    var containerIdentifier = "week-event-detail-card"
    let onClose: () -> Void
    let onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if isInline {
                HStack(alignment: .top, spacing: 12) {
                    title
                    Spacer(minLength: 8)
                    closeButton
                }
                detailRows
            } else {
                ZStack(alignment: .topTrailing) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            title
                            detailRows
                        }
                        .padding(.trailing, CalendarTheme.minimumTapSize + 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    closeButton
                        .accessibilitySortPriority(1)
                }
                .frame(maxHeight: 360)
            }

            Button("Open Event", action: onOpen)
                .buttonStyle(.borderedProminent)
                .tint(CalendarTheme.accent)
                .controlSize(.large)
                .frame(maxWidth: .infinity, minHeight: CalendarTheme.minimumTapSize)
                .accessibilityIdentifier("week-open-selected-item")
        }
        .padding(20)
        .frame(
            width: isInline ? nil : 320,
            height: isInline ? nil : 240,
            alignment: .leading
        )
        .frame(maxWidth: isInline ? .infinity : nil, alignment: .leading)
        .background(CalendarTheme.surface)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(containerIdentifier)
    }

    private var title: some View {
        Text(event.title)
            .font(.headline)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("week-event-detail-title")
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .frame(
                    width: CalendarTheme.minimumTapSize,
                    height: CalendarTheme.minimumTapSize
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close")
        .accessibilityIdentifier("week-event-detail-close")
    }

    private var timeDescription: String {
        if event.isAllDay {
            return "All day"
        }
        let start = event.start.formatted(date: .abbreviated, time: .shortened)
        let end: String
        if calendar.isDate(event.start, inSameDayAs: event.end) {
            end = event.end.formatted(date: .omitted, time: .shortened)
        } else {
            end = event.end.formatted(date: .abbreviated, time: .shortened)
        }
        return "\(start)–\(end)"
    }

    private var detailRows: some View {
        VStack(alignment: .leading, spacing: 10) {
            detailRow(systemImage: "clock", identifier: "week-event-detail-time") {
                Text(timeDescription)
            }

            if let location = normalized(event.location) {
                detailRow(systemImage: "mappin.and.ellipse", identifier: "week-event-detail-location") {
                    Text(location)
                }
            }

            detailRow(systemImage: "calendar", identifier: "week-event-detail-calendar") {
                Text(event.calendarTitle)
            }

            if let notes = normalized(event.notes) {
                Divider()
                detailRow(systemImage: "note.text", identifier: "week-event-detail-notes") {
                    Text(notes)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .font(.subheadline)
    }

    private func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func detailRow<Content: View>(
        systemImage: String,
        identifier: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(CalendarTheme.accent)
                .frame(width: 18)
                .accessibilityHidden(true)
            content()
                .accessibilityIdentifier(identifier)
        }
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
