import Foundation

enum RefreshReason: Equatable {
    case launch
    case foreground
    case eventStoreChanged
    case localMutation
}

@MainActor
struct RefreshActions {
    let refreshPermissions: @MainActor () async -> Void
    let migrateProfiles: @MainActor () async -> Void
    let refreshSources: @MainActor () async -> Void
    let reloadProfiles: @MainActor () async -> Void
    let refreshAgenda: @MainActor () async -> Void
    let cleanCategoryLinks: @MainActor () async -> Void
    let refreshTimetable: @MainActor () async -> Void
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
        await actions.migrateProfiles()
        await actions.refreshSources()
        await actions.reloadProfiles()
        await actions.refreshAgenda()
        await actions.cleanCategoryLinks()
        await actions.refreshTimetable()
        await actions.rescheduleNotifications()
    }
}

@MainActor
final class AgendaRefreshRegistry {
    private var refreshers: [UUID: @MainActor () async -> Void] = [:]

    func register(id: UUID, refresh: @escaping @MainActor () async -> Void) {
        refreshers[id] = refresh
    }

    func unregister(id: UUID) {
        refreshers[id] = nil
    }

    func refreshAll() async {
        let currentRefreshers = Array(refreshers.values)
        for refresh in currentRefreshers {
            await refresh()
        }
    }
}
