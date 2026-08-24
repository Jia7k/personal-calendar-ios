import SwiftUI

enum RootTab: Hashable { case calendar, today, tasks, routines }

struct RootTabView: View {
    let environment: AppEnvironment
    @State private var selection: RootTab = .calendar
    @State private var showingSettings = false
    @State private var lifecycle: RootLifecycleController
    @Environment(\.scenePhase) private var scenePhase
    init(environment: AppEnvironment) {
        self.environment = environment
        _lifecycle = State(initialValue: RootLifecycleController(permissions: environment.permissions))
    }
    var body: some View {
        Group {
            if environment.settings.didCompleteOnboarding {
                TabView(selection: $selection) {
                    CalendarHomeView(environment: environment, revision: lifecycle.revision, openSettings: { showingSettings = true }).tabItem { Label("Calendar", systemImage: "calendar") }.tag(RootTab.calendar)
                    TodayView(environment: environment, revision: lifecycle.revision, openSettings: { showingSettings = true }).tabItem { Label("Today", systemImage: "sun.max") }.tag(RootTab.today)
                    TasksView(environment: environment, revision: lifecycle.revision).tabItem { Label("Tasks", systemImage: "checklist") }.tag(RootTab.tasks)
                    RoutinesView(environment: environment).tabItem { Label("Routines", systemImage: "repeat") }.tag(RootTab.routines)
                }.sheet(isPresented: $showingSettings, onDismiss: { lifecycle.advanceRevision() }) { SettingsView(environment: environment, onContentChanged: { lifecycle.advanceRevision() }) }
            } else { PermissionOnboardingView(environment: environment) }
        }.tint(CalendarTheme.accent).onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await lifecycle.sceneBecameActive() }
        }
    }
}
