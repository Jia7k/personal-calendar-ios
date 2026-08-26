import Foundation
import Observation

struct AppContentRevision: Hashable {
    let lifecycle: Int
    let profileScope: Int
}

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
    private let reconcileForegroundLiveActivity: @MainActor () async -> Void
    private var activationGeneration = 0

    init(
        permissions: any PermissionRefreshing,
        validateDefaults: @escaping @MainActor () -> Void = {},
        refreshCoordinator: AppRefreshCoordinator? = nil,
        reconcileForegroundLiveActivity: @escaping @MainActor () async -> Void = {}
    ) {
        self.permissions = permissions
        self.validateDefaults = validateDefaults
        self.refreshCoordinator = refreshCoordinator
        self.reconcileForegroundLiveActivity = reconcileForegroundLiveActivity
    }

    func advanceRevision() { revision &+= 1 }

    func sceneBecameActive() async {
        await refresh(reason: .foreground)
    }

    func appLaunched() async {
        await refresh(reason: .launch)
    }

    private func refresh(reason: RefreshReason) async {
        activationGeneration &+= 1
        let generation = activationGeneration
        if let refreshCoordinator {
            await refreshCoordinator.refreshNow(reason: reason)
        } else {
            await permissions.refresh()
        }
        guard generation == activationGeneration else { return }
        await reconcileForegroundLiveActivity()
        guard generation == activationGeneration else { return }
        if refreshCoordinator == nil {
            validateDefaults()
            advanceRevision()
        }
    }
}
