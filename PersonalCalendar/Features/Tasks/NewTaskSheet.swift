import SwiftUI

struct NewTaskSheet: View {
    let model: TasksViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""; @State private var notes = ""; @State private var hasDueDate = false; @State private var hasTime = false; @State private var dueDate = Date(); @State private var priority = 0; @State private var listID: String?
    var body: some View {
        NavigationStack { Form {
            Section("Task") { TextField("Title", text: $title).accessibilityIdentifier("Task title"); TextField("Notes", text: $notes, axis: .vertical) }
            Section("Schedule") { Toggle("Due date", isOn: $hasDueDate); if hasDueDate { DatePicker("Date", selection: $dueDate, displayedComponents: hasTime ? [.date, .hourAndMinute] : .date); Toggle("Due time", isOn: $hasTime) } }
            Section("Details") { Picker("Priority", selection: $priority) { Text("None").tag(0); Text("Low").tag(1); Text("Medium").tag(5); Text("High").tag(9) }; Picker("List", selection: $listID) { ForEach(model.writableLists) { Text($0.title).tag(Optional($0.id)) } } }
            if model.writableLists.isEmpty { Section { Label("No writable reminder list is available.", systemImage: "exclamationmark.triangle") } }
            if let error = model.errorMessage { Section { Text(error).foregroundStyle(.red); Button("Retry") { save() }.frame(minHeight: 44) } }
        }.navigationTitle("New Task").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.frame(minHeight: 44) }; ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.writableLists.isEmpty).frame(minHeight: 44) } }.onAppear { listID = model.defaultWritableListID } }
    }
    private func save() { let draft = ReminderDraft(title: title, notes: notes.isEmpty ? nil : notes, dueDate: hasDueDate ? dueDate : nil, dueHasTime: hasDueDate && hasTime, priority: priority, listID: listID); Task { if await model.create(draft) { dismiss() } } }
}
