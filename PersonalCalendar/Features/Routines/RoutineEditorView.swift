import SwiftUI

struct RoutineEditorView: View {
    let model: RoutinesViewModel
    let row: RoutineRowState?
    let categories: [CategorySnapshot]
    let profiles: [ProfileSnapshot]
    let creationIdentity: ProfileIdentity?
    private let sourceDraft: RoutineDraft?

    @Environment(\.dismiss) private var dismiss
    @State private var operation: RoutineEditorOperation
    @State private var capturedProfileID: UUID?
    @State private var showingProfileChooser = false
    @State private var title: String
    @State private var days: Set<Int>
    @State private var window: RoutineWindow
    @State private var usesReminder: Bool
    @State private var reminder: Date
    @State private var categoryID: UUID?

    init(
        model: RoutinesViewModel,
        row: RoutineRowState? = nil,
        categories: [CategorySnapshot] = [],
        profiles: [ProfileSnapshot] = [],
        creationIdentity: ProfileIdentity? = nil,
        initialDraft: RoutineDraft? = nil,
        capturedProfileID: UUID? = nil
    ) {
        self.model = model
        self.row = row
        self.categories = categories
        self.profiles = profiles
        self.creationIdentity = creationIdentity

        let initialOperation: RoutineEditorOperation = initialDraft != nil
            ? .create
            : row.map { .update($0.id) } ?? .create
        let failed = model.failedDraft(for: initialOperation)
        let sourceDraft = row.map {
            RoutineDraft(
                title: $0.routine.title,
                weekdays: $0.routine.weekdays,
                window: $0.routine.window,
                reminderHour: $0.routine.reminderHour,
                reminderMinute: $0.routine.reminderMinute,
                categoryID: $0.routine.categoryID
            )
        }
        self.sourceDraft = sourceDraft
        let draft = failed ?? initialDraft ?? sourceDraft

        _operation = State(initialValue: initialOperation)
        _capturedProfileID = State(initialValue: capturedProfileID)
        _title = State(initialValue: draft?.title ?? "")
        _days = State(initialValue: draft?.weekdays ?? [])
        _window = State(initialValue: draft?.window ?? .anytime)
        _usesReminder = State(initialValue: draft?.reminderHour != nil)
        _reminder = State(
            initialValue: model.reminderDate(
                hour: draft?.reminderHour,
                minute: draft?.reminderMinute
            )
        )
        _categoryID = State(initialValue: draft?.categoryID)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Routine") {
                    TextField("Title", text: $title)
                        .accessibilityIdentifier("Routine title")
                    Picker("Window", selection: $window) {
                        ForEach(RoutineWindow.allCases, id: \.self) {
                            Text(model.windowName($0)).tag($0)
                        }
                    }
                    .accessibilityIdentifier("Routine window")
                }

