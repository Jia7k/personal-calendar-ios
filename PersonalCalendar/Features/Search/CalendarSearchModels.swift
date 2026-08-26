import Foundation

enum CalendarSearchGroup: Int, CaseIterable, Equatable, Sendable {
    case upcoming
    case pastAndCompleted
    case routines
}

enum CalendarSearchSource: String, Equatable, Sendable {
    case event
    case task
    case routine
}

struct CalendarSearchResult: Identifiable, Equatable, Sendable {
    let id: String
    let group: CalendarSearchGroup
    let source: CalendarSearchSource
    let title: String
    let subtitle: String
    let date: Date?
    let origin: AgendaItemOrigin
    let searchableText: String
}

struct CalendarSearchSections: Equatable, Sendable {
    let upcoming: [CalendarSearchResult]
    let pastAndCompleted: [CalendarSearchResult]
    let routines: [CalendarSearchResult]

    static let empty = CalendarSearchSections(upcoming: [], pastAndCompleted: [], routines: [])
}
