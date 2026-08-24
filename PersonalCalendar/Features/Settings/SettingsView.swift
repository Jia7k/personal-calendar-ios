import SwiftUI
import UIKit

struct SettingsView: View {
    let environment: AppEnvironment
    let openSystemSettings: @MainActor () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var loading = true
    @State private var pending: String?
    init(environment: AppEnvironment, openSystemSettings: @escaping @MainActor () -> Void = { UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!) }) { self.environment = environment; self.openSystemSettings = openSystemSettings }
    var body: some View {
        NavigationStack { List {
            Section("Permissions") {
                permission("Calendar", state: environment.permissions.calendarAccess, request: environment.permissions.requestCalendar)
                permission("Reminders", state: environment.permissions.remindersAccess, request: environment.permissions.requestReminders)
                permission("Notifications", state: environment.permissions.notificationAccess, request: environment.permissions.requestNotifications)
            }
            Section("Visible calendars") { ForEach(environment.calendar.calendars()) { value in Toggle(value.title, isOn: Binding(get: { environment.settings.visibleCalendarIDs(availableIDs: Set(environment.calendar.calendars().map(\.id))).contains(value.id) }, set: { _ in environment.settings.toggleCalendar(id: value.id, availableIDs: Set(environment.calendar.calendars().map(\.id))) })) } }
            Section("Visible reminder lists") { ForEach(environment.reminders.lists()) { value in Toggle(value.title, isOn: Binding(get: { environment.settings.visibleReminderListIDs(availableIDs: Set(environment.reminders.lists().map(\.id))).contains(value.id) }, set: { _ in environment.settings.toggleReminderList(id: value.id, availableIDs: Set(environment.reminders.lists().map(\.id))) })) } }
            defaults
        }.navigationTitle("Settings").toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.frame(minWidth: 44, minHeight: 44) } }.task { await environment.permissions.refresh(); loading = false } }
    }
    @ViewBuilder private var defaults: some View {
        let calendars = environment.calendar.calendars().filter(\.allowsContentModifications).sorted { $0.title == $1.title ? $0.id < $1.id : $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        let lists = environment.reminders.lists().filter(\.allowsContentModifications).sorted { $0.title == $1.title ? $0.id < $1.id : $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        Section("Defaults") {
            if calendars.isEmpty { Text("No writable calendar is available.").foregroundStyle(.secondary) } else { Picker("Calendar", selection: Binding(get: { calendars.contains { $0.id == environment.settings.defaultCalendarID } ? environment.settings.defaultCalendarID : nil }, set: { environment.settings.defaultCalendarID = $0 })) { Text("None").tag(String?.none); ForEach(calendars) { Text($0.title).tag(Optional($0.id)) } } }
            if lists.isEmpty { Text("No writable reminder list is available.").foregroundStyle(.secondary) } else { Picker("Reminder list", selection: Binding(get: { lists.contains { $0.id == environment.settings.defaultReminderListID } ? environment.settings.defaultReminderListID : nil }, set: { environment.settings.defaultReminderListID = $0 })) { Text("None").tag(String?.none); ForEach(lists) { Text($0.title).tag(Optional($0.id)) } } }
        }
    }
    @ViewBuilder private func permission(_ source: String, state: AccessState, request: @escaping @MainActor () async -> Void) -> some View {
        if environment.permissions.isRefreshing {
            PermissionCard(title: "Checking \(source) access", explanation: "Loading current permission status.", actionTitle: nil, action: nil)
        } else {
            switch state {
            case .granted: PermissionCard(title: "\(source) access is on", explanation: "This source is available.", actionTitle: nil, action: nil)
            case .restricted: PermissionCard(title: "\(source) access is restricted", explanation: "This access is controlled by your device or account.", actionTitle: nil, action: nil)
            case .denied: PermissionCard(title: "\(source) access is off", explanation: "Allow access in System Settings.", actionTitle: "Open System Settings", action: openSystemSettings)
            case .notDetermined: PermissionCard(title: "Allow \(source)", explanation: "You can choose this later.", actionTitle: "Allow", action: { pending = source; Task { await request(); pending = nil } }).disabled(loading || pending != nil)
            }
        }
    }
}
