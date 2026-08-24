import SwiftUI
import SwiftData

@main
struct PersonalCalendarApp: App {
    private let environment = AppEnvironment.bootstrap

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .modelContainer(environment.modelContainer)
        }
    }
}
