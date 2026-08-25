import Foundation

@MainActor
protocol RefreshDebouncing: AnyObject {
    func schedule(_ operation: @escaping @MainActor () async -> Void)
}

@MainActor
final class TaskRefreshDebouncer: RefreshDebouncing {
    private var task: Task<Void, Never>?

    func schedule(_ operation: @escaping @MainActor () async -> Void) {
        task?.cancel()
        task = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await operation()
        }
    }
}
