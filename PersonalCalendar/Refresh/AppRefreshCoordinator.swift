import Observation

enum RefreshReason: Equatable {
    case launch
    case foreground
    case eventStoreChanged
    case localMutation
}

@MainActor
struct RefreshActions {
    let refreshPermissions: @MainActor () async -> Void
    let refreshSources: @MainActor () async -> Void
    let refreshAgenda: @MainActor () async -> Void
    let cleanCategoryLinks: @MainActor () async -> Void
    let rescheduleNotifications: @MainActor () async -> Void
}

@MainActor
final class AppRefreshCoordinator {
    private let debouncer: any RefreshDebouncing
    private let actions: RefreshActions

    init(debouncer: any RefreshDebouncing = TaskRefreshDebouncer(), actions: RefreshActions) {
        self.debouncer = debouncer
        self.actions = actions
    }

    func eventStoreDidChange() {
        debouncer.schedule { [weak self] in
            await self?.refreshNow(reason: .eventStoreChanged)
        }
    }

    func refreshNow(reason: RefreshReason) async {
        await actions.refreshPermissions()
        await actions.refreshSources()
        await actions.refreshAgenda()
        await actions.cleanCategoryLinks()
        await actions.rescheduleNotifications()
    }
}

@MainActor
@Observable
final class AgendaRefreshPublisher {
    private(set) var revision = 0

    func publish() {
        revision &+= 1
    }
}
