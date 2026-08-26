import Foundation

enum WeekPlannerTimedKind: Equatable, Sendable {
    case event
    case taskDue
}

struct WeekPlannerAllDayItem: Identifiable, Equatable, Sendable {
    let id: String
    let day: LocalDay
    let item: AgendaItem
}

struct WeekPlannerTimedItem: Identifiable, Equatable, Sendable {
    let id: String
    let day: LocalDay
    let item: AgendaItem
    let kind: WeekPlannerTimedKind
    let start: Date
    let end: Date?
    let overlapColumn: Int
    let overlapColumnCount: Int
}

struct WeekPlannerSnapshot: Equatable, Sendable {
    let days: [LocalDay]
    let allDayItems: [WeekPlannerAllDayItem]
    let timedItems: [WeekPlannerTimedItem]
    let laterItems: [AgendaItem]
    let startHour: Int
    let endHour: Int

    static let empty = WeekPlannerSnapshot(
        days: [],
        allDayItems: [],
        timedItems: [],
        laterItems: [],
        startHour: 8,
        endHour: 18
    )
}
