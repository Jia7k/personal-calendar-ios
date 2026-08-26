import SwiftUI

struct ProfilesSettingsView: View {
    private struct EditorPresentation: Identifiable {
        let id = UUID()
        let editor: ProfileEditorState
    }

    @State private var model: ProfilesSettingsModel
    @State private var editorPresentation: EditorPresentation?
    @State private var pendingDelete: ProfileSnapshot?
    @State private var errorMessage: String?

    init(environment: AppEnvironment) {
        let selection = environment.profileSelection
        let timetable = environment.timetableSnapshotCoordinator
        let liveActivity = environment.timetableLiveActivityCoordinator
        let notificationCoordinator = environment.notificationCoordinator
        let rescheduleNotifications = environment.rescheduleNotifications
        let rebuildTimetable: @MainActor (Bool) -> Void = { failClosed in
            guard (try? timetable.refresh(failClosed: failClosed)) != nil,
                  let catalog = timetable.latestCatalog else { return }
            Task { await liveActivity.reconcile(catalog: catalog) }
        }
        _model = State(initialValue: ProfilesSettingsModel(
            repository: environment.profiles,
            calendar: environment.calendar,
            reminders: environment.reminders,
            routines: environment.routines,
            profileImpactDidChange: { id, visibilityChanged, removedCalendarMembership in
                defer {
                    rebuildTimetable(removedCalendarMembership)
                    if visibilityChanged {
                        Task {
                            await notificationCoordinator.clear()
                            await rescheduleNotifications()
                        }
                    }
                }
                try selection.profileDidChange(id: id, visibilityChanged: visibilityChanged)
            },
            profileWasDeleted: { id in
                defer {
                    rebuildTimetable(true)
                    Task {
                        await notificationCoordinator.clear()
                        await rescheduleNotifications()
                    }
                }
                try selection.profileWasDeleted(id: id)
            }
        ))
    }

    var body: some View {
        List {
            Section("Everything") {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Everything")
                        Text("Shows the combined contents assigned to any saved profile.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "rectangle.stack.fill")
                        .foregroundStyle(CalendarTheme.accent)
                }
                .frame(minHeight: CalendarTheme.minimumTapSize)
            }

            Section("Saved Profiles") {
                ForEach(model.profiles) { profile in
                    profileRow(profile)
                        .swipeActions(edge: .trailing) {
                            Button("Delete", role: .destructive) {
                                pendingDelete = profile
                            }
                            .disabled(model.profiles.count == 1)
                        }
                }
                .onMove(perform: moveProfiles)
            }
        }
        .navigationTitle("Profiles")
        .task { reload() }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                EditButton()
                    .disabled(model.profiles.count < 2)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    presentEditor(profileID: nil)
                } label: {
                    Label("Add Profile", systemImage: "plus")
                }
                .frame(
                    minWidth: CalendarTheme.minimumTapSize,
                    minHeight: CalendarTheme.minimumTapSize
                )
                .accessibilityIdentifier("profile-add")
            }
        }
        .sheet(item: $editorPresentation) { presentation in
            ProfileEditorView(editor: presentation.editor) { editor in
                _ = try model.save(editor)
            }
        }
        .confirmationDialog(
            "Delete \(pendingDelete?.name ?? "profile")?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let profile = pendingDelete {
                Button("Delete Profile", role: .destructive) {
                    delete(profile)
                }
                .disabled(model.profiles.count == 1)
                .accessibilityIdentifier("profile-confirm-delete")
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("Only this profile is deleted. Its calendars, reminders, and routines stay untouched.")
        }
        .alert(
            "Couldn’t Update Profiles",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func profileRow(_ profile: ProfileSnapshot) -> some View {
        Button {
            presentEditor(profileID: profile.id)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: profile.symbolName)
                    .foregroundStyle(CalendarTheme.color(hex: profile.colorHex) ?? .secondary)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                Text(profile.name)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: CalendarTheme.minimumTapSize)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(profile.name)
        .accessibilityHint("Opens profile editing")
        .accessibilityIdentifier("profile-row-\(profile.id.uuidString)")
    }

    private func reload() {
        do {
            try model.reload()
            errorMessage = nil
        } catch {
            errorMessage = "Profiles could not be loaded. Try again."
        }
    }

    private func presentEditor(profileID: UUID?) {
        do {
            editorPresentation = EditorPresentation(
                editor: try model.makeEditor(profileID: profileID)
            )
        } catch {
            errorMessage = "This profile could not be opened. Try again."
        }
    }

    private func moveProfiles(from source: IndexSet, to destination: Int) {
        var ids = model.profiles.map(\.id)
        ids.move(fromOffsets: source, toOffset: destination)
        do {
            try model.reorder(ids)
        } catch {
            try? model.reload()
            errorMessage = "Profiles could not be reordered. Try again."
        }
    }

    private func delete(_ profile: ProfileSnapshot) {
        defer { pendingDelete = nil }
        do {
            try model.delete(id: profile.id)
        } catch ProfileRepositoryError.cannotDeleteLastProfile {
            errorMessage = "Keep at least one saved profile."
        } catch {
            errorMessage = "The profile could not be deleted. Try again."
        }
    }
}
