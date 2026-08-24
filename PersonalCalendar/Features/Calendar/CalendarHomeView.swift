import SwiftUI

struct CalendarHomeView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var viewModel: CalendarViewModel
    @State private var editorPresentation: CalendarEditorPresentation?
    private let environment: AppEnvironment
    private let openSettings: @MainActor () -> Void
    private let revision: Int
    private var calendar: Calendar { .current }

    init(environment: AppEnvironment, revision: Int = 0, openSettings: @escaping @MainActor () -> Void = {}) {
        self.environment = environment
        self.openSettings = openSettings
        self.revision = revision
        let systemCalendar = Calendar.current
        _viewModel = State(initialValue: CalendarViewModel(today: LocalDay(date: .now, calendar: systemCalendar), calendarService: environment.calendar, remindersService: environment.reminders, routines: environment.routines, composer: environment.agendaComposer, settings: environment.settings, systemCalendar: systemCalendar))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    monthHeader
                    grid
                    DayTrayView(day: viewModel.selectedDay, agenda: viewModel.agenda, state: viewModel.trayState, isLoading: viewModel.isLoading, errorMessage: viewModel.errorMessage, sourceAccessNotices: viewModel.sourceAccessNotices, calendar: calendar, openSettings: openSettings, onSetState: setTray, onRetry: { Task { await viewModel.load() } }, onOpenItem: openAgendaItem, onSetTaskCompleted: { item, completed in Task { await viewModel.setTaskCompleted(item, completed: completed) } })
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .navigationTitle("Calendar")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Settings", systemImage: "gearshape", action: openSettings).frame(minWidth: CalendarTheme.minimumTapSize, minHeight: CalendarTheme.minimumTapSize) }
                ToolbarItem(placement: .topBarTrailing) { Button("New Event", systemImage: "plus", action: presentNewEvent).frame(minWidth: CalendarTheme.minimumTapSize, minHeight: CalendarTheme.minimumTapSize) }
            }
            .task(id: revision) { await viewModel.load() }
            .sheet(item: $editorPresentation) { presentation in
                switch presentation.content {
                case let .event(model, calendars, nilDestinationLabel, showsDelete):
                    EventEditorView(model: model, calendars: calendars, nilDestinationLabel: nilDestinationLabel, showsDelete: showsDelete, onDismiss: dismissEditor)
                        .task { await model.load() }
                case let .task(model, lists):
                    TaskEditorView(model: model, lists: lists, nilDestinationLabel: "Preserve Current", showsDelete: true, onDismiss: dismissEditor)
                }
            }
        }
    }

    private var monthHeader: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
            Button { Task { await viewModel.moveMonth(by: -1) } } label: { Image(systemName: "chevron.left") }.accessibilityLabel("Previous month").frame(minWidth: CalendarTheme.minimumTapSize, minHeight: CalendarTheme.minimumTapSize)
            Spacer()
            Text(viewModel.displayedMonth.startDate(in: calendar).formatted(.dateTime.month(.wide).year())).font(.title2.weight(.semibold))
            Spacer()
            Button { Task { await viewModel.moveMonth(by: 1) } } label: { Image(systemName: "chevron.right") }.accessibilityLabel("Next month").frame(minWidth: CalendarTheme.minimumTapSize, minHeight: CalendarTheme.minimumTapSize)
            }
            Button("Today") { Task { await viewModel.showToday() } }.frame(minWidth: CalendarTheme.minimumTapSize, minHeight: CalendarTheme.minimumTapSize)
        }
    }

    private var grid: some View {
        let builder = MonthGridBuilder(calendar: calendar)
        let cells = viewModel.trayState == .expanded
            ? builder.week(containing: viewModel.selectedDay, displayedMonth: viewModel.displayedMonth)
            : builder.days(containing: viewModel.displayedMonth)
        return MonthGridView(cells: cells, displayedMonth: viewModel.displayedMonth, selectedDay: viewModel.selectedDay, today: LocalDay(date: .now, calendar: calendar), agendaByDay: viewModel.visibleAgendas, calendar: calendar, onSelect: { day in Task { await viewModel.select(day) } })
            .accessibilityIdentifier(viewModel.trayState == .expanded ? "selected-week-strip" : "month-grid")
            .gesture(DragGesture(minimumDistance: 20).onEnded { value in
                if abs(value.translation.width) > abs(value.translation.height), abs(value.translation.width) >= 60 {
                    Task { await viewModel.moveMonth(by: value.translation.width < 0 ? 1 : -1) }
                } else if abs(value.translation.height) >= 60 {
                    setTray(value.translation.height < 0 ? .expanded : .resting)
                }
            })
    }

    private func setTray(_ state: TrayState) {
        if reduceMotion || environment.reduceMotionOverride { viewModel.setTray(state) }
        else { withAnimation(.easeInOut(duration: 0.2)) { viewModel.setTray(state) } }
    }

    private func presentNewEvent() {
        let dayStart = viewModel.selectedDay.startDate(in: calendar)
        let start = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: dayStart) ?? dayStart
        let end = calendar.date(byAdding: .hour, value: 1, to: start) ?? start.addingTimeInterval(3_600)
        let model = EventEditorViewModel.create(
            service: environment.calendar,
            savedDefaultCalendarID: environment.settings.defaultCalendarID,
            initialStart: start,
            initialEnd: end,
            onCommitted: { commit in finishEditorAndReload(operation: calendarOperation(for: commit)) }
        )
        let writable = environment.calendar.calendars().filter(\.allowsContentModifications)
        editorPresentation = .init(content: .event(model: model, calendars: writable, nilDestinationLabel: "System Default", showsDelete: false))
    }

    private func openAgendaItem(_ origin: AgendaItemOrigin) {
        switch origin {
        case let .event(displayID):
            let model = EventEditorViewModel.edit(
                displayID: displayID,
                service: environment.calendar,
                onCommitted: { commit in finishEditorAndReload(operation: calendarOperation(for: commit)) },
                onReconciliationNeeded: reconcileEditorWithoutDismissing
            )
            editorPresentation = .init(content: .event(model: model, calendars: environment.calendar.calendars(), nilDestinationLabel: "Preserve Current", showsDelete: true))
        case let .reminder(reminderID):
            let model = TaskEditorViewModel.editing(
                reminderID: reminderID,
                service: environment.reminders,
                onCommitted: { commit in finishEditorAndReload(operation: calendarOperation(for: commit)) },
                onReconciliationNeeded: reconcileEditorWithoutDismissing
            )
            editorPresentation = .init(content: .task(model: model, lists: environment.reminders.lists()))
        case .routine, .synthetic:
            break
        }
    }

    private func dismissEditor() {
        editorPresentation = nil
    }

    private func reconcileEditorWithoutDismissing() {
        Task { @MainActor in await viewModel.load() }
    }

    private func finishEditorAndReload(operation: CalendarEditorRefreshOperation) {
        Task { @MainActor in
            editorPresentation = nil
            await viewModel.refreshAfterEditorCommit(operation)
        }
    }

    private func calendarOperation(for commit: EventEditorCommit) -> CalendarEditorRefreshOperation {
        switch commit { case .deleted: .eventDeleted; case .created, .updated: .eventSaved }
    }

    private func calendarOperation(for commit: TaskEditorCommit) -> CalendarEditorRefreshOperation {
        switch commit { case .deleted: .taskDeleted; case .created, .updated: .taskSaved }
    }
}

private struct CalendarEditorPresentation: Identifiable {
    enum Content {
        case event(model: EventEditorViewModel, calendars: [CalendarDescriptor], nilDestinationLabel: String, showsDelete: Bool)
        case task(model: TaskEditorViewModel, lists: [ReminderListDescriptor])
    }

    let id = UUID()
    let content: Content
}
