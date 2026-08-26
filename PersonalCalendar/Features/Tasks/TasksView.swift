import SwiftUI

struct TasksView: View {
    @State private var model: TasksViewModel
    @State private var editorPresentation: TasksEditorPresentation?
    @State private var pickedTask: ReminderSnapshot?
    @State private var pickedDate = Date()
    @State private var pickedDateHasTime = true
    @State private var refreshRegistrationID = UUID()
    private let environment: AppEnvironment
    private let revision: AppContentRevision
    private let quickEntryRefresh: QuickEntryRefreshSignal?

    init(
        environment: AppEnvironment,
        revision: AppContentRevision = .init(lifecycle: 0, profileScope: 0),
        quickEntryRefresh: QuickEntryRefreshSignal? = nil
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
                    onDismiss: dismissEditor
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
            .task(id: revision) { await model.load() }
            .task(id: quickEntryRefresh?.id) {
                guard let quickEntryRefresh,
                      case .task = quickEntryRefresh.outcome else { return }
                await model.refreshAfterQuickEntry(quickEntryRefresh.outcome)
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

            if offersQuickReschedule, canQuickReschedule(task) {
                Menu {
                    quickRescheduleMenuActions(task)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                }
                .frame(minWidth: CalendarTheme.minimumTapSize, minHeight: CalendarTheme.minimumTapSize)
                .accessibilityIdentifier("task-reschedule-more-\(task.id)")
                .accessibilityLabel("More reschedule options for \(task.title)")
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

    private func quickReschedule(_ task: ReminderSnapshot, command: TaskQuickReschedule) {
        Task { await model.quickReschedule(id: task.id, command: command) }
    }

    private func presentDatePicker(for task: ReminderSnapshot) {
        pickedDate = task.dueDate ?? .now
        pickedDateHasTime = task.dueHasTime
        pickedTask = task
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
    }

    private func dismissEditor() {
        editorPresentation = nil
    }

    private func reconcileEditorWithoutDismissing() {
        Task { @MainActor in await model.load() }
    }

    private func finishEditorAndReload(_ commit: TaskEditorCommit) {
        Task { @MainActor in
            editorPresentation = nil
            await model.refreshAfterEditorCommit(commit)
        }
    }
}

private struct TasksEditorPresentation: Identifiable {
    let id = UUID()
    let model: TaskEditorViewModel
    let lists: [ReminderListDescriptor]
    let nilDestinationLabel: String
    let showsDelete: Bool
}
