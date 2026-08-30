import SwiftUI

struct NotificationSettingsView: View {
    let settings: AppSettingsStore
    let coordinator: NotificationCoordinator
    let profiles: [ProfileSnapshot]
    let reschedule: @MainActor @Sendable () async -> Void

    init(
        settings: AppSettingsStore,
        coordinator: NotificationCoordinator,
        profiles: [ProfileSnapshot] = [],
        reschedule: @escaping @MainActor @Sendable () async -> Void
    ) {
        self.settings = settings
        self.coordinator = coordinator
        self.profiles = profiles
        self.reschedule = reschedule
    }

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
            if settings.notificationsPausedForStaleInput
                || settings.lastSuccessfulNotificationRefresh != nil {
                VStack(alignment: .leading, spacing: 4) {
                    if settings.notificationsPausedForStaleInput {
                        Text("Notification scheduling is paused because current calendar data could not be refreshed. Check permissions and try again.")
                    }
                    if let refreshed = settings.lastSuccessfulNotificationRefresh {
                        Text("Last successful refresh: \(refreshed.formatted(date: .abbreviated, time: .shortened)).")
                    } else if settings.notificationsPausedForStaleInput {
                        Text("No successful notification refresh has been recorded.")
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("notification-schedule-status")
            }
            if let error = coordinator.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }

        if !profiles.isEmpty {
            Section("Class alerts") {
                ForEach(profiles) { profile in
                    Toggle(profile.name, isOn: enabledBinding(for: profile))
                        .accessibilityIdentifier("class-alert-\(profile.id.uuidString)")

                    if settings.classAlertPreference(for: profile.id).enabled {
                        Picker("\(profile.name) lead time", selection: leadTimeBinding(for: profile)) {
                            ForEach(ClassAlertPreference.allowedLeadMinutes.sorted(), id: \.self) { minutes in
                                Text("\(minutes) minutes before").tag(minutes)
                            }
                        }
                        .accessibilityIdentifier("class-alert-lead-\(profile.id.uuidString)")
                    }
                }
            }
        }
    }

    private func enabledBinding(for profile: ProfileSnapshot) -> Binding<Bool> {
        Binding(
            get: { settings.classAlertPreference(for: profile.id).enabled },
            set: { enabled in
                var preference = settings.classAlertPreference(for: profile.id)
                preference.enabled = enabled
                settings.setClassAlertPreference(preference, for: profile.id)
                refreshNotifications(failClosed: true)
            }
        )
    }

    private func leadTimeBinding(for profile: ProfileSnapshot) -> Binding<Int> {
        Binding(
            get: { settings.classAlertPreference(for: profile.id).leadMinutes },
            set: { leadMinutes in
                var preference = settings.classAlertPreference(for: profile.id)
                preference.leadMinutes = leadMinutes
                settings.setClassAlertPreference(preference, for: profile.id)
                refreshNotifications(failClosed: true)
            }
        )
    }

    private func refreshNotifications(failClosed: Bool = true) {
        Task {
            if failClosed {
                await coordinator.clear()
            }
            await reschedule()
        }
    }
}
