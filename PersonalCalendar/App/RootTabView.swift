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
            NavigationStack { Text("Today") }
                .tabItem { Label("Today", systemImage: "sun.max") }
                .tag(RootTab.today)
            NavigationStack { Text("Tasks") }
                .tabItem { Label("Tasks", systemImage: "checklist") }
                .tag(RootTab.tasks)
            NavigationStack { Text("Routines") }
                .tabItem { Label("Routines", systemImage: "repeat") }
                .tag(RootTab.routines)
        }
        .tint(CalendarTheme.accent)
    }
}
