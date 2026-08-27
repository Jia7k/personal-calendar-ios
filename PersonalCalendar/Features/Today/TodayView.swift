import SwiftUI

struct TodayView: View {
    @State private var model: TodayViewModel
    @State private var editorPresentation: TodayEditorPresentation?
    @State private var taskActionPresentation: TodayTaskActionPresentation?
    @State private var pickedDate = Date()
    @State private var pickedDateHasTime = true
    @State private var taskActionError: String?
    @State private var refreshRegistrationID = UUID()
    private let environment: AppEnvironment
    private let openSettings: @MainActor () -> Void
    private let onOpenRoutine: @MainActor (UUID) -> Void
    private let revision: AppContentRevision
    private let quickEntryRefresh: QuickEntryRefreshSignal?
    private let onPresentationChanged: @MainActor (Bool) -> Void

    init(
        environment: AppEnvironment,
        revision: AppContentRevision = .init(lifecycle: 0, profileScope: 0),
        quickEntryRefresh: QuickEntryRefreshSignal? = nil,
        openSettings: @escaping @MainActor () -> Void = {},
        onOpenRoutine: @escaping @MainActor (UUID) -> Void = { _ in },
        onPresentationChanged: @escaping @MainActor (Bool) -> Void = { _ in }
    ) {
        self.environment = environment
        let profileScopes = environment.profileScopes
        let profileSelection = environment.profileSelection
        _model = State(initialValue: TodayViewModel(
            calendar: environment.calendar,
            reminders: environment.reminders,
            routines: environment.routines,
            composer: environment.agendaComposer,
            settings: environment.settings,
            currentScope: {
                try profileScopes.resolve(profileSelection.activeIdentity)
            },
            rescheduleNotifications: {
                await environment.notificationCoordinator.clear()
                await environment.rescheduleNotifications()
            }
        ))
        self.openSettings = openSettings
        self.onOpenRoutine = onOpenRoutine
        self.revision = revision
        self.quickEntryRefresh = quickEntryRefresh
        self.onPresentationChanged = onPresentationChanged
    }

