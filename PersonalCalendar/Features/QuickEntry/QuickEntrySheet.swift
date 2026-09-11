import SwiftUI

/// A confirmed, editable quick-entry flow. The model owns parsing and exactly
/// one write; the root owns presentation, permission routing, and refresh.
struct QuickEntrySheet: View {
    let model: QuickEntryViewModel
    let onDismiss: () -> Void
    let onRequestAccess: (QuickEntryKind) -> Void
    let onOpenSettings: () -> Void
    let onAddAnother: (() -> Void)?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @State private var showsDiscardConfirmation = false
    @State private var showsDraftSaveFailure = false
    @State private var recurrenceIntervalText: String?
    @FocusState private var inputIsFocused: Bool
    @AccessibilityFocusState private var savedAnnouncementIsFocused: Bool

    init(
        model: QuickEntryViewModel,
        onDismiss: @escaping () -> Void,
        onRequestAccess: @escaping (QuickEntryKind) -> Void,
        onOpenSettings: @escaping () -> Void,
        onAddAnother: (() -> Void)? = nil
    ) {
        self.model = model
        self.onDismiss = onDismiss
        self.onRequestAccess = onRequestAccess
        self.onOpenSettings = onOpenSettings
        self.onAddAnother = onAddAnother
    }

    var body: some View {
        NavigationStack {
            phaseContent
                .scrollContentBackground(.hidden)
                .background(CalendarTheme.background)
                .navigationTitle(navigationTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { navigationToolbar }
        }
        .alert(
            "Discard quick entry?",
            isPresented: $showsDiscardConfirmation
        ) {
            Button("Keep Editing", role: .cancel) {}

            if model.captureSource == .inApp {
                Button("Save Draft") {
                    if model.checkpointDraft() {
                        onDismiss()
                    } else {
                        showsDraftSaveFailure = true
                    }
                }
                .accessibilityIdentifier("quick-entry-save-draft")
            }

            Button("Discard", role: .destructive) {
                model.confirmDiscard()
                onDismiss()
            }
        } message: {
            Text("Your unsaved quick-entry changes will be discarded.")
        }
        .alert("Draft not saved", isPresented: $showsDraftSaveFailure) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This quick entry is too large to store locally. Your changes are still here.")
        }
        .interactiveDismissDisabled(model.requestDismissal() != .dismiss)
        .onAppear {
            recurrenceIntervalText = model.preview?.recurrence.map { String($0.interval) }
            focusBlankInAppEntryIfAppropriate()
        }
        .onChange(of: model.preview?.recurrence?.interval) { _, interval in
            recurrenceIntervalText = interval.map { String($0) }
        }
        .onChange(of: model.phase) { _, phase in
            if case .committed = phase {
                savedAnnouncementIsFocused = true
            } else if case .entry = phase {
                focusBlankInAppEntryIfAppropriate()
            }
            model.checkpointDraft()
        }
        .onChange(of: model.text) { _, _ in
            model.checkpointDraft()
        }
        .onChange(of: model.preview) { _, _ in
            model.checkpointDraft()
        }
        .onChange(of: model.availableDraft) { _, draft in
            if draft == nil { focusBlankInAppEntryIfAppropriate() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { model.checkpointDraft() }
        }
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch model.phase {
        case let .entry(parseError):
            entryForm(parseError: parseError)
        case let .confirmation(state):
            confirmationForm(state: state)
        case let .saving(kind):
            savingForm(kind: kind)
        case let .committed(outcome):
            committedForm(outcome: outcome)
        }
    }

    @ToolbarContentBuilder
    private var navigationToolbar: some ToolbarContent {
        if case .entry = model.phase {
            ToolbarItem(placement: .cancellationAction) {
                Button(action: requestDismissal) {
                    CalendarToolbarActionLabel(title: "Cancel")
                }
                    .accessibilityIdentifier("quick-entry-cancel")
            }
        }

        if case .confirmation = model.phase {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    model.returnToEntry()
                } label: {
                    CalendarToolbarActionLabel(title: "Back")
                }
                    .accessibilityIdentifier("quick-entry-back")
            }
        }

