import SwiftUI

struct ProfileEditorView: View {
    private struct ColorChoice: Identifiable {
        let name: String
        let hex: String
        var id: String { hex }
    }

    private static let symbols = [
        "person.fill",
        "graduationcap.fill",
        "briefcase.fill",
        "house.fill",
        "calendar",
        "book.fill",
        "heart.fill",
        "figure.run",
        "star.fill"
    ]

    private static let colors = [
        ColorChoice(name: "Terracotta", hex: "#CB6B4F"),
        ColorChoice(name: "Sage", hex: "#3A8D7C"),
        ColorChoice(name: "Slate Blue", hex: "#4868A8"),
        ColorChoice(name: "Lavender", hex: "#8A63B8")
    ]

    @Environment(\.dismiss) private var dismiss
    @State private var editor: ProfileEditorState
    @State private var errorMessage: String?
    private let onSave: @MainActor (ProfileEditorState) throws -> Void

    init(
        editor: ProfileEditorState,
        onSave: @escaping @MainActor (ProfileEditorState) throws -> Void
    ) {
        _editor = State(initialValue: editor)
        self.onSave = onSave
    }

    var body: some View {
        @Bindable var editor = editor

        NavigationStack {
            Form {
                Section("Profile") {
                    TextField("Name", text: $editor.draft.name)
                        .accessibilityIdentifier("profile-name")

                    Picker("Icon", selection: $editor.draft.symbolName) {
                        ForEach(Self.symbols, id: \.self) { symbol in
                            Label(symbolLabel(symbol), systemImage: symbol)
                                .tag(symbol)
                        }
                    }
                    .accessibilityIdentifier("profile-symbol")

                    Picker("Color", selection: $editor.draft.colorHex) {
                        ForEach(Self.colors) { choice in
                            HStack {
                                Circle()
                                    .fill(CalendarTheme.color(hex: choice.hex) ?? .secondary)
                                    .frame(width: 16, height: 16)
                                Text(choice.name)
                            }
                            .tag(choice.hex)
                        }
                    }
                    .accessibilityIdentifier("profile-color")
                }

                Section("Calendars") {
                    if editor.calendars.isEmpty {
                        Text("No calendars are currently available.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(editor.calendars) { calendar in
                        Toggle(isOn: calendarMembership(calendar.id)) {
                            sourceLabel(
                                title: calendar.title,
                                colorHex: calendar.colorHex,
                                isReadOnly: !calendar.allowsContentModifications
                            )
                        }
                        .accessibilityIdentifier("profile-calendar-\(calendar.id)")
                    }

                    if editor.waitingCalendarCount > 0 {
                        waitingRow(
                            count: editor.waitingCalendarCount,
                            singular: "calendar",
                            plural: "calendars"
                        )
                    }
                }

                Section("Default Calendar") {
                    Picker("New events", selection: defaultCalendarSelection) {
                        Text("Ask Every Time").tag(String?.none)
                        ForEach(editor.defaultCalendarChoices) { calendar in
                            Text(calendar.title).tag(Optional(calendar.id))
                        }
                    }
                    .disabled(editor.defaultCalendarChoices.isEmpty)
                    .accessibilityIdentifier("profile-default-calendar")

                    if editor.draft.defaultCalendarID != nil,
                       editor.validatedDefaultCalendarID == nil {
                        Text("The previous default is no longer writable. Choose another or ask every time.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Reminder Lists") {
                    if editor.reminderLists.isEmpty {
                        Text("No reminder lists are currently available.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(editor.reminderLists) { list in
                        Toggle(isOn: reminderMembership(list.id)) {
                            sourceLabel(
                                title: list.title,
                                colorHex: list.colorHex,
                                isReadOnly: !list.allowsContentModifications
                            )
                        }
                        .accessibilityIdentifier("profile-reminder-list-\(list.id)")
                    }

                    if editor.waitingReminderListCount > 0 {
                        waitingRow(
                            count: editor.waitingReminderListCount,
                            singular: "reminder list",
                            plural: "reminder lists"
                        )
                    }
                }

                Section("Default Reminder List") {
                    Picker("New tasks", selection: defaultReminderSelection) {
                        Text("Ask Every Time").tag(String?.none)
                        ForEach(editor.defaultReminderListChoices) { list in
                            Text(list.title).tag(Optional(list.id))
                        }
                    }
                    .disabled(editor.defaultReminderListChoices.isEmpty)
                    .accessibilityIdentifier("profile-default-reminder-list")

                    if editor.draft.defaultReminderListID != nil,
                       editor.validatedDefaultReminderListID == nil {
                        Text("The previous default is no longer writable. Choose another or ask every time.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Routines") {
                    if editor.routines.isEmpty {
                        Text("No routines are available.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(editor.routines) { routine in
                        Toggle(isOn: routineMembership(routine.id)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(routine.title)
                                if routine.isArchived {
                                    Text("Archived")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .accessibilityIdentifier("profile-routine-\(routine.id.uuidString)")
                    }
                }
            }
            .navigationTitle(editor.profileID == nil ? "New Profile" : "Edit Profile")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .frame(
                            minWidth: CalendarTheme.minimumTapSize,
                            minHeight: CalendarTheme.minimumTapSize
                        )
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(editor.draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .frame(
                            minWidth: CalendarTheme.minimumTapSize,
                            minHeight: CalendarTheme.minimumTapSize
                        )
                        .accessibilityIdentifier("profile-save")
                }
            }
            .alert(
                "Couldn’t Save Profile",
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
    }

    private var defaultCalendarSelection: Binding<String?> {
        Binding(
            get: { editor.validatedDefaultCalendarID },
            set: { editor.draft.defaultCalendarID = $0 }
        )
    }

    private var defaultReminderSelection: Binding<String?> {
        Binding(
            get: { editor.validatedDefaultReminderListID },
            set: { editor.draft.defaultReminderListID = $0 }
        )
    }

    private func calendarMembership(_ id: String) -> Binding<Bool> {
        Binding(
            get: { editor.draft.calendarIDs.contains(id) },
            set: { selected in
                if selected {
                    editor.draft.calendarIDs.insert(id)
                } else {
                    editor.draft.calendarIDs.remove(id)
                    if editor.draft.defaultCalendarID == id {
                        editor.draft.defaultCalendarID = nil
                    }
                }
            }
        )
    }

    private func reminderMembership(_ id: String) -> Binding<Bool> {
        Binding(
            get: { editor.draft.reminderListIDs.contains(id) },
            set: { selected in
                if selected {
                    editor.draft.reminderListIDs.insert(id)
                } else {
                    editor.draft.reminderListIDs.remove(id)
                    if editor.draft.defaultReminderListID == id {
                        editor.draft.defaultReminderListID = nil
                    }
                }
            }
        )
    }

    private func routineMembership(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: { editor.draft.routineIDs.contains(id) },
            set: { selected in
                if selected {
                    editor.draft.routineIDs.insert(id)
                } else {
                    editor.draft.routineIDs.remove(id)
                }
            }
        )
    }

    private func sourceLabel(
        title: String,
        colorHex: String,
        isReadOnly: Bool
    ) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(CalendarTheme.color(hex: colorHex) ?? .secondary)
                .frame(width: 12, height: 12)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if isReadOnly {
                    Text("Read-only")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func waitingRow(count: Int, singular: String, plural: String) -> some View {
        Label(
            "Waiting to reconnect: \(count) \(count == 1 ? singular : plural)",
            systemImage: "arrow.triangle.2.circlepath"
        )
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("profile-waiting-to-reconnect")
    }

    private func symbolLabel(_ symbol: String) -> String {
        switch symbol {
        case "person.fill": "Personal"
        case "graduationcap.fill": "School"
        case "briefcase.fill": "Work"
        case "house.fill": "Home"
        case "calendar": "Calendar"
        case "book.fill": "Study"
        case "heart.fill": "Health"
        case "figure.run": "Fitness"
        case "star.fill": "Favorite"
        default: "Profile"
        }
    }

    private func save() {
        do {
            try onSave(editor)
            dismiss()
        } catch ProfileRepositoryError.duplicateName {
            errorMessage = "Choose a different profile name."
        } catch {
            errorMessage = "The profile could not be saved. Check its details and try again."
        }
    }
}
