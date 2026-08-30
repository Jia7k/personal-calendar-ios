import Foundation
import Observation

struct AppRouteEnvelope: Equatable, Sendable, Identifiable {
    let id: UUID
    let route: AppRoute
}

@MainActor
@Observable
final class AppRouteController {
    private static let maximumPendingRoutes = 16
    private var queue: [AppRouteEnvelope] = []

    var pending: AppRouteEnvelope? {
        queue.first
    }

    @discardableResult
    func submit(_ route: AppRoute) -> Bool {
        guard queue.count < Self.maximumPendingRoutes else { return false }
        queue.append(.init(id: UUID(), route: route))
        return true
    }

    func consume(id: UUID) {
        guard queue.first?.id == id else { return }
        queue.removeFirst()
    }
}

struct AppRoutePresentationState: Equatable, Hashable, Sendable {
    var root = false
    var calendar = false
    var today = false
    var tasks = false
    var routines = false

    var isIdle: Bool {
        !root && !calendar && !today && !tasks && !routines
    }
}