        if case let .confirmation(state) = model.phase {
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    model.confirmSave()
                } label: {
                    CalendarToolbarActionLabel(
                        title: state.isFailure ? "Retry" : "Save",
                        isProminent: true
                    )
                }
                .disabled(!canSubmitConfirmation)
                .accessibilityIdentifier(state.isFailure ? "quick-entry-retry" : "quick-entry-save")
            }
        }
    }

    private func entryForm(parseError: QuickEntryParseError?) -> some View {
        Form {
            captureSourceSection
            draftRecoverySection

            Section {
                TextField("Describe what you want to add", text: textBinding)
                    .textInputAutocapitalization(.sentences)
                    .submitLabel(.continue)
                    .focused($inputIsFocused)
                    .onSubmit {
                        guard model.canReview,
                              model.availableDraft == nil else { return }
                        model.parse()
                    }
                    .disabled(model.availableDraft != nil)
                    .accessibilityValue(
                        model.text.isEmpty ? "Describe what you want to add" : model.text
                    )
                    .accessibilityIdentifier("quick-entry-input")

                Text("Try a title with a date, time, or repeat phrase. You can review every detail before saving.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("Quick entry")
            }

            if !model.recentEntries.isEmpty {
                Section {
                    ForEach(model.recentEntries) { item in
                        Button {
                            model.selectRecent(id: item.id)
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text(item.text)
                                    .foregroundStyle(.primary)
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                Text(item.lastUsedAt, style: .relative)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(minHeight: CalendarTheme.minimumTapSize)
                        }
                        .accessibilityIdentifier("quick-entry-recent-\(item.id.uuidString)")
                    }

                    Button("Clear Recent", role: .destructive) {
                        model.clearRecent()
                    }
                    .frame(minHeight: CalendarTheme.minimumTapSize)
                    .accessibilityIdentifier("quick-entry-recent-clear")
                } header: {
                    Text("Recent")
                }
                .disabled(model.availableDraft != nil)
                .accessibilityIdentifier("quick-entry-recent")
            }

            if let parseError {
                Section {
                    errorText(parseErrorMessage(parseError))
                }
            }

            Section {
                Button {
                    model.parse()
                } label: {
                    Text("Review")
                        .frame(maxWidth: .infinity, minHeight: CalendarTheme.minimumTapSize)
                }
                .disabled(!model.canReview || model.availableDraft != nil)
                .accessibilityIdentifier("quick-entry-parse")
            }
        }
    }

    @ViewBuilder
    private var draftRecoverySection: some View {
        if model.availableDraft != nil {
            Section("Unsaved draft") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Resume your last quick entry for this profile, or discard it to start fresh.")
                        .fixedSize(horizontal: false, vertical: true)

                    Button("Resume Draft") {
                        model.resumeDraft()
                    }
                    .buttonStyle(.borderless)
                    .frame(minHeight: CalendarTheme.minimumTapSize)
                    .accessibilityIdentifier("quick-entry-draft-resume")

                    Button("Discard Draft", role: .destructive) {
                        model.discardDraft()
                    }
                    .buttonStyle(.borderless)
                    .frame(minHeight: CalendarTheme.minimumTapSize)
                    .accessibilityIdentifier("quick-entry-draft-discard")
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("quick-entry-draft-recovery")
            }
        }
    }

    private func confirmationForm(state: QuickEntryConfirmationState) -> some View {
        Form {
            captureSourceSection
            kindSection
            sourceAccessSection

            if case let .failed(failure) = state {
                Section("Couldn’t save") {
                    errorText(saveFailureMessage(failure))
                }
            }

            detailsSection
            destinationSection
            recurrenceSection
            reminderSection
            categorySection
            informationSections
        }
    }

    @ViewBuilder
    private var captureSourceSection: some View {
        if model.captureSource != .inApp {
            Section {
                Label(
                    model.captureSource == .shortcut
                        ? "Captured from Siri or Shortcuts — review before saving."
                        : "Opened from a link — review before saving.",
                    systemImage: model.captureSource == .shortcut ? "waveform.badge.mic" : "link"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("quick-entry-capture-source")
            }
        }
    }

    private func savingForm(kind: QuickEntryKind) -> some View {
        Form {
            Section {
                VStack(spacing: 16) {
                    ProgressView()
                        .controlSize(.large)
                    Text("Saving \(kind.title.lowercased())…")
                        .font(.headline)
                    Text("Keep this sheet open until saving finishes.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 180)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Saving \(kind.title.lowercased())")
                .accessibilityIdentifier("quick-entry-saving")
            }
        }
    }

    private func committedForm(outcome: QuickEntrySaveOutcome) -> some View {
        Form {
            Section {
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 52))
                        .foregroundStyle(CalendarTheme.accent)
                        .accessibilityHidden(true)

                    Text("\(outcome.kind.title) saved")
                        .font(.title2.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("quick-entry-saved")
                        .accessibilityFocused($savedAnnouncementIsFocused)

                    Text("Your item was saved. Choose Done when you’re ready to return.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, minHeight: 220)
            }

            Section {
                Button {
                    if let onAddAnother {
                        onAddAnother()
                    } else {
                        model.startAnotherEntry()
                    }
                } label: {
                    Text("Add Another")
                        .frame(maxWidth: .infinity, minHeight: CalendarTheme.minimumTapSize)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("quick-entry-add-another")

                Button {
                    onDismiss()
                } label: {
                    Text("Done")
                        .frame(maxWidth: .infinity, minHeight: CalendarTheme.minimumTapSize)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("quick-entry-done")
            }
        }
    }

    private var kindSection: some View {
        Section("Type") {
            kindControl
        }
    }

    private var kindControl: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 8))
            : AnyLayout(HStackLayout(spacing: 8))

        return layout {
            ForEach(QuickEntryKind.allCases, id: \.self) { kind in
                let isSelected = model.preview?.kind == kind
                Button {
                    model.selectKind(kind)
                } label: {
                    Text(kind.title)
                        .frame(maxWidth: .infinity, minHeight: CalendarTheme.minimumTapSize)
                }
                .buttonStyle(.bordered)
                .tint(isSelected ? CalendarTheme.accent : Color.secondary)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityIdentifier("quick-entry-kind-\(kind.rawValue)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Type")
        .accessibilityValue(model.preview?.kind.title ?? "")
        .accessibilityIdentifier("quick-entry-kind")
    }

    @ViewBuilder
    private var detailsSection: some View {
        if let preview = model.preview {
            Section("Details") {
                TextField("Title", text: previewBinding(\.title, fallback: preview.title))
                    .accessibilityLabel("Title")
                    .accessibilityIdentifier("quick-entry-title")

                switch preview.kind {
                case .event:
                    eventDetails(preview)
                case .task:
                    taskDetails(preview)
                case .routine:
                    routineDetails(preview)
                }
            }
        }
    }

    @ViewBuilder
    private func eventDetails(_ preview: QuickEntryPreview) -> some View {
        Toggle("All-day", isOn: previewBinding(\.isAllDay, fallback: preview.isAllDay))
            .frame(minHeight: CalendarTheme.minimumTapSize)
            .accessibilityIdentifier("quick-entry-event-all-day")

        if let start = preview.startDate {
            DatePicker(
                "Starts",
                selection: optionalDateBinding(\.startDate, fallback: start),
                displayedComponents: preview.isAllDay ? [.date] : [.date, .hourAndMinute]
            )
            .accessibilityIdentifier("quick-entry-event-start")
        }

        if let end = preview.endDate {
            DatePicker(
                "Ends",
                selection: optionalDateBinding(\.endDate, fallback: end),
                displayedComponents: preview.isAllDay ? [.date] : [.date, .hourAndMinute]
            )
            .accessibilityIdentifier("quick-entry-event-end")
        }
    }

    @ViewBuilder
    private func taskDetails(_ preview: QuickEntryPreview) -> some View {
        Toggle(
            "Set a due date",
            isOn: Binding(
                get: { model.preview?.dueDate != nil },
                set: { model.setTaskDueEnabled($0) }
            )
        )
        .frame(minHeight: CalendarTheme.minimumTapSize)
        .accessibilityIdentifier("quick-entry-task-due-enabled")

        if let due = preview.dueDate {
            Toggle("Include time", isOn: previewBinding(\.dueHasTime, fallback: preview.dueHasTime))
                .frame(minHeight: CalendarTheme.minimumTapSize)
                .accessibilityIdentifier("quick-entry-task-due-has-time")

            DatePicker(
                "Due",
                selection: optionalDateBinding(\.dueDate, fallback: due),
                displayedComponents: preview.dueHasTime ? [.date, .hourAndMinute] : [.date]
            )
            .accessibilityIdentifier("quick-entry-task-due-date")
        }
    }

    @ViewBuilder
    private func routineDetails(_ preview: QuickEntryPreview) -> some View {
        let selectedWindow = preview.routineWindow ?? .anytime

        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 8) {
                    ForEach(RoutineWindow.allCases, id: \.self) { window in
                        routineWindowButton(window, selectedWindow: selectedWindow)
                    }
                }
            } else {
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    spacing: 8
                ) {
                    ForEach(RoutineWindow.allCases, id: \.self) { window in
                        routineWindowButton(window, selectedWindow: selectedWindow)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Window")
        .accessibilityValue(selectedWindow.title)
        .accessibilityIdentifier("quick-entry-routine-window")

        Text("Days")
            .font(.subheadline.weight(.semibold))

        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 4) {
                    ForEach(model.weekdayOrder, id: \.self) { day in
                        weekdayButton(day, inRecurrence: false)
                    }
                }
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 96), spacing: 8)],
                    spacing: 8
                ) {
                    ForEach(model.weekdayOrder, id: \.self) { day in
                        weekdayButton(day, inRecurrence: false)
                    }
                }
            }
        }
    }

    private func routineWindowButton(
        _ window: RoutineWindow,
        selectedWindow: RoutineWindow
    ) -> some View {
        let isSelected = selectedWindow == window
        return Button {
            setPreview(\.routineWindow, to: Optional(window))
        } label: {
            Text(window.title)
                .frame(maxWidth: .infinity, minHeight: CalendarTheme.minimumTapSize)
        }
        .buttonStyle(.bordered)
        .tint(isSelected ? CalendarTheme.accent : Color.secondary)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("quick-entry-routine-window-\(window.rawValue)")
    }

    @ViewBuilder
    private var destinationSection: some View {
        if let preview = model.preview, preview.kind != .routine {
            Section(preview.kind == .event ? "Calendar" : "List") {
                destinationMenu(preview)

                if let hint = model.destinationVisibilityHint {
                    Text(hint)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("quick-entry-destination-hint")
                }
            }
        }
    }

    private func destinationMenu(_ preview: QuickEntryPreview) -> some View {
        Menu {
            Button {
                model.selectDestination(nil)
            } label: {
                if preview.destinationID == nil {
                    Label("System Default", systemImage: "checkmark")
                } else {
                    Text("System Default")
                }
            }
            .disabled(!model.systemDefaultIsAvailable(for: preview.kind))
            .accessibilityIdentifier("quick-entry-destination-system-default")

            switch preview.kind {
            case .event:
                ForEach(model.destinations.calendars.filter(\.allowsContentModifications)) { calendar in
                    Button {
                        model.selectDestination(calendar.id)
                    } label: {
                        if preview.destinationID == calendar.id {
                            Label(calendar.title, systemImage: "checkmark")
                        } else {
                            Text(calendar.title)
                        }
                    }
                    .accessibilityIdentifier("quick-entry-destination-\(calendar.id)")
                }
            case .task:
                ForEach(model.destinations.reminderLists.filter(\.allowsContentModifications)) { list in
                    Button {
                        model.selectDestination(list.id)
                    } label: {
                        if preview.destinationID == list.id {
                            Label(list.title, systemImage: "checkmark")
                        } else {
                            Text(list.title)
                        }
                    }
                    .accessibilityIdentifier("quick-entry-destination-\(list.id)")
                }
            case .routine:
                EmptyView()
            }
        } label: {
            HStack {
                Text("Destination")
                Spacer()
                Text(destinationTitle(for: preview))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
            .frame(minHeight: CalendarTheme.minimumTapSize)
        }
        .accessibilityLabel("Destination")
        .accessibilityValue(destinationTitle(for: preview))
        .accessibilityIdentifier("quick-entry-destination")
    }

    private var categorySection: some View {
        Section("Organization") {
            Picker(
                "Category",
                selection: previewBinding(\.categoryID, fallback: model.preview?.categoryID)
            ) {
                Text("No Category").tag(UUID?.none)
                ForEach(model.categories) { category in
                    Text(category.name).tag(Optional(category.id))
                }
            }
                .frame(minHeight: CalendarTheme.minimumTapSize)
                .accessibilityIdentifier("quick-entry-category")
        }
    }

    @ViewBuilder
    private var recurrenceSection: some View {
        if let preview = model.preview, preview.kind != .routine {
            Section("Repeat") {
                Toggle(
                    "Repeats",
                    isOn: Binding(
                        get: { model.preview?.recurrence != nil },
                        set: { model.setRecurrenceEnabled($0) }
                    )
                )
                .frame(minHeight: CalendarTheme.minimumTapSize)
                .accessibilityIdentifier("quick-entry-recurrence-enabled")

                if let recurrence = preview.recurrence {
                    Picker("Frequency", selection: recurrenceFrequencyBinding) {
                        ForEach(RecurrenceFrequency.allCases, id: \.self) { frequency in
                            Text(frequency.title).tag(frequency)
                        }
                    }
                    .accessibilityIdentifier("quick-entry-recurrence-frequency")

                    TextField("Repeat interval", text: recurrenceIntervalBinding)
                        .keyboardType(.numberPad)
                        .accessibilityLabel("Repeat interval")
                        .accessibilityValue(recurrenceIntervalText ?? String(recurrence.interval))
                        .accessibilityIdentifier("quick-entry-recurrence-interval")

                    Text("Every \(recurrence.interval) \(recurrence.frequency.unit(interval: recurrence.interval))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    if recurrence.frequency == .weekly {
                        Text("Repeat on")
                            .font(.subheadline.weight(.semibold))

                        Group {
                            if dynamicTypeSize.isAccessibilitySize {
                                VStack(spacing: 4) {
                                    ForEach(model.weekdayOrder, id: \.self) { day in
                                        weekdayButton(day, inRecurrence: true)
                                    }
                                }
                            } else {
                                LazyVGrid(
                                    columns: [GridItem(.adaptive(minimum: 96), spacing: 8)],
                                    spacing: 8
                                ) {
                                    ForEach(model.weekdayOrder, id: \.self) { day in
                                        weekdayButton(day, inRecurrence: true)
                                    }
                                }
                            }
                        }
                    }

                    Toggle(
                        "End repeat",
                        isOn: Binding(
                            get: { model.preview?.recurrence?.endDate != nil },
                            set: { model.setRecurrenceEndEnabled($0) }
                        )
                    )
                    .frame(minHeight: CalendarTheme.minimumTapSize)
                    .accessibilityIdentifier("quick-entry-recurrence-end-enabled")

                    if let endDate = recurrence.endDate {
                        DatePicker(
                            "Repeat ends",
                            selection: recurrenceEndDateBinding(fallback: endDate),
                            displayedComponents: .date
                        )
                        .accessibilityIdentifier("quick-entry-recurrence-end-date")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var reminderSection: some View {
        if let preview = model.preview {
            Section("Reminder") {
                Toggle(
                    "Set a reminder",
                    isOn: Binding(
                        get: { model.preview?.reminderDate != nil },
                        set: { model.setReminderEnabled($0) }
                    )
                )
                .frame(minHeight: CalendarTheme.minimumTapSize)
                .accessibilityIdentifier("quick-entry-reminder-enabled")

                if let reminder = preview.reminderDate {
                    DatePicker(
                        preview.kind == .routine ? "Time" : "Reminder",
                        selection: optionalDateBinding(\.reminderDate, fallback: reminder),
                        displayedComponents: preview.kind == .routine ? [.hourAndMinute] : [.date, .hourAndMinute]
                    )
                    .accessibilityIdentifier("quick-entry-reminder-date")
                }
            }
        }
    }

    @ViewBuilder
    private var sourceAccessSection: some View {
        if let explanation = sourceExplanation {
            Section("Source access") {
                Text(explanation)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("quick-entry-source-explanation")

                switch model.sourceAction {
                case .requestAccess:
                    Button(sourceActionTitle) {
                        if let kind = model.preview?.kind { onRequestAccess(kind) }
                    }
                    .frame(minHeight: CalendarTheme.minimumTapSize)
                    .accessibilityIdentifier("quick-entry-source-action")
                case .openSettings:
                    Button("Open Settings", action: onOpenSettings)
                        .frame(minHeight: CalendarTheme.minimumTapSize)
                        .accessibilityIdentifier("quick-entry-source-action")
                case .none:
                    EmptyView()
                }
            }
        }
    }

    @ViewBuilder
    private var informationSections: some View {
        if let transformationNotice = model.transformationNotice {
            Section("Adjusted for this type") {
                Label(transformationNotice, systemImage: "arrow.triangle.2.circlepath")
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("quick-entry-transformation-notice")
            }
        }

        if let warning = model.warningMessage {
            Section("Check this date") {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("quick-entry-warning")
            }
        }

    }

    private func weekdayButton(_ day: Int, inRecurrence: Bool) -> some View {
        let isSelected = inRecurrence
            ? model.preview?.recurrence?.weekdays.contains(day) == true
            : model.preview?.weekdays.contains(day) == true
        let identifier = inRecurrence
            ? "quick-entry-recurrence-weekday-\(day)"
            : "quick-entry-routine-weekday-\(day)"

        return Button {
            if inRecurrence {
                updateRecurrence { rule in
                    if rule.weekdays.contains(day) {
                        rule.weekdays.remove(day)
                    } else {
                        rule.weekdays.insert(day)
                    }
                }
            } else if var days = model.preview?.weekdays {
                if days.contains(day) {
                    days.remove(day)
                } else {
                    days.insert(day)
                }
                setPreview(\.weekdays, to: days)
            }
        } label: {
            HStack {
                Text(model.weekdayName(day))
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: CalendarTheme.minimumTapSize)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityIdentifier(identifier)
    }

    private var navigationTitle: String {
        switch model.phase {
        case .entry: "Quick Entry"
        case .confirmation: "Review"
        case .saving: "Saving"
        case .committed: "Saved"
        }
    }

    private var textBinding: Binding<String> {
        Binding(
            get: { model.text },
            set: { model.text = $0 }
        )
    }

    private var recurrenceFrequencyBinding: Binding<RecurrenceFrequency> {
        Binding(
            get: { model.preview?.recurrence?.frequency ?? .daily },
            set: { frequency in
                updateRecurrence { $0.frequency = frequency }
            }
        )
    }

    private var recurrenceIntervalBinding: Binding<String> {
        Binding(
            get: {
                recurrenceIntervalText
                    ?? model.preview?.recurrence.map { String($0.interval) }
                    ?? ""
            },
            set: { input in
                let digits = input.filter { $0.isWholeNumber }
                recurrenceIntervalText = digits
                guard let interval = Int(digits), interval > 0 else { return }
                updateRecurrence { $0.interval = interval }
            }
        )
    }

    private var recurrenceIntervalIsValid: Bool {
        guard model.preview?.recurrence != nil else { return true }
        let text = recurrenceIntervalText
            ?? model.preview?.recurrence.map { String($0.interval) }
            ?? ""
        guard let interval = Int(text) else { return false }
        return interval > 0
    }

    private var canSubmitConfirmation: Bool {
        model.canSave && recurrenceIntervalIsValid
    }

    private var sourceExplanation: String? {
        model.sourceExplanation
    }

    private var sourceActionTitle: String {
        model.preview?.kind == .task ? "Allow Reminders Access" : "Allow Calendar Access"
    }

    private func destinationTitle(for preview: QuickEntryPreview) -> String {
        guard let id = preview.destinationID else { return "System Default" }
        switch preview.kind {
        case .event:
            return model.destinations.calendars.first(where: { $0.id == id })?.title ?? "Unavailable"
        case .task:
            return model.destinations.reminderLists.first(where: { $0.id == id })?.title ?? "Unavailable"
        case .routine:
            return "None"
        }
    }

    private func parseErrorMessage(_ error: QuickEntryParseError) -> String {
        switch error {
        case .emptyInput: "Enter something to add."
        case .noUsableTitle: "Add a title and try again."
        case .invalidClock: "Enter a valid time."
        case .invalidDate: "Enter a valid date."
        case .nonexistentLocalTime: "That local time does not exist. Choose another time."
        case .ambiguousExpression: "Use one clear date and time, then try again."
        }
    }

    private func saveFailureMessage(_ failure: QuickEntryFailure) -> String {
        switch failure {
        case .writeFailed:
            let kind = model.preview?.kind ?? .task
            return "Your \(kind.title.lowercased()) was not saved. Edit it and try again."
        case .validation:
            return "Check the details and try again."
        case .accessUnavailable:
            return sourceExplanation ?? "This source is unavailable. Choose another type."
        case .systemDefaultUnavailable:
            return "No writable System Default destination is available. Choose another type or destination."
        case .invalidDestination:
            return "The selected destination is no longer writable. Choose another destination."
        case .explicitDestinationRequired:
            return model.preview?.kind == .event
                ? "Choose a calendar before saving."
                : "Choose a reminder list before saving."
        }
    }

    private func errorText(_ message: String) -> some View {
        Text(message)
            .foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("quick-entry-error")
    }

    private func requestDismissal() {
        switch model.requestDismissal() {
        case .dismiss:
            onDismiss()
        case .confirmDiscard:
            showsDiscardConfirmation = true
        case .blocked:
            break
        }
    }

    private func focusBlankInAppEntryIfAppropriate() {
        guard !voiceOverEnabled,
              model.captureSource == .inApp,
              model.availableDraft == nil,
              case .entry = model.phase,
              model.text.isEmpty else { return }
        inputIsFocused = true
    }

    private func previewBinding<Value>(
        _ keyPath: WritableKeyPath<QuickEntryPreview, Value>,
        fallback: Value
    ) -> Binding<Value> {
        Binding(
            get: { model.preview?[keyPath: keyPath] ?? fallback },
            set: { setPreview(keyPath, to: $0) }
        )
    }

    private func optionalDateBinding(
        _ keyPath: WritableKeyPath<QuickEntryPreview, Date?>,
        fallback: Date
    ) -> Binding<Date> {
        Binding(
            get: { model.preview?[keyPath: keyPath] ?? fallback },
            set: { setPreview(keyPath, to: Optional($0)) }
        )
    }

    private func recurrenceEndDateBinding(fallback: Date) -> Binding<Date> {
        Binding(
            get: { model.preview?.recurrence?.endDate ?? fallback },
            set: { value in updateRecurrence { $0.endDate = value } }
        )
    }

    private func setPreview<Value>(
        _ keyPath: WritableKeyPath<QuickEntryPreview, Value>,
        to value: Value
    ) {
        guard var preview = model.preview else { return }
        preview[keyPath: keyPath] = value
        model.preview = preview
    }

    private func updateRecurrence(_ mutation: (inout RecurrenceRuleDraft) -> Void) {
        guard var preview = model.preview, var recurrence = preview.recurrence else { return }
        mutation(&recurrence)
        preview.recurrence = recurrence
        model.preview = preview
    }
}

private extension QuickEntryConfirmationState {
    var isFailure: Bool {
        if case .failed = self { return true }
        return false
    }
}

private extension QuickEntryKind {
    var title: String { rawValue.capitalized }
}

private extension QuickEntrySaveOutcome {
    var kind: QuickEntryKind {
        switch self {
        case .event: .event
        case .task: .task
        case .routine: .routine
        }
    }
}

private extension RoutineWindow {
    var title: String { rawValue.capitalized }
}

private extension RecurrenceFrequency {
    var title: String { rawValue.capitalized }

    func unit(interval: Int) -> String {
        let isPlural = interval != 1
        return switch self {
        case .daily: isPlural ? "days" : "day"
        case .weekly: isPlural ? "weeks" : "week"
        case .monthly: isPlural ? "months" : "month"
        case .yearly: isPlural ? "years" : "year"
        }
    }
}
