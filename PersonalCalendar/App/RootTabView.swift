import SwiftUI

enum RootTab: Hashable {
    case calendar, today, tasks, routines
}

struct RootTabView: View {
    let environment: AppEnvironment
    @State private var selection: RootTab = .calendar

    var body: some View {
        TabView(selection: $selection) {
            CalendarHomeView(environment: environment)
                .tabItem { Label("Calendar", systemImage: "calendar") }
                .tag(RootTab.calendar)
            TodayView(environment: environment)
                .tabItem { Label("Today", systemImage: "sun.max") }
                .tag(RootTab.today)
            TasksView(environment: environment)
                .tabItem { Label("Tasks", systemImage: "checklist") }
                .tag(RootTab.tasks)
            RoutinesView(environment: environment)
                .tabItem { Label("Routines", systemImage: "repeat") }
                .tag(RootTab.routines)
        }
        .tint(CalendarTheme.accent)
    }
}
