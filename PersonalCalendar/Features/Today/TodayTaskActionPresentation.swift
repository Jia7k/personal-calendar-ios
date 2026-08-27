import Foundation

enum TodayTaskActionPresentationGate {
    enum Decision: Equatable {
        case busy
        case unavailable
        case ready
    }

    static func decide(
        editorIsPresented: Bool,
        actionIsPresented: Bool,
        resolveAvailability: () -> Bool
    ) -> Decision {
        guard !editorIsPresented, !actionIsPresented else { return .busy }
        return resolveAvailability() ? .ready : .unavailable
    }
}

struct TodayTaskPickDate: Identifiable {
    let id = UUID()
    let reminderID: String
}

enum TodayTaskActionPresentation: Identifiable {
    case pickDate(TodayTaskPickDate)
    case timeBlock(TaskTimeBlockSession)

    var id: UUID {
        switch self {
        case let .pickDate(request): request.id
        case let .timeBlock(session): session.id
        }
    }
}
