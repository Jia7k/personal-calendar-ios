import SwiftUI

struct TimetableSettingsView: View {
    let snapshotCoordinator: TimetableSnapshotCoordinator
    let activityCoordinator: TimetableLiveActivityCoordinator
    let refresh: @MainActor () async -> Void

    @State private var selectedIdentity: ProfileIdentity?

    init(
        snapshotCoordinator: TimetableSnapshotCoordinator,
        activityCoordinator: TimetableLiveActivityCoordinator,
        initialProfileIdentity: ProfileIdentity? = nil,
        refresh: @escaping @MainActor () async -> Void
    ) {
        self.snapshotCoordinator = snapshotCoordinator
        self.activityCoordinator = activityCoordinator
        self.refresh = refresh
        _selectedIdentity = State(initialValue: initialProfileIdentity)
    }

    var body: some View {
        List {
            Section("Timetable profile") {
                if profiles.isEmpty {
                    Text("Refresh to load your profiles.")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Profile", selection: $selectedIdentity) {
                        Text("Choose a profile").tag(ProfileIdentity?.none)
                        ForEach(profiles) { profile in
                            Label(profile.name, systemImage: profile.symbolName)
                                .tag(Optional(profile.id))
                        }
                    }
                    .accessibilityIdentifier("timetable-profile")
                }

                Text(selectionSummary)
                    .foregroundStyle(.secondary)

                Button("Refresh timetable") {
                    Task {
                        await refresh()
                        validateSelection()
                    }
                }
                .accessibilityIdentifier("timetable-refresh")

                if let actionTitle {
                    Button(actionTitle) {
                        guard let selectedProfile else { return }
                        Task { await activityCoordinator.start(profile: selectedProfile) }
                    }
                    .disabled(!canStart)
                    .accessibilityIdentifier("timetable-start")
                }

                if activityCoordinator.activeProfileIdentity != nil {
                    Button("Stop Live Activity", role: .destructive) {
                        Task { await activityCoordinator.stop() }
                    }
                    .accessibilityIdentifier("timetable-stop")
                }
            }

            if let activityStatus {
                Section("Live Activity") {
                    Text(activityStatus)
                        .foregroundStyle(.secondary)
                }
            }

            Section("About updates") {
                Text("Widgets stay available all week. The live timetable updates while My Calendar is running; fully automatic background transitions require a future push service.")
                    .foregroundStyle(.secondary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(CalendarTheme.background)
        .navigationTitle("Timetable")
        .task {
            await refresh()
            if let active = activityCoordinator.activeProfileIdentity {
                selectedIdentity = active
            }
            validateSelection()
        }
        .onChange(of: snapshotCoordinator.latestCatalog?.generatedAt) {
            validateSelection()
        }
    }

    private var profiles: [TimetableWidgetProfile] {
        snapshotCoordinator.latestCatalog?.profiles ?? []
    }

    private var selectedProfile: TimetableWidgetProfile? {
        guard let selectedIdentity else { return nil }
        return snapshotCoordinator.latestCatalog?.profile(for: selectedIdentity)
    }

    private var actionTitle: String? {
        guard let selectedIdentity else { return "Start Live Activity" }
        guard let active = activityCoordinator.activeProfileIdentity else {
            return "Start Live Activity"
        }
        return active == selectedIdentity ? nil : "Switch Live Activity"
    }

    private var canStart: Bool {
        guard let profile = selectedProfile,
              profile.snapshot.availability == .ready else { return false }
        let calendar = calendar(for: profile.snapshot)
        return profile.snapshot.entries.contains { calendar.isDate($0.start, inSameDayAs: .now) }
    }

    private var selectionSummary: String {
        if let error = snapshotCoordinator.errorMessage {
            return "The timetable could not sync: \(error)"
        }
        guard let selectedIdentity else {
            return "Choose which profile the Lock Screen should show."
        }
        guard let profile = snapshotCoordinator.latestCatalog?.profile(for: selectedIdentity) else {
            return "This profile is no longer available. Choose another profile."
        }
        switch profile.snapshot.availability {
        case .calendarAccessRequired:
            return "Calendar access is required for \(profile.name)."
        case .emptyProfile:
            return "\(profile.name) has no calendars."
        case .noClasses:
            return "No events were found this week for \(profile.name)."
        case .ready:
            let count = profile.snapshot.entries.count
            if count == 0 { return "No events were found this week for \(profile.name)." }
            let weekSummary = "\(count) \(count == 1 ? "event" : "events") this week"
            let entries = profile.snapshot.entries.sorted { $0.start < $1.start }
            let now = Date.now
            if let current = entries.first(where: { $0.start <= now && now < $0.end }) {
                return "Now: \(current.title), until \(timeText(current.end, snapshot: profile.snapshot)). \(weekSummary)."
            }
            if let next = entries.first(where: { $0.start > now }) {
                return "Next: \(next.title) at \(timeText(next.start, snapshot: profile.snapshot)). \(weekSummary)."
            }
            return "\(weekSummary) for \(profile.name)."
        }
    }

    private var activityStatus: String? {
        switch activityCoordinator.status {
        case .idle:
            nil
        case .running:
            if let name = activityCoordinator.activeProfileName {
                "\(name) is active on the Lock Screen."
            } else {
                "A timetable is active on the Lock Screen."
            }
        case let .unavailable(message), let .failed(message):
            message
        }
    }

    private func validateSelection() {
        guard let selectedIdentity,
              let catalog = snapshotCoordinator.latestCatalog else { return }
        if catalog.profile(for: selectedIdentity) == nil {
            self.selectedIdentity = nil
        }
    }

    private func timeText(_ date: Date, snapshot: TimetableSnapshotV1) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = TimeZone(identifier: snapshot.timeZoneIdentifier) ?? .current
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func calendar(for snapshot: TimetableSnapshotV1) -> Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: snapshot.timeZoneIdentifier) ?? .current
        return value
    }
}
