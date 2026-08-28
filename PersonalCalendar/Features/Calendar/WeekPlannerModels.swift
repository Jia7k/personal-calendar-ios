import Foundation

enum WeekPlannerTimedKind: Equatable, Sendable {
    case event
    case taskDue
}

struct WeekPlannerEventOccurrenceKey: Hashable, Sendable {
    let displayID: String
    let start: Date
    let occurrenceDate: Date

    init(displayID: String, start: Date, occurrenceDate: Date? = nil) {
        self.displayID = displayID
        self.start = start
        self.occurrenceDate = occurrenceDate ?? start
    }

    init?(item: AgendaItem) {
        guard case let .event(displayID) = item.origin,
              case let .timed(start) = item.placement else {
            return nil
        }
        self.init(
            displayID: displayID,
            start: start,
            occurrenceDate: item.eventOccurrenceDate
        )
    }
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
    let eventDetailsByOccurrence: [WeekPlannerEventOccurrenceKey: CalendarEventSnapshot]
    let startHour: Int
    let endHour: Int

    static let empty = WeekPlannerSnapshot(
        days: [],
        allDayItems: [],
        timedItems: [],
        laterItems: [],
        eventDetailsByOccurrence: [:],
        startHour: 8,
        endHour: 18
    )
}

struct WeekPlannerTimelineMetrics {
    static let minimumControlSize: CGFloat = 44

    static func dayWidth(
        availableWidth: CGFloat,
        timeGutterWidth: CGFloat,
        dayCount: Int,
        maximumOverlapCount: Int
    ) -> CGFloat {
        let visibleWidth = max(1, (availableWidth - timeGutterWidth) / CGFloat(max(1, dayCount)))
        let controlWidth = 6 + minimumControlSize * CGFloat(max(1, maximumOverlapCount))
        return max(visibleWidth, controlWidth)
    }

    static func eventWidth(dayWidth: CGFloat, overlapCount: Int) -> CGFloat {
        max(minimumControlSize, (dayWidth - 6) / CGFloat(max(1, overlapCount)))
    }

    static func taskWidth(dayWidth: CGFloat) -> CGFloat {
        max(minimumControlSize, dayWidth - 6)
    }
}
