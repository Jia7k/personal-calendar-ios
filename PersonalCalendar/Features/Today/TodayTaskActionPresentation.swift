import Foundation

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
