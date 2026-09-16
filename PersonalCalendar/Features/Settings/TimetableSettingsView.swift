import SwiftUI

struct TimetableSettingsView: View {
    let dailySnapshots: DailyActivitySnapshotCoordinator
    let profileSelection: ProfileSelectionController
    let activityCoordinator: TimetableLiveActivityCoordinator
    let settings: AppSettingsStore
    let refresh: @MainActor () async -> Void

    @State private var selectedIdentity: ProfileIdentity?
    @State private var preview: DailyActivitySnapshot?
    @State private var previewError: String?
    @State private var isLoading = false
    @State private var previewGeneration = 0

    init(
        dailySnapshots: DailyActivitySnapshotCoordinator,
        profileSelection: ProfileSelectionController,
        activityCoordinator: TimetableLiveActivityCoordinator,
        settings: AppSettingsStore,
        initialProfileIdentity: ProfileIdentity? = nil,
        refresh: @escaping @MainActor () async -> Void
    ) {
        self.dailySnapshots = dailySnapshots
        self.profileSelection = profileSelection
        self.activityCoordinator = activityCoordinator
        self.settings = settings
        self.refresh = refresh
        _selectedIdentity = State(initialValue: settings.preferredLiveActivityProfile ?? initialProfileIdentity)
    }

    var body: some View {
        List {
            Section("Daily Live Activity") {
                Picker("Profile", selection: $selectedIdentity) {
                    Text("Choose a profile").tag(ProfileIdentity?.none)
                    ForEach(profiles, id: \.id) { profile in
                        Label(profile.name, systemImage: profile.symbolName)
                            .tag(Optional(profile.id))
                    }
                }
                .accessibilityIdentifier("timetable-profile")
                .onChange(of: selectedIdentity) { _, identity in
                    let wasAutomaticallyEnabled = settings.automaticallyStartsLiveActivityOnForeground
                    savePreferredProfile(identity)
                    let preferred = settings.preferredLiveActivityProfile
                    Task {
                        await activityCoordinator.applyPreferenceSelectionChange(
                            wasAutomaticallyEnabled: wasAutomaticallyEnabled,
                            preferredProfileIdentity: preferred
                        )
                    }
                }

                Text(selectionSummary).foregroundStyle(.secondary)

                Toggle("Start when Personal Calendar opens", isOn: Binding(
                    get: { settings.automaticallyStartsLiveActivityOnForeground },
                    set: updateAutomaticStart
                ))
                .disabled(selectedIdentity == nil && !settings.automaticallyStartsLiveActivityOnForeground)
                .accessibilityIdentifier("timetable-auto-start")

                Text("Starts when you open the app. Background starts and automatic renewal are not guaranteed.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button("Refresh daily schedule") {
                    Task {
                        await refresh()
                        validateSelection()
                        await loadPreview()
                    }
                }
                .accessibilityIdentifier("timetable-refresh")

                if let actionTitle {
                    Button(actionTitle) {
                        guard let selectedIdentity else { return }
                        savePreferredProfile(selectedIdentity)
                        Task { await activityCoordinator.start(profileIdentity: selectedIdentity) }
                    }
                    .disabled(!canStart)
                    .accessibilityIdentifier("timetable-start")
                }

                if activityCoordinator.activeProfileIdentity != nil {
                    Button("Stop for now", role: .destructive) {
                        Task { await activityCoordinator.stop() }
                    }
                    .accessibilityIdentifier("timetable-stop")
                }
            }

            if let activityStatus {
                Section("Live Activity") {
                    Text(activityStatus).foregroundStyle(.secondary)
                }
            }

            Section("About updates") {
                Text("Shows today's remaining events and incomplete tasks due today. Tasks from Reminders appear once; their alert is not a separate item. Weekly Home Screen widgets stay unchanged.")
                Text("This is a glanceable view of the last app refresh, not an always-current all-day service. Open Personal Calendar to update completed tasks or changed events.")
                Text("iOS allows up to eight active hours. After that, the activity leaves the Dynamic Island and may remain on the Lock Screen for up to four more hours. It cannot renew itself while the app is suspended.")
            }
            .foregroundStyle(.secondary)
        }
        .scrollContentBackground(.hidden)
        .background(CalendarTheme.background)
        .navigationTitle("Timetable")
        .task(id: selectedIdentity) {
            await refresh()
            guard !Task.isCancelled else { return }
            validateSelection()
            await loadPreview()
        }
        .onChange(of: profileSelection.profiles) {
            validateSelection()
            Task { await loadPreview() }
        }
        .onChange(of: dailySnapshots.revision) {
            Task { await loadPreview() }
        }
    }

