import SwiftUI

/// Host-owned event editor. Provider writes are owned by the model; the host
/// owns dismissal and the one post-commit agenda refresh.
struct EventEditorView: View {
    let model: EventEditorViewModel
    let calendars: [CalendarDescriptor]
    let nilDestinationLabel: String
    let showsDelete: Bool
    let onDismiss: () -> Void

    @State private var showsDiscardConfirmation = false
    @State private var selectedSaveScope: RecurrenceEditScope = .thisOccurrence
    @State private var selectedDeleteScope: RecurrenceEditScope = .thisOccurrence
    @State private var replacementAlarmOffsets: [TimeInterval] = []
    @State private var replacementRecurrence = Self.defaultRecurrence

    var body: some View {
        NavigationStack {
            Form {
                detailsSection.disabled(isUnavailable)
                destinationSection.disabled(isUnavailable)
                categorySection.disabled(isUnavailable)
                alarmsSection.disabled(isUnavailable)
                recurrenceSection.disabled(isUnavailable)
                mutationSection
                failureSection
            }
            .navigationTitle(showsDelete ? "Event" : "New Event")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: requestDismiss)
                        .frame(minWidth: CalendarTheme.minimumTapSize, minHeight: CalendarTheme.minimumTapSize)
                        .accessibilityIdentifier("event-editor-cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isWriting ? "Saving…" : "Save") {
                        Task { await model.requestSave(scope: selectedSaveScope) }
                    }
                    .disabled(!canSave)
                    .frame(minWidth: CalendarTheme.minimumTapSize, minHeight: CalendarTheme.minimumTapSize)
                    .accessibilityIdentifier("event-editor-save")
                }
            }
            .confirmationDialog("Discard changes?", isPresented: $showsDiscardConfirmation, titleVisibility: .visible) {
                Button("Discard Changes", role: .destructive) {
                    model.confirmDiscard()
                    onDismiss()
                }
                .accessibilityIdentifier("event-editor-discard")
                Button("Keep Editing", role: .cancel) {}
            } message: {
                Text("Your unsaved event changes will be discarded.")
            }
            .confirmationDialog(confirmationTitle, isPresented: confirmationBinding, titleVisibility: .visible) {
                confirmationActions
            } message: {
                Text(confirmationMessage)
            }
            .interactiveDismissDisabled(isWriting || model.requiresDiscardConfirmation)
            .task {
                await model.load()
                synchronizeProviderSeeds()
            }
            .onChange(of: model.alarmSnapshot) { _, _ in synchronizeAlarmSeed() }
            .onChange(of: model.recurrenceSnapshot) { _, _ in synchronizeRecurrenceSeed() }
            .onChange(of: model.phase) { _, phase in
                if phase.isCommitted { onDismiss() }
            }
        }
    }

    private var detailsSection: some View {
        Section("Details") {
            TextField("Title", text: binding(\.title))
                .accessibilityIdentifier("event-editor-title")
            Toggle("All-day", isOn: binding(\.isAllDay))
                .accessibilityIdentifier("event-editor-all-day")
            DatePicker("Starts", selection: binding(\.start), displayedComponents: dateComponents)
                .accessibilityIdentifier("event-editor-start")
            DatePicker("Ends", selection: binding(\.end), displayedComponents: dateComponents)
                .accessibilityIdentifier("event-editor-end")
            TextField("Location", text: optionalStringBinding(\.location))
                .accessibilityIdentifier("event-editor-location")
            TextField("URL", text: urlBinding)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                .accessibilityIdentifier("event-editor-url")
            TextField("Notes", text: optionalStringBinding(\.notes), axis: .vertical)
                .lineLimit(3...8)
                .accessibilityIdentifier("event-editor-notes")
        }
    }

    private var destinationSection: some View {
        Section("Calendar") {
            if let current = model.currentCalendarTitle {
                LabeledContent("Current calendar", value: current)
                    .accessibilityIdentifier("event-editor-current-calendar")
            }
            Picker("Calendar", selection: binding(\.destinationCalendarID)) {
                Text(nilDestinationLabel).tag(String?.none)
                ForEach(calendars) { calendar in
                    Text(calendar.title)
                        .tag(Optional(calendar.id))
                        .disabled(!calendar.allowsContentModifications)
                }
            }
            .accessibilityIdentifier("event-editor-destination")
            Text(destinationHelp)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var categorySection: some View {
        Section("App Color") {
            Picker("Category", selection: binding(\.categoryID)) {
                Text("No Category").tag(UUID?.none)
                ForEach(model.availableCategories) { category in
                    HStack {
                        Circle()
                            .fill(CalendarTheme.color(hex: category.colorHex) ?? .secondary)
                            .frame(width: 12, height: 12)
                        Text(category.name)
                    }
                    .tag(Optional(category.id))
                }
            }
            .frame(minHeight: CalendarTheme.minimumTapSize)
            .accessibilityIdentifier("event-editor-category")
            if let warning = model.categoryWarning {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var alarmsSection: some View {
        Section {
            providerAlarmContent
            Picker("Alerts", selection: alarmChoiceBinding) {
                if showsDelete {
                    Text("Preserve Current").tag(EventAlarmChoice.preserve)
                }
                Text("None").tag(EventAlarmChoice.clear)
                Text("Custom").tag(EventAlarmChoice.replace)
            }
            .accessibilityIdentifier("event-editor-alarm-intent")

            if alarmChoice == .replace {
                ForEach(replacementAlarmOffsets.indices, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("Seconds from event start", value: alarmOffsetBinding(index), format: .number)
                            .keyboardType(.numbersAndPunctuation)
                            .accessibilityIdentifier("event-editor-alarm-offset-\(index)")
                        Text("Use a negative value for an alert before the event.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button("Remove Alert", role: .destructive) { removeAlarm(at: index) }
                            .frame(minHeight: CalendarTheme.minimumTapSize)
                            .accessibilityIdentifier("event-editor-alarm-remove-\(index)")
                    }
                }
                Button("Add Alert") { addAlarm() }
                    .frame(minHeight: CalendarTheme.minimumTapSize)
                    .accessibilityIdentifier("event-editor-alarm-add")
            }
        } header: {
            Text("Alerts")
        } footer: {
            if case .unsupported = model.alarmSnapshot, alarmChoice == .preserve {
                Text("The provider’s alert collection stays unchanged until you explicitly clear or replace it.")
            }
        }
    }

    @ViewBuilder private var providerAlarmContent: some View {
        switch model.alarmSnapshot {
        case .none:
            if showsDelete {
                LabeledContent("Current alerts", value: "None")
                    .accessibilityIdentifier("event-editor-current-alarm")
            }
        case let .editable(offsets):
            LabeledContent("Current alerts", value: offsets.map(offsetDescription).joined(separator: ", "))
                .accessibilityIdentifier("event-editor-current-alarm")
        case let .unsupported(summary):
            Label(summary, systemImage: "exclamationmark.triangle")
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("event-editor-unsupported-alarm")
        }
    }

    private var recurrenceSection: some View {
        Section {
            providerRecurrenceContent
            Picker("Repeat", selection: recurrenceChoiceBinding) {
                if showsDelete {
                    Text("Preserve Current").tag(EventRecurrenceChoice.preserve)
                }
                Text("Never").tag(EventRecurrenceChoice.clear)
                Text("Custom").tag(EventRecurrenceChoice.replace)
            }
            .accessibilityIdentifier("event-editor-recurrence-intent")

            if recurrenceChoice == .replace {
                recurrenceRuleFields
            }

            if model.availableSaveScopes.count == 2 {
                Picker("Apply saved changes to", selection: $selectedSaveScope) {
                    Text("This Event").tag(RecurrenceEditScope.thisOccurrence)
                        .disabled(model.recurrenceIntent != .preserve)
                    Text("This and Future Events").tag(RecurrenceEditScope.futureOccurrences)
                }
                .accessibilityIdentifier("event-editor-recurrence-scope")
                if let explanation = model.scopeExplanation ?? saveScopeHint {
                    Text(explanation)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } header: {
            Text("Repeat")
        } footer: {
            if case .unsupported = model.recurrenceSnapshot, recurrenceChoice == .preserve {
                Text("The provider’s repeat pattern stays unchanged until you explicitly clear or replace it.")
            }
        }
    }

    @ViewBuilder private var providerRecurrenceContent: some View {
        switch model.recurrenceSnapshot {
        case .none:
            if showsDelete {
                LabeledContent("Current repeat", value: "Never")
                    .accessibilityIdentifier("event-editor-current-recurrence")
            }
        case let .editable(rule):
            LabeledContent("Current repeat", value: recurrenceDescription(rule))
                .accessibilityIdentifier("event-editor-current-recurrence")
        case let .unsupported(summary):
            Label(summary, systemImage: "exclamationmark.triangle")
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("event-editor-unsupported-recurrence")
        }
    }

    private var recurrenceRuleFields: some View {
        Group {
            Picker("Frequency", selection: recurrenceFrequencyBinding) {
                ForEach(RecurrenceFrequency.allCases, id: \.self) { frequency in
                    Text(frequency.title).tag(frequency)
                }
            }
            .accessibilityIdentifier("event-editor-recurrence-frequency")

            TextField("Repeat interval", value: recurrenceIntervalBinding, format: .number)
                .keyboardType(.numberPad)
                .accessibilityLabel("Repeat interval")
                .accessibilityValue("\(replacementRecurrence.interval)")
            .accessibilityIdentifier("event-editor-recurrence-interval")
            Text("Every \(replacementRecurrence.interval) \(replacementRecurrence.frequency.unit(interval: replacementRecurrence.interval))")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if replacementRecurrence.frequency == .weekly {
                ForEach(Array(Calendar.current.weekdaySymbols.enumerated()), id: \.offset) { offset, name in
                    Toggle(name, isOn: recurrenceWeekdayBinding(offset + 1))
                        .frame(minHeight: CalendarTheme.minimumTapSize)
                        .accessibilityIdentifier("event-editor-recurrence-weekday-\(offset + 1)")
                }
            }

            Toggle("End repeat", isOn: recurrenceHasEndDateBinding)
                .frame(minHeight: CalendarTheme.minimumTapSize)
                .accessibilityIdentifier("event-editor-recurrence-end-toggle")
            if replacementRecurrence.endDate != nil {
                DatePicker("Ends", selection: recurrenceEndDateBinding, displayedComponents: .date)
                    .accessibilityIdentifier("event-editor-recurrence-end-date")
            }
        }
    }

    @ViewBuilder private var mutationSection: some View {
        if let reason = model.unavailableReason {
            Section("This event can’t be changed") {
                Text(unavailableText(reason))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("event-editor-unavailable-reason")
                if showsDelete {
                    Button("Edit") {}
                        .disabled(true)
                        .frame(minHeight: CalendarTheme.minimumTapSize)
                        .accessibilityIdentifier("event-editor-edit-unavailable")
                        .accessibilityHint(unavailableText(reason))
                    Button("Delete", role: .destructive) {}
                        .disabled(true)
                        .frame(minHeight: CalendarTheme.minimumTapSize)
                        .accessibilityIdentifier("event-editor-delete")
                        .accessibilityHint(unavailableText(reason))
                }
            }
        } else if showsDelete {
            Section {
                if model.availableSaveScopes.count == 2 {
                    Picker("Delete", selection: $selectedDeleteScope) {
                        Text("This Event").tag(RecurrenceEditScope.thisOccurrence)
                        Text("This and Future Events").tag(RecurrenceEditScope.futureOccurrences)
                    }
                    .accessibilityIdentifier("event-editor-delete-scope")
                }
                Button("Delete Event", role: .destructive) {
                    Task { await model.requestDelete(scope: selectedDeleteScope) }
                }
                .disabled(!canDelete)
                .frame(minHeight: CalendarTheme.minimumTapSize)
                .accessibilityIdentifier("event-editor-delete")
            }
        }
    }

    @ViewBuilder private var failureSection: some View {
        if case let .failed(action, error) = model.phase {
            Section(action.isDelete ? "Could not delete" : "Could not save") {
                Label(errorText(error, action: action), systemImage: "exclamationmark.triangle")
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("event-editor-error")
                Button(action.isDelete ? "Try Delete Again" : "Retry Save") {
                    Task { await model.retry() }
                }
                .disabled(isWriting)
                .frame(minHeight: CalendarTheme.minimumTapSize)
                .accessibilityIdentifier(action.isDelete ? "event-delete-retry" : "event-save-retry")
            }
        }
    }

    @ViewBuilder private var confirmationActions: some View {
        if case let .confirming(action) = model.phase {
            switch action {
            case .save:
                Button("Save Changes") { model.confirm() }
                    .accessibilityIdentifier("event-editor-confirm-save")
            case let .delete(scope):
                Button(deleteConfirmationLabel(scope), role: .destructive) { model.confirm() }
                    .accessibilityIdentifier("event-editor-confirm-delete")
            }
            Button("Keep Event") { model.cancelConfirmation() }
                .accessibilityIdentifier("event-editor-confirm-cancel")
        }
    }

    private var confirmationBinding: Binding<Bool> {
        let generation = model.confirmationGeneration
        return Binding(
            get: { if case .confirming = model.phase { return true }; return false },
            // An affirmative action consumes `confirming` synchronously. A
            // subsequent false write therefore sees another phase and cannot
            // cancel it; a passive dismissal still returns an open dialog to
            // its safe idle state.
            set: { model.setConfirmationPresented($0, generation: generation) }
        )
    }

    private var alarmChoice: EventAlarmChoice { EventAlarmChoice(model.alarmIntent) }
    private var recurrenceChoice: EventRecurrenceChoice { EventRecurrenceChoice(model.recurrenceIntent) }
    private var isWriting: Bool { if case .writing = model.phase { return true }; return false }
    private var isUnavailable: Bool { model.unavailableReason != nil }
    private var isTerminal: Bool { model.phase.isCommitted || isUnavailable }
    private var canSave: Bool { model.canSave }
    private var canDelete: Bool { !isWriting && !isTerminal }
    private var dateComponents: DatePickerComponents { model.isAllDay ? [.date] : [.date, .hourAndMinute] }

    private var destinationHelp: String {
        if model.destinationCalendarID != nil { return "Choose a writable calendar to move this event." }
        return showsDelete
            ? "Preserve Current keeps the event in \(model.currentCalendarTitle ?? "its current calendar")."
            : "System Default lets Apple Calendar choose the writable default calendar."
    }

    private var saveScopeHint: String? {
        model.recurrenceIntent == .preserve ? nil : "Changes to repeat settings apply to this and future events."
    }

    private var confirmationTitle: String {
        guard case let .confirming(action) = model.phase else { return "Confirm event change" }
        return action.isDelete ? "Delete event?" : "Save recurring event?"
    }

    private var confirmationMessage: String {
        guard case let .confirming(action) = model.phase else { return "" }
        switch action {
        case .save:
            return model.confirmationSaveScope == .futureOccurrences
                ? "Save these changes to this and all future events?"
                : "Save these changes only to this event?"
        case let .delete(scope):
            return scope == .futureOccurrences
                ? "Delete this and all future events? This can’t be undone."
                : "Delete only this event? This can’t be undone."
        }
    }

    private var alarmChoiceBinding: Binding<EventAlarmChoice> {
        Binding(get: { alarmChoice }, set: { choice in
            switch choice {
            case .preserve:
                model.alarmIntent = .preserve
            case .clear:
                model.alarmIntent = .clear
            case .replace:
                if replacementAlarmOffsets.isEmpty { synchronizeAlarmSeed(forceDefault: true) }
                model.alarmIntent = .replace(replacementAlarmOffsets)
            }
        })
    }

    private var recurrenceChoiceBinding: Binding<EventRecurrenceChoice> {
        Binding(get: { recurrenceChoice }, set: { choice in
            switch choice {
            case .preserve:
                model.recurrenceIntent = .preserve
            case .clear:
                model.recurrenceIntent = .clear
                selectedSaveScope = .futureOccurrences
            case .replace:
                synchronizeRecurrenceSeed(forceDefault: true)
                model.recurrenceIntent = .replace(replacementRecurrence)
                selectedSaveScope = .futureOccurrences
            }
        })
    }

    private func alarmOffsetBinding(_ index: Int) -> Binding<TimeInterval> {
        Binding(
            get: { replacementAlarmOffsets.indices.contains(index) ? replacementAlarmOffsets[index] : 0 },
            set: { value in
                guard replacementAlarmOffsets.indices.contains(index) else { return }
                replacementAlarmOffsets[index] = value
                model.alarmIntent = .replace(replacementAlarmOffsets)
            }
        )
    }

    private var recurrenceFrequencyBinding: Binding<RecurrenceFrequency> {
        Binding(get: { replacementRecurrence.frequency }, set: { frequency in
            updateRecurrence { rule in
                rule.frequency = frequency
                if frequency != .weekly { rule.weekdays = [] }
            }
        })
    }

    private var recurrenceIntervalBinding: Binding<Int> {
        Binding(get: { replacementRecurrence.interval }, set: { interval in
            updateRecurrence { $0.interval = max(1, interval) }
        })
    }

    private var recurrenceHasEndDateBinding: Binding<Bool> {
        Binding(get: { replacementRecurrence.endDate != nil }, set: { enabled in
            updateRecurrence { $0.endDate = enabled ? max(model.start, .now) : nil }
        })
    }

    private var recurrenceEndDateBinding: Binding<Date> {
        Binding(get: { replacementRecurrence.endDate ?? max(model.start, .now) }, set: { date in
            updateRecurrence { $0.endDate = date }
        })
    }

    private func recurrenceWeekdayBinding(_ day: Int) -> Binding<Bool> {
        Binding(get: { replacementRecurrence.weekdays.contains(day) }, set: { selected in
            updateRecurrence { rule in
                if selected { rule.weekdays.insert(day) } else { rule.weekdays.remove(day) }
            }
        })
    }

    private var urlBinding: Binding<String> {
        Binding(get: { model.url?.absoluteString ?? "" }, set: { model.url = $0.isEmpty ? nil : URL(string: $0) })
    }

    private func binding<T>(_ keyPath: ReferenceWritableKeyPath<EventEditorViewModel, T>) -> Binding<T> {
        Binding(get: { model[keyPath: keyPath] }, set: { model[keyPath: keyPath] = $0 })
    }

    private func optionalStringBinding(_ keyPath: ReferenceWritableKeyPath<EventEditorViewModel, String?>) -> Binding<String> {
        Binding(get: { model[keyPath: keyPath] ?? "" }, set: { model[keyPath: keyPath] = $0.isEmpty ? nil : $0 })
    }

    private func requestDismiss() {
        if model.requiresDiscardConfirmation { showsDiscardConfirmation = true }
        else { onDismiss() }
    }

    private func addAlarm() {
        replacementAlarmOffsets.append(-600)
        model.alarmIntent = .replace(replacementAlarmOffsets)
    }

    private func removeAlarm(at index: Int) {
        guard replacementAlarmOffsets.indices.contains(index) else { return }
        replacementAlarmOffsets.remove(at: index)
        model.alarmIntent = replacementAlarmOffsets.isEmpty ? .clear : .replace(replacementAlarmOffsets)
    }

    private func synchronizeProviderSeeds() {
        synchronizeAlarmSeed()
        synchronizeRecurrenceSeed()
    }

    private func synchronizeAlarmSeed(forceDefault: Bool = false) {
        guard alarmChoice != .replace || replacementAlarmOffsets.isEmpty else { return }
        if case let .editable(offsets) = model.alarmSnapshot, !offsets.isEmpty {
            replacementAlarmOffsets = offsets
        } else if forceDefault || !showsDelete {
            replacementAlarmOffsets = [-600]
        }
    }

    private func synchronizeRecurrenceSeed(forceDefault: Bool = false) {
        guard recurrenceChoice != .replace || model.recurrenceIntent == .preserve else { return }
        if case let .editable(rule) = model.recurrenceSnapshot {
            replacementRecurrence = rule
        } else if forceDefault || !showsDelete {
            replacementRecurrence = Self.defaultRecurrence
        }
    }

    private func updateRecurrence(_ update: (inout RecurrenceRuleDraft) -> Void) {
        update(&replacementRecurrence)
        model.recurrenceIntent = .replace(replacementRecurrence)
    }

    private func unavailableText(_ reason: EventEditorUnavailableReason) -> String {
        switch reason {
        case .accessUnavailable: "Calendar access is unavailable."
        case .itemGone: "This event is no longer available."
        case .readOnlySource: "This event belongs to a read-only calendar."
        case .nonaddressable: "Calendar did not provide a stable editing identifier for this event."
        case .immutable: "This event can’t be changed."
        }
    }

    private func errorText(_ error: EventEditorError, action: EventEditorAction) -> String {
        switch error {
        case .accessUnavailable: "Calendar access is unavailable."
        case .itemGone: "This event is no longer available."
        case .immutable: "This event can’t be changed."
        case .invalidDestination: "Choose an available writable calendar."
        case .validationFailure: "Check the event details and try again."
        case .retryableWriteFailure where action.isDelete: "Your event was not deleted. Confirm before trying again."
        case .retryableWriteFailure: "Your event was not saved. Your edits are still here."
        }
    }

    private func deleteConfirmationLabel(_ scope: RecurrenceEditScope) -> String {
        scope == .futureOccurrences ? "Delete This and Future Events" : "Delete This Event"
    }

    private func offsetDescription(_ offset: TimeInterval) -> String {
        if offset == 0 { return "At start" }
        let absolute = abs(offset)
        let amount: String
        if absolute.truncatingRemainder(dividingBy: 3_600) == 0 {
            let hours = Int(absolute / 3_600)
            amount = "\(hours) hour\(hours == 1 ? "" : "s")"
        } else if absolute.truncatingRemainder(dividingBy: 60) == 0 {
            let minutes = Int(absolute / 60)
            amount = "\(minutes) minute\(minutes == 1 ? "" : "s")"
        } else {
            amount = "\(absolute.formatted(.number.precision(.fractionLength(0...2)))) seconds"
        }
        return offset < 0 ? "\(amount) before" : "\(amount) after"
    }

    private func recurrenceDescription(_ rule: RecurrenceRuleDraft) -> String {
        var parts = ["Every \(rule.interval) \(rule.frequency.unit(interval: rule.interval))"]
        if rule.frequency == .weekly, !rule.weekdays.isEmpty {
            let symbols = Calendar.current.shortWeekdaySymbols
            let days = rule.weekdays.sorted().compactMap { day in symbols.indices.contains(day - 1) ? symbols[day - 1] : nil }
            if !days.isEmpty { parts.append("on \(days.joined(separator: ", "))") }
        }
        if let endDate = rule.endDate { parts.append("until \(endDate.formatted(date: .abbreviated, time: .omitted))") }
        return parts.joined(separator: " ")
    }

    private static let defaultRecurrence = RecurrenceRuleDraft(frequency: .daily, interval: 1, weekdays: [], endDate: nil)
}

private enum EventAlarmChoice: Hashable {
    case preserve, clear, replace
    init(_ intent: EventAlarmMutationIntent) {
        switch intent { case .preserve: self = .preserve; case .clear: self = .clear; case .replace: self = .replace }
    }
}

private enum EventRecurrenceChoice: Hashable {
    case preserve, clear, replace
    init(_ intent: RecurrenceMutationIntent) {
        switch intent { case .preserve: self = .preserve; case .clear: self = .clear; case .replace: self = .replace }
    }
}

private extension EventEditorAction {
    var isDelete: Bool { if case .delete = self { return true }; return false }
}

private extension EventEditorPhase {
    var isCommitted: Bool {
        switch self {
        case .created, .updated, .deleted: true
        case .idle, .confirming, .writing, .failed, .unavailable: false
        }
    }
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
