import Foundation

struct DailyActivityPresentation: Equatable, Sendable {
    let hero: DailyActivityItem?
    let rows: [DailyActivityItem]
    /// Nil means omission metadata cannot truthfully describe the remaining count.
    let hiddenCount: Int?
    let requiresRefresh: Bool
    let countdownBoundary: Date?
    let remainingCount: Int

    static func make(snapshot: DailyActivitySnapshot, now: Date, rowLimit: Int) -> Self {
        guard snapshot.hasValidDay, now.timeIntervalSinceReferenceDate.isFinite,
              now >= snapshot.dayStart, now < snapshot.dayEnd else {
            return Self(hero: nil, rows: [], hiddenCount: nil, requiresRefresh: true,
                        countdownBoundary: nil, remainingCount: 0)
        }
        var seen = Set<String>()
        let eligible = snapshot.items.filter { $0.isEligible(in: snapshot, at: now) }
            .sorted(by: itemOrder)
            .filter { seen.insert($0.id).inserted }
        let active = eligible.filter { isActive($0, at: now) }
        let upcoming = eligible.filter { !$0.isAllDay && $0.start > now }
        let hero = active.first ?? upcoming.first
        let agenda = eligible.filter { $0.id != hero?.id }.sorted { left, right in
            let leftRank = rank(left, at: now)
            let rightRank = rank(right, at: now)
            return leftRank == rightRank ? itemOrder(left, right) : leftRank < rightRank
        }
        let rows = Array(agenda.prefix(max(0, rowLimit)))
        let boundary = hero.flatMap { isActive($0, at: now) ? $0.end : $0.start }
        return Self(hero: hero, rows: rows, hiddenCount: agenda.count - rows.count,
                    requiresRefresh: eligible.isEmpty && (snapshot.calendarUnavailable || snapshot.tasksUnavailable),
                    countdownBoundary: boundary.flatMap { $0 > now ? $0 : nil },
                    remainingCount: eligible.count)
    }

    static func isActive(_ item: DailyActivityItem, at now: Date) -> Bool {
        item.kind == .event && !item.isAllDay && item.start <= now && (item.end ?? now) > now
    }

    static func itemOrder(_ left: DailyActivityItem, _ right: DailyActivityItem) -> Bool {
        if left.start != right.start { return left.start < right.start }
        let leftEnd = left.end ?? left.start
        let rightEnd = right.end ?? right.start
        if leftEnd != rightEnd { return leftEnd < rightEnd }
        if left.title != right.title { return left.title < right.title }
        if left.id != right.id { return left.id < right.id }
        // Deterministic deduplication even if a provider repeats an inconsistent row.
        if left.location != right.location { return (left.location ?? "") < (right.location ?? "") }
        if left.isAllDay != right.isAllDay { return !left.isAllDay }
        if left.hasAlert != right.hasAlert { return left.hasAlert }
        return left.shortTitle < right.shortTitle
    }

    private static func rank(_ item: DailyActivityItem, at now: Date) -> Int {
        if isActive(item, at: now) { return 0 }
        if item.isAllDay { return 3 }
        if item.kind == .task && item.start <= now { return 1 }
        return 2
    }
}
