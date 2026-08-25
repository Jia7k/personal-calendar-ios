import SwiftUI

struct RoutinesView: View {
    private struct DeleteRequest: Identifiable { let id: UUID; let title: String }
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var model: RoutinesViewModel
    @State private var editing: RoutineRowState?
    @State private var deleteRequest: DeleteRequest?
    private let revision: Int
    private let quickEntryRefresh: QuickEntryRefreshSignal?
    private let categories: [CategorySnapshot]
    init(
        environment: AppEnvironment,
        revision: Int = 0,
        quickEntryRefresh: QuickEntryRefreshSignal? = nil
    ) {
        _model = State(initialValue: RoutinesViewModel(repository: environment.routines))
        categories = (try? environment.categories.list()) ?? []
        self.revision = revision
        self.quickEntryRefresh = quickEntryRefresh
    }
    var body: some View { NavigationStack { List {
        if let error = model.refreshErrorMessage { Section { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary); Button("Retry Refresh") { model.reload() }.frame(minWidth: 44, minHeight: 44) } }
        if let error = model.actionErrorMessage { Section { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary); Button(actionRetryLabel) { if let target = model.resolveDeleteRetryTarget() { requestDelete(target) } else if model.failedActionOperation != nil { model.retryFailedAction() } }.frame(minWidth: 44, minHeight: 44) } }
        Section("Active") { if model.active.isEmpty { ContentUnavailableView(model.archived.isEmpty ? "No routines" : "No active routines", systemImage: "repeat", description: Text("Use Add to create a routine for the habits you want to keep.")) }; ForEach(model.active) { row($0) } }
        if !model.archived.isEmpty { Section { DisclosureGroup("Archived") { ForEach(model.archived) { row($0) } } } }
    }.navigationTitle("Routines")
    .sheet(item: $editing) { RoutineEditorView(model: model, row: $0, categories: categories) }.sheet(item: $deleteRequest, onDismiss: { deleteRequest = nil }) { deleteConfirmation($0) }
    .task(id: revision) { model.reload() }
    .onChange(of: quickEntryRefresh, initial: true) { _, signal in
        guard let signal else { return }
        model.refreshAfterQuickEntry(signal)
    }
    .refreshable { model.reload() }
    }
    }
    private var actionRetryLabel: String { switch model.failedActionOperation { case .pause: "Retry Pause"; case .archive: "Retry Archive"; case .completion: "Retry Completion"; case .delete: "Retry Delete"; case nil: "Retry" } }
    private func row(_ row: RoutineRowState) -> some View { VStack(alignment: .leading, spacing: 8) {
        HStack { Button { Task { await model.setCompleted(id: row.id, completed: !row.isCompletedToday) } } label: { Image(systemName: row.isCompletedToday ? "checkmark.circle.fill" : "circle") }.frame(minWidth: 44, minHeight: 44).disabled(!model.canChangeCompletion(row)).accessibilityLabel("Mark \(row.routine.title) \(row.isCompletedToday ? "incomplete" : "complete")").accessibilityValue(row.isCompletedToday ? "Completed" : "Not completed").accessibilityHint(!model.isRepresentingCurrentDay(row) ? "Refresh routines before changing completion." : (model.canChangeCompletion(row) ? "" : "This routine is not scheduled for completion today."))
        VStack(alignment: .leading) { Text(row.routine.title); Text("\(row.streak) \(row.streak == 1 ? "day" : "days") streak").font(.footnote).foregroundStyle(.secondary) }; Spacer(); Button("Edit") { editing = row }.frame(minWidth: 44, minHeight: 44).accessibilityIdentifier("routine-edit-\(row.id.uuidString)") }
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 4) { ForEach(row.history) { day in Image(systemName: day.isCompleted ? "checkmark.circle.fill" : (day.isScheduled ? "circle" : "minus")) } }.accessibilityElement(children: .ignore).accessibilityLabel("14-day history").accessibilityValue(model.historyAccessibilityValue(row.history))
        if dynamicTypeSize.isAccessibilitySize { VStack(alignment: .leading) { routineActions(row) } } else { HStack { routineActions(row) } }
    }.buttonStyle(.borderless).padding(.vertical, 4) }
    @ViewBuilder private func routineActions(_ row: RoutineRowState) -> some View { Button(row.routine.isPaused ? "Resume" : "Pause") { model.setPaused(id: row.id, paused: !row.routine.isPaused) }.frame(minWidth: 44, minHeight: 44).accessibilityIdentifier("routine-pause-\(row.id.uuidString)"); Button(row.routine.isArchived ? "Unarchive" : "Archive") { model.setArchived(id: row.id, archived: !row.routine.isArchived) }.frame(minWidth: 44, minHeight: 44).accessibilityIdentifier("routine-archive-\(row.id.uuidString)"); Button("Delete", role: .destructive) { requestDelete(row) }.frame(minWidth: 44, minHeight: 44).accessibilityIdentifier("routine-delete-\(row.id.uuidString)") }
    private func deleteConfirmation(_ request: DeleteRequest) -> some View { NavigationStack { ScrollView { VStack(alignment: .leading, spacing: 16) { Text("Delete \(request.title)?").font(.headline); Text("This routine and its completion history will be permanently removed from this iPhone.").foregroundStyle(.secondary); if let error = model.deleteErrorMessage(for: request.id) { Text(error).foregroundStyle(.red) } }.frame(maxWidth: .infinity, alignment: .leading).padding() }.navigationTitle("Confirm delete").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel Delete") { deleteRequest = nil }.frame(minWidth: 44, minHeight: 44) }; ToolbarItem(placement: .confirmationAction) { Button("Confirm Delete", role: .destructive) { confirmDelete(request) }.frame(minWidth: 44, minHeight: 44) } } } }
    private func requestDelete(_ row: RoutineRowState) { deleteRequest = .init(id: row.id, title: row.routine.title) }
    private func confirmDelete(_ request: DeleteRequest) { guard (model.active + model.archived).contains(where: { $0.id == request.id }) else { deleteRequest = nil; return }; if model.delete(id: request.id) { deleteRequest = nil } }
}
