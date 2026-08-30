import AppIntents
import SwiftData
import SwiftUI

@main
struct PersonalCalendarApp: App {
    @UIApplicationDelegateAdaptor(AppNotificationDelegate.self) private var notificationDelegate

    private let container: ModelContainer
    private let environment: AppEnvironment
    private let routeController: AppRouteController
    private let quickEntryHandoffStore: AppRouteHandoffStore?
    private let quickEntryHandoffMonitor: AppRouteHandoffMonitor

    init() {
        quickEntryHandoffMonitor = AppRouteHandoffMonitor()
        routeController = AppRouteController()
        let arguments = ProcessInfo.processInfo.arguments
        let isUITesting = arguments.contains("-ui-testing")
        let handoffStore = try? AppRouteHandoffStore.appGroup()
        quickEntryHandoffStore = handoffStore
        if isUITesting, let handoffStore {
            while (try? handoffStore.consume()) != nil {}
            if arguments.contains("-demo-shortcut-quick-entry") {
                try? handoffStore.write(.quickEntry(
                    text: "Shortcut study session today at 3pm",
                    profile: .saved(SeedProfile.schoolID)
                ))
            } else if arguments.contains("-demo-queued-shortcut-quick-entry") {
                try? handoffStore.write(.quickEntry(
                    text: "First queued class review today at 3pm",
                    profile: .saved(SeedProfile.schoolID)
                ))
                try? handoffStore.write(.quickEntry(
                    text: "Second queued errand tomorrow at 4pm",
                    profile: .saved(SeedProfile.personalID)
                ))
            }
        }
        container = Self.makeModelContainer(isStoredInMemoryOnly: isUITesting)
        environment = isUITesting
            ? .demo(container: container, arguments: arguments)
            : .live(container: container)
        environment.notificationRenewalScheduler.register()
        notificationDelegate.configure(
            routeController: routeController,
            actionHandler: environment.notificationActionHandler
        )
        PersonalCalendarShortcuts.updateAppShortcutParameters()
        environment.startRefreshMonitoring()
    }

    var body: some Scene {
        WindowGroup {
            RootTabView(
                environment: environment,
                routeController: routeController,
                quickEntryHandoffStore: quickEntryHandoffStore,
                quickEntryHandoffMonitor: quickEntryHandoffMonitor
            )
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
