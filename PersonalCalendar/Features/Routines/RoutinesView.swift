import SwiftUI

struct RoutinesView: View {
    @State private var model: RoutinesViewModel
    @State private var editing: RoutineRowState?
    @State private var showingNew = false
    @State private var deleteTarget: RoutineRowState?
    init(environment: AppEnvironment) { _model = State(initialValue: RoutinesViewModel(repository: environment.routines)) }
    var body: some View { NavigationStack { List {
        if let error = model.refreshErrorMessage { Section { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary); Button("Retry Refresh") { model.reload() }.frame(minWidth: 44, minHeight: 44) } }
        if let error = model.actionErrorMessage { Section { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary); Button(actionRetryLabel) { if let target = model.deleteRetryTarget { deleteTarget = target } else { model.retryFailedAction() } }.frame(minWidth: 44, minHeight: 44) } }
        Section("Active") { if model.active.isEmpty { ContentUnavailableView(model.archived.isEmpty ? "No routines" : "No active routines", systemImage: "repeat", description: Text("Create a routine for the habits you want to keep.")) }; ForEach(model.active) { row($0) } }
        if !model.archived.isEmpty { Section { DisclosureGroup("Archived") { ForEach(model.archived) { row($0) } } } }
    }.navigationTitle("Routines").toolbar { ToolbarItem(placement: .topBarTrailing) { Button("New Routine", systemImage: "plus") { showingNew = true }.frame(minWidth: 44, minHeight: 44) } }
    .sheet(isPresented: $showingNew) { RoutineEditorView(model: model) }.sheet(item: $editing) { RoutineEditorView(model: model, row: $0) }
    .confirmationDialog("Delete \(deleteTarget?.routine.title ?? "routine")?", isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }), titleVisibility: .visible) { Button("Delete", role: .destructive) { if let target = deleteTarget, model.delete(id: target.id) { deleteTarget = nil } }; Button("Cancel", role: .cancel) { deleteTarget = nil } }
    .task { model.reload() }.refreshable { model.reload() }
    } }
    private var actionRetryLabel: String { switch model.failedActionOperation { case .pause: "Retry Pause"; case .archive: "Retry Archive"; case .completion: "Retry Completion"; case .delete: "Retry Delete"; case nil: "Retry" } }
    private func row(_ row: RoutineRowState) -> some View { VStack(alignment: .leading, spacing: 8) {
        HStack { Button { Task { await model.setCompleted(id: row.id, completed: !row.isCompletedToday) } } label: { Image(systemName: row.isCompletedToday ? "checkmark.circle.fill" : "circle") }.frame(minWidth: 44, minHeight: 44).disabled(!row.isCompletedToday && !model.canCompleteToday(row)).accessibilityLabel("Mark \(row.routine.title) \(row.isCompletedToday ? "incomplete" : "complete")").accessibilityValue(row.isCompletedToday ? "Completed" : "Not completed").accessibilityHint(row.isCompletedToday || model.canCompleteToday(row) ? "" : "This routine is not scheduled for completion today.")
        VStack(alignment: .leading) { Text(row.routine.title); Text("\(row.streak) \(row.streak == 1 ? "day" : "days") streak").font(.footnote).foregroundStyle(.secondary) }; Spacer(); Button("Edit") { editing = row }.frame(minWidth: 44, minHeight: 44) }
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 4) { ForEach(row.history) { day in Image(systemName: day.isCompleted ? "checkmark.circle.fill" : (day.isScheduled ? "circle" : "minus")) } }.accessibilityElement(children: .ignore).accessibilityLabel("14-day history").accessibilityValue(model.historyAccessibilityValue(row.history))
        ViewThatFits(in: .horizontal) { HStack { routineActions(row) }; VStack(alignment: .leading) { routineActions(row) } }
    }.padding(.vertical, 4) }
    @ViewBuilder private func routineActions(_ row: RoutineRowState) -> some View { Button(row.routine.isPaused ? "Resume" : "Pause") { model.setPaused(id: row.id, paused: !row.routine.isPaused) }.frame(minWidth: 44, minHeight: 44); Button(row.routine.isArchived ? "Unarchive" : "Archive") { model.setArchived(id: row.id, archived: !row.routine.isArchived) }.frame(minWidth: 44, minHeight: 44); Button("Delete", role: .destructive) { deleteTarget = row }.frame(minWidth: 44, minHeight: 44) }
}
