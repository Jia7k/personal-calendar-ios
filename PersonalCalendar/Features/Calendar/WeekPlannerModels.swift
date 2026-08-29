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

struct WeekPlannerTimedEventStack: Identifiable, Equatable, Sendable {
    let id: String
    let day: LocalDay
    let events: [WeekPlannerTimedItem]
    let start: Date
    let end: Date
}

struct WeekPlannerTimedCollisionStack: Identifiable, Equatable, Sendable {
    let id: String
    let day: LocalDay
    let items: [WeekPlannerTimedItem]
    let start: Date
    let end: Date
    let renderedStart: Date
    let renderedEnd: Date
}

struct WeekPlannerSnapshot: Equatable, Sendable {
    let calendar: Calendar
    let days: [LocalDay]
    let allDayItems: [WeekPlannerAllDayItem]
    let timedItems: [WeekPlannerTimedItem]
    let laterItems: [AgendaItem]
    let eventDetailsByOccurrence: [WeekPlannerEventOccurrenceKey: CalendarEventSnapshot]
    let startHour: Int
    let endHour: Int

    var collisionStacks: [WeekPlannerTimedCollisionStack] {
        days.flatMap { day in
            let values = timedItems
                .filter { $0.day == day }
                .sorted {
                    let leftStart = renderedStart(for: $0)
                    let rightStart = renderedStart(for: $1)
                    return (leftStart, $0.start, kindOrder($0.kind), $0.item.title, $0.id) <
                        (rightStart, $1.start, kindOrder($1.kind), $1.item.title, $1.id)
                }
            var result: [WeekPlannerTimedCollisionStack] = []
            var cluster: [WeekPlannerTimedItem] = []
            var clusterRenderedStart: Date?
            var clusterRenderedEnd: Date?

            func appendCluster() {
                let ordered = cluster.sorted(by: itemOrder)
                guard let first = ordered.first,
                      let renderedStart = clusterRenderedStart,
                      let renderedEnd = clusterRenderedEnd else { return }
                let end = ordered.map { $0.end ?? $0.start }.max() ?? first.start
                result.append(
                    WeekPlannerTimedCollisionStack(
                        id: ordered.map(\.id).joined(separator: "|"),
                        day: day,
                        items: ordered,
                        start: first.start,
                        end: end,
                        renderedStart: renderedStart,
                        renderedEnd: renderedEnd
                    )
                )
            }

            for value in values {
                let valueStart = renderedStart(for: value)
                let valueEnd = renderedEnd(for: value)
                if let activeClusterEnd = clusterRenderedEnd, valueStart >= activeClusterEnd {
                    appendCluster()
                    cluster = []
                    clusterRenderedStart = nil
                    clusterRenderedEnd = nil
                }
                cluster.append(value)
                clusterRenderedStart = min(clusterRenderedStart ?? valueStart, valueStart)
                clusterRenderedEnd = max(clusterRenderedEnd ?? valueEnd, valueEnd)
            }
            appendCluster()
            return result
        }
    }

    var eventStacks: [WeekPlannerTimedEventStack] {
        collisionStacks.compactMap { stack in
            let events = stack.items.filter { $0.kind == .event }
            guard let first = events.first else { return nil }
            return WeekPlannerTimedEventStack(
                id: events.map(\.id).joined(separator: "|"),
                day: stack.day,
                events: events,
                start: first.start,
                end: events.map { $0.end ?? $0.start }.max() ?? first.start
            )
        }
    }

    private func renderedStart(for item: WeekPlannerTimedItem) -> Date {
        guard item.kind == .taskDue else { return item.start }
        let centeredStart = item.start.addingTimeInterval(
            -WeekPlannerTimelineMetrics.minimumRenderedEventDuration / 2
        )
        let timelineStart = item.day.startDate(in: calendar).addingTimeInterval(
            TimeInterval(startHour * 60 * 60)
        )
        return max(centeredStart, timelineStart)
    }

    private func renderedEnd(for item: WeekPlannerTimedItem) -> Date {
        let minimumDuration = WeekPlannerTimelineMetrics.minimumRenderedEventDuration
        if item.kind == .taskDue {
            return renderedStart(for: item).addingTimeInterval(minimumDuration)
        }
        return max(item.end ?? item.start, item.start.addingTimeInterval(minimumDuration))
    }

    private func kindOrder(_ kind: WeekPlannerTimedKind) -> Int {
        switch kind {
        case .event: 0
        case .taskDue: 1
        }
    }

    private func itemOrder(_ left: WeekPlannerTimedItem, _ right: WeekPlannerTimedItem) -> Bool {
        (left.start, kindOrder(left.kind), left.item.title, left.id) <
            (right.start, kindOrder(right.kind), right.item.title, right.id)
    }

    static let empty = WeekPlannerSnapshot(
        calendar: .current,
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
    static let pointsPerHour: CGFloat = 52

    static var minimumRenderedEventDuration: TimeInterval {
        TimeInterval(minimumControlSize / pointsPerHour) * 60 * 60
    }

    static func dayWidth(
        availableWidth: CGFloat,
        timeGutterWidth: CGFloat,
        dayCount: Int,
        maximumOverlapCount _: Int
    ) -> CGFloat {
        max(1, (availableWidth - timeGutterWidth) / CGFloat(max(1, dayCount)))
    }

    static func eventWidth(dayWidth: CGFloat, overlapCount: Int) -> CGFloat {
        max(minimumControlSize, (dayWidth - 6) / CGFloat(max(1, overlapCount)))
    }

    static func taskWidth(dayWidth: CGFloat) -> CGFloat {
        max(minimumControlSize, dayWidth - 6)
    }

    static func stackedEventWidth(dayWidth: CGFloat) -> CGFloat {
        max(minimumControlSize, dayWidth - 2)
    }

    static func contentHeight(baseHeight: CGFloat) -> CGFloat {
        baseHeight + minimumControlSize
    }

    static func taskTopOffset(minuteOffset: CGFloat) -> CGFloat {
        max(0, minuteOffset - minimumControlSize / 2)
    }
}

struct WeekPlannerCompactCardPresentation: Equatable, Sendable {
    let showsTime: Bool
    let titleLineLimit: Int

    static func resolve(height: CGFloat, itemCount: Int) -> Self {
        Self(
            showsTime: itemCount == 1 && height >= 72,
            titleLineLimit: height >= 60 ? 2 : 1
        )
    }
}
