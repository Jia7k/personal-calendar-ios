import SwiftUI

struct TodayView: View {
    @State private var model: TodayViewModel
    @State private var editorPresentation: TodayEditorPresentation?
    private let environment: AppEnvironment
    private let openSettings: @MainActor () -> Void
    private let revision: Int
    private let quickEntryRefresh: QuickEntryRefreshSignal?

    init(
        environment: AppEnvironment,
        revision: Int = 0,
        quickEntryRefresh: QuickEntryRefreshSignal? = nil,
        openSettings: @escaping @MainActor () -> Void = {}
    ) {
        self.environment = environment
        _model = State(initialValue: TodayViewModel(calendar: environment.calendar, reminders: environment.reminders, routines: environment.routines, composer: environment.agendaComposer, settings: environment.settings))
        self.openSettings = openSettings
        self.revision = revision
        self.quickEntryRefresh = quickEntryRefresh
    }

    var body: some View {
        NavigationStack {
            List {
                if model.showsCalendarPermissionCard { permissionCard(title: "Calendar events are unavailable", restricted: model.calendarAccessState == .restricted) }
                if model.showsRemindersPermissionCard { permissionCard(title: "Tasks are unavailable", restricted: model.remindersAccessState == .restricted) }
                errorRow(model.calendarError, source: "Calendar")
                errorRow(model.remindersError, source: "Reminders")
                errorRow(model.routinesError, source: "Routines")
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
            .overlay { if model.isLoading && !model.hasLoaded { ProgressView() } }
            .navigationTitle("Today")
            .task(id: revision) { await model.load() }
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
                    TaskEditorView(model: editorModel, lists: lists, nilDestinationLabel: "Preserve Current", showsDelete: true, onDismiss: dismissEditor)
                }
            }
        }
    }

    @ViewBuilder private func section(_ title: LocalizedStringKey, items: [AgendaItem]) -> some View {
        if !items.isEmpty {
            Section(title) {
                ForEach(items) { item in
                    AgendaRow(item: item, isMutating: model.mutatingItemIDs.contains(item.id), open: openAction(for: item)) { state in
                        Task {
                            if item.source == .task {
                                await model.setTaskCompleted(item, completed: state)
                            } else {
                                await model.setRoutineCompleted(item, completed: state)
                            }
                        }
                    }
                }
            }
        }
    }

    private func openAction(for item: AgendaItem) -> (() -> Void)? {
        switch item.origin {
        case .event, .reminder:
            { openAgendaItem(item.origin) }
        case .routine, .synthetic:
            nil
        }
    }

    private func openAgendaItem(_ origin: AgendaItemOrigin) {
        switch origin {
        case let .event(displayID):
            let editorModel = EventEditorViewModel.edit(
                displayID: displayID,
                service: environment.calendar,
                categories: environment.categories,
                onCommitted: { commit in finishEventEditorAndReload(commit) },
                onReconciliationNeeded: reconcileEditorWithoutDismissing
            )
            editorPresentation = .init(content: .event(model: editorModel, calendars: environment.calendar.calendars()))
        case let .reminder(reminderID):
            let editorModel = TaskEditorViewModel.editing(
                reminderID: reminderID,
                service: environment.reminders,
                categories: environment.categories,
                onCommitted: { commit in finishTaskEditorAndReload(commit) },
                onReconciliationNeeded: reconcileEditorWithoutDismissing
            )
            editorPresentation = .init(content: .task(model: editorModel, lists: environment.reminders.lists()))
        case .routine, .synthetic:
            break
        }
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
