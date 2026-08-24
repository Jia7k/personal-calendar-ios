import EventKit
import SwiftData

@MainActor
struct AppEnvironment {
    let calendar: any CalendarServicing
    let reminders: any RemindersServicing
    let notifications: any NotificationAuthorizing
    let permissionCoordinator: PermissionCoordinator
    let modelContainer: ModelContainer
    let routineRepository: any RoutineRepository

    static let bootstrap = AppEnvironment()

    init() {
        let store = EKEventStore()
        let modelContainer = Self.makeModelContainer()
        self.init(
            calendar: EventKitCalendarService(store: store),
            reminders: EventKitRemindersService(store: store),
            notifications: SystemNotificationAuthorizer(),
            modelContainer: modelContainer
        )
    }

    init(
        calendar: any CalendarServicing,
        reminders: any RemindersServicing,
        notifications: any NotificationAuthorizing,
        modelContainer: ModelContainer? = nil
    ) {
        self.calendar = calendar
        self.reminders = reminders
        self.notifications = notifications
        let modelContainer = modelContainer ?? Self.makeModelContainer()
        self.modelContainer = modelContainer
        routineRepository = SwiftDataRoutineRepository(context: modelContainer.mainContext)
        permissionCoordinator = PermissionCoordinator(
            calendar: calendar,
            reminders: reminders,
            notifications: notifications
        )
    }

    private static func makeModelContainer() -> ModelContainer {
        do {
            return try ModelContainer(for: RoutineRecord.self, RoutineCompletionRecord.self)
        } catch {
            fatalError("Unable to initialize local routine storage: \(error)")
        }
    }
}
