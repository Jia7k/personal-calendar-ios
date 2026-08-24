import SwiftUI

enum RootTab: Hashable { case calendar, today, tasks, routines }

struct RootTabView: View {
    let environment: AppEnvironment
    @State private var selection: RootTab = .calendar
    @State private var showingSettings = false
    @State private var revision = 0
    var body: some View {
        Group {
            if environment.settings.didCompleteOnboarding {
                TabView(selection: $selection) {
                    CalendarHomeView(environment: environment, openSettings: { showingSettings = true }).id("calendar-\(revision)").tabItem { Label("Calendar", systemImage: "calendar") }.tag(RootTab.calendar)
                    TodayView(environment: environment).id("today-\(revision)").tabItem { Label("Today", systemImage: "sun.max") }.tag(RootTab.today)
                    TasksView(environment: environment).tabItem { Label("Tasks", systemImage: "checklist") }.tag(RootTab.tasks)
                    RoutinesView(environment: environment).tabItem { Label("Routines", systemImage: "repeat") }.tag(RootTab.routines)
                }.sheet(isPresented: $showingSettings, onDismiss: { revision += 1 }) { SettingsView(environment: environment) }
            } else { PermissionOnboardingView(environment: environment) }
        }.tint(CalendarTheme.accent)
    }
}
