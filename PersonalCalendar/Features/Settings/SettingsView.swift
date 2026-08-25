import SwiftUI
import UIKit

enum SettingsDefaultPickerValue {
    static func calendar(selectedID: String?, writableCalendars: [CalendarDescriptor]) -> String {
        guard !writableCalendars.isEmpty else { return "No writable calendar available" }
        guard let selectedID else { return "None" }
        return writableCalendars.first(where: { $0.id == selectedID })?.title ?? "Unavailable calendar"
    }

    static func reminderList(selectedID: String?, writableLists: [ReminderListDescriptor]) -> String {
        guard !writableLists.isEmpty else { return "No writable reminder list available" }
        guard let selectedID else { return "None" }
        return writableLists.first(where: { $0.id == selectedID })?.title ?? "Unavailable reminder list"
    }
}

struct SettingsView: View {
    let environment: AppEnvironment
    let openSystemSettings: @MainActor () -> Void
    let onContentChanged: @MainActor () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var loading = true
    init(environment: AppEnvironment, onContentChanged: @escaping @MainActor () -> Void = {}, openSystemSettings: @escaping @MainActor () -> Void = { UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!) }) { self.environment = environment; self.onContentChanged = onContentChanged; self.openSystemSettings = openSystemSettings }
    var body: some View {
        NavigationStack { List {
            Section("Permissions") {
                permission("Calendar", state: environment.permissions.calendarAccess, request: environment.permissions.requestCalendar)
                permission("Reminders", state: environment.permissions.remindersAccess, request: environment.permissions.requestReminders)
                permission("Notifications", state: environment.permissions.notificationAccess, request: environment.permissions.requestNotifications)
            }
            Section("Visible calendars") { ForEach(environment.calendar.calendars()) { value in Toggle(value.title, isOn: Binding(get: { environment.settings.visibleCalendarIDs(availableIDs: Set(environment.calendar.calendars().map(\.id))).contains(value.id) }, set: { _ in environment.settings.toggleCalendar(id: value.id, availableIDs: Set(environment.calendar.calendars().map(\.id))); onContentChanged() })) } }
            Section("Visible reminder lists") { ForEach(environment.reminders.lists()) { value in Toggle(value.title, isOn: Binding(get: { environment.settings.visibleReminderListIDs(availableIDs: Set(environment.reminders.lists().map(\.id))).contains(value.id) }, set: { _ in environment.settings.toggleReminderList(id: value.id, availableIDs: Set(environment.reminders.lists().map(\.id))); onContentChanged() })) } }
            defaults
            Section("Organization") {
                NavigationLink("Categories") {
                    CategorySettingsView(
                        repository: environment.categories,
                        onContentChanged: onContentChanged
                    )
                }
                .accessibilityIdentifier("settings-categories")
            }
        }.navigationTitle("Settings").toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.frame(minWidth: 44, minHeight: 44) } }.task { await environment.permissions.refresh(); environment.settings.validateDefaults(calendarAccess: environment.calendar.accessState, calendars: environment.calendar.calendars(), remindersAccess: environment.reminders.accessState, lists: environment.reminders.lists()); loading = false } }
    }
    @ViewBuilder private var defaults: some View {
        let calendars = SourceDescriptorOrdering.calendars(environment.calendar.calendars().filter(\.allowsContentModifications))
        let lists = SourceDescriptorOrdering.reminderLists(environment.reminders.lists().filter(\.allowsContentModifications))
        Section("Defaults") {
            Picker("Calendar", selection: Binding(get: { calendars.contains { $0.id == environment.settings.defaultCalendarID } ? environment.settings.defaultCalendarID : nil }, set: { environment.settings.setDefaultCalendarID($0, descriptors: environment.calendar.calendars(), access: environment.calendar.accessState) })) { Text("None").tag(String?.none); ForEach(calendars) { Text($0.title).tag(Optional($0.id)) } }
                .disabled(calendars.isEmpty)
                .accessibilityValue(SettingsDefaultPickerValue.calendar(selectedID: environment.settings.defaultCalendarID, writableCalendars: calendars))
            if calendars.isEmpty { Text("No writable calendar is available, so new events cannot be saved here.").foregroundStyle(.secondary) }
            Picker("Reminder list", selection: Binding(get: { lists.contains { $0.id == environment.settings.defaultReminderListID } ? environment.settings.defaultReminderListID : nil }, set: { environment.settings.setDefaultReminderListID($0, descriptors: environment.reminders.lists(), access: environment.reminders.accessState) })) { Text("None").tag(String?.none); ForEach(lists) { Text($0.title).tag(Optional($0.id)) } }
                .disabled(lists.isEmpty)
                .accessibilityValue(SettingsDefaultPickerValue.reminderList(selectedID: environment.settings.defaultReminderListID, writableLists: lists))
            if lists.isEmpty { Text("No writable reminder list is available, so new tasks cannot be saved here.").foregroundStyle(.secondary) }
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
            case .notDetermined: PermissionCard(title: "Allow \(source)", explanation: "You can choose this later.", actionTitle: "Allow", action: { Task { await request(); onContentChanged() } }).disabled(loading || environment.permissions.isPending(source.lowercased()))
            }
        }
    }
}
