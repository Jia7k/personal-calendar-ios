import SwiftUI

@MainActor
struct TaskTimeBlockSession: Identifiable {
    let id = UUID()
    let model: TaskTimeBlockViewModel
    let profiles: [ProfileSnapshot]
    let resolveProfile: @MainActor (UUID) throws -> CreationProfileContext
    let onSaved: @MainActor () async -> Void

    static func make(
        task: ReminderSnapshot,
        environment: AppEnvironment
    ) -> TaskTimeBlockSession? {
        let scopes = environment.profileScopes
        let resolver = CreationProfileResolver(
            profiles: environment.profileSelection.profiles,
            resolveScope: { try scopes.resolve($0) }
        )
        let creationProfile: CreationProfileContext?
        do {
            switch try resolver.resolve(
                active: environment.profileSelection.activeIdentity
            ) {
            case let .ready(context):
                creationProfile = context
            case .chooseSavedProfile:
                creationProfile = nil
            }
        } catch {
            return nil
        }

        var calendar = Calendar.current
        calendar.timeZone = .current
        return TaskTimeBlockSession(
            model: TaskTimeBlockViewModel(
                task: task,
                creationProfile: creationProfile,
                calendarService: environment.calendar,
                resolveScope: { try scopes.resolve($0) },
                planner: TaskTimeBlockPlanner(calendar: calendar),
                calendar: calendar,
                now: { Date() }
            ),
            profiles: environment.profileSelection.profiles,
            resolveProfile: { try resolver.resolve(chosen: $0) },
            onSaved: {
                await environment.refreshCoordinator.refreshNow(
                    reason: .localMutation
                )
            }
        )
    }
}

struct TaskTimeBlockView: View {
    let model: TaskTimeBlockViewModel
    let profiles: [ProfileSnapshot]
    let resolveProfile: @MainActor (UUID) throws -> CreationProfileContext
    let onSaved: @MainActor () async -> Void
    let onDismiss: @MainActor () -> Void

