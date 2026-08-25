import SwiftUI

struct TimeRailsView: View {
    let snapshot: TimetableSnapshotV1
    let now: Date
    let showsStatusStrip: Bool

    private let weekdayLabels = ["M", "T", "W", "T", "F"]

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text("SCHOOL WEEK").font(.caption2.weight(.bold))
                Spacer()
                Text(snapshot.weekStart, format: .dateTime.month(.abbreviated).day())
                    .font(.caption2)
            }
            HStack(spacing: 4) {
                ForEach(0..<5, id: \.self) { index in
                    dayRail(index: index)
                }
            }
            if showsStatusStrip {
                statusStrip
            }
        }
        .foregroundStyle(.white)
    }

    private func dayRail(index: Int) -> some View {
        VStack(spacing: 2) {
            Text(weekdayLabels[index]).font(.caption2.weight(.semibold))
            GeometryReader { proxy in
                ZStack(alignment: .top) {
                    RoundedRectangle(cornerRadius: 5).fill(.white.opacity(0.08))
                    ForEach(entries(for: index)) { entry in
                        let geometry = railGeometry(for: entry, height: proxy.size.height)
                        Text(entry.shortTitle)
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity, minHeight: max(geometry.height, 10), alignment: .top)
                            .padding(.top, 2)
                            .background(Color.teal.opacity(isCurrent(entry) ? 0.95 : 0.55))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .offset(y: geometry.offset)
                    }
                }
            }
        }
    }

    private var statusStrip: some View {
        Group {
            switch snapshot.moment(at: now, calendar: localCalendar) {
            case .none:
                Text("No more classes today")
            case let .current(entry):
                Text("NOW  \(entry.shortTitle) · until \(entry.end.formatted(date: .omitted, time: .shortened))")
            case let .next(entry), let .gap(entry):
                Text("NEXT  \(entry.shortTitle) · \(entry.start.formatted(date: .omitted, time: .shortened))")
            }
        }
        .font(.caption2.weight(.semibold))
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func entries(for index: Int) -> [TimetableEntry] {
        snapshot.entries.filter { entry in
            let weekday = localCalendar.component(.weekday, from: entry.start)
            return (weekday + 5) % 7 == index
        }
    }

    private func railGeometry(for entry: TimetableEntry, height: CGFloat) -> (offset: CGFloat, height: CGFloat) {
        let dayStart = localCalendar.startOfDay(for: entry.start)
        let railStart = localCalendar.date(bySettingHour: 9, minute: 0, second: 0, of: dayStart) ?? dayStart
        let railEnd = localCalendar.date(bySettingHour: 18, minute: 0, second: 0, of: dayStart)
            ?? railStart.addingTimeInterval(9 * 3_600)
        let clippedStart = max(entry.start, railStart)
        let clippedEnd = min(entry.end, railEnd)
        let total = railEnd.timeIntervalSince(railStart)
        let offset = max(0, clippedStart.timeIntervalSince(railStart) / total)
        let duration = max(0, clippedEnd.timeIntervalSince(clippedStart) / total)
        return (CGFloat(offset) * height, CGFloat(duration) * height)
    }

    private func isCurrent(_ entry: TimetableEntry) -> Bool {
        entry.start <= now && now < entry.end
    }

    private var localCalendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: snapshot.timeZoneIdentifier) ?? .current
        return value
    }
}
