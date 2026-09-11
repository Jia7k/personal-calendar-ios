import SwiftUI

/// Host-owned event editor. Provider writes are owned by the model; the host
/// owns dismissal and the one post-commit agenda refresh.
struct EventEditorView: View {
    let model: EventEditorViewModel
    let calendars: [CalendarDescriptor]
    let nilDestinationLabel: String
    let showsDelete: Bool
    let isDuplicateCopy: Bool
    let onDismiss: () -> Void

    @State private var showsDiscardConfirmation = false
    @State private var selectedSaveScope: RecurrenceEditScope = .thisOccurrence
    @State private var selectedDeleteScope: RecurrenceEditScope = .thisOccurrence
    @State private var replacementAlarmOffsets: [TimeInterval] = []
    @State private var customAlarmValues: [Int: EventAlarmCustomValue] = [:]
    @State private var replacementRecurrence = Self.defaultRecurrence
    @State private var duplicatePresentation: EventDuplicatePresentation?
    @State private var pendingDuplicateCommit: EventEditorCommit?
    @State private var showsMoreOptions = false

    init(
        model: EventEditorViewModel,
        calendars: [CalendarDescriptor],
        nilDestinationLabel: String,
        showsDelete: Bool,
        isDuplicateCopy: Bool = false,
        onDismiss: @escaping () -> Void
    ) {
        self.model = model
        self.calendars = calendars
        self.nilDestinationLabel = nilDestinationLabel
        self.showsDelete = showsDelete
        self.isDuplicateCopy = isDuplicateCopy
        self.onDismiss = onDismiss
        if case let .replace(offsets) = model.alarmIntent {
            _replacementAlarmOffsets = State(initialValue: offsets)
        }
        if case let .replace(rule) = model.recurrenceIntent {
            _replacementRecurrence = State(initialValue: rule)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                if isDuplicateCopy {
                    Section {
                        Label(
                            "Duplicated copy — review before saving",
                            systemImage: "doc.on.doc"
                        )
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("event-duplicate-editor-screen")
                    }
                }
                detailsSection.disabled(isUnavailable)
                moreOptionsSection
                preflightSection
                if showsMoreOptions {
                    optionalDetailsSection.disabled(isUnavailable)
                    destinationSection.disabled(isUnavailable)
                    categorySection.disabled(isUnavailable)
                    alarmsSection.disabled(isUnavailable)
                    recurrenceSection.disabled(isUnavailable)
                }
                mutationSection
                failureSection
            }
            .navigationTitle(showsDelete ? "Event" : "New Event")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: requestDismiss) {
                        CalendarToolbarActionLabel(title: "Cancel")
                    }
                        .accessibilityIdentifier("event-editor-cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await model.requestSave(scope: selectedSaveScope) }
                    } label: {
                        CalendarToolbarActionLabel(
                            title: isWriting ? "Saving…" : "Save",
                            isProminent: true
                        )
                    }
                    .disabled(!canSave)
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
            .sheet(
                item: $duplicatePresentation,
                onDismiss: finishDuplicatePresentation
            ) { presentation in
                EventDuplicateFlowView(
                    sourceModel: model,
                    calendars: calendars,
                    initialStart: presentation.initialStart,
                    onCommitted: { pendingDuplicateCommit = $0 },
                    onDismiss: { duplicatePresentation = nil }
                )
            }
            .task {
                await model.load()
                synchronizeProviderSeeds()
            }
            .onChange(of: model.alarmSnapshot) { _, _ in synchronizeAlarmSeed() }
            .onChange(of: model.recurrenceSnapshot) { _, _ in synchronizeRecurrenceSeed() }
            .onChange(of: model.phase) { _, phase in
                if shouldRevealMoreOptions(for: phase) { showsMoreOptions = true }
                if phase.isCommitted { onDismiss() }
            }
        }
    }

    private var detailsSection: some View {
        Section("Details") {
            TextField("Title", text: binding(\.title), axis: .vertical)
                .lineLimit(1...3)
                .accessibilityIdentifier("event-editor-title")
            Toggle("All-day", isOn: binding(\.isAllDay))
                .accessibilityIdentifier("event-editor-all-day")
            DatePicker("Starts", selection: binding(\.start), displayedComponents: dateComponents)
                .accessibilityIdentifier("event-editor-start")
            DatePicker("Ends", selection: binding(\.end), displayedComponents: dateComponents)
                .accessibilityIdentifier("event-editor-end")
            TextField("Location", text: optionalStringBinding(\.location))
                .accessibilityIdentifier("event-editor-location")
        }
    }

    private var optionalDetailsSection: some View {
        Section("Additional Details") {
            TextField("URL", text: urlBinding)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                .accessibilityIdentifier("event-editor-url")
            TextField("Notes", text: optionalStringBinding(\.notes), axis: .vertical)
                .lineLimit(3...8)
                .accessibilityIdentifier("event-editor-notes")
        }
    }

    private var moreOptionsSection: some View {
        Section {
            Button {
                showsMoreOptions.toggle()
            } label: {
                HStack(spacing: 12) {
                    Text("More options")
                    Spacer()
                    Image(systemName: showsMoreOptions ? "chevron.up" : "chevron.down")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(minHeight: CalendarTheme.minimumTapSize)
            .accessibilityLabel("More options")
            .accessibilityValue(showsMoreOptions ? "Expanded" : "Collapsed")
            .accessibilityHint(showsMoreOptions ? "Hides optional event fields" : "Shows optional event fields")
            .accessibilityIdentifier("event-editor-more-options")

            Text(optionsSummary)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("event-editor-options-summary")
        }
    }

    @ViewBuilder private var preflightSection: some View {
        if let issue = model.savePreflightIssue {
            Section("Needs attention") {
                Label(preflightMessage(issue), systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("event-editor-preflight-message")
                if issue.concernsMoreOptions, !showsMoreOptions {
                    Button("Show affected options") {
                        showsMoreOptions = true
                    }
                    .frame(minHeight: CalendarTheme.minimumTapSize)
                    .accessibilityIdentifier("event-editor-show-invalid-options")
                }
            }
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
                        Picker("Alert \(index + 1)", selection: alarmOffsetChoiceBinding(index)) {
                            ForEach(EventAlarmPreset.allCases) { preset in
                                Text(preset.title).tag(EventAlarmOffsetChoice.preset(preset))
                            }
                            Text("Custom").tag(EventAlarmOffsetChoice.custom)
                        }
                        .frame(minHeight: CalendarTheme.minimumTapSize)
                        .accessibilityIdentifier("event-editor-alarm-preset-\(index)")

                        if alarmOffsetChoice(at: index) == .custom {
                            TextField(
                                "Amount",
                                value: alarmAmountBinding(index),
                                format: .number
                            )
                            .keyboardType(.decimalPad)
                            .frame(minHeight: CalendarTheme.minimumTapSize)
                            .accessibilityIdentifier("event-editor-alarm-offset-\(index)")
                            Picker("Unit", selection: alarmUnitBinding(index)) {
                                ForEach(EventAlarmUnit.allCases) { unit in
                                    Text(unit.title).tag(unit)
                                }
                            }
                            .frame(minHeight: CalendarTheme.minimumTapSize)
                            .accessibilityIdentifier("event-editor-alarm-unit-\(index)")
                            Picker("Timing", selection: alarmTimingBinding(index)) {
                                ForEach(EventAlarmTiming.allCases) { timing in
                                    Text(timing.title).tag(timing)
                                }
                            }
                            .frame(minHeight: CalendarTheme.minimumTapSize)
                            .accessibilityIdentifier("event-editor-alarm-timing-\(index)")
                        }
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
                if model.canDuplicate {
                    Button("Duplicate Event", systemImage: "plus.square.on.square") {
                        let suggested = Calendar.current.date(
                            byAdding: .weekOfYear,
                            value: 1,
                            to: model.start
                        ) ?? model.start
                        duplicatePresentation = .init(initialStart: suggested)
                    }
                    .disabled(isWriting || model.requiresDiscardConfirmation)
                    .frame(minHeight: CalendarTheme.minimumTapSize)
                    .accessibilityIdentifier("event-editor-duplicate")
                    if model.requiresDiscardConfirmation {
                        Text("Save or discard your edits before duplicating this event.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
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

    private var optionsSummary: String {
        EditorOptionsSummary.event(
            alarmIntent: model.alarmIntent,
            alarmSnapshot: model.alarmSnapshot,
            recurrenceIntent: model.recurrenceIntent,
            recurrenceSnapshot: model.recurrenceSnapshot,
            destinationTitle: selectedDestinationTitle,
            categoryTitle: selectedCategoryTitle,
            notes: model.notes,
            url: model.url
        )
    }

    private var selectedDestinationTitle: String {
        if let id = model.destinationCalendarID,
           let calendar = calendars.first(where: { $0.id == id }) {
            return calendar.title
        }
        return model.currentCalendarTitle ?? nilDestinationLabel
    }

    private var selectedCategoryTitle: String? {
        guard let id = model.categoryID else { return nil }
        return model.availableCategories.first(where: { $0.id == id })?.name
    }

    private var destinationHelp: String {
        if model.destinationCalendarID != nil {
            return showsDelete
                ? "Choose a writable calendar to move this event."
                : "Choose the writable calendar for this new event."
        }
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

    private func alarmOffsetChoice(at index: Int) -> EventAlarmOffsetChoice {
        guard replacementAlarmOffsets.indices.contains(index) else { return .custom }
        if customAlarmValues[index] != nil { return .custom }
        guard let preset = EventAlarmPreset(offset: replacementAlarmOffsets[index]) else {
            return .custom
        }
        return .preset(preset)
    }

    private func alarmOffsetChoiceBinding(_ index: Int) -> Binding<EventAlarmOffsetChoice> {
        Binding(
            get: { alarmOffsetChoice(at: index) },
            set: { choice in
                guard replacementAlarmOffsets.indices.contains(index) else { return }
                switch choice {
                case let .preset(preset):
                    customAlarmValues[index] = nil
                    replaceAlarm(at: index, with: preset.offset)
                case .custom:
                    customAlarmValues[index] = EventAlarmCustomValue(
                        offset: replacementAlarmOffsets[index]
                    )
                }
            }
        )
    }

    private func alarmAmountBinding(_ index: Int) -> Binding<Double> {
        Binding(
            get: { alarmCustomValue(at: index).amount },
            set: { amount in
                var value = alarmCustomValue(at: index)
                value.amount = abs(amount)
                customAlarmValues[index] = value
                replaceAlarm(at: index, with: value.offset)
            }
        )
    }

    private func alarmUnitBinding(_ index: Int) -> Binding<EventAlarmUnit> {
        Binding(
            get: { alarmCustomValue(at: index).unit },
            set: { unit in
                var value = alarmCustomValue(at: index)
                value.unit = unit
                customAlarmValues[index] = value
                replaceAlarm(at: index, with: value.offset)
            }
        )
    }

    private func alarmTimingBinding(_ index: Int) -> Binding<EventAlarmTiming> {
        Binding(
            get: { alarmCustomValue(at: index).timing },
            set: { timing in
                var value = alarmCustomValue(at: index)
                value.timing = timing
                customAlarmValues[index] = value
                replaceAlarm(at: index, with: value.offset)
            }
        )
    }

    private func alarmCustomValue(at index: Int) -> EventAlarmCustomValue {
        if let value = customAlarmValues[index] { return value }
        guard replacementAlarmOffsets.indices.contains(index) else {
            return EventAlarmCustomValue(offset: 0)
        }
        return EventAlarmCustomValue(offset: replacementAlarmOffsets[index])
    }

    private func replaceAlarm(at index: Int, with offset: TimeInterval) {
        guard replacementAlarmOffsets.indices.contains(index) else { return }
        replacementAlarmOffsets[index] = offset
        model.alarmIntent = .replace(replacementAlarmOffsets)
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

    private func shouldRevealMoreOptions(for phase: EventEditorPhase) -> Bool {
        guard case let .failed(action, error) = phase, action == .save else { return false }
        return error == .invalidDestination || error == .validationFailure
    }

    private func preflightMessage(_ issue: EventEditorSavePreflightIssue) -> String {
        switch issue {
        case .titleRequired:
            "Enter an event title."
        case .datesOrAlertsInvalid:
            "Ends must be after Starts, and custom alert values under More options must be valid."
        case .repeatInvalid:
            "The repeat rule conflicts with this event’s dates. Review Repeat under More options."
        case .destinationRequired:
            "Choose an available calendar under More options."
        case .detailsInvalid:
            "Check the event details and the fields under More options."
        }
    }

    private func finishDuplicatePresentation() {
        guard let commit = pendingDuplicateCommit else { return }
        pendingDuplicateCommit = nil
        model.finishDuplicateCommit(commit)
    }

    private func addAlarm() {
        replacementAlarmOffsets.append(-600)
        model.alarmIntent = .replace(replacementAlarmOffsets)
    }

    private func removeAlarm(at index: Int) {
        guard replacementAlarmOffsets.indices.contains(index) else { return }
        replacementAlarmOffsets.remove(at: index)
        customAlarmValues = Dictionary(uniqueKeysWithValues: customAlarmValues.compactMap { customIndex, value in
            if customIndex == index { return nil }
            return (customIndex > index ? customIndex - 1 : customIndex, value)
        })
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
            customAlarmValues = [:]
        } else if forceDefault || !showsDelete {
            replacementAlarmOffsets = [-600]
            customAlarmValues = [:]
        }
    }

    private func synchronizeRecurrenceSeed(forceDefault: Bool = false) {
        if case let .replace(rule) = model.recurrenceIntent,
           recurrenceChoice == .replace {
            replacementRecurrence = rule
            return
        }
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
        if absolute.truncatingRemainder(dividingBy: 86_400) == 0 {
            let days = Int(absolute / 86_400)
            amount = "\(days) day\(days == 1 ? "" : "s")"
        } else if absolute.truncatingRemainder(dividingBy: 3_600) == 0 {
            let hours = Int(absolute / 3_600)
            amount = "\(hours) hour\(hours == 1 ? "" : "s")"
        } else if absolute.truncatingRemainder(dividingBy: 60) == 0 {
            let minutes = Int(absolute / 60)
            amount = "\(minutes) minute\(minutes == 1 ? "" : "s")"
        } else {
            amount = "\(absolute.formatted(.number)) seconds"
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

private struct EventDuplicatePresentation: Identifiable {
    let id = UUID()
    let initialStart: Date
}

private struct EventDuplicateFlowView: View {
    let sourceModel: EventEditorViewModel
    let calendars: [CalendarDescriptor]
    let onCommitted: @MainActor (EventEditorCommit) -> Void
    let onDismiss: () -> Void

    @State private var confirmedStart: Date
    @State private var duplicateModel: EventEditorViewModel?
    @State private var errorMessage: String?

    init(
        sourceModel: EventEditorViewModel,
        calendars: [CalendarDescriptor],
        initialStart: Date,
        onCommitted: @escaping @MainActor (EventEditorCommit) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.sourceModel = sourceModel
        self.calendars = calendars
        self.onCommitted = onCommitted
        self.onDismiss = onDismiss
        _confirmedStart = State(initialValue: initialStart)
    }

    var body: some View {
        if let duplicateModel {
            AnyView(
                EventEditorView(
                    model: duplicateModel,
                    calendars: calendars.filter {
                        duplicateModel.creationDestinationCalendarIDs?
                            .contains($0.id) ?? true
                    },
                    nilDestinationLabel: "Choose Calendar",
                    showsDelete: false,
                    isDuplicateCopy: true,
                    onDismiss: onDismiss
                )
            )
        } else {
            NavigationStack {
                Form {
                    Section("New event") {
                        DatePicker(
                            "Starts",
                            selection: $confirmedStart,
                            displayedComponents: sourceModel.isAllDay
                                ? [.date]
                                : [.date, .hourAndMinute]
                        )
                        .accessibilityIdentifier("event-duplicate-start")
                        Text("The copy starts with the same duration, details, alerts, repeat rule, color, and calendar. You can change them before saving.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if let errorMessage {
                        Section {
                            Label(errorMessage, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .navigationTitle("Duplicate Event")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(action: onDismiss) {
                            CalendarToolbarActionLabel(title: "Cancel")
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            guard let model = sourceModel.makeDuplicate(
                                confirmedStart: confirmedStart,
                                onCommitted: onCommitted
                            ) else {
                                errorMessage = "The event details or destination could not be loaded. Try again."
                                return
                            }
                            duplicateModel = model
                        } label: {
                            CalendarToolbarActionLabel(
                                title: "Review",
                                isProminent: true
                            )
                        }
                        .accessibilityIdentifier("event-duplicate-review")
                    }
                }
            }
        }
    }
}

enum EventAlarmPreset: CaseIterable, Hashable, Identifiable {
    case atStart
    case fiveMinutesBefore
    case tenMinutesBefore
    case fifteenMinutesBefore
    case thirtyMinutesBefore
    case oneHourBefore
    case oneDayBefore

    init?(offset: TimeInterval) {
        guard let preset = Self.allCases.first(where: { $0.offset == offset }) else {
            return nil
        }
        self = preset
    }

    var id: Self { self }

    var title: String {
        switch self {
        case .atStart: "At start"
        case .fiveMinutesBefore: "5 minutes before"
        case .tenMinutesBefore: "10 minutes before"
        case .fifteenMinutesBefore: "15 minutes before"
        case .thirtyMinutesBefore: "30 minutes before"
        case .oneHourBefore: "1 hour before"
        case .oneDayBefore: "1 day before"
        }
    }

    var offset: TimeInterval {
        switch self {
        case .atStart: 0
        case .fiveMinutesBefore: -300
        case .tenMinutesBefore: -600
        case .fifteenMinutesBefore: -900
        case .thirtyMinutesBefore: -1_800
        case .oneHourBefore: -3_600
        case .oneDayBefore: -86_400
        }
    }
}

enum EventAlarmUnit: CaseIterable, Hashable, Identifiable {
    case seconds
    case minutes
    case hours
    case days

    var id: Self { self }

    var title: String {
        switch self {
        case .seconds: "Seconds"
        case .minutes: "Minutes"
        case .hours: "Hours"
        case .days: "Days"
        }
    }

    fileprivate var seconds: TimeInterval {
        switch self {
        case .seconds: 1
        case .minutes: 60
        case .hours: 3_600
        case .days: 86_400
        }
    }
}

enum EventAlarmTiming: CaseIterable, Hashable, Identifiable {
    case before
    case after

    var id: Self { self }
    var title: String { self == .before ? "Before" : "After" }
}

struct EventAlarmCustomValue: Equatable {
    var amount: Double
    var unit: EventAlarmUnit
    var timing: EventAlarmTiming

    init(offset: TimeInterval) {
        let magnitude = abs(offset)
        unit = [.days, .hours, .minutes].first(where: { candidate in
            guard magnitude >= candidate.seconds else { return false }
            let hundredths = magnitude / candidate.seconds * 100
            return abs(hundredths - hundredths.rounded()) < 0.000_000_001
        }) ?? .seconds
        amount = magnitude / unit.seconds
        timing = offset < 0 ? .before : .after
    }

    var offset: TimeInterval {
        let magnitude = abs(amount) * unit.seconds
        return timing == .before ? -magnitude : magnitude
    }
}

private enum EventAlarmOffsetChoice: Hashable {
    case preset(EventAlarmPreset)
    case custom
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

private extension EventEditorSavePreflightIssue {
    var concernsMoreOptions: Bool { self != .titleRequired }
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
