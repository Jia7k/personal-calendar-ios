import SwiftUI

struct NotificationSettingsView: View {
    let settings: AppSettingsStore
    let coordinator: NotificationCoordinator
    let reschedule: @MainActor @Sendable () async -> Void

    var body: some View {
        Section("Notifications") {
            Toggle("Morning summary", isOn: Binding(
                get: { settings.morningSummaryEnabled },
                set: { value in
                    settings.morningSummaryEnabled = value
                    refreshNotifications()
                }
            ))
            if settings.morningSummaryEnabled {
                Picker("Hour", selection: Binding(
                    get: { settings.morningSummaryHour },
                    set: { value in
                        guard (0...23).contains(value) else { return }
                        settings.morningSummaryHour = value
                        refreshNotifications()
                    }
                )) {
                    ForEach(0...23, id: \.self) { Text(String(format: "%02d", $0)).tag($0) }
                }
                Picker("Minute", selection: Binding(
                    get: { settings.morningSummaryMinute },
                    set: { value in
                        guard (0...59).contains(value) else { return }
                        settings.morningSummaryMinute = value
                        refreshNotifications()
                    }
                )) {
                    ForEach(0...59, id: \.self) { Text(String(format: "%02d", $0)).tag($0) }
                }
                Toggle("Show next timed item", isOn: Binding(
                    get: { settings.showNextItemOnLockScreen },
                    set: { value in
                        settings.showNextItemOnLockScreen = value
                        refreshNotifications()
                    }
                ))
            }
            if coordinator.deferredRoutineRequestCount > 0 {
                Text("\(coordinator.deferredRoutineRequestCount) later routine alerts will be filled during a future refresh.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let error = coordinator.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func refreshNotifications() {
        Task { await reschedule() }
    }
}
