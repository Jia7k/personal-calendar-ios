import Foundation

struct TimetableTimelineBuilder: Sendable {
    let calendar: Calendar

    func refreshDates(snapshot: TimetableSnapshotV1, now: Date) -> [Date] {
        let startOfToday = calendar.startOfDay(for: now)
        let nextMidnight = calendar.date(byAdding: .day, value: 1, to: startOfToday)
            ?? startOfToday.addingTimeInterval(86_400)
        let boundaries = snapshot.entries
            .flatMap { [$0.start, $0.end] }
            .filter { $0 > now }
        return Array(Set([now, nextMidnight] + boundaries)).sorted()
    }
}
