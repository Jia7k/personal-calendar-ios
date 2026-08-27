import SwiftUI

struct CalendarHomeView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var viewModel: CalendarViewModel
    @State private var editorPresentation: CalendarEditorPresentation?
    @State private var timeBlockPresentation: TaskTimeBlockSession?
    @State private var taskActionError: String?
    @State private var showingSearch = false
    @State private var showingJumpToDate = false
    @State private var jumpDate = Date()
    @State private var jumpScrollDay: LocalDay?
    @State private var isTransitioningPresentation = false
    @State private var presentationGeneration = 0
    @State private var refreshRegistrationID = UUID()
    @State private var deepLinkResolver = CalendarDeepLinkResolver()
    private let environment: AppEnvironment
    private let openSettings: @MainActor () -> Void
    private let onOpenRoutine: @MainActor (UUID) -> Void
    private let revision: AppContentRevision
    private let quickEntryRefresh: QuickEntryRefreshSignal?
    private let calendarDeepLink: CalendarDeepLinkSignal?
    private let onDeepLinkHandled: @MainActor (UUID, Bool) -> Void
    private let onPresentationChanged: @MainActor (Bool) -> Void
    private let calendar: Calendar

    init(
        environment: AppEnvironment,
        revision: AppContentRevision = .init(lifecycle: 0, profileScope: 0),
        quickEntryRefresh: QuickEntryRefreshSignal? = nil,
        calendarDeepLink: CalendarDeepLinkSignal? = nil,
        openSettings: @escaping @MainActor () -> Void = {},
        onOpenRoutine: @escaping @MainActor (UUID) -> Void = { _ in },
        onDeepLinkHandled: @escaping @MainActor (UUID, Bool) -> Void = { _, _ in },
        onPresentationChanged: @escaping @MainActor (Bool) -> Void = { _ in }
    ) {
        let systemCalendar = Calendar.current
        self.environment = environment
        self.calendar = systemCalendar
        self.openSettings = openSettings
        self.onOpenRoutine = onOpenRoutine
        self.revision = revision
        self.quickEntryRefresh = quickEntryRefresh
        self.calendarDeepLink = calendarDeepLink
        self.onDeepLinkHandled = onDeepLinkHandled
        self.onPresentationChanged = onPresentationChanged
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
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Search", systemImage: "magnifyingglass") {
                        guard editorPresentation == nil,
                              timeBlockPresentation == nil,
                              !showingJumpToDate,
                              calendarDeepLink == nil,
                              !isTransitioningPresentation else { return }
                        showingSearch = true
                        onPresentationChanged(true)
                    }
                    .frame(minWidth: CalendarTheme.minimumTapSize, minHeight: CalendarTheme.minimumTapSize)
                    .accessibilityIdentifier("calendar-search-open")
                    Button("Jump to Date", systemImage: "calendar.badge.clock") {
                        guard editorPresentation == nil,
                              timeBlockPresentation == nil,
                              !showingSearch,
                              calendarDeepLink == nil,
                              !isTransitioningPresentation else { return }
                        jumpDate = viewModel.selectedDay.startDate(in: calendar)
                        showingJumpToDate = true
                        onPresentationChanged(true)
                    }
                    .frame(minWidth: CalendarTheme.minimumTapSize, minHeight: CalendarTheme.minimumTapSize)
                    .accessibilityIdentifier("calendar-jump-open")
                    ProfileSelectorToolbar(selection: environment.profileSelection)
                }
            }
            .navigationDestination(isPresented: $showingSearch) {
                CalendarSearchView(
                    environment: environment,
                    onSelect: selectSearchResult,
                    onOpenSettings: openSettings
                )
            }
            .task(id: revision) {
                guard calendarDeepLink == nil else { return }
                await viewModel.load()
            }
            .task(id: quickEntryRefresh?.id) {
                guard let quickEntryRefresh else { return }
                await viewModel.refreshAfterQuickEntry(quickEntryRefresh.outcome)
            }
            .task(id: CalendarDeepLinkProcessingKey(
                signalID: calendarDeepLink?.id,
                editorID: editorPresentation?.id,
                timeBlockID: timeBlockPresentation?.id,
                showsSearch: showingSearch,
                showsJumpToDate: showingJumpToDate
            )) {
                await handleCalendarDeepLink()
            }
            .onChange(
                of: editorPresentation != nil
                    || timeBlockPresentation != nil
                    || showingSearch
                    || showingJumpToDate
                    || isTransitioningPresentation,
                initial: true
            ) { _, isPresented in
                presentationGeneration &+= 1
                onPresentationChanged(isPresented)
            }
            .sheet(item: $editorPresentation) { presentation in
                switch presentation.content {
                case let .event(model, calendars, nilDestinationLabel, showsDelete):
                    EventEditorView(model: model, calendars: calendars, nilDestinationLabel: nilDestinationLabel, showsDelete: showsDelete, onDismiss: dismissEditor)
                        .task { await model.load() }
                case let .task(model, lists):
                    TaskEditorView(
                        model: model,
                        lists: lists,
                        nilDestinationLabel: "Preserve Current",
                        showsDelete: true,
                        makeTimeBlockSession: {
                            guard let task = model.schedulingSnapshot,
                                  !task.isCompleted else { return nil }
                            return TaskTimeBlockSession.make(
                                task: task,
                                environment: environment
                            )
                        },
                        onDismiss: dismissEditor
                    )
                }
            }
            .sheet(item: $timeBlockPresentation) { session in
                TaskTimeBlockView(
                    model: session.model,
                    profiles: session.profiles,
                    resolveProfile: session.resolveProfile,
                    onSaved: session.onSaved,
                    onDismiss: dismissTimeBlock
                )
            }
            .sheet(isPresented: $showingJumpToDate) {
                jumpToDateSheet
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
            .task {
                guard dynamicTypeSize.isAccessibilitySize else { return }
                await Task.yield()
                proxy.scrollTo(viewModel.selectedDay, anchor: .center)
            }
            .task(id: jumpScrollDay) {
                guard let jumpScrollDay else { return }
                await Task.yield()
                proxy.scrollTo(jumpScrollDay, anchor: .center)
                self.jumpScrollDay = nil
            }
        }
    }

    private var jumpToDateSheet: some View {
        NavigationStack {
            Form {
                DatePicker(
                    "Date",
                    selection: $jumpDate,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .accessibilityIdentifier("calendar-jump-date-picker")
            }
            .navigationTitle("Jump to Date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingJumpToDate = false }
                        .frame(minWidth: CalendarTheme.minimumTapSize, minHeight: CalendarTheme.minimumTapSize)
                        .accessibilityIdentifier("calendar-jump-cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Jump", action: jumpToChosenDate)
                        .frame(minWidth: CalendarTheme.minimumTapSize, minHeight: CalendarTheme.minimumTapSize)
                        .accessibilityIdentifier("calendar-jump-confirm")
                }
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
                onOpenItem: openAgendaItem,
                onSetTaskCompleted: { reminderID, completed in
                    Task {
                        await viewModel.setTaskCompleted(
                            reminderID: reminderID,
                            completed: completed
                        )
                    }
                },
                onScheduleTaskTime: { reminderID in
                    presentTimeBlock(reminderID: reminderID)
                }
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
        if let taskActionError {
            Label(taskActionError, systemImage: "exclamationmark.triangle")
                .font(.footnote)
                .foregroundStyle(.secondary)
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
        guard timeBlockPresentation == nil else { return }
        let capturedProfileIdentity = environment.profileSelection.activeIdentity
        let capturedScope = try? environment.profileScopes.resolve(capturedProfileIdentity)
        switch origin {
        case let .event(displayID):
            let model = EventEditorViewModel.edit(
                displayID: displayID,
                service: environment.calendar,
                categories: environment.categories,
                duplicateDestinationCalendarIDs: capturedScope?.calendarIDs ?? [],
                resolveDuplicateDestinationCalendarIDs: {
                    try environment.profileScopes
                        .resolve(capturedProfileIdentity).calendarIDs
                },
                onCommitted: { commit in finishEditorAndReload(operation: calendarOperation(for: commit)) },
                onReconciliationNeeded: reconcileEditorWithoutDismissing
            )
            editorPresentation = .init(content: .event(model: model, calendars: environment.calendar.calendars(), nilDestinationLabel: "Preserve Current", showsDelete: true))
            onPresentationChanged(true)
        case let .reminder(reminderID):
            let model = TaskEditorViewModel.editing(
                reminderID: reminderID,
                service: environment.reminders,
                categories: environment.categories,
                duplicateDestinationListIDs: capturedScope?.reminderListIDs ?? [],
                resolveDuplicateDestinationListIDs: {
                    try environment.profileScopes
                        .resolve(capturedProfileIdentity).reminderListIDs
                },
                onCommitted: { commit in finishEditorAndReload(operation: calendarOperation(for: commit)) },
                onReconciliationNeeded: reconcileEditorWithoutDismissing
            )
            editorPresentation = .init(content: .task(model: model, lists: environment.reminders.lists()))
            onPresentationChanged(true)
        case let .routine(id, _):
            onOpenRoutine(id)
        case .synthetic:
            break
        }
    }

    private func selectSearchResult(_ origin: AgendaItemOrigin) {
        guard editorPresentation == nil,
              timeBlockPresentation == nil,
              !showingJumpToDate,
              !isTransitioningPresentation else { return }
        isTransitioningPresentation = true
        showingSearch = false
        Task { @MainActor in
            await Task.yield()
            openAgendaItem(origin)
            isTransitioningPresentation = false
        }
    }

    private func jumpToChosenDate() {
        guard editorPresentation == nil,
              timeBlockPresentation == nil,
              !showingSearch,
              !isTransitioningPresentation else { return }
        let day = LocalDay(date: jumpDate, calendar: calendar)
        isTransitioningPresentation = true
        showingJumpToDate = false
        Task { @MainActor in
            await Task.yield()
            await viewModel.jump(to: day)
            await Task.yield()
            jumpScrollDay = day
            isTransitioningPresentation = false
        }
    }

    private func handleCalendarDeepLink() async {
        guard editorPresentation == nil,
              timeBlockPresentation == nil,
              !showingSearch,
              !showingJumpToDate,
              !isTransitioningPresentation,
              let signal = calendarDeepLink else { return }
        let capturedPresentationGeneration = presentationGeneration
        if let day = signal.day {
            await viewModel.jump(to: day)
        } else {
            await viewModel.load()
        }
        let localPresentationIsActive = editorPresentation != nil
            || timeBlockPresentation != nil
            || showingSearch
            || showingJumpToDate
            || isTransitioningPresentation
        if HostRouteCancellationPolicy.shouldFinishAsUnavailable(
            taskIsCancelled: Task.isCancelled,
            signalIsCurrent: calendarDeepLink?.id == signal.id,
            localPresentationIsActive: localPresentationIsActive,
            presentationGenerationIsUnchanged:
                capturedPresentationGeneration == presentationGeneration
        ) {
            onDeepLinkHandled(signal.id, false)
            return
        }
        guard !Task.isCancelled,
              calendarDeepLink?.id == signal.id,
              editorPresentation == nil,
              timeBlockPresentation == nil,
              !showingSearch,
              !showingJumpToDate,
              !isTransitioningPresentation else { return }

        let routeEvents: [CalendarEventSnapshot]
        if signal.entryID != nil {
            guard let authoritative = viewModel.authoritativeRouteEvents(
                for: signal.day
            ) else {
                _ = deepLinkResolver.resolve(signal, events: [])
                onDeepLinkHandled(signal.id, false)
                return
            }
            routeEvents = authoritative
        } else {
            routeEvents = []
        }

        guard let resolution = deepLinkResolver.resolve(
            signal,
            events: routeEvents
        ) else { return }
        switch resolution {
        case .navigate:
            onDeepLinkHandled(signal.id, true)
        case let .open(_, event):
            openAgendaItem(.event(id: event.id))
            onDeepLinkHandled(signal.id, true)
        case .unavailable:
            onDeepLinkHandled(signal.id, false)
        }
    }

    private func dismissEditor() {
        editorPresentation = nil
        onPresentationChanged(false)
    }

    private func presentTimeBlock(reminderID: String) {
        guard editorPresentation == nil,
              timeBlockPresentation == nil,
              !showingSearch,
              !showingJumpToDate,
              calendarDeepLink == nil,
              !isTransitioningPresentation else { return }
        guard let reminder = viewModel.scopedIncompleteReminder(id: reminderID),
              let session = TaskTimeBlockSession.make(
                  task: reminder,
                  environment: environment
              ) else {
            taskActionError = "This task is no longer available in this profile. Refresh and try again."
            return
        }
        taskActionError = nil
        timeBlockPresentation = session
        onPresentationChanged(true)
    }

    private func dismissTimeBlock() {
        timeBlockPresentation = nil
        onPresentationChanged(false)
    }

    private func reconcileEditorWithoutDismissing() {
        Task { @MainActor in await viewModel.load() }
    }

    private func finishEditorAndReload(operation: CalendarEditorRefreshOperation) {
        Task { @MainActor in
            editorPresentation = nil
            onPresentationChanged(false)
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

private struct CalendarDeepLinkProcessingKey: Hashable {
    let signalID: UUID?
    let editorID: UUID?
    let timeBlockID: UUID?
    let showsSearch: Bool
    let showsJumpToDate: Bool
}