    @State private var profileError: String?
    @State private var handledSave = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Task") {
                    Text(model.task.title)
                    Text("This creates a separate calendar event. Your reminder stays unchanged.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                profileSection
                durationSection
                suggestionsSection
                timeSection
                destinationSection
                conflictSection
                failureSection
            }
            .accessibilityIdentifier("time-block-form")
            .navigationTitle("Schedule Time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: onDismiss) {
                        CalendarToolbarActionLabel(title: "Cancel")
                    }
                        .accessibilityIdentifier("time-block-cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            await model.save(
                                confirmingConflicts: model.requiresConflictConfirmation
                            )
                        }
                    } label: {
                        CalendarToolbarActionLabel(
                            title: LocalizedStringKey(saveTitle),
                            isProminent: true
                        )
                    }
                    .disabled(saveIsDisabled)
                    .accessibilityIdentifier(saveIdentifier)
                }
            }
            .task { await model.load() }
            .onChange(of: model.phase, initial: true) { _, phase in
                guard case .saved = phase, !handledSave else { return }
                handledSave = true
                Task {
                    await onSaved()
                    onDismiss()
                }
            }
        }
    }

    @ViewBuilder private var profileSection: some View {
        if model.requiresProfileSelection {
            Section("Profile") {
                Text("Choose which saved profile should own the calendar destination.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("time-block-profile-required")
                ForEach(profiles) { profile in
                    Button {
                        chooseProfile(profile.id)
                    } label: {
                        Label(profile.name, systemImage: profile.symbolName)
                    }
                    .accessibilityIdentifier("time-block-profile-\(profile.id.uuidString)")
                }
                if let profileError {
                    Label(profileError, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                }
            }
        } else if let profileName = model.selectedProfileName {
            Section("Profile") {
                LabeledContent("Scheduling in", value: profileName)
            }
        }
    }

    private var durationSection: some View {
        Section("Duration") {
            Picker("Duration", selection: durationBinding) {
                Text("30 min").tag(30)
                Text("60 min").tag(60)
                Text("90 min").tag(90)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("time-block-duration")
        }
    }

    @ViewBuilder private var suggestionsSection: some View {
        Section("Suggested times") {
            if model.requiresProfileSelection {
                Text("Choose a profile to find free time.")
                    .foregroundStyle(.secondary)
            } else if model.suggestions.isEmpty {
                Text("No free suggestion found. Choose a time below.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(model.suggestions.enumerated()), id: \.element.id) { index, suggestion in
                    Button {
                        model.setInterval(
                            start: suggestion.interval.start,
                            end: suggestion.interval.end
                        )
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(suggestion.interval.start, format: .dateTime.weekday().month().day())
                                Text("\(suggestion.interval.start.formatted(date: .omitted, time: .shortened))–\(suggestion.interval.end.formatted(date: .omitted, time: .shortened))")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if model.start == suggestion.interval.start,
                               model.end == suggestion.interval.end {
                                Image(systemName: "checkmark")
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .frame(minHeight: CalendarTheme.minimumTapSize)
                    .accessibilityIdentifier("time-block-suggestion-\(index)")
                    .accessibilityAddTraits(
                        model.start == suggestion.interval.start
                            && model.end == suggestion.interval.end
                            ? .isSelected
                            : []
                    )
                }
            }
        }
    }

    private var timeSection: some View {
        Section("Time") {
            DatePicker(
                "Start",
                selection: startBinding,
                displayedComponents: [.date, .hourAndMinute]
            )
            .accessibilityIdentifier("time-block-start")
            DatePicker(
                "End",
                selection: endBinding,
                in: model.start...,
                displayedComponents: [.date, .hourAndMinute]
            )
            .accessibilityIdentifier("time-block-end")
        }
    }

    private var destinationSection: some View {
        Section("Calendar") {
            Picker("Calendar", selection: destinationBinding) {
                Text("Choose a calendar").tag(String?.none)
                ForEach(model.availableCalendars) { calendar in
                    Text(calendar.title)
                        .tag(Optional(calendar.id))
                        .accessibilityIdentifier("time-block-calendar-\(calendar.id)")
                }
            }
            .accessibilityIdentifier("time-block-calendar")
            if !model.requiresProfileSelection, model.availableCalendars.isEmpty {
                Text("Add a writable calendar to this profile before scheduling time.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var conflictSection: some View {
        if !model.conflicts.isEmpty {
            Section("Conflict") {
                Label(
                    "Overlaps \(model.conflicts.joined(separator: ", "))",
                    systemImage: "exclamationmark.triangle"
                )
                .foregroundStyle(.orange)
                .accessibilityIdentifier("time-block-conflicts")
                Text("You can still save after confirming the overlap.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var failureSection: some View {
        if case let .failed(failure) = model.phase {
            Section("Couldn’t schedule time") {
                Label(failureMessage(failure), systemImage: "exclamationmark.triangle")
                    .accessibilityIdentifier("time-block-error")
                Text("Your choices are still here. Fix the issue and try again.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var durationBinding: Binding<Int> {
        Binding(
            get: { model.durationMinutes },
            set: { model.setDurationMinutes($0) }
        )
    }

    private var startBinding: Binding<Date> {
        Binding(
            get: { model.start },
            set: { value in
                let duration = max(30 * 60, model.end.timeIntervalSince(model.start))
                model.setInterval(start: value, end: value.addingTimeInterval(duration))
            }
        )
    }

    private var endBinding: Binding<Date> {
        Binding(
            get: { model.end },
            set: { value in
                let minimum = model.start.addingTimeInterval(30 * 60)
                model.setInterval(start: model.start, end: max(value, minimum))
            }
        )
    }

    private var destinationBinding: Binding<String?> {
        Binding(
            get: { model.destinationCalendarID },
            set: { model.selectDestination(calendarID: $0) }
        )
    }

    private var saveTitle: String {
        model.requiresConflictConfirmation ? "Save Anyway" : "Save"
    }

    private var saveIdentifier: String {
        model.requiresConflictConfirmation ? "time-block-save-anyway" : "time-block-save"
    }

    private var saveIsDisabled: Bool {
        model.requiresProfileSelection
            || model.destinationCalendarID == nil
            || model.start >= model.end
    }

    private func chooseProfile(_ id: UUID) {
        do {
            let context = try resolveProfile(id)
            profileError = nil
            Task { await model.chooseProfile(context) }
        } catch {
            profileError = "This profile is no longer available."
        }
    }

    private func failureMessage(_ failure: TaskTimeBlockFailure) -> String {
        switch failure {
        case .profileUnavailable:
            "The selected profile or its calendars are unavailable."
        case .invalidDestination:
            "Choose an available writable calendar and a valid time."
        case .writeFailed:
            "The calendar event was not created."
        }
    }
}
