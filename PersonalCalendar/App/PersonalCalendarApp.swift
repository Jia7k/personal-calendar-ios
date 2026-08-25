import SwiftData
import SwiftUI

@main
struct PersonalCalendarApp: App {
    private let container: ModelContainer
    private let environment: AppEnvironment

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        let isUITesting = arguments.contains("-ui-testing")
        container = Self.makeModelContainer(isStoredInMemoryOnly: isUITesting)
        environment = isUITesting
            ? .demo(container: container, arguments: arguments)
            : .live(container: container)
        environment.startRefreshMonitoring()
    }

    var body: some Scene {
        WindowGroup {
            RootTabView(environment: environment)
                .modelContainer(container)
        }
    }

    private static func makeModelContainer(isStoredInMemoryOnly: Bool) -> ModelContainer {
        let configuration = ModelConfiguration(
            isStoredInMemoryOnly: isStoredInMemoryOnly,
            cloudKitDatabase: .none
        )
        do {
            return try ModelContainer(
                for: RoutineRecord.self,
                RoutineCompletionRecord.self,
                CategoryRecord.self,
                ExternalCategoryLinkRecord.self,
                ProfileRecord.self,
                configurations: configuration
            )
        } catch {
            fatalError("Unable to initialize local routine storage: \(error)")
        }
    }
}
