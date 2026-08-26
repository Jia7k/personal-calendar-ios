import SwiftUI

struct TasksView: View {
    @State private var model: TasksViewModel
    @State private var editorPresentation: TasksEditorPresentation?
    @State private var timeBlockPresentation: TaskTimeBlockSession?
    @State private var pickedTask: ReminderSnapshot?
    @State private var pickedDate = Date()
    @State private var pickedDateHasTime = true
    @State private var refreshRegistrationID = UUID()
    @State private var deepLinkResolver = TaskDeepLinkResolver()
    @State private var presentationGeneration = 0
    private let environment: AppEnvironment
    private let revision: AppContentRevision
    private let quickEntryRefresh: QuickEntryRefreshSignal?
    private let taskDeepLink: TaskDeepLinkSignal?
    private let onDeepLinkHandled: @MainActor (UUID, Bool) -> Void
    private let onPresentationChanged: @MainActor (Bool) -> Void

    init(
        environment: AppEnvironment,
        revision: AppContentRevision = .init(lifecycle: 0, profileScope: 0),
        quickEntryRefresh: QuickEntryRefreshSignal? = nil,
        taskDeepLink: TaskDeepLinkSignal? = nil,
        onDeepLinkHandled: @escaping @MainActor (UUID, Bool) -> Void = { _, _ in },
        onPresentationChanged: @escaping @MainActor (Bool) -> Void = { _ in }
    ) {
        self.environment = environment
        let selection = environment.profileSelection
        let scopes = environment.profileScopes
        _model = State(initialValue: TasksViewModel(
            service: environment.reminders,
            settings: environment.settings,
            currentScope: { try scopes.resolve(selection.activeIdentity) }
        ))
        self.revision = revision
        self.quickEntryRefresh = quickEntryRefresh
        self.taskDeepLink = taskDeepLink
        self.onDeepLinkHandled = onDeepLinkHandled
        self.onPresentationChanged = onPresentationChanged
    }