    var body: some View {
        NavigationStack {
            List {
                if model.showsCalendarPermissionCard { permissionCard(title: "Calendar events are unavailable", restricted: model.calendarAccessState == .restricted) }
                if model.showsRemindersPermissionCard { permissionCard(title: "Tasks are unavailable", restricted: model.remindersAccessState == .restricted) }
                errorRow(model.calendarError, source: "Calendar")
                errorRow(model.remindersError, source: "Reminders")
                errorRow(model.routinesError, source: "Routines")
                errorRow(model.rescheduleError, source: "Task schedule")
                if let taskActionError {
                    Section {
                        Label(taskActionError, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.secondary)
                    }
                }
                overdueSection
                if let nextUp = model.nextUp {
                    nextUpSection(nextUp)
                }
                if model.latestRescheduleUndo != nil {
                    Section {
                        HStack {
                            Text("Task rescheduled")
                            Spacer(minLength: 8)
                            Button("Undo") {
                                Task { await model.undoLastTaskReschedule() }
                            }
                            .frame(
                                minWidth: CalendarTheme.minimumTapSize,
                                minHeight: CalendarTheme.minimumTapSize
                            )
                            .disabled(!model.mutatingItemIDs.isEmpty)
                            .accessibilityIdentifier("today-reschedule-undo")
                            .accessibilityLabel("Undo task reschedule")
                            .accessibilityHint("Restores the task's previous due date and time.")
                        }
                    }
                }
                if let undo = model.latestTaskUndo {
                    Section {
                        HStack {
                            Text("Marked \(undo.title) complete")
                            Spacer(minLength: 8)
                            Button("Undo") { Task { await model.undoLastTaskCompletion() } }
                                .frame(minWidth: CalendarTheme.minimumTapSize, minHeight: CalendarTheme.minimumTapSize)
                                .disabled(undo.isPending)
                                .accessibilityLabel("Undo completion for \(undo.title)")
                        }
                    }
                }
                section("All Day", items: model.agenda.allDay)
                section("Schedule", items: model.agenda.scheduled)
                section("Priority", items: model.agenda.priority)
                if model.isGenuinelyEmpty {
                    ContentUnavailableView("Nothing planned today", systemImage: "sun.max", description: Text("New events, tasks, and routines will appear here."))
                }
            }
            .scrollContentBackground(.hidden)
            .background(CalendarTheme.background)
            .overlay { if model.isLoading && !model.hasLoaded { ProgressView() } }
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ProfileSelectorToolbar(selection: environment.profileSelection)
                }
            }
            .task(id: revision) { await model.load() }
            .task {
                while !Task.isCancelled {
                    do {
                        try await Task.sleep(for: .seconds(60))
                    } catch {
                        return
                    }
                    model.refreshNextUp()
                }
            }
            .task(id: quickEntryRefresh?.id) {
                guard let quickEntryRefresh else { return }
                await model.refreshAfterQuickEntry(quickEntryRefresh.outcome)
            }
            .refreshable { await model.load() }
            .sheet(item: $editorPresentation) { presentation in
                switch presentation.content {
                case let .event(editorModel, calendars):
                    EventEditorView(model: editorModel, calendars: calendars, nilDestinationLabel: "Preserve Current", showsDelete: true, onDismiss: dismissEditor)
                        .task { await editorModel.load() }
                case let .task(editorModel, lists):
                    TaskEditorView(
                        model: editorModel,
                        lists: lists,
                        nilDestinationLabel: "Preserve Current",
                        showsDelete: true,
                        makeTimeBlockSession: {
                            guard let task = editorModel.schedulingSnapshot,
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
            .sheet(item: $taskActionPresentation) { presentation in
                switch presentation {
                case let .pickDate(request):
                    NavigationStack {
                        Form {
                            DatePicker(
                                "Due date",
                                selection: $pickedDate,
                                displayedComponents: pickedDateHasTime
                                    ? [.date, .hourAndMinute]
                                    : .date
                            )
                            Toggle("Include time", isOn: $pickedDateHasTime)
                        }
                        .navigationTitle("Reschedule")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Cancel") { taskActionPresentation = nil }
                            }
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Save") {
                                    let date = pickedDate
                                    let hasTime = pickedDateHasTime
                                    taskActionPresentation = nil
                                    Task {
                                        await model.quickRescheduleTask(
                                            id: request.reminderID,
                                            command: .pick(date, hasTime: hasTime)
                                        )
                                    }
                                }
                            }
                        }
                    }
                case let .timeBlock(session):
                    TaskTimeBlockView(
                        model: session.model,
                        profiles: session.profiles,
                        resolveProfile: session.resolveProfile,
                        onSaved: session.onSaved,
                        onDismiss: dismissTaskAction
                    )
                }
            }
            .onChange(
                of: editorPresentation != nil || taskActionPresentation != nil,
                initial: true
            ) { _, isPresented in
                onPresentationChanged(isPresented)
            }
        }
        .onAppear {
            environment.agendaRefreshRegistry.register(id: refreshRegistrationID) { [weak model] in
                await model?.refreshForExternalChange()
            }
        }
        .onDisappear {
            environment.agendaRefreshRegistry.unregister(id: refreshRegistrationID)
        }
    }

    @ViewBuilder private var overdueSection: some View {
        if !model.overdueTasks.isEmpty {
            Section("Overdue") {
                ForEach(model.overdueTasks) { overdue in
                    overdueTaskRow(overdue)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("today-overdue")
        }
    }

    private func overdueTaskRow(_ overdue: TodayOverdueTask) -> some View {
        let reminder = overdue.reminder
        let item = AgendaItem(reminder: reminder)
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(reminder.title)
                Text(overdueDescription(overdue))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(reminder.title), \(overdueDescription(overdue))")

            Button {
                Task { await model.setTaskCompleted(item, completed: true) }
            } label: {
                Image(systemName: "circle")
                    .foregroundStyle(CalendarTheme.task)
            }
            .buttonStyle(.borderless)
            .frame(
                minWidth: CalendarTheme.minimumTapSize,
                minHeight: CalendarTheme.minimumTapSize
            )
            .disabled(!reminder.allowsModification || isTaskMutating(reminder.id))
            .accessibilityIdentifier("today-overdue-complete-\(reminder.id)")
            .accessibilityLabel("Mark \(reminder.title) complete")
            .accessibilityValue("Not completed")
            .accessibilityHint(
                reminder.allowsModification
                    ? ""
                    : "This task is read-only."
            )

            taskActionsMenu(
                reminderID: reminder.id,
                title: reminder.title,
                identifier: "today-overdue-actions-\(reminder.id)"
            )
        }
        .padding(.vertical, 4)
    }

    private func overdueDescription(_ overdue: TodayOverdueTask) -> String {
        let age = overdue.daysOverdue == 1
            ? "Due yesterday"
            : "Due \(overdue.daysOverdue) days ago"
        guard overdue.reminder.dueHasTime,
              let dueDate = overdue.reminder.dueDate else { return age }
        return "\(age) · \(dueDate.formatted(date: .omitted, time: .shortened))"
    }

    @ViewBuilder private func section(_ title: LocalizedStringKey, items: [AgendaItem]) -> some View {
        if !items.isEmpty {
            Section(title) {
                ForEach(items) { item in
                    HStack(spacing: 4) {
                        AgendaRow(
                            item: item,
                            isMutating: model.mutatingItemIDs.contains(item.id),
                            open: openAction(for: item)
                        ) { state in
                            Task {
                                if item.source == .task {
                                    await model.setTaskCompleted(item, completed: state)
                                } else {
                                    await model.setRoutineCompleted(item, completed: state)
                                }
                            }
                        }
                        if case let .reminder(reminderID) = item.origin,
                           !item.isCompleted {
                            taskActionsMenu(
                                reminderID: reminderID,
                                title: item.title,
                                identifier: "today-task-actions-\(reminderID)"
                            )
                        }
                    }
                }
            }
        }
    }

    private func taskActionsMenu(
        reminderID: String,
        title: String,
        identifier: String
    ) -> some View {
        Menu {
            if canQuickReschedule(reminderID: reminderID) {
                Button("Later Today", systemImage: "clock") {
                    quickReschedule(reminderID: reminderID, command: .laterToday)
                }
                Button("Tomorrow", systemImage: "sunrise") {
                    quickReschedule(reminderID: reminderID, command: .tomorrow)
                }
                Button("Pick Date", systemImage: "calendar") {
                    presentPickDate(reminderID: reminderID)
                }
                Divider()
            }
            Button("Schedule Time", systemImage: "calendar.badge.clock") {
                presentTimeBlock(reminderID: reminderID)
            }
            Divider()
            Button("Open", systemImage: "square.and.pencil") {
                openAgendaItem(.reminder(id: reminderID))
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3)
        }
        .frame(
            minWidth: CalendarTheme.minimumTapSize,
            minHeight: CalendarTheme.minimumTapSize
        )
        .accessibilityIdentifier(identifier)
        .accessibilityLabel("Actions for \(title)")
        .accessibilityHint("Choose scheduling, rescheduling, or open actions.")
    }

    private func openAction(for item: AgendaItem) -> (() -> Void)? {
        switch item.origin {
        case .event, .reminder, .routine:
            { openAgendaItem(item.origin) }
        case .synthetic:
            nil
        }
    }

    private func openAgendaItem(_ origin: AgendaItemOrigin) {
        guard taskActionPresentation == nil else { return }
        let capturedProfileIdentity = environment.profileSelection.activeIdentity
        let capturedScope = try? environment.profileScopes.resolve(capturedProfileIdentity)
        switch origin {
        case let .event(displayID):
            let editorModel = EventEditorViewModel.edit(
                displayID: displayID,
                service: environment.calendar,
                categories: environment.categories,
                duplicateDestinationCalendarIDs: capturedScope?.calendarIDs ?? [],
                resolveDuplicateDestinationCalendarIDs: {
                    try environment.profileScopes
                        .resolve(capturedProfileIdentity).calendarIDs
                },
                onCommitted: { commit in finishEventEditorAndReload(commit) },
                onReconciliationNeeded: reconcileEditorWithoutDismissing
            )
            editorPresentation = .init(content: .event(model: editorModel, calendars: environment.calendar.calendars()))
        case let .reminder(reminderID):
            let editorModel = TaskEditorViewModel.editing(
                reminderID: reminderID,
                service: environment.reminders,
                categories: environment.categories,
                duplicateDestinationListIDs: capturedScope?.reminderListIDs ?? [],
                resolveDuplicateDestinationListIDs: {
                    try environment.profileScopes
                        .resolve(capturedProfileIdentity).reminderListIDs
                },
                onCommitted: { commit in finishTaskEditorAndReload(commit) },
                onReconciliationNeeded: reconcileEditorWithoutDismissing
            )
            editorPresentation = .init(content: .task(model: editorModel, lists: environment.reminders.lists()))
        case let .routine(id, _):
            onOpenRoutine(id)
        case .synthetic:
            break
        }
    }

    private func canQuickReschedule(reminderID: String) -> Bool {
        guard let reminder = environment.reminders.reminder(id: reminderID) else {
            return false
        }
        return !reminder.isCompleted
            && reminder.allowsModification
            && !reminder.hasRecurrence
            && !isTaskMutating(reminderID)
    }

    private func isTaskMutating(_ reminderID: String) -> Bool {
        model.mutatingItemIDs.contains(reminderID)
            || model.mutatingItemIDs.contains("task|\(reminderID)")
    }

    private func quickReschedule(
        reminderID: String,
        command: TaskQuickReschedule
    ) {
        Task {
            await model.quickRescheduleTask(id: reminderID, command: command)
        }
    }

    private func presentPickDate(reminderID: String) {
        guard editorPresentation == nil,
              taskActionPresentation == nil,
              let reminder = model.scopedIncompleteReminder(id: reminderID),
              reminder.allowsModification,
              !reminder.hasRecurrence else { return }
        taskActionError = nil
        pickedDate = reminder.dueDate ?? .now
        pickedDateHasTime = reminder.dueHasTime
        taskActionPresentation = .pickDate(
            TodayTaskPickDate(reminderID: reminderID)
        )
    }

    private func presentTimeBlock(reminderID: String) {
        var resolvedSession: TaskTimeBlockSession?
        let decision = TodayTaskActionPresentationGate.decide(
            editorIsPresented: editorPresentation != nil,
            actionIsPresented: taskActionPresentation != nil
        ) {
            guard let reminder = model.scopedIncompleteReminder(id: reminderID),
                  let session = TaskTimeBlockSession.make(
                    task: reminder,
                    environment: environment
                  ) else { return false }
            resolvedSession = session
            return true
        }

        switch decision {
        case .busy:
            return
        case .unavailable:
            taskActionError = "This task is no longer available in this profile. Refresh and try again."
        case .ready:
            guard let resolvedSession else { return }
            taskActionError = nil
            taskActionPresentation = .timeBlock(resolvedSession)
        }
    }

    private func dismissTaskAction() {
        taskActionPresentation = nil
    }

    private func nextUpSection(_ snapshot: NextUpSnapshot) -> some View {
        Section("Next Up") {
            VStack(alignment: .leading, spacing: 12) {
                if let event = snapshot.event {
                    nextUpEvent(event)
                }
                if snapshot.event != nil, snapshot.deadline != nil {
                    Divider()
                }
                if let deadline = snapshot.deadline {
                    nextUpDeadline(deadline)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func nextUpEvent(_ event: NextUpEventSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(event.phase == .current ? "Happening now" : "Next event", systemImage: "calendar")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(event.title)
                .font(.headline)
            Text(eventTimeDescription(event))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let location = event.location {
                Label(location, systemImage: "mappin.and.ellipse")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            HStack(spacing: 12) {
                Button("Open") { openAgendaItem(event.origin) }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .frame(minHeight: CalendarTheme.minimumTapSize)
                    .accessibilityLabel("Open event \(event.title)")
                    .accessibilityIdentifier("today-next-up-open-event")
                if let location = event.location {
                    Button {
                        Task {
                            await environment.eventLocationMapsOpener.open(location: location)
                        }
                    } label: {
                        Label("Maps", systemImage: "map")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .frame(minHeight: CalendarTheme.minimumTapSize)
                    .accessibilityLabel("Open \(location) in Maps")
                    .accessibilityIdentifier("today-next-up-maps")
                }
            }
        }
    }

    private func nextUpDeadline(_ deadline: NextUpDeadlineSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Nearest deadline", systemImage: "checkmark.circle")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(deadline.title)
                .font(.headline)
            Text(deadlineDescription(deadline))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Open") { openAgendaItem(deadline.origin) }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .frame(minHeight: CalendarTheme.minimumTapSize)
                .accessibilityLabel("Open task \(deadline.title)")
                .accessibilityIdentifier("today-next-up-open-task")
        }
    }

    private func eventTimeDescription(_ event: NextUpEventSnapshot) -> String {
        let end = event.end.formatted(date: .omitted, time: .shortened)
        if event.phase == .current {
            return "Now · until \(end)"
        }
        let start = event.start.formatted(date: .omitted, time: .shortened)
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        let countdown = formatter.localizedString(
            for: event.start,
            relativeTo: model.nextUpReferenceDate
        )
        return "\(start)–\(end) · Starts \(countdown)"
    }

    private func deadlineDescription(_ deadline: NextUpDeadlineSnapshot) -> String {
        if deadline.dueHasTime {
            return "Due \(deadline.dueDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()))"
        }
        return "Due \(deadline.dueDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))"
    }

    private func dismissEditor() {
        editorPresentation = nil
    }

    private func reconcileEditorWithoutDismissing() {
        Task { @MainActor in await model.load() }
    }

    private func finishEventEditorAndReload(_ commit: EventEditorCommit) {
        Task { @MainActor in
            editorPresentation = nil
            await model.refreshAfterEventEditorCommit(commit)
        }
    }

    private func finishTaskEditorAndReload(_ commit: TaskEditorCommit) {
        Task { @MainActor in
            editorPresentation = nil
            await model.refreshAfterTaskEditorCommit(commit)
        }
    }

    @ViewBuilder private func errorRow(_ message: String?, source: String) -> some View {
        if let message {
            Section {
                HStack {
                    Label(message, systemImage: "exclamationmark.triangle")
                    Spacer(minLength: 8)
                    Button("Retry") { Task { await model.load() }
                    }
                    .frame(minWidth: CalendarTheme.minimumTapSize, minHeight: CalendarTheme.minimumTapSize)
                    .accessibilityLabel("Retry \(source)")
                }
            }
        }
    }
    private func permissionCard(title: String, restricted: Bool) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Label(title, systemImage: "lock")
                Text(restricted ? "This access is controlled by your device or account." : "Open Settings to manage this source.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if !restricted {
                    Button("Open Settings", action: openSettings)
                        .frame(minWidth: CalendarTheme.minimumTapSize, minHeight: CalendarTheme.minimumTapSize)
                        .accessibilityIdentifier(title.hasPrefix("Calendar") ? "today-calendar-permission-settings" : "today-reminders-permission-settings")
                        .accessibilityLabel("Open in-app Settings for \(title)")
                }
            }
        }
    }
}

private struct TodayEditorPresentation: Identifiable {
    enum Content {
        case event(model: EventEditorViewModel, calendars: [CalendarDescriptor])
        case task(model: TaskEditorViewModel, lists: [ReminderListDescriptor])
    }

    let id = UUID()
    let content: Content
}
