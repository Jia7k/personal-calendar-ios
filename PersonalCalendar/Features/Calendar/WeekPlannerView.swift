import SwiftUI

struct WeekPlannerView: View {
    private struct SelectedItem: Identifiable {
        let id: String
        let item: AgendaItem
    }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var selectedItem: SelectedItem?
    @State private var selectedEventStackID: String?
    @State private var selectedStackEventID: String?

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
        Group {
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
        .onChange(of: snapshot) { _, updatedSnapshot in
            reconcileSelection(in: updatedSnapshot)
        }
    }

    private var sevenDayTimeline: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: 12) {
                    allDayStrip
                    dayHeaders
                    timeline
                    selectedDetail
                    laterStrip
                }
                .padding(.bottom, 12)
            }
            .accessibilityElement(children: .contain)
        }
    }

    @ViewBuilder
    private var allDayStrip: some View {
        if !snapshot.allDayItems.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("All day")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(snapshot.days, id: \.self) { day in
                        let items = snapshot.allDayItems.filter { $0.day == day }
                        if !items.isEmpty {
                            HStack(alignment: .top, spacing: 8) {
                                Text(day.startDate(in: calendar), format: .dateTime.weekday(.narrow))
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(day == selectedDay ? CalendarTheme.accent : .secondary)
                                    .frame(
                                        width: timeGutterWidth,
                                        height: CalendarTheme.minimumTapSize
                                    )
                                VStack(alignment: .leading, spacing: 4) {
                                    ForEach(items) { value in
                                        Button {
                                            select(day: day, item: value.item, identifier: value.id)
                                        } label: {
                                            Text(value.item.title)
                                                .font(.caption)
                                                .lineLimit(2)
                                                .frame(
                                                    maxWidth: .infinity,
                                                    minHeight: CalendarTheme.minimumTapSize,
                                                    alignment: .leading
                                                )
                                                .padding(.horizontal, 10)
                                                .background(
                                                    itemColor(value.item).opacity(0.14),
                                                    in: RoundedRectangle(cornerRadius: 9)
                                                )
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityIdentifier(
                                            "week-all-day-\(originIdentifier(value.item.origin) ?? value.item.id)"
                                        )
                                        .accessibilityLabel("All day, \(value.item.title), \(dayLabel(day))")
                                    }
                                }
                            }
                        }
                    }
                }
                .accessibilityIdentifier("week-all-day-list")
            }
            .padding(.horizontal, 4)
            .accessibilityElement(children: .contain)
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
            ZStack(alignment: .topLeading) {
                hourRules(width: contentWidth)
                dayDividers(dayWidth: dayWidth)
                currentTimeLine(dayWidth: dayWidth)
                ForEach(snapshot.collisionStacks) { stack in
                    if stack.items.count == 1,
                       let item = stack.items.first,
                       item.kind == .taskDue {
                        timedTask(item, dayWidth: dayWidth)
                    } else {
                        timedCollisionStack(stack, dayWidth: dayWidth)
                    }
                }
            }
            .frame(width: contentWidth, height: timelineContentHeight, alignment: .topLeading)
        }
        .frame(height: timelineContentHeight)
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
                    .frame(width: 1, height: timelineContentHeight)
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
    private func timedCollisionStack(
        _ stack: WeekPlannerTimedCollisionStack,
        dayWidth: CGFloat
    ) -> some View {
        if let dayIndex = snapshot.days.firstIndex(of: stack.day),
           let y = minuteOffset(for: stack.renderedStart, on: stack.day),
           let first = stack.items.first {
            let x = timeGutterWidth + CGFloat(dayIndex) * dayWidth + 1
            let height = max(
                CalendarTheme.minimumTapSize,
                (minuteOffset(for: stack.renderedEnd, on: stack.day) ?? y) - y
            )
            let width = WeekPlannerTimelineMetrics.stackedEventWidth(dayWidth: dayWidth)
            let presentation = WeekPlannerCompactCardPresentation.resolve(
                height: height,
                itemCount: stack.items.count
            )
            Button {
                selectCollisionStack(stack)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(first.item.title)
                        .font(.caption.weight(.semibold))
                        .lineLimit(presentation.titleLineLimit)

                    if presentation.showsTime || stack.items.count > 1 {
                        HStack(alignment: .center, spacing: 2) {
                            if presentation.showsTime {
                                Text(stack.start.formatted(date: .omitted, time: .shortened))
                                    .font(.caption2)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                            if stack.items.count > 1 {
                                Text("+\(stack.items.count - 1)")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(CalendarTheme.accent, in: Capsule())
                            }
                        }
                    }
                }
                .foregroundStyle(.primary)
                .padding(5)
                .frame(maxWidth: .infinity, minHeight: height, alignment: .topLeading)
                .background(itemColor(first.item).opacity(0.22), in: RoundedRectangle(cornerRadius: 7))
                .overlay {
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(itemColor(first.item).opacity(0.7), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .frame(width: width, height: height, alignment: .topLeading)
            .popover(
                isPresented: collisionStackPopoverBinding(identifier: stack.id),
                attachmentAnchor: .point(.top),
                arrowEdge: .top
            ) {
                collisionStackPopover(stack)
                    .presentationCompactAdaptation(.popover)
            }
            .alignmentGuide(.leading) { dimensions in
                dimensions[.leading] - x
            }
            .alignmentGuide(.top) { dimensions in
                dimensions[.top] - y
            }
            .accessibilityIdentifier(collisionStackIdentifier(stack))
            .accessibilityLabel(collisionStackAccessibilityLabel(stack))
            .accessibilityValue(selectedEventStackID == stack.id ? "Expanded" : "Collapsed")
            .accessibilityHint(
                stack.items.count > 1
                    ? "Shows the overlapping items to choose from."
                    : "Shows full event details before opening the event."
            )
        }
    }

    @ViewBuilder
    private func timedTask(_ value: WeekPlannerTimedItem, dayWidth: CGFloat) -> some View {
        if let dayIndex = snapshot.days.firstIndex(of: value.day),
           let y = minuteOffset(for: value.start, on: value.day) {
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
            .frame(
                width: WeekPlannerTimelineMetrics.taskWidth(dayWidth: dayWidth),
                height: CalendarTheme.minimumTapSize,
                alignment: .leading
            )
            .offset(
                x: timeGutterWidth + CGFloat(dayIndex) * dayWidth + 3,
                y: WeekPlannerTimelineMetrics.taskTopOffset(minuteOffset: y)
            )
            .accessibilityIdentifier("week-task-\(originIdentifier(value.item.origin) ?? value.item.id)")
            .accessibilityLabel("Task due, \(value.item.title), \(value.start.formatted(date: .omitted, time: .shortened)), \(dayLabel(value.day))")
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
    private let pointsPerHour = WeekPlannerTimelineMetrics.pointsPerHour

    private var timelineHeight: CGFloat {
        CGFloat(max(1, snapshot.endHour - snapshot.startHour)) * pointsPerHour
    }

    private var timelineContentHeight: CGFloat {
        WeekPlannerTimelineMetrics.contentHeight(baseHeight: timelineHeight)
    }

    private func minuteOffset(for date: Date, on day: LocalDay) -> CGFloat? {
        let start = day.startDate(in: calendar)
        guard let minutes = calendar.dateComponents([.minute], from: start, to: date).minute else {
            return nil
        }
        return CGFloat(minutes - snapshot.startHour * 60) / 60 * pointsPerHour
    }

    private var maximumOverlapCount: Int {
        snapshot.timedItems
            .filter { $0.kind == .event }
            .map(\.overlapColumnCount)
            .max() ?? 1
    }

    private func select(day: LocalDay, item: AgendaItem, identifier: String) {
        selectedEventStackID = nil
        selectedStackEventID = nil
        onSelectDay(day)
        selectedItem = .init(id: identifier, item: item)
    }

    private func selectEvent(item: AgendaItem, identifier: String) {
        selectedEventStackID = nil
        selectedStackEventID = nil
        selectedItem = .init(id: identifier, item: item)
    }

    private func selectCollisionStack(_ stack: WeekPlannerTimedCollisionStack) {
        selectedItem = nil
        selectedEventStackID = stack.id
        selectedStackEventID = stack.items.count == 1 ? stack.items.first?.id : nil
    }

    private func reconcileSelection(in updatedSnapshot: WeekPlannerSnapshot) {
        if let selectedItem {
            if let currentItem = currentSelectedItem(in: updatedSnapshot, matching: selectedItem) {
                self.selectedItem = .init(id: selectedItem.id, item: currentItem)
            } else {
                self.selectedItem = nil
            }
        }

        guard let selectedEventStackID else { return }
        guard let currentStack = updatedSnapshot.collisionStacks.first(where: { $0.id == selectedEventStackID }) else {
            self.selectedEventStackID = nil
            selectedStackEventID = nil
            return
        }
        if let selectedStackEventID,
           !currentStack.items.contains(where: { $0.id == selectedStackEventID }) {
            self.selectedStackEventID = nil
        }
    }

    private func currentSelectedItem(
        in updatedSnapshot: WeekPlannerSnapshot,
        matching selection: SelectedItem
    ) -> AgendaItem? {
        if let match = updatedSnapshot.allDayItems.first(where: {
            $0.id == selection.id && $0.item.origin == selection.item.origin
        }) {
            return match.item
        }
        if let match = updatedSnapshot.timedItems.first(where: {
            $0.id == selection.id && $0.item.origin == selection.item.origin
        }) {
            return match.item
        }
        return updatedSnapshot.laterItems.first(where: {
            $0.id == selection.id && $0.origin == selection.item.origin
        })
    }

    private func collisionStackPopoverBinding(identifier: String) -> Binding<Bool> {
        Binding(
            get: { selectedEventStackID == identifier },
            set: { isPresented in
                if !isPresented, selectedEventStackID == identifier {
                    selectedEventStackID = nil
                    selectedStackEventID = nil
                }
            }
        )
    }

    @ViewBuilder
    private func collisionStackPopover(_ stack: WeekPlannerTimedCollisionStack) -> some View {
        if let selectedStackEventID,
           let item = stack.items.first(where: { $0.id == selectedStackEventID }) {
            if let event = eventDetails(for: item.item) {
                WeekEventDetailCard(
                    event: event,
                    calendar: calendar,
                    onClose: closeCollisionStack,
                    onOpen: { openEvent(event) }
                )
            } else {
                collisionTaskDetail(item)
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text("Overlapping items")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Text("Choose an event or task to see its actions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ScrollView(.vertical) {
                    LazyVStack(spacing: 6) {
                        ForEach(stack.items) { value in
                            Button {
                                selectedStackEventID = value.id
                            } label: {
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Image(systemName: symbol(for: value.item.source))
                                        .foregroundStyle(itemColor(value.item))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(value.item.title)
                                            .font(.subheadline.weight(.semibold))
                                            .lineLimit(2)
                                        Text(timeRange(start: value.start, end: value.end ?? value.start))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 4)
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                                .frame(
                                    maxWidth: .infinity,
                                    minHeight: CalendarTheme.minimumTapSize,
                                    alignment: .leading
                                )
                                .padding(.horizontal, 10)
                                .background(
                                    itemColor(value.item).opacity(0.14),
                                    in: RoundedRectangle(cornerRadius: 9)
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier(
                                collisionChoiceIdentifier(value)
                            )
                            .accessibilityLabel(
                                "\(value.item.title), \(timeRange(start: value.start, end: value.end ?? value.start))"
                            )
                        }
                    }
                }
            }
            .padding(16)
            .frame(
                width: WeekPlannerPopupMetrics.width,
                height: WeekPlannerPopupMetrics.height,
                alignment: .topLeading
            )
            .background(CalendarTheme.surface)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("week-event-stack-picker")
        }
    }

    private func collisionTaskDetail(_ value: WeekPlannerTimedItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(value.item.title)
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    Text("Due \(value.start.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Button(action: closeCollisionStack) {
                    Image(systemName: "xmark")
                        .frame(
                            width: CalendarTheme.minimumTapSize,
                            height: CalendarTheme.minimumTapSize
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
                .accessibilityIdentifier("week-task-stack-close")
            }

            ScrollView(.vertical) {
                VStack(spacing: 8) {
                    if let reminderID = reminderID(for: value.item),
                       value.item.allowsModification,
                       !value.item.isCompleted {
                        if let onScheduleTaskTime {
                            Button("Schedule Time") {
                                performAfterClosingCollision {
                                    onScheduleTaskTime(reminderID)
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                            .frame(maxWidth: .infinity, minHeight: CalendarTheme.minimumTapSize)
                            .accessibilityIdentifier("week-task-schedule-\(reminderID)")
                        }
                        Button("Complete") {
                            closeCollisionStack()
                            onSetTaskCompleted(reminderID, true)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .frame(maxWidth: .infinity, minHeight: CalendarTheme.minimumTapSize)
                        .accessibilityIdentifier("week-task-complete-\(reminderID)")
                    }
                    if canOpen(value.item.origin) {
                        Button("Open Task") {
                            performAfterClosingCollision {
                                onOpenItem(value.item.origin)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(CalendarTheme.accent)
                        .controlSize(.large)
                        .frame(maxWidth: .infinity, minHeight: CalendarTheme.minimumTapSize)
                        .accessibilityIdentifier("week-open-selected-item")
                    }
                }
            }
        }
        .padding(16)
        .frame(
            width: WeekPlannerPopupMetrics.width,
            height: WeekPlannerPopupMetrics.height,
            alignment: .topLeading
        )
        .background(CalendarTheme.surface)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("week-task-stack-detail")
    }

    private func closeCollisionStack() {
        selectedEventStackID = nil
        selectedStackEventID = nil
    }

    private func performAfterClosingCollision(_ action: @escaping @MainActor () -> Void) {
        closeCollisionStack()
        Task { @MainActor in
            await Task.yield()
            action()
        }
    }

    private func collisionChoiceIdentifier(_ value: WeekPlannerTimedItem) -> String {
        let identifier = originIdentifier(value.item.origin) ?? value.item.id
        return value.kind == .event
            ? "week-event-choice-\(identifier)"
            : "week-task-choice-\(identifier)"
    }

    private func collisionStackIdentifier(_ stack: WeekPlannerTimedCollisionStack) -> String {
        let firstEvent = stack.items.first(where: { $0.kind == .event })
        let first = firstEvent ?? stack.items.first
        let firstIdentifier = first.flatMap { originIdentifier($0.item.origin) }
            ?? first?.item.id
            ?? stack.id
        if stack.items.count == 1 {
            return first?.kind == .taskDue
                ? "week-task-\(firstIdentifier)"
                : "week-event-\(firstIdentifier)"
        }
        return firstEvent == nil
            ? "week-task-stack-\(firstIdentifier)"
            : "week-event-stack-\(firstIdentifier)"
    }

    private func collisionStackAccessibilityLabel(_ stack: WeekPlannerTimedCollisionStack) -> String {
        guard let first = stack.items.first else { return "Scheduled item" }
        if stack.items.count == 1 {
            return "Event, \(first.item.title), \(timeRange(start: stack.start, end: stack.end)), \(dayLabel(stack.day))"
        }
        return "\(stack.items.count) overlapping items, \(timeRange(start: stack.start, end: stack.end)), \(dayLabel(stack.day))"
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
        selectedEventStackID = nil
        selectedStackEventID = nil
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

private enum WeekPlannerPopupMetrics {
    static let width: CGFloat = 340
    static let height: CGFloat = 260
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
                .frame(maxHeight: .infinity, alignment: .top)
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
            width: isInline ? nil : WeekPlannerPopupMetrics.width,
            height: isInline ? nil : WeekPlannerPopupMetrics.height,
            alignment: .topLeading
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
