import SwiftUI

struct TasksView: View {
    @State private var model: TasksViewModel
    @State private var showingNewTask = false
    init(environment: AppEnvironment) { _model = State(initialValue: TasksViewModel(service: environment.reminders, settings: environment.settings)) }
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
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("New Task", systemImage: "plus") { showingNewTask = true }.disabled(model.accessExplanation != nil).frame(minWidth: 44, minHeight: 44) } }
            .sheet(isPresented: $showingNewTask) { NewTaskSheet(model: model) }
            .task { await model.load() }
            .refreshable { await model.load() }
        }
    }
    @ViewBuilder private func taskSection(_ title: String, _ values: [ReminderSnapshot]) -> some View { if !values.isEmpty { Section(title) { ForEach(values) { taskRow($0) } } } }
    private func taskRow(_ task: ReminderSnapshot) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Button { Task { await model.setCompleted(id: task.id, completed: !task.isCompleted) } } label: { Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle").font(.title3) }
                .disabled(!task.allowsModification || model.mutatingIDs.contains(task.id)).frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel("Mark \(task.title) \(task.isCompleted ? "incomplete" : "complete")").accessibilityValue(task.isCompleted ? "Completed" : "Not completed").accessibilityHint(task.allowsModification ? "" : "This task is read-only.")
            VStack(alignment: .leading, spacing: 3) { Text(task.title).strikethrough(task.isCompleted); if let due = task.dueDate { Text(due, format: task.dueHasTime ? .dateTime.month().day().hour().minute() : .dateTime.month().day()).font(.footnote).foregroundStyle(.secondary) } else { Text("No due date").font(.footnote).foregroundStyle(.secondary) } }
        }.buttonStyle(.borderless)
    }
}
