import SwiftUI
import UIKit

struct TodayView: View {
    @State private var model: TodayViewModel
    private let openSettings: @MainActor () -> Void

    init(environment: AppEnvironment, openSettings: @escaping @MainActor () -> Void = TodayView.defaultOpenSettings) {
        _model = State(initialValue: TodayViewModel(calendar: environment.calendar, reminders: environment.reminders, routines: environment.routines, composer: environment.agendaComposer, settings: environment.settings))
        self.openSettings = openSettings
    }

    var body: some View {
        NavigationStack {
            List {
                if model.showsCalendarPermissionCard { permissionCard(title: "Calendar events are unavailable", restricted: model.calendarAccessState == .restricted) }
                if model.showsRemindersPermissionCard { permissionCard(title: "Tasks are unavailable", restricted: model.remindersAccessState == .restricted) }
                errorRow(model.calendarError); errorRow(model.remindersError); errorRow(model.routinesError)
                section("All Day", items: model.agenda.allDay)
                section("Schedule", items: model.agenda.scheduled)
                section("Priority", items: model.agenda.priority)
                if model.isGenuinelyEmpty {
                    ContentUnavailableView("Nothing planned today", systemImage: "sun.max", description: Text("New events, tasks, and routines will appear here."))
                }
            }
            .overlay { if model.isLoading && !model.hasLoaded { ProgressView() } }
            .navigationTitle("Today")
            .task { await model.load() }
            .refreshable { await model.load() }
        }
    }

    @ViewBuilder private func section(_ title: LocalizedStringKey, items: [AgendaItem]) -> some View {
        if !items.isEmpty { Section(title) { ForEach(items) { item in AgendaRow(item: item, isMutating: model.mutatingItemIDs.contains(item.id)) { state in
            Task { if item.source == .task { await model.setTaskCompleted(item, completed: state) } else { await model.setRoutineCompleted(item, completed: state) } }
        } } } }
    }
    @ViewBuilder private func errorRow(_ message: String?) -> some View {
        if let message { Section { HStack { Image(systemName: "exclamationmark.triangle"); Text(message); Spacer(); Button("Retry") { Task { await model.load() } }.frame(minHeight: CalendarTheme.minimumTapSize) }.accessibilityElement(children: .combine) } }
    }
    private func permissionCard(title: String, restricted: Bool) -> some View {
        Section { VStack(alignment: .leading, spacing: 8) { Label(title, systemImage: "lock") ; Text(restricted ? "This access is controlled by your device or account." : "Allow access in System Settings to include this source.").font(.footnote).foregroundStyle(.secondary); if !restricted { Button("Open System Settings", action: openSettings).frame(minHeight: CalendarTheme.minimumTapSize) } } }
    }
    @MainActor private static func defaultOpenSettings() { UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!) }
}
