import SwiftUI

struct RoutineDeepLinkSignal: Equatable, Sendable {
    let id: UUID
    let routineID: UUID
}

struct RoutineDeepLinkResolver {
    private(set) var lastSignalID: UUID?

    mutating func resolve(
        _ signal: RoutineDeepLinkSignal?,
        rows: [RoutineRowState]
    ) -> RoutineRowState? {
        guard let signal, signal.id != lastSignalID else { return nil }
        lastSignalID = signal.id
        return rows.first { $0.id == signal.routineID }
    }
}

struct RoutinesView: View {
    private struct DeleteRequest: Identifiable { let id: UUID; let title: String }
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var model: RoutinesViewModel
    @State private var editing: RoutineRowState?
    @State private var deleteRequest: DeleteRequest?
    @State private var deepLinkResolver = RoutineDeepLinkResolver()
    @State private var refreshRegistrationID = UUID()
    private let revision: AppContentRevision
    private let quickEntryRefresh: QuickEntryRefreshSignal?
    private let routineDeepLink: RoutineDeepLinkSignal?
    private let categories: [CategorySnapshot]
    private let environment: AppEnvironment
    private let profileSelection: ProfileSelectionController
    private let onDeepLinkHandled: @MainActor (UUID, Bool) -> Void
    private let onPresentationChanged: @MainActor (Bool) -> Void
    init(
        environment: AppEnvironment,
        revision: AppContentRevision = .init(lifecycle: 0, profileScope: 0),
        quickEntryRefresh: QuickEntryRefreshSignal? = nil,
        routineDeepLink: RoutineDeepLinkSignal? = nil,
        onDeepLinkHandled: @escaping @MainActor (UUID, Bool) -> Void = { _, _ in },
        onPresentationChanged: @escaping @MainActor (Bool) -> Void = { _ in }
    ) {
        let selection = environment.profileSelection
        _model = State(initialValue: RoutinesViewModel(
            repository: environment.routines,
            routineProfileMutations: environment.routineProfileMutations,
            selectedProfileID: {
                guard case let .saved(id) = selection.activeIdentity else { return nil }
                return id
            },
            onProfileMembershipChanged: { try? selection.refreshScope() },
            currentScope: { try environment.profileScopes.resolve(selection.activeIdentity) },
            rescheduleNotifications: {
                await environment.notificationCoordinator.clear()
                await environment.rescheduleNotifications()
            }
        ))
        categories = (try? environment.categories.list()) ?? []
        self.environment = environment
        profileSelection = selection
        self.revision = revision
        self.quickEntryRefresh = quickEntryRefresh
        self.routineDeepLink = routineDeepLink
        self.onDeepLinkHandled = onDeepLinkHandled
        self.onPresentationChanged = onPresentationChanged
    }
    var body: some View { NavigationStack { List {
        if let error = model.refreshErrorMessage { Section { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary); Button("Retry Refresh") { model.reload() }.frame(minWidth: 44, minHeight: 44) } }
        if let error = model.actionErrorMessage { Section { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary); Button(actionRetryLabel) { if let target = model.resolveDeleteRetryTarget() { requestDelete(target) } else if model.failedActionOperation != nil { model.retryFailedAction() } }.frame(minWidth: 44, minHeight: 44) } }
        if model.isProfileEmpty { ContentUnavailableView("No routines in this profile", systemImage: "repeat", description: Text("Add routines to this profile in Settings.")) }
        Section("Active") { if model.active.isEmpty && !model.isProfileEmpty { ContentUnavailableView(model.archived.isEmpty ? "No routines" : "No active routines", systemImage: "repeat", description: Text("Use Add to create a routine for the habits you want to keep.")) }; ForEach(model.active) { row($0) } }
        if !model.archived.isEmpty { Section { DisclosureGroup("Archived") { ForEach(model.archived) { row($0) } } } }
    }
    .scrollContentBackground(.hidden)
    .background(CalendarTheme.background)
    .navigationTitle("Routines")
    .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
            ProfileSelectorToolbar(selection: profileSelection)
        }
    }
    .sheet(item: $editing) {
        RoutineEditorView(
            model: model,
            row: $0,
            categories: categories,
            profiles: profileSelection.profiles,
            creationIdentity: profileSelection.activeIdentity
        )
    }
    .sheet(item: $deleteRequest, onDismiss: { deleteRequest = nil }) {
        deleteConfirmation($0)
    }
    .task(id: revision) {
        guard routineDeepLink == nil else { return }
        model.reload()
    }
    .onChange(of: quickEntryRefresh, initial: true) { _, signal in
        guard let signal else { return }
        model.refreshAfterQuickEntry(signal)
    }
    .task(id: RoutineDeepLinkProcessingKey(
        signalID: routineDeepLink?.id,
        editorID: editing?.id,
        deleteRequestID: deleteRequest?.id
    )) {
        handleRoutineDeepLink()
    }
    .onChange(
        of: editing != nil || deleteRequest != nil,
        initial: true
    ) { _, isPresented in
        onPresentationChanged(isPresented)
    }
    .refreshable { model.reload() }
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
    private var actionRetryLabel: String { switch model.failedActionOperation { case .pause: "Retry Pause"; case .archive: "Retry Archive"; case .completion: "Retry Completion"; case .delete: "Retry Delete"; case nil: "Retry" } }
    private func row(_ row: RoutineRowState) -> some View { VStack(alignment: .leading, spacing: 8) {
        HStack { Button { Task { await model.setCompleted(id: row.id, completed: !row.isCompletedToday) } } label: { Image(systemName: row.isCompletedToday ? "checkmark.circle.fill" : "circle").foregroundStyle(CalendarTheme.routine) }.frame(minWidth: 44, minHeight: 44).disabled(!model.canChangeCompletion(row)).accessibilityLabel("Mark \(row.routine.title) \(row.isCompletedToday ? "incomplete" : "complete")").accessibilityValue(row.isCompletedToday ? "Completed" : "Not completed").accessibilityHint(!model.isRepresentingCurrentDay(row) ? "Refresh routines before changing completion." : (model.canChangeCompletion(row) ? "" : "This routine is not scheduled for completion today."))
        VStack(alignment: .leading) { Text(row.routine.title); Text("\(row.streak) \(row.streak == 1 ? "day" : "days") streak").font(.footnote).foregroundStyle(.secondary) }; Spacer(); Button("Edit") { presentEditor(row) }.frame(minWidth: 44, minHeight: 44).accessibilityIdentifier("routine-edit-\(row.id.uuidString)") }
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 4) { ForEach(row.history) { day in Image(systemName: day.isCompleted ? "checkmark.circle.fill" : (day.isScheduled ? "circle" : "minus")).foregroundStyle(day.isScheduled ? CalendarTheme.routine : Color.secondary) } }.accessibilityElement(children: .ignore).accessibilityLabel("14-day history").accessibilityValue(model.historyAccessibilityValue(row.history))
        if dynamicTypeSize.isAccessibilitySize { VStack(alignment: .leading) { routineActions(row) } } else { HStack { routineActions(row) } }
    }.buttonStyle(.borderless).padding(.vertical, 4) }
    @ViewBuilder private func routineActions(_ row: RoutineRowState) -> some View { Button(row.routine.isPaused ? "Resume" : "Pause") { model.setPaused(id: row.id, paused: !row.routine.isPaused) }.frame(minWidth: 44, minHeight: 44).accessibilityIdentifier("routine-pause-\(row.id.uuidString)"); Button(row.routine.isArchived ? "Unarchive" : "Archive") { model.setArchived(id: row.id, archived: !row.routine.isArchived) }.frame(minWidth: 44, minHeight: 44).accessibilityIdentifier("routine-archive-\(row.id.uuidString)"); Button("Delete", role: .destructive) { requestDelete(row) }.frame(minWidth: 44, minHeight: 44).accessibilityIdentifier("routine-delete-\(row.id.uuidString)") }
    private func deleteConfirmation(_ request: DeleteRequest) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Delete \(request.title)?").font(.headline)
                    Text("This routine and its completion history will be permanently removed from this iPhone.")
                        .foregroundStyle(.secondary)
                    if let error = model.deleteErrorMessage(for: request.id) {
                        Text(error).foregroundStyle(.red)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .navigationTitle("Confirm delete")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { deleteRequest = nil } label: {
                        CalendarToolbarActionLabel(title: "Cancel Delete")
                    }
                    .accessibilityIdentifier("routine-delete-cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .destructive) { confirmDelete(request) } label: {
                        CalendarToolbarActionLabel(title: "Confirm Delete", isProminent: true)
                    }
                    .accessibilityIdentifier("routine-delete-confirm")
                }
            }
        }
    }
    private func requestDelete(_ row: RoutineRowState) {
        deleteRequest = .init(id: row.id, title: row.routine.title)
        onPresentationChanged(true)
    }
    private func confirmDelete(_ request: DeleteRequest) { guard (model.active + model.archived).contains(where: { $0.id == request.id }) else { deleteRequest = nil; onPresentationChanged(false); return }; if model.delete(id: request.id) { deleteRequest = nil; onPresentationChanged(false) } }

    private func presentEditor(_ row: RoutineRowState) {
        editing = row
        onPresentationChanged(true)
    }

    private func handleRoutineDeepLink() {
        guard editing == nil,
              deleteRequest == nil,
              let signal = routineDeepLink else { return }
        model.reload()
        guard !Task.isCancelled,
              routineDeepLink?.id == signal.id,
              editing == nil,
              deleteRequest == nil else { return }

        let scope = try? environment.profileScopes.resolve(
            environment.profileSelection.activeIdentity
        )
        let liveRoutines = try? environment.routines.list(includeArchived: true)
        let isAvailable = scope?.routineIDs.contains(signal.routineID) == true
            && liveRoutines?.contains(where: { $0.id == signal.routineID }) == true
        editing = deepLinkResolver.resolve(
            signal,
            rows: isAvailable ? model.active + model.archived : []
        )
        if editing != nil { onPresentationChanged(true) }
        onDeepLinkHandled(signal.id, editing != nil)
    }
}

private struct RoutineDeepLinkProcessingKey: Hashable {
    let signalID: UUID?
    let editorID: UUID?
    let deleteRequestID: UUID?
}
