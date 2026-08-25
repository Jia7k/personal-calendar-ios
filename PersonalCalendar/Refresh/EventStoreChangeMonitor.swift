import EventKit
import Foundation

@MainActor
protocol EventStoreChangeMonitoring: AnyObject {
    var onChange: (() -> Void)? { get set }
    func start()
    func stop()
}

@MainActor
final class EventStoreChangeMonitor: EventStoreChangeMonitoring {
    var onChange: (() -> Void)?

    private let store: EKEventStore
    private let center: NotificationCenter
    private var token: NSObjectProtocol?

    init(store: EKEventStore, center: NotificationCenter = .default) {
        self.store = store
        self.center = center
    }

    func start() {
        guard token == nil else { return }
        token = center.addObserver(
            forName: .EKEventStoreChanged,
            object: store,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.onChange?()
            }
        }
    }

    func stop() {
        if let token {
            center.removeObserver(token)
        }
        token = nil
    }

}

@MainActor
final class EventStoreRefreshRuntime {
    private let coordinator: AppRefreshCoordinator
    private let monitor: (any EventStoreChangeMonitoring)?

    init(coordinator: AppRefreshCoordinator, monitor: (any EventStoreChangeMonitoring)?) {
        self.coordinator = coordinator
        self.monitor = monitor
    }

    func start() {
        monitor?.onChange = { [weak coordinator] in
            coordinator?.eventStoreDidChange()
        }
        monitor?.start()
    }

    func stop() {
        monitor?.stop()
    }

}
