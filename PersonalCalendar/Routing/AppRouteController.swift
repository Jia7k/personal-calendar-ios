import Foundation
import Observation

struct AppRouteEnvelope: Equatable, Sendable, Identifiable {
    let id: UUID
    let route: AppRoute
}

@MainActor
@Observable
final class AppRouteController {
    private(set) var pending: AppRouteEnvelope?

    func submit(_ route: AppRoute) {
        pending = .init(id: UUID(), route: route)
    }

    func consume(id: UUID) {
        guard pending?.id == id else { return }
        pending = nil
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
