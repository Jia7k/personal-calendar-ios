import SwiftUI

struct RoutineEditorView: View {
    let model: RoutinesViewModel; let row: RoutineRowState?
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""; @State private var days: Set<Int> = []; @State private var window: RoutineWindow = .anytime; @State private var usesReminder = false; @State private var reminder = Date()
    init(model: RoutinesViewModel, row: RoutineRowState? = nil) { self.model = model; self.row = row; _title = State(initialValue: row?.routine.title ?? ""); _days = State(initialValue: row?.routine.weekdays ?? []); _window = State(initialValue: row?.routine.window ?? .anytime); _usesReminder = State(initialValue: row?.routine.reminderHour != nil) }
    var body: some View { NavigationStack { Form { Section("Routine") { TextField("Title", text: $title); Picker("Window", selection: $window) { ForEach(RoutineWindow.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) } } }
        Section("Days") { Button(days.count == 7 ? "Clear daily" : "Daily") { days = days.count == 7 ? [] : Set(1...7) }.frame(minHeight: 44); ForEach(model.weekdayOrder, id: \.self) { day in Button { toggle(day) } label: { HStack { Text(model.weekdayName(day)); Spacer(); if days.contains(day) { Image(systemName: "checkmark") } } }.frame(minHeight: 44).accessibilityLabel(model.weekdayName(day)).accessibilityAddTraits(days.contains(day) ? .isSelected : []) } }
        Section("Reminder") { Toggle("Set a reminder", isOn: $usesReminder); if usesReminder { DatePicker("Time", selection: $reminder, displayedComponents: .hourAndMinute) } }
        if let error = model.errorMessage { Section { Text(error).foregroundStyle(.red); Button("Retry") { save() }.frame(minHeight: 44) } }
    }.navigationTitle(row == nil ? "New Routine" : "Edit Routine").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.frame(minHeight: 44) }; ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.frame(minHeight: 44) } } } }
    private func toggle(_ day: Int) { if days.contains(day) { days.remove(day) } else { days.insert(day) } }
    private func save() { let c = model.reminderComponents(for: reminder); let draft = RoutineDraft(title: title, weekdays: days, window: window, reminderHour: usesReminder ? c.hour : nil, reminderMinute: usesReminder ? c.minute : nil); let success = row.map { model.update(id: $0.id, draft: draft) } ?? model.create(draft); if success { dismiss() } }
}
