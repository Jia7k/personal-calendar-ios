import Foundation

enum OpeningScreenPreference: String, CaseIterable, Identifiable, Sendable {
    case calendar, today, tasks, routines, lastUsed

    var id: Self { self }

    var title: String {
        switch self {
        case .calendar: "Calendar"
        case .today: "Today"
        case .tasks: "Tasks"
        case .routines: "Routines"
        case .lastUsed: "Last Used"
        }
    }

    func initialTab(lastUsed: RootTab) -> RootTab {
        switch self {
        case .calendar: .calendar
        case .today: .today
        case .tasks: .tasks
        case .routines: .routines
        case .lastUsed: lastUsed
        }
    }
}
