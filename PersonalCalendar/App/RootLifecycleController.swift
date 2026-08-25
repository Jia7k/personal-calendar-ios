import Foundation
import Observation

@MainActor
protocol PermissionRefreshing: AnyObject {
    func refresh() async
}

@MainActor
@Observable
final class RootLifecycleController {
    private(set) var revision = 0
    private let permissions: any PermissionRefreshing
    private let validateDefaults: @MainActor () -> Void
    private let refreshCoordinator: AppRefreshCoordinator?
    private var activationGeneration = 0

    init(
        permissions: any PermissionRefreshing,
        validateDefaults: @escaping @MainActor () -> Void = {},
        refreshCoordinator: AppRefreshCoordinator? = nil
    ) {
        self.permissions = permissions
        self.validateDefaults = validateDefaults
        self.refreshCoordinator = refreshCoordinator
    }

    func advanceRevision() { revision &+= 1 }

    func sceneBecameActive() async {
        activationGeneration &+= 1
        let generation = activationGeneration
        if let refreshCoordinator {
            await refreshCoordinator.refreshNow(reason: .foreground)
        } else {
            await permissions.refresh()
        }
        guard generation == activationGeneration else { return }
        if refreshCoordinator == nil {
            validateDefaults()
            advanceRevision()
        }
    }
}