    private var profiles: [DailyActivityProfile] {
        [DailyActivityProfile(id: .everything, name: "Everything", symbolName: "rectangle.stack.fill")]
            + profileSelection.profiles.map {
                DailyActivityProfile(id: .saved($0.id), name: $0.name, symbolName: $0.symbolName)
            }
    }

    private var actionTitle: String? {
        guard let selectedIdentity,
              let active = activityCoordinator.activeProfileIdentity else { return "Start Live Activity" }
        return active == selectedIdentity ? nil : "Switch Live Activity"
    }

    private var canStart: Bool {
        guard !isLoading, previewError == nil, let preview,
              preview.profile.id == selectedIdentity else { return false }
        let presentation = DailyActivityPresentation.make(snapshot: preview, now: .now, rowLimit: 3)
        return presentation.remainingCount > 0 && !presentation.requiresRefresh
    }

    private var selectionSummary: String {
        guard selectedIdentity != nil else { return "Choose which profile the Lock Screen should show." }
        if isLoading { return "Loading today's schedule…" }
        if let previewError { return previewError }
        guard let preview, preview.profile.id == selectedIdentity else { return "Refresh to load today's schedule." }
        let presentation = DailyActivityPresentation.make(snapshot: preview, now: .now, rowLimit: 3)
        let count = presentation.remainingCount
        let summary = count == 0
            ? "No remaining events or tasks today for \(preview.profile.name)."
            : "\(count) \(count == 1 ? "item" : "items") remaining today for \(preview.profile.name)."
        let unavailable = [
            preview.calendarUnavailable ? "Some calendars unavailable." : nil,
            preview.tasksUnavailable ? "Some tasks unavailable." : nil
        ].compactMap { $0 }.joined(separator: " ")
        if count == 0, !unavailable.isEmpty { return "\(unavailable) Check access and refresh." }
        return unavailable.isEmpty ? summary : "\(summary) \(unavailable)"
    }

    private var activityStatus: String? {
        switch activityCoordinator.status {
        case .idle: nil
        case .running: "\(activityCoordinator.activeProfileName ?? "Your day") is active on the Lock Screen."
        case let .unavailable(message), let .failed(message): message
        }
    }

    private func validateSelection() {
        guard let selectedIdentity,
              !profiles.contains(where: { $0.id == selectedIdentity }) else { return }
        self.selectedIdentity = nil
        savePreferredProfile(nil)
        Task { await activityCoordinator.reconcileActive() }
    }

    private func savePreferredProfile(_ identity: ProfileIdentity?) {
        settings.setPreferredLiveActivityProfile(identity, validProfileIDs: Set(profileSelection.profiles.map(\.id)))
    }

    private func updateAutomaticStart(_ enabled: Bool) {
        if enabled { savePreferredProfile(selectedIdentity) }
        settings.setAutomaticallyStartsLiveActivityOnForeground(enabled)
        Task {
            await activityCoordinator.applyAutomaticStartSettingChange(
                isEnabled: settings.automaticallyStartsLiveActivityOnForeground,
                preferredProfileIdentity: settings.preferredLiveActivityProfile
            )
        }
    }

    private func loadPreview() async {
        previewGeneration += 1
        let generation = previewGeneration
        preview = nil
        previewError = nil
        guard let identity = selectedIdentity else { isLoading = false; return }
        isLoading = true
        defer { if generation == previewGeneration { isLoading = false } }
        do {
            let snapshot = try await dailySnapshots.snapshot(for: identity, now: .now)
            guard !Task.isCancelled, generation == previewGeneration, selectedIdentity == identity else { return }
            preview = snapshot
        } catch {
            guard !Task.isCancelled, generation == previewGeneration, selectedIdentity == identity else { return }
            previewError = "Today's schedule could not refresh. Please try again."
        }
    }
}
