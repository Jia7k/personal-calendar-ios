import SwiftUI

struct CalendarHomeView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var viewModel: CalendarViewModel
    @State private var editorPresentation: CalendarEditorPresentation?
    @State private var refreshRegistrationID = UUID()
    private let environment: AppEnvironment
    private let openSettings: @MainActor () -> Void
    private let onOpenRoutine: @MainActor (UUID) -> Void
    private let revision: AppContentRevision
    private let quickEntryRefresh: QuickEntryRefreshSignal?
    private var calendar: Calendar { .current }

    init(
        environment: AppEnvironment,
        revision: AppContentRevision = .init(lifecycle: 0, profileScope: 0),
        quickEntryRefresh: QuickEntryRefreshSignal? = nil,
        openSettings: @escaping @MainActor () -> Void = {},
        onOpenRoutine: @escaping @MainActor (UUID) -> Void = { _ in }
    ) {
        self.environment = environment
        self.openSettings = openSettings
        self.onOpenRoutine = onOpenRoutine
        self.revision = revision
        self.quickEntryRefresh = quickEntryRefresh
        let systemCalendar = Calendar.current
        let profileScopes = environment.profileScopes
        let profileSelection = environment.profileSelection
        _viewModel = State(initialValue: CalendarViewModel(
            today: LocalDay(date: .now, calendar: systemCalendar),
            calendarService: environment.calendar,
            remindersService: environment.reminders,
            routines: environment.routines,
            composer: environment.agendaComposer,
            settings: environment.settings,
            currentScope: {
                try profileScopes.resolve(profileSelection.activeIdentity)
            },
            systemCalendar: systemCalendar
        ))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                displayModePicker
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                switch viewModel.displayMode {
                case .month:
                    monthContent
                case .week:
                    weekContent
                }
            }
            .background(CalendarTheme.background)
            .navigationTitle("Calendar")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Settings", systemImage: "gearshape", action: openSettings).frame(minWidth: CalendarTheme.minimumTapSize, minHeight: CalendarTheme.minimumTapSize) }
                ToolbarItem(placement: .topBarTrailing) {
                    ProfileSelectorToolbar(selection: environment.profileSelection)
                }
            }
            .task(id: revision) { await viewModel.load() }
            .task(id: quickEntryRefresh?.id) {
                guard let quickEntryRefresh else { return }
                await viewModel.refreshAfterQuickEntry(quickEntryRefresh.outcome)
            }
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
        .onAppear {
            environment.agendaRefreshRegistry.register(id: refreshRegistrationID) { [weak viewModel] in
                await viewModel?.refreshForExternalChange()
            }
        }
        .onDisappear {
            environment.agendaRefreshRegistry.unregister(id: refreshRegistrationID)
        }
    }

    private var displayModePicker: some View {
        Picker("Calendar view", selection: Binding(
            get: { viewModel.displayMode },
            set: { mode in Task { await viewModel.setDisplayMode(mode) } }
        )) {
            Text("Month")
                .tag(CalendarDisplayMode.month)
                .accessibilityIdentifier("calendar-mode-month")
            Text("Week")
                .tag(CalendarDisplayMode.week)
                .accessibilityIdentifier("calendar-mode-week")
        }
        .pickerStyle(.segmented)
    }

    private var monthContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 16) {
                    periodHeader
                    grid
                    DayTrayView(day: viewModel.selectedDay, agenda: viewModel.agenda, state: viewModel.trayState, isLoading: viewModel.isLoading, errorMessage: viewModel.errorMessage, sourceAccessNotices: viewModel.sourceAccessNotices, calendar: calendar, openSettings: openSettings, onSetState: setTray, onRetry: { Task { await viewModel.load() } }, onOpenItem: openAgendaItem, onSetTaskCompleted: { item, completed in Task { await viewModel.setTaskCompleted(item, completed: completed) } })
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .onChange(of: viewModel.selectedDay) { _, selectedDay in
                guard dynamicTypeSize.isAccessibilitySize else { return }
                proxy.scrollTo(selectedDay, anchor: .center)
            }
        }
    }

    private var weekContent: some View {
        VStack(spacing: 12) {
            periodHeader
                .padding(.horizontal, 16)
            weekStatus
                .padding(.horizontal, 16)
            WeekPlannerView(
                snapshot: viewModel.weekPlanner,
                selectedDay: viewModel.selectedDay,
                now: .now,
                calendar: calendar,
                onSelectDay: { day in Task { await viewModel.select(day) } },
                onOpenItem: openAgendaItem
            )
        }
        .padding(.vertical, 12)
    }

    @ViewBuilder private var weekStatus: some View {
        if viewModel.isLoading {
            ProgressView("Loading your week")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        if let errorMessage = viewModel.errorMessage {
            HStack {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                Spacer()
                Button("Retry") { Task { await viewModel.load() } }
            }
        }
        ForEach(viewModel.sourceAccessNotices) { notice in
            HStack {
                Label(notice.message, systemImage: "lock.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
                if notice.canOpenSettings {
                    Button("Open Settings", action: openSettings)
                        .accessibilityIdentifier(notice.settingsActionIdentifier)
                }
            }
        }
    }

    private var periodHeader: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button { Task { await viewModel.movePeriod(by: -1) } } label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel(viewModel.displayMode == .week ? "Previous week" : "Previous month")
                    .frame(minWidth: CalendarTheme.minimumTapSize, minHeight: CalendarTheme.minimumTapSize)
                Spacer()
                Text(periodTitle).font(.title2.weight(.semibold))
                Spacer()
                Button { Task { await viewModel.movePeriod(by: 1) } } label: { Image(systemName: "chevron.right") }
                    .accessibilityLabel(viewModel.displayMode == .week ? "Next week" : "Next month")
                    .frame(minWidth: CalendarTheme.minimumTapSize, minHeight: CalendarTheme.minimumTapSize)
            }
            Button("Today") { Task { await viewModel.showToday() } }.frame(minWidth: CalendarTheme.minimumTapSize, minHeight: CalendarTheme.minimumTapSize)
        }
    }

    private var periodTitle: String {
        switch viewModel.displayMode {
        case .month:
            return viewModel.displayedMonth.startDate(in: calendar)
                .formatted(.dateTime.month(.wide).year())
        case .week:
            guard let first = viewModel.visibleDays.first,
                  let last = viewModel.visibleDays.last else { return "Week" }
            let start = first.startDate(in: calendar)
                .formatted(.dateTime.month(.abbreviated).day())
            let end = last.startDate(in: calendar)
                .formatted(.dateTime.month(.abbreviated).day().year())
            return "\(start) – \(end)"
        }
    }

    private var grid: some View {
        let builder = MonthGridBuilder(calendar: calendar)
        let showsSelectedWeek = viewModel.trayState == .expanded || dynamicTypeSize.isAccessibilitySize
        let cells = showsSelectedWeek
            ? builder.week(containing: viewModel.selectedDay, displayedMonth: viewModel.displayedMonth)
            : builder.days(containing: viewModel.displayedMonth)
        return MonthGridView(cells: cells, displayedMonth: viewModel.displayedMonth, selectedDay: viewModel.selectedDay, today: LocalDay(date: .now, calendar: calendar), agendaByDay: viewModel.visibleAgendas, calendar: calendar, onSelect: { day in Task { await viewModel.select(day) } })
            .accessibilityIdentifier(showsSelectedWeek ? "selected-week-strip" : "month-grid")
            .gesture(DragGesture(minimumDistance: 20).onEnded { value in
                if abs(value.translation.width) > abs(value.translation.height), abs(value.translation.width) >= 60 {
                    Task { await viewModel.movePeriod(by: value.translation.width < 0 ? 1 : -1) }
                } else if abs(value.translation.height) >= 60 {
                    setTray(value.translation.height < 0 ? .expanded : .resting)
                }
            })
    }

    private func setTray(_ state: TrayState) {
        if reduceMotion || environment.reduceMotionOverride { viewModel.setTray(state) }
        else { withAnimation(.easeInOut(duration: 0.2)) { viewModel.setTray(state) } }
    }

    private func openAgendaItem(_ origin: AgendaItemOrigin) {
        switch origin {
        case let .event(displayID):
            let model = EventEditorViewModel.edit(
                displayID: displayID,
                service: environment.calendar,
                categories: environment.categories,
                onCommitted: { commit in finishEditorAndReload(operation: calendarOperation(for: commit)) },
                onReconciliationNeeded: reconcileEditorWithoutDismissing
            )
            editorPresentation = .init(content: .event(model: model, calendars: environment.calendar.calendars(), nilDestinationLabel: "Preserve Current", showsDelete: true))
        case let .reminder(reminderID):
            let model = TaskEditorViewModel.editing(
                reminderID: reminderID,
                service: environment.reminders,
                categories: environment.categories,
                onCommitted: { commit in finishEditorAndReload(operation: calendarOperation(for: commit)) },
                onReconciliationNeeded: reconcileEditorWithoutDismissing
            )
            editorPresentation = .init(content: .task(model: model, lists: environment.reminders.lists()))
        case let .routine(id, _):
            onOpenRoutine(id)
        case .synthetic:
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