                Section("Days") {
                    Button(days.count == 7 ? "Clear daily" : "Daily") {
                        days = days.count == 7 ? [] : Set(1...7)
                    }
                    .frame(minHeight: CalendarTheme.minimumTapSize)

                    ForEach(model.weekdayOrder, id: \.self) { day in
                        Button { toggle(day) } label: {
                            HStack {
                                Text(model.weekdayName(day))
                                Spacer()
                                if days.contains(day) {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                        .frame(minHeight: CalendarTheme.minimumTapSize)
                        .accessibilityLabel(model.weekdayName(day))
                        .accessibilityAddTraits(
                            days.contains(day) ? .isSelected : []
                        )
                    }
                }

                Section("App Color") {
                    Picker("Category", selection: $categoryID) {
                        Text("No Category").tag(UUID?.none)
                        ForEach(categories) { category in
                            Text(category.name).tag(Optional(category.id))
                        }
                    }
                    .frame(minHeight: CalendarTheme.minimumTapSize)
                    .accessibilityIdentifier("routine-editor-category")
                }

                Section("Reminder") {
                    Toggle("Set a reminder", isOn: $usesReminder)
                        .accessibilityIdentifier("Routine reminder toggle")
                    if usesReminder {
                        DatePicker(
                            "Time",
                            selection: $reminder,
                            displayedComponents: .hourAndMinute
                        )
                        .accessibilityIdentifier("Routine reminder time")
                    }
                }

                if canOfferDuplicate {
                    Section("Create another") {
                        Button(
                            "Duplicate Routine",
                            systemImage: "plus.square.on.square"
                        ) {
                            requestDuplicate()
                        }
                        .disabled(hasUnsavedSourceChanges)
                        .frame(minHeight: CalendarTheme.minimumTapSize)
                        .accessibilityIdentifier("routine-duplicate")
                        Text(
                            hasUnsavedSourceChanges
                                ? "Save or discard your edits before duplicating this routine."
                                : "The copy starts active with no completion history. Choose its profile before saving when Everything is selected."
                        )
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if let error = model.editorErrorMessage,
                   model.canRetryEditor(operation) {
                    Section {
                        Text(error).foregroundStyle(.red)
                        Button("Retry") { save() }
                            .disabled(!isValid)
                            .frame(
                                minWidth: CalendarTheme.minimumTapSize,
                                minHeight: CalendarTheme.minimumTapSize
                            )
                            .accessibilityIdentifier("routine-save-retry")
                    }
                }
            }
            .navigationTitle(navigationTitle)
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
                        .disabled(!isValid)
                        .frame(
                            minWidth: CalendarTheme.minimumTapSize,
                            minHeight: CalendarTheme.minimumTapSize
                        )
                        .accessibilityIdentifier("routine-save")
                }
            }
            .confirmationDialog(
                "Duplicate in Profile",
                isPresented: $showingProfileChooser,
                titleVisibility: .visible
            ) {
                ForEach(orderedProfiles) { profile in
                    Button(profile.name) {
                        beginDuplicate(profileID: profile.id)
                    }
                    .accessibilityIdentifier(
                        "routine-duplicate-profile-\(profile.id.uuidString)"
                    )
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Choose the saved profile that should contain the new routine.")
            }
        }
    }

    private var navigationTitle: String {
        switch operation {
        case .create: "New Routine"
        case .update: "Edit Routine"
        }
    }

    private var orderedProfiles: [ProfileSnapshot] {
        profiles.sorted {
            if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    private var canOfferDuplicate: Bool {
        guard case .update = operation, row != nil else { return false }
        switch creationIdentity {
        case let .saved(id):
            return profiles.contains(where: { $0.id == id })
        case .everything:
            return !profiles.isEmpty
        case nil:
            return false
        }
    }

    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !days.isEmpty
            && (!usesReminder || {
                let components = model.reminderComponents(for: reminder)
                return components.hour != nil && components.minute != nil
            }())
    }

    private var currentDraft: RoutineDraft {
        let components = model.reminderComponents(for: reminder)
        return RoutineDraft(
            title: title,
            weekdays: days,
            window: window,
            reminderHour: usesReminder ? components.hour : nil,
            reminderMinute: usesReminder ? components.minute : nil,
            categoryID: categoryID
        )
    }

    private var hasUnsavedSourceChanges: Bool {
        guard case .update = operation, let sourceDraft else { return false }
        return currentDraft != sourceDraft
    }

    private func toggle(_ day: Int) {
        if days.contains(day) { days.remove(day) }
        else { days.insert(day) }
    }

    private func requestDuplicate() {
        guard !hasUnsavedSourceChanges else { return }
        switch creationIdentity {
        case let .saved(id):
            guard profiles.contains(where: { $0.id == id }) else { return }
            beginDuplicate(profileID: id)
        case .everything:
            showingProfileChooser = true
        case nil:
            break
        }
    }

    private func beginDuplicate(profileID: UUID) {
        guard let row,
              profiles.contains(where: { $0.id == profileID }) else { return }
        let draft = RoutinesViewModel.duplicateDraft(from: row.routine)
        title = draft.title
        days = draft.weekdays
        window = draft.window
        usesReminder = draft.reminderHour != nil
        reminder = model.reminderDate(
            hour: draft.reminderHour,
            minute: draft.reminderMinute
        )
        categoryID = draft.categoryID
        capturedProfileID = profileID
        operation = .create
    }

    private func save() {
        let draft = currentDraft
        let success: Bool
        switch operation {
        case .create:
            if let capturedProfileID {
                success = model.create(
                    draft,
                    capturedProfileID: capturedProfileID
                )
            } else {
                success = model.create(draft)
            }
        case let .update(id):
            success = model.update(id: id, draft: draft)
        }
        if success { dismiss() }
    }
}
