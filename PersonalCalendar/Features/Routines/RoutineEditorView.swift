import SwiftUI

struct RoutineEditorView: View {
    let model: RoutinesViewModel; let row: RoutineRowState?; let categories: [CategorySnapshot]
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""; @State private var days: Set<Int> = []; @State private var window: RoutineWindow = .anytime; @State private var usesReminder = false; @State private var reminder = Date(); @State private var categoryID: UUID?
    init(model: RoutinesViewModel, row: RoutineRowState? = nil, categories: [CategorySnapshot] = []) {
        self.model = model; self.row = row; self.categories = categories
        let operation: RoutineEditorOperation = row.map { .update($0.id) } ?? .create
        let failed = model.failedDraft(for: operation)
        let draft = failed ?? row.map { RoutineDraft(title: $0.routine.title, weekdays: $0.routine.weekdays, window: $0.routine.window, reminderHour: $0.routine.reminderHour, reminderMinute: $0.routine.reminderMinute, categoryID: $0.routine.categoryID) }
        _title = State(initialValue: draft?.title ?? "")
        _days = State(initialValue: draft?.weekdays ?? [])
        _window = State(initialValue: draft?.window ?? .anytime)
        _usesReminder = State(initialValue: draft?.reminderHour != nil)
        _reminder = State(initialValue: model.reminderDate(hour: draft?.reminderHour, minute: draft?.reminderMinute))
        _categoryID = State(initialValue: draft?.categoryID)
    }
    var body: some View { NavigationStack { Form { Section("Routine") { TextField("Title", text: $title).accessibilityIdentifier("Routine title"); Picker("Window", selection: $window) { ForEach(RoutineWindow.allCases, id: \.self) { Text(model.windowName($0)).tag($0) } }.accessibilityIdentifier("Routine window") }
        Section("Days") { Button(days.count == 7 ? "Clear daily" : "Daily") { days = days.count == 7 ? [] : Set(1...7) }.frame(minHeight: 44); ForEach(model.weekdayOrder, id: \.self) { day in Button { toggle(day) } label: { HStack { Text(model.weekdayName(day)); Spacer(); if days.contains(day) { Image(systemName: "checkmark") } } }.frame(minHeight: 44).accessibilityLabel(model.weekdayName(day)).accessibilityAddTraits(days.contains(day) ? .isSelected : []) } }
        Section("App Color") { Picker("Category", selection: $categoryID) { Text("No Category").tag(UUID?.none); ForEach(categories) { category in Text(category.name).tag(Optional(category.id)) } }.frame(minHeight: 44).accessibilityIdentifier("routine-editor-category") }
        Section("Reminder") { Toggle("Set a reminder", isOn: $usesReminder).accessibilityIdentifier("Routine reminder toggle"); if usesReminder { DatePicker("Time", selection: $reminder, displayedComponents: .hourAndMinute).accessibilityIdentifier("Routine reminder time") } }
        if let error = model.editorErrorMessage, model.canRetryEditor(row.map { .update($0.id) } ?? .create) { Section { Text(error).foregroundStyle(.red); Button("Retry") { save() }.disabled(!isValid).frame(minWidth: 44, minHeight: 44).accessibilityIdentifier("routine-save-retry") } }
    }.navigationTitle(row == nil ? "New Routine" : "Edit Routine").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.frame(minWidth: 44, minHeight: 44) }; ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(!isValid).frame(minWidth: 44, minHeight: 44).accessibilityIdentifier("routine-save") } } } }
    private func toggle(_ day: Int) { if days.contains(day) { days.remove(day) } else { days.insert(day) } }
    private var isValid: Bool { !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !days.isEmpty && (!usesReminder || { let c = model.reminderComponents(for: reminder); return c.hour != nil && c.minute != nil }()) }
    private func save() { let c = model.reminderComponents(for: reminder); let draft = RoutineDraft(title: title, weekdays: days, window: window, reminderHour: usesReminder ? c.hour : nil, reminderMinute: usesReminder ? c.minute : nil, categoryID: categoryID); let success = row.map { model.update(id: $0.id, draft: draft) } ?? model.create(draft); if success { dismiss() } }
}