    var body: some View {
        NavigationStack {
            List {
                if let explanation = model.accessExplanation { ContentUnavailableView("Tasks unavailable", systemImage: "checklist", description: Text(explanation)) }
                else if model.isProfileEmpty { ContentUnavailableView("No tasks in this profile", systemImage: "checklist", description: Text("Add a reminder list to this profile in Settings.")) }
                if let error = model.refreshErrorMessage { Section { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary); Button("Retry Refresh") { Task { await model.load() } }.frame(minWidth: 44, minHeight: 44) } }
                if let error = model.mutationErrorMessage { Section { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary); Button(model.failedMutationOperation?.completed == true ? "Retry Completion" : "Retry Undo") { Task { await model.retryFailedMutation() } }.frame(minWidth: 44, minHeight: 44) } }
                if let error = model.rescheduleErrorMessage {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.secondary)
                    }
                }
                if model.rescheduleUndo != nil {
                    Section {
                        Button {
                            Task { await model.undoQuickReschedule() }
                        } label: {
                            Label("Undo reschedule", systemImage: "arrow.uturn.backward")
                        }
                        .disabled(!model.mutatingIDs.isEmpty)
                        .accessibilityIdentifier("task-reschedule-undo")
                    }
                }
                overdueSection
                taskSection("Today", model.today)
                taskSection("Upcoming", model.upcoming)
                if !model.completed.isEmpty { Section { DisclosureGroup("Completed") { ForEach(model.completed) { taskRow($0) } } } }
            }
            .scrollContentBackground(.hidden)
            .background(CalendarTheme.background)
            .navigationTitle("Tasks")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ProfileSelectorToolbar(selection: environment.profileSelection)
                }
            }
            .sheet(item: $editorPresentation) { presentation in
                TaskEditorView(
                    model: presentation.model,
                    lists: presentation.lists,
                    nilDestinationLabel: presentation.nilDestinationLabel,
                    showsDelete: presentation.showsDelete,
                    makeTimeBlockSession: {
                        guard let task = presentation.model.schedulingSnapshot,
                              !task.isCompleted else { return nil }
                        return TaskTimeBlockSession.make(
                            task: task,
                            environment: environment
                        )
                    },
                    onDismiss: dismissEditor
                )
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
            .sheet(item: $pickedTask) { task in
                NavigationStack {
                    Form {
                        DatePicker(
                            "Due date",
                            selection: $pickedDate,
                            displayedComponents: pickedDateHasTime ? [.date, .hourAndMinute] : .date
                        )
                        Toggle("Include time", isOn: $pickedDateHasTime)
                    }
                    .navigationTitle("Reschedule")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { pickedTask = nil }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save") {
                                let date = pickedDate
                                let hasTime = pickedDateHasTime
                                pickedTask = nil
                                Task {
                                    await model.quickReschedule(
                                        id: task.id,
                                        command: .pick(date, hasTime: hasTime)
                                    )
                                }
                            }
                        }
                    }
                }
            }
            .task(id: revision) {
                guard taskDeepLink == nil else { return }
                await model.load()
            }
            .task(id: quickEntryRefresh?.id) {
                guard let quickEntryRefresh,
                      case .task = quickEntryRefresh.outcome else { return }
                await model.refreshAfterQuickEntry(quickEntryRefresh.outcome)
            }
            .task(id: TaskDeepLinkProcessingKey(
                signalID: taskDeepLink?.id,
                editorID: editorPresentation?.id,
                pickerTaskID: pickedTask?.id,
                timeBlockID: timeBlockPresentation?.id
            )) {
                await handleTaskDeepLink()
            }
            .onChange(
                of: editorPresentation != nil
                    || pickedTask != nil
                    || timeBlockPresentation != nil,
                initial: true
            ) { _, isPresented in
                presentationGeneration &+= 1
                onPresentationChanged(isPresented)
            }
            .refreshable { await model.load() }
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
        if !model.overdue.isEmpty {
            Section("Overdue") {
                ForEach(model.overdue) { task in
                    taskRow(task, offersQuickReschedule: true)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("tasks-overdue")
        }
    }

    @ViewBuilder private func taskSection(_ title: String, _ values: [ReminderSnapshot]) -> some View { if !values.isEmpty { Section(title) { ForEach(values) { taskRow($0) } } } }

    private func taskRow(_ task: ReminderSnapshot, offersQuickReschedule: Bool = false) -> some View {
        HStack(spacing: 12) {
            Button {
                Task { await model.setCompleted(id: task.id, completed: !task.isCompleted) }
            } label: {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(CalendarTheme.task)
            }
            .buttonStyle(.borderless)
            .disabled(!task.allowsModification || model.mutatingIDs.contains(task.id))
            .frame(minWidth: CalendarTheme.minimumTapSize, minHeight: CalendarTheme.minimumTapSize)
            .accessibilityIdentifier("task-complete-\(task.id)")
            .accessibilityLabel("Mark \(task.title) \(task.isCompleted ? "incomplete" : "complete")")
            .accessibilityValue(task.isCompleted ? "Completed" : "Not completed")
            .accessibilityHint(task.allowsModification ? "" : "This task is read-only.")

            Button { openTask(task) } label: {
                taskDetails(task)
            }
            .buttonStyle(.borderless)
            .frame(maxWidth: .infinity, minHeight: CalendarTheme.minimumTapSize, alignment: .leading)
            .contentShape(Rectangle())
            .accessibilityIdentifier("task-open-\(task.id)")
            .accessibilityLabel("Open task \(task.title)")

            if canScheduleTime(task) || (offersQuickReschedule && canQuickReschedule(task)) {
                Menu {
                    if canScheduleTime(task) {
                        Button("Schedule Time", systemImage: "calendar.badge.clock") {
                            presentTimeBlock(for: task)
                        }
                        .accessibilityIdentifier("task-schedule-time-\(task.id)")
                    }
                    if offersQuickReschedule, canQuickReschedule(task) {
                        Divider()
                        quickRescheduleMenuActions(task)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                }
                .frame(minWidth: CalendarTheme.minimumTapSize, minHeight: CalendarTheme.minimumTapSize)
                .accessibilityIdentifier(
                    offersQuickReschedule && canQuickReschedule(task)
                        ? "task-reschedule-more-\(task.id)"
                        : "task-actions-\(task.id)"
                )
                .accessibilityLabel("Actions for \(task.title)")
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if offersQuickReschedule, canQuickReschedule(task) {
                Button {
                    quickReschedule(task, command: .tomorrow)
                } label: {
                    Label("Tomorrow", systemImage: "sunrise")
                }
                .tint(CalendarTheme.task)
                .accessibilityIdentifier("task-reschedule-tomorrow-\(task.id)")

                Button {
                    quickReschedule(task, command: .nextWeek)
                } label: {
                    Label("Next Week", systemImage: "calendar.badge.plus")
                }
            }
        }
        .contextMenu {
            Button("Open", systemImage: "square.and.pencil") {
                openTask(task)
            }
            if canScheduleTime(task) {
                Button("Schedule Time", systemImage: "calendar.badge.clock") {
                    presentTimeBlock(for: task)
                }
                .accessibilityIdentifier("task-schedule-time-\(task.id)")
            }
            if offersQuickReschedule, canQuickReschedule(task) {
                quickRescheduleMenuActions(task)
            }
        }
    }

    @ViewBuilder private func quickRescheduleMenuActions(_ task: ReminderSnapshot) -> some View {
        Button("Later Today", systemImage: "clock") {
            quickReschedule(task, command: .laterToday)
        }
        Button("Tomorrow", systemImage: "sunrise") {
            quickReschedule(task, command: .tomorrow)
        }
        Button("Next Week", systemImage: "calendar.badge.plus") {
            quickReschedule(task, command: .nextWeek)
        }
        Button("Pick Date", systemImage: "calendar") {
            presentDatePicker(for: task)
        }
    }

    private func canQuickReschedule(_ task: ReminderSnapshot) -> Bool {
        !task.isCompleted
            && task.allowsModification
            && !task.hasRecurrence
            && !model.mutatingIDs.contains(task.id)
    }

    private func canScheduleTime(_ task: ReminderSnapshot) -> Bool {
        !task.isCompleted
    }

    private func quickReschedule(_ task: ReminderSnapshot, command: TaskQuickReschedule) {
        Task { await model.quickReschedule(id: task.id, command: command) }
    }

    private func presentDatePicker(for task: ReminderSnapshot) {
        pickedDate = task.dueDate ?? .now
        pickedDateHasTime = task.dueHasTime
        pickedTask = task
        onPresentationChanged(true)
    }

    private func taskDetails(_ task: ReminderSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(task.title).strikethrough(task.isCompleted)
            if let due = task.dueDate {
                Text(due, format: task.dueHasTime ? .dateTime.month().day().hour().minute() : .dateTime.month().day())
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("No due date")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func openTask(_ task: ReminderSnapshot) {
        let editorModel = TaskEditorViewModel.editing(
            reminderID: task.id,
            service: environment.reminders,
            categories: environment.categories,
            onCommitted: { commit in finishEditorAndReload(commit) },
            onReconciliationNeeded: reconcileEditorWithoutDismissing
        )
        editorPresentation = .init(
            model: editorModel,
            lists: environment.reminders.lists(),
            nilDestinationLabel: "Preserve Current",
            showsDelete: true
        )
        onPresentationChanged(true)
    }

    private func handleTaskDeepLink() async {
        guard editorPresentation == nil,
              pickedTask == nil,
              timeBlockPresentation == nil,
              let signal = taskDeepLink else { return }
        let capturedPresentationGeneration = presentationGeneration
        await model.load()
        let localPresentationIsActive = editorPresentation != nil
            || pickedTask != nil
            || timeBlockPresentation != nil
        if HostRouteCancellationPolicy.shouldFinishAsUnavailable(
            taskIsCancelled: Task.isCancelled,
            signalIsCurrent: taskDeepLink?.id == signal.id,
            localPresentationIsActive: localPresentationIsActive,
            presentationGenerationIsUnchanged:
                capturedPresentationGeneration == presentationGeneration
        ) {
            onDeepLinkHandled(signal.id, false)
            return
        }
        guard !Task.isCancelled,
              taskDeepLink?.id == signal.id,
              editorPresentation == nil,
              pickedTask == nil,
              timeBlockPresentation == nil else { return }
        let liveReminder = environment.reminders.reminder(id: signal.reminderID)
        let scope = try? environment.profileScopes.resolve(
            environment.profileSelection.activeIdentity
        )
        let reminders: [ReminderSnapshot]
        if environment.reminders.accessState == .granted,
           let liveReminder,
           let scope,
           scope.reminderListIDs.contains(liveReminder.listID) {
            reminders = [liveReminder]
        } else {
            reminders = []
        }
        guard let resolution = deepLinkResolver.resolve(
            signal,
            reminders: reminders
        ) else { return }
        switch resolution {
        case let .open(task):
            openTask(task)
            onDeepLinkHandled(signal.id, true)
        case .unavailable:
            onDeepLinkHandled(signal.id, false)
        }
    }

    private func dismissEditor() {
        editorPresentation = nil
        onPresentationChanged(false)
    }

    private func reconcileEditorWithoutDismissing() {
        Task { @MainActor in await model.load() }
    }

    private func finishEditorAndReload(_ commit: TaskEditorCommit) {
        Task { @MainActor in
            editorPresentation = nil
            onPresentationChanged(false)
            await model.refreshAfterEditorCommit(commit)
        }
    }

    private func presentTimeBlock(for task: ReminderSnapshot) {
        guard timeBlockPresentation == nil else { return }
        timeBlockPresentation = TaskTimeBlockSession.make(
            task: task,
            environment: environment
        )
        onPresentationChanged(timeBlockPresentation != nil)
    }

    private func dismissTimeBlock() {
        timeBlockPresentation = nil
        onPresentationChanged(false)
    }

}

private struct TasksEditorPresentation: Identifiable {
    let id = UUID()
    let model: TaskEditorViewModel
    let lists: [ReminderListDescriptor]
    let nilDestinationLabel: String
    let showsDelete: Bool
}

private struct TaskDeepLinkProcessingKey: Hashable {
    let signalID: UUID?
    let editorID: UUID?
    let pickerTaskID: String?
    let timeBlockID: UUID?
}
