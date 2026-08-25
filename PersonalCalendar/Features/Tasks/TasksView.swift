import SwiftUI

struct TasksView: View {
    @State private var model: TasksViewModel
    @State private var editorPresentation: TasksEditorPresentation?
    private let environment: AppEnvironment
    private let revision: Int
    private let quickEntryRefresh: QuickEntryRefreshSignal?

    init(
        environment: AppEnvironment,
        revision: Int = 0,
        quickEntryRefresh: QuickEntryRefreshSignal? = nil
    ) {
        self.environment = environment
        _model = State(initialValue: TasksViewModel(service: environment.reminders, settings: environment.settings))
        self.revision = revision
        self.quickEntryRefresh = quickEntryRefresh
    }

    var body: some View {
        NavigationStack {
            List {
                if let explanation = model.accessExplanation { ContentUnavailableView("Tasks unavailable", systemImage: "checklist", description: Text(explanation)) }
                if let error = model.refreshErrorMessage { Section { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary); Button("Retry Refresh") { Task { await model.load() } }.frame(minWidth: 44, minHeight: 44) } }
                if let error = model.mutationErrorMessage { Section { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary); Button(model.failedMutationOperation?.completed == true ? "Retry Completion" : "Retry Undo") { Task { await model.retryFailedMutation() } }.frame(minWidth: 44, minHeight: 44) } }
                taskSection("Today", model.today)
                taskSection("Upcoming", model.upcoming)
                if !model.completed.isEmpty { Section { DisclosureGroup("Completed") { ForEach(model.completed) { taskRow($0) } } } }
            }
            .navigationTitle("Tasks")
            .sheet(item: $editorPresentation) { presentation in
                TaskEditorView(
                    model: presentation.model,
                    lists: presentation.lists,
                    nilDestinationLabel: presentation.nilDestinationLabel,
                    showsDelete: presentation.showsDelete,
                    onDismiss: dismissEditor
                )
            }
            .task(id: revision) { await model.load() }
            .task(id: quickEntryRefresh?.id) {
                guard let quickEntryRefresh,
                      case .task = quickEntryRefresh.outcome else { return }
                await model.refreshAfterQuickEntry(quickEntryRefresh.outcome)
            }
            .refreshable { await model.load() }
        }
    }

    @ViewBuilder private func taskSection(_ title: String, _ values: [ReminderSnapshot]) -> some View { if !values.isEmpty { Section(title) { ForEach(values) { taskRow($0) } } } }

    private func taskRow(_ task: ReminderSnapshot) -> some View {
        HStack(spacing: 12) {
            Button {
                Task { await model.setCompleted(id: task.id, completed: !task.isCompleted) }
            } label: {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
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
        }
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
