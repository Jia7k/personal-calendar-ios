import Foundation

enum AgendaSource: String, Equatable, Sendable {
    case event, task, routine
}

enum AgendaPlacement: Equatable, Sendable {
    case allDay, timed(Date), window(RoutineWindow), unscheduled
}

struct AgendaItem: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let source: AgendaSource
    let placement: AgendaPlacement
    let sortDate: Date?
    let priority: Int
    let isCompleted: Bool
    let allowsModification: Bool
}
