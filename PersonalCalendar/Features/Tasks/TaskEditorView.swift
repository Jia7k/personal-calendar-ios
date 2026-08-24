import SwiftUI

/// A host-owned task editor. The host supplies destination metadata and owns
/// dismissal/reconciliation; this view never refreshes Reminders itself.
struct TaskEditorView: View {
    let model: TaskEditorViewModel
    let lists: [ReminderListDescriptor]
    /// Pass "System Default" for create and "Preserve Current" for edit.
    let nilDestinationLabel: String
    let showsDelete: Bool
    let onDismiss: () -> Void

    @State private var preservedSchedule: ReminderScheduleValue?
    @State private var showsDiscardConfirmation = false

    init(
        model: TaskEditorViewModel,
        lists: [ReminderListDescriptor],
        nilDestinationLabel: String,
        showsDelete: Bool,
        onDismiss: @escaping () -> Void
    ) {
        self.model = model
        self.lists = lists
        self.nilDestinationLabel = nilDestinationLabel
        self.showsDelete = showsDelete
        self.onDismiss = onDismiss
        if case let .preserve(current) = model.form.schedule {
            _preservedSchedule = State(initialValue: current)
        } else {
            _preservedSchedule = State(initialValue: nil)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                detailsSection
                scheduleSection
                destinationSection
                alarmSection
                recurrenceSection
                recurringInformationSection
                mutationSection
                failureSection
            }
            .navigationTitle(showsDelete ? "Task" : "New Task")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: requestDismiss)
                        .frame(minWidth: CalendarTheme.minimumTapSize, minHeight: CalendarTheme.minimumTapSize)
                        .accessibilityIdentifier("task-editor-cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isWriting ? "Saving…" : "Save") {
                        Task { await model.requestSave() }
                    }
                    .disabled(!canSave)
                    .frame(minWidth: CalendarTheme.minimumTapSize, minHeight: CalendarTheme.minimumTapSize)
                    .accessibilityIdentifier("task-editor-save")
                }
            }
            .confirmationDialog("Discard changes?", isPresented: $showsDiscardConfirmation, titleVisibility: .visible) {
                Button("Discard Changes", role: .destructive, action: discardAndDismiss)
                    .accessibilityIdentifier("task-editor-discard")
                Button("Keep Editing", role: .cancel) {}
            } message: {
                Text("Your unsaved task changes will be discarded.")
            }
            .confirmationDialog("Delete task?", isPresented: deleteConfirmationBinding, titleVisibility: .visible) {
                Button("Delete Task", role: .destructive) { model.confirm() }
                    .accessibilityIdentifier("task-editor-confirm-delete")
                Button("Keep Task") { model.cancelConfirmation() }
                    .accessibilityIdentifier("task-editor-confirm-cancel")
            } message: {
                Text(model.recurringDeleteExplanation ?? "Deleting this task cannot be undone.")
            }
            .interactiveDismissDisabled(model.requiresDiscardConfirmation || isWriting)
            .onChange(of: model.phase) { _, phase in
                if phase.isCommitted { onDismiss() }
            }
        }
    }

    private var detailsSection: some View {
        Section("Details") {
            TextField("Title", text: formBinding(\.title))
                .disabled(isUnavailable)
                .accessibilityIdentifier("task-editor-title")
                .accessibilityLabel("Task title")
            TextField("Notes", text: optionalStringBinding(\.notes), axis: .vertical)
                .lineLimit(3...8)
                .disabled(isUnavailable)
                .accessibilityIdentifier("task-editor-notes")
            Picker("Priority", selection: formBinding(\.priority)) {
                if !TaskEditorPriority.allCases.map(\.value).contains(model.form.priority) {
                    Text("Provider priority \(model.form.priority)").tag(model.form.priority)
                }
                ForEach(TaskEditorPriority.allCases) { priority in
                    Text(priority.title).tag(priority.value)
                }
            }
            .disabled(isUnavailable)
            .accessibilityIdentifier("task-editor-priority")
        }
    }

    private var scheduleSection: some View {
        Section {
            Picker("Due", selection: scheduleChoiceBinding) {
                if showsDelete { Text("Preserve Current").tag(TaskScheduleChoice.preserve) }
                Text("No Due Date").tag(TaskScheduleChoice.clear)
                Text("Set Due Date").tag(TaskScheduleChoice.replace)
            }
            .disabled(isUnavailable)
            .accessibilityIdentifier("task-editor-schedule-intent")

            if scheduleChoice == .replace {
                Toggle("Include time", isOn: dueHasTimeBinding)
                    .disabled(isUnavailable)
                    .accessibilityIdentifier("task-editor-due-time")
                DatePicker(
                    "Due",
                    selection: dueDateBinding,
                    displayedComponents: dueHasTime ? [.date, .hourAndMinute] : [.date]
                )
                .disabled(isUnavailable)
                .accessibilityIdentifier("task-editor-due-date")
            } else if case let .preserve(current) = model.form.schedule, let current {
                LabeledContent("Current due date") {
                    Text(formattedSchedule(current))
                        .multilineTextAlignment(.trailing)
                }
                .accessibilityIdentifier("task-editor-current-due-date")
            }
        } header: {
            Text("Schedule")
        } footer: {
            if scheduleChoice == .preserve {
                Text("The provider’s current due and start metadata stays unchanged.")
            }
        }
    }

    private var destinationSection: some View {
        Section("List") {
            Picker("List", selection: destinationBinding) {
                Text(nilDestinationLabel).tag(String?.none)
                ForEach(lists) { list in
                    Text(list.title)
                        .tag(Optional(list.id))
                        .disabled(!list.allowsContentModifications)
                }
            }
            .disabled(isUnavailable)
            .accessibilityIdentifier("task-editor-destination")

            Text(destinationHelp)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var alarmSection: some View {
        Section("Alert") {
            if let snapshot = model.providerAlarmSnapshot {
                switch snapshot {
                case .none:
                    LabeledContent("Current alert", value: "None")
                        .accessibilityIdentifier("task-editor-current-alarm")
                case let .editable(date):
                    LabeledContent("Current alert") {
                        Text(date.formatted(date: .abbreviated, time: .shortened))
                            .multilineTextAlignment(.trailing)
                    }
                    .accessibilityIdentifier("task-editor-current-alarm")
                case let .unsupported(summary):
                    Label(summary, systemImage: "exclamationmark.triangle")
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("task-editor-unsupported-alarm")
                    Text("This provider alert stays unchanged unless you clear or replace it.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Picker("Alert", selection: alarmChoiceBinding) {
                if showsDelete {
                    Text("Preserve Current").tag(TaskAlarmChoice.preserve)
                    Text("None").tag(TaskAlarmChoice.clear)
                } else {
                    Text("None").tag(TaskAlarmChoice.preserve)
                }
                Text("Set Alert").tag(TaskAlarmChoice.replace)
            }
            .disabled(isUnavailable)
            .accessibilityIdentifier("task-editor-alarm-intent")

            if alarmChoice == .replace {
                DatePicker("Alert", selection: alarmDateBinding, displayedComponents: [.date, .hourAndMinute])
                    .disabled(isUnavailable)
                    .accessibilityIdentifier("task-editor-alarm-date")
            }
        }
    }

    private var recurrenceSection: some View {
        Section {
            if let snapshot = model.providerRecurrenceSnapshot {
                switch snapshot {
                case .none:
                    LabeledContent("Current repeat", value: "Never")
                        .accessibilityIdentifier("task-editor-current-recurrence")
                case let .editable(rule):
                    LabeledContent("Current repeat", value: recurrenceDescription(rule))
                        .accessibilityIdentifier("task-editor-current-recurrence")
                case let .unsupported(summary):
                    Label(summary, systemImage: "exclamationmark.triangle")
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("task-editor-unsupported-recurrence")
                    Text("This provider repeat pattern stays unchanged unless you clear or replace it.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Picker("Repeat", selection: recurrenceChoiceBinding) {
                if showsDelete {
                    Text("Preserve Current").tag(TaskRecurrenceChoice.preserve)
                    Text("Never").tag(TaskRecurrenceChoice.clear)
                } else {
                    Text("Never").tag(TaskRecurrenceChoice.preserve)
                }
                Text("Custom").tag(TaskRecurrenceChoice.replace)
            }
            .disabled(isUnavailable)
            .accessibilityIdentifier("task-editor-recurrence-intent")

            if recurrenceChoice == .replace {
                recurrenceRuleFields
            }
        } header: {
            Text("Repeat")
        } footer: {
            if recurrenceChoice == .replace && effectiveDueDate == nil {
                Text("A repeating task needs a due date.")
                    .foregroundStyle(.red)
            }
        }
    }

    private var recurrenceRuleFields: some View {
        Group {
            Picker("Frequency", selection: recurrenceFrequencyBinding) {
                ForEach(RecurrenceFrequency.allCases, id: \.self) { frequency in
                    Text(frequency.title).tag(frequency)
                }
            }
            .accessibilityIdentifier("task-editor-recurrence-frequency")

            TextField("Repeat interval", value: recurrenceIntervalBinding, format: .number)
                .keyboardType(.numberPad)
                .accessibilityLabel("Repeat interval")
                .accessibilityValue("\(recurrenceInterval)")
            .accessibilityIdentifier("task-editor-recurrence-interval")
            Text("Every \(recurrenceInterval) \(recurrenceFrequency.unit(interval: recurrenceInterval))")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if recurrenceFrequency == .weekly {
                ForEach(Array(Calendar.current.weekdaySymbols.enumerated()), id: \.offset) { offset, name in
                    Toggle(name, isOn: weekdayBinding(offset + 1))
                        .frame(minHeight: CalendarTheme.minimumTapSize)
                        .accessibilityIdentifier("task-editor-recurrence-weekday-\(offset + 1)")
                }
            }

            Toggle("End repeat", isOn: recurrenceHasEndDateBinding)
                .frame(minHeight: CalendarTheme.minimumTapSize)
                .accessibilityIdentifier("task-editor-recurrence-end-toggle")
            if recurrenceEndDate != nil {
                DatePicker("Ends", selection: recurrenceEndDateBinding, displayedComponents: .date)
                    .accessibilityValue(recurrenceEndDateBinding.wrappedValue.formatted(date: .abbreviated, time: .omitted))
                    .accessibilityIdentifier("task-editor-recurrence-end-date")
            }
        }
        .disabled(isUnavailable)
    }

    @ViewBuilder private var recurringInformationSection: some View {
        if let explanation = model.recurringDetailExplanation {
            Section("Repeating Reminder") {
                Label(explanation, systemImage: "repeat")
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("task-editor-recurring-detail")
                if let deleteExplanation = model.recurringDeleteExplanation {
                    Text(deleteExplanation)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("task-editor-recurring-delete-explanation")
                }
            }
        }
    }

    @ViewBuilder private var mutationSection: some View {
        if isUnavailable {
            Section("This task can’t be changed") {
                Text(model.mutationExplanation ?? "This task is unavailable.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("task-editor-unavailable-reason")
                if showsDelete {
                    Button("Edit") {}
                        .disabled(true)
                        .frame(minWidth: CalendarTheme.minimumTapSize, minHeight: CalendarTheme.minimumTapSize)
                        .accessibilityIdentifier("task-editor-edit-unavailable")
                        .accessibilityHint(model.mutationExplanation ?? "This task is unavailable.")
                    Button("Delete", role: .destructive) {}
                        .disabled(true)
                        .frame(minWidth: CalendarTheme.minimumTapSize, minHeight: CalendarTheme.minimumTapSize)
                        .accessibilityIdentifier("task-editor-delete")
                        .accessibilityHint(model.mutationExplanation ?? "This task is unavailable.")
                }
            }
        } else if showsDelete {
            Section {
                Button("Delete Task", role: .destructive) { model.requestDelete() }
                    .disabled(!canDelete)
                    .frame(minWidth: CalendarTheme.minimumTapSize, minHeight: CalendarTheme.minimumTapSize)
                    .accessibilityIdentifier("task-editor-delete")
            }
        }
    }

    @ViewBuilder private var failureSection: some View {
        if case let .failed(action, error) = model.phase {
            Section(action == .delete ? "Could not delete" : "Could not save") {
                Label(errorText(error, action: action), systemImage: "exclamationmark.triangle")
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("task-editor-error")
                Button(action == .delete ? "Try Delete Again" : "Retry Save") {
                    Task { await model.retry() }
                }
                .disabled(isWriting)
                .frame(minWidth: CalendarTheme.minimumTapSize, minHeight: CalendarTheme.minimumTapSize)
                .accessibilityIdentifier(action == .delete ? "task-delete-retry" : "task-save-retry")
            }
        }
    }

    private var isWriting: Bool { if case .writing = model.phase { return true }; return false }
    private var isUnavailable: Bool { if case .unavailable = model.phase { return true }; return false }
    private var isTerminal: Bool { model.phase.isCommitted || isUnavailable }
    private var canSave: Bool { model.canSave }
    private var canDelete: Bool { !isWriting && !isTerminal }

    private var scheduleChoice: TaskScheduleChoice { TaskScheduleChoice(model.form.schedule) }
    private var alarmChoice: TaskAlarmChoice { TaskAlarmChoice(model.form.alarm) }
    private var recurrenceChoice: TaskRecurrenceChoice { TaskRecurrenceChoice(model.form.recurrence) }
    private var dueHasTime: Bool { effectiveSchedule?.hasTime ?? false }
    private var effectiveSchedule: ReminderScheduleValue? {
        switch model.form.schedule {
        case let .preserve(current): current
        case .clear: nil
        case let .replace(value): value
        }
    }
    private var effectiveDueDate: Date? { effectiveSchedule?.date }
    private var recurrenceRule: RecurrenceRuleDraft {
        if case let .replace(rule) = model.form.recurrence { return rule }
        return .init(frequency: .daily, interval: 1, weekdays: [], endDate: nil)
    }
    private var recurrenceFrequency: RecurrenceFrequency { recurrenceRule.frequency }
    private var recurrenceInterval: Int { recurrenceRule.interval }
    private var recurrenceEndDate: Date? { recurrenceRule.endDate }

    private var scheduleChoiceBinding: Binding<TaskScheduleChoice> {
        Binding(get: { scheduleChoice }, set: { choice in
            switch choice {
            case .preserve: model.form.schedule = .preserve(current: preservedSchedule)
            case .clear: model.form.schedule = .clear
            case .replace: model.form.schedule = .replace(effectiveSchedule ?? .init(date: .now, hasTime: false))
            }
        })
    }

    private var dueDateBinding: Binding<Date> {
        Binding(get: { effectiveDueDate ?? .now }, set: { model.form.schedule = .replace(.init(date: $0, hasTime: dueHasTime)) })
    }

    private var dueHasTimeBinding: Binding<Bool> {
        Binding(get: { dueHasTime }, set: { model.form.schedule = .replace(.init(date: effectiveDueDate ?? .now, hasTime: $0)) })
    }

    private var destinationBinding: Binding<String?> {
        Binding(get: { model.form.listID }, set: { id in
            if let id { model.selectDestination(.explicit(id: id)) }
            else { model.selectDestination(.nilDestination) }
        })
    }

    private var alarmChoiceBinding: Binding<TaskAlarmChoice> {
        Binding(get: { alarmChoice }, set: { choice in
            switch choice {
            case .preserve: model.form.alarm = .preserve
            case .clear: model.form.alarm = .clear
            case .replace:
                if case let .editable(date) = model.providerAlarmSnapshot {
                    model.form.alarm = .replace(date)
                } else {
                    model.form.alarm = .replace(.now)
                }
            }
        })
    }

    private var alarmDateBinding: Binding<Date> {
        Binding(
            get: { if case let .replace(date) = model.form.alarm { return date }; return .now },
            set: { model.form.alarm = .replace($0) }
        )
    }

    private var recurrenceChoiceBinding: Binding<TaskRecurrenceChoice> {
        Binding(get: { recurrenceChoice }, set: { choice in
            switch choice {
            case .preserve: model.form.recurrence = .preserve
            case .clear: model.form.recurrence = .clear
            case .replace:
                if case let .editable(rule) = model.providerRecurrenceSnapshot {
                    model.form.recurrence = .replace(rule)
                } else {
                    model.form.recurrence = .replace(recurrenceRule)
                }
            }
        })
    }

    private var recurrenceFrequencyBinding: Binding<RecurrenceFrequency> {
        Binding(get: { recurrenceFrequency }, set: { frequency in
            updateRecurrence { rule in
                rule.frequency = frequency
                if frequency != .weekly { rule.weekdays = [] }
            }
        })
    }

    private var recurrenceIntervalBinding: Binding<Int> {
        Binding(get: { recurrenceInterval }, set: { interval in
            updateRecurrence { $0.interval = max(1, interval) }
        })
    }

    private var recurrenceHasEndDateBinding: Binding<Bool> {
        Binding(get: { recurrenceEndDate != nil }, set: { enabled in
            updateRecurrence { $0.endDate = enabled ? recurrenceEndDateSeed : nil }
        })
    }

    private var recurrenceEndDateBinding: Binding<Date> {
        Binding(get: { recurrenceEndDate ?? recurrenceEndDateSeed }, set: { date in updateRecurrence { $0.endDate = date } })
    }

    private func weekdayBinding(_ day: Int) -> Binding<Bool> {
        Binding(get: { recurrenceRule.weekdays.contains(day) }, set: { selected in
            updateRecurrence { rule in
                if selected { rule.weekdays.insert(day) } else { rule.weekdays.remove(day) }
            }
        })
    }

    private func updateRecurrence(_ update: (inout RecurrenceRuleDraft) -> Void) {
        var rule = recurrenceRule
        update(&rule)
        model.form.recurrence = .replace(rule)
    }

    private func requestDismiss() {
        switch model.requestDismissal() {
        case .dismiss: onDismiss()
        case .confirmDiscard: showsDiscardConfirmation = true
        }
    }

    private func discardAndDismiss() {
        if model.confirmDiscard() == .dismiss { onDismiss() }
    }

    private var deleteConfirmationBinding: Binding<Bool> {
        let generation = model.deleteConfirmationGeneration
        return Binding(
            get: { if case .confirming(.delete) = model.phase { return true }; return false },
            // `confirm()` moves out of `confirming` synchronously. That lets
            // an action-driven false write pass through safely, while passive
            // dismissal of a still-open confirmation is treated as cancel.
            set: { model.setDeleteConfirmationPresented($0, generation: generation) }
        )
    }

    private var destinationHelp: String {
        switch model.destination {
        case .systemDefault:
            "System Default lets Apple Reminders choose the writable list."
        case let .preserveCurrent(_, title):
            model.form.listID == nil ? "The current list, \(title), stays unchanged." : "Choose a writable list to move this task."
        case .explicit:
            model.form.listID == nil ? "\(nilDestinationLabel) leaves the destination unchanged by this editor." : "This task will be saved to the selected writable list."
        }
    }

    /// A newly enabled end date must never precede the effective task due
    /// date. If there is no due date, the current instant is the safe seed.
    private var recurrenceEndDateSeed: Date {
        taskRecurrenceEndDateSeed(effectiveDueDate: effectiveDueDate, now: .now)
    }

    private func formBinding<Value>(_ keyPath: WritableKeyPath<ReminderDraft, Value>) -> Binding<Value> {
        Binding(get: { model.form[keyPath: keyPath] }, set: { model.form[keyPath: keyPath] = $0 })
    }

    private func optionalStringBinding(_ keyPath: WritableKeyPath<ReminderDraft, String?>) -> Binding<String> {
        Binding(get: { model.form[keyPath: keyPath] ?? "" }, set: { model.form[keyPath: keyPath] = $0.isEmpty ? nil : $0 })
    }

    private func errorText(_ error: TaskEditorFailure, action: TaskEditorAction) -> String {
        switch error {
        case .validation: "Check the task details and try again."
        case .invalidDestination: "Choose an available writable reminder list."
        case .retryableWrite where action == .delete: "Your task was not deleted. Confirm before trying again."
        case .retryableWrite: "Your task was not saved. Your edits are still here."
        }
    }

    private func formattedSchedule(_ value: ReminderScheduleValue) -> String {
        value.date.formatted(date: .abbreviated, time: value.hasTime ? .shortened : .omitted)
    }

    private func recurrenceDescription(_ rule: RecurrenceRuleDraft) -> String {
        var parts = ["Every \(rule.interval) \(rule.frequency.unit(interval: rule.interval))"]
        if rule.frequency == .weekly, !rule.weekdays.isEmpty {
            let symbols = Calendar.current.shortWeekdaySymbols
            let days = rule.weekdays.sorted().compactMap { day in
                symbols.indices.contains(day - 1) ? symbols[day - 1] : nil
            }
            if !days.isEmpty { parts.append("on \(days.joined(separator: ", "))") }
        }
        if let endDate = rule.endDate {
            parts.append("until \(endDate.formatted(date: .abbreviated, time: .omitted))")
        }
        return parts.joined(separator: " ")
    }
}

private enum TaskScheduleChoice: String, Hashable { case preserve, clear, replace
    init(_ intent: ReminderScheduleMutationIntent) { switch intent { case .preserve: self = .preserve; case .clear: self = .clear; case .replace: self = .replace } }
}

private enum TaskAlarmChoice: String, Hashable { case preserve, clear, replace
    init(_ intent: ReminderAlarmMutationIntent) { switch intent { case .preserve: self = .preserve; case .clear: self = .clear; case .replace: self = .replace } }
}

private enum TaskRecurrenceChoice: String, Hashable { case preserve, clear, replace
    init(_ intent: RecurrenceMutationIntent) { switch intent { case .preserve: self = .preserve; case .clear: self = .clear; case .replace: self = .replace } }
}

private enum TaskEditorPriority: Int, CaseIterable, Identifiable {
    case none = 0, high = 1, medium = 5, low = 9
    var id: Int { rawValue }
    var value: Int { rawValue }
    var title: String { switch self { case .none: "None"; case .high: "High"; case .medium: "Medium"; case .low: "Low" } }
}

private extension RecurrenceFrequency {
    var title: String { rawValue.capitalized }
    func unit(interval: Int) -> String {
        switch self {
        case .daily: interval == 1 ? "day" : "days"
        case .weekly: interval == 1 ? "week" : "weeks"
        case .monthly: interval == 1 ? "month" : "months"
        case .yearly: interval == 1 ? "year" : "years"
        }
    }
}

private extension TaskEditorPhase {
    var isCommitted: Bool {
        switch self {
        case .created, .updated, .deleted: true
        case .idle, .confirming, .writing, .failed, .unavailable: false
        }
    }
}
