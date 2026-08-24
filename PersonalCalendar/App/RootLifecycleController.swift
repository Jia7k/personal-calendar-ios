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
    private var activationGeneration = 0

    init(permissions: any PermissionRefreshing, validateDefaults: @escaping @MainActor () -> Void = {}) {
        self.permissions = permissions
        self.validateDefaults = validateDefaults
    }

    func advanceRevision() { revision &+= 1 }

    func sceneBecameActive() async {
        activationGeneration &+= 1
        let generation = activationGeneration
        await permissions.refresh()
        guard generation == activationGeneration else { return }
        validateDefaults()
        advanceRevision()
    }
}
