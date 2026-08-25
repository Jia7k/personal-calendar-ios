import SwiftUI

struct TimetableSettingsView: View {
    let snapshotCoordinator: TimetableSnapshotCoordinator
    let activityCoordinator: TimetableLiveActivityCoordinator
    let refresh: @MainActor () async -> Void

    var body: some View {
        List {
            Section("School timetable") {
                Text(snapshotStatus)
                    .foregroundStyle(.secondary)

                Button("Refresh timetable") {
                    Task { await refresh() }
                }
                .accessibilityIdentifier("timetable-refresh")

                Button("Start Today's Timetable") {
                    guard let snapshot = snapshotCoordinator.latestSnapshot else { return }
                    Task { await activityCoordinator.start(snapshot: snapshot) }
                }
                .disabled(!canStart)
                .accessibilityIdentifier("timetable-start")

                if activityCoordinator.status == .running {
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
                Text("Widgets stay available all week. The live timetable updates while My Calendar is running; fully automatic background transitions will require a future push service.")
                    .foregroundStyle(.secondary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(CalendarTheme.background)
        .navigationTitle("School Timetable")
    }

    private var canStart: Bool {
        guard activityCoordinator.status != .running,
              let snapshot = snapshotCoordinator.latestSnapshot,
              snapshot.availability == .ready else { return false }

        let calendar = calendar(for: snapshot)
        return snapshot.entries.contains { calendar.isDate($0.start, inSameDayAs: .now) }
    }

    private var snapshotStatus: String {
        if let error = snapshotCoordinator.errorMessage {
            return "The timetable could not sync: \(error)"
        }
        guard let snapshot = snapshotCoordinator.latestSnapshot else {
            return "The timetable has not synced yet."
        }
        guard snapshot.availability == .ready else {
            return "Calendar access is required to build your timetable."
        }
        if snapshot.entries.isEmpty {
            return "No weekday classes were found this week."
        }
        return "\(snapshot.entries.count) classes are synced for this week."
    }

    private var activityStatus: String? {
        switch activityCoordinator.status {
        case .idle:
            nil
        case .running:
            "Today's timetable is active on the Lock Screen."
        case let .unavailable(message), let .failed(message):
            message
        }
    }

    private func calendar(for snapshot: TimetableSnapshotV1) -> Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: snapshot.timeZoneIdentifier) ?? .current
        return value
    }
}
