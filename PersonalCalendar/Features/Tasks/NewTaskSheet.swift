import SwiftUI

enum TaskPriorityChoice: CaseIterable { case none, high, medium, low; var label: String { switch self { case .none: "None"; case .high: "High"; case .medium: "Medium"; case .low: "Low" } }; var value: Int { switch self { case .none: 0; case .high: 1; case .medium: 5; case .low: 9 } } }
enum TaskFormValidation { static func canSave(title: String, isSaving: Bool, listID: String?, writableLists: [ReminderListDescriptor]) -> Bool { !isSaving && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && writableLists.contains { $0.id == listID && $0.allowsContentModifications } } }

struct NewTaskSheet: View {
    let model: TasksViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""; @State private var notes = ""; @State private var hasDueDate = false; @State private var hasTime = false; @State private var dueDate = Date(); @State private var priority = 0; @State private var listID: String?
    init(model: TasksViewModel) {
        self.model = model
        let draft = model.draftOnFailure
        _title = State(initialValue: draft?.title ?? "")
        _notes = State(initialValue: draft?.notes ?? "")
        _hasDueDate = State(initialValue: draft?.dueDate != nil)
        _hasTime = State(initialValue: draft?.dueHasTime ?? false)
        _dueDate = State(initialValue: draft?.dueDate ?? .now)
        _priority = State(initialValue: draft?.priority ?? 0)
        _listID = State(initialValue: draft?.listID ?? model.defaultWritableListID)
    }
    var body: some View {
        NavigationStack { Form {
            Section("Task") { TextField("Title", text: $title).accessibilityIdentifier("Task title"); TextField("Notes", text: $notes, axis: .vertical) }
            Section("Schedule") { Toggle("Due date", isOn: $hasDueDate); if hasDueDate { DatePicker("Date", selection: $dueDate, displayedComponents: hasTime ? [.date, .hourAndMinute] : .date); Toggle("Due time", isOn: $hasTime) } }
            Section("Details") { Picker("Priority", selection: $priority) { ForEach(TaskPriorityChoice.allCases, id: \.value) { Text($0.label).tag($0.value) } }; Picker("List", selection: $listID) { ForEach(model.writableLists) { Text($0.title).tag(Optional($0.id)) } } }
            if model.writableLists.isEmpty { Section { Label("No writable reminder list is available.", systemImage: "exclamationmark.triangle") } }
            if let error = model.createErrorMessage, model.draftOnFailure != nil { Section { Text(error).foregroundStyle(.red); Button("Retry") { save() }.disabled(!canSave).frame(minWidth: 44, minHeight: 44) } }
        }.navigationTitle("New Task").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.frame(minWidth: 44, minHeight: 44) }; ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(!canSave).frame(minWidth: 44, minHeight: 44) } } }
    }
    private var canSave: Bool { TaskFormValidation.canSave(title: title, isSaving: model.isSaving, listID: listID, writableLists: model.writableLists) }
    private func save() { let draft = ReminderDraft(title: title, notes: notes.isEmpty ? nil : notes, dueDate: hasDueDate ? dueDate : nil, dueHasTime: hasDueDate && hasTime, priority: priority, listID: listID); Task { if await model.create(draft) { dismiss() } } }
}
