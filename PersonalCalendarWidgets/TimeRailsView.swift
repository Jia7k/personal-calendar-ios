import SwiftUI

struct TimeRailsView: View {
    let snapshot: TimetableSnapshotV1
    let now: Date
    let showsStatusStrip: Bool
    let profileName: String

    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    private let weekdayLabels = ["M", "T", "W", "T", "F"]
    private let railStartHour = 9
    private let railEndHour = 18

    init(
        snapshot: TimetableSnapshotV1,
        now: Date,
        showsStatusStrip: Bool,
        profileName: String
    ) {
        self.snapshot = snapshot
        self.now = now
        self.showsStatusStrip = showsStatusStrip
        self.profileName = profileName
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(profileName.uppercased())
                    .font(.caption2.weight(.bold))
                    .lineLimit(1)
                Spacer()
                Text(snapshot.weekStart, format: .dateTime.month(.abbreviated).day())
                    .font(.caption2)
            }

            HStack(spacing: 4) {
                timeScale
                    .frame(width: 20)
                HStack(spacing: 3) {
                    ForEach(0..<5, id: \.self) { index in
                        dayRail(index: index)
                    }
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
            Text(weekdayLabels[index])
                .font(.caption2.weight(.bold))
                .foregroundStyle(index == todayIndex ? railAccent : .white.opacity(0.72))
            GeometryReader { proxy in
                ZStack(alignment: .top) {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(.white.opacity(isLuminanceReduced ? 0.02 : 0.08))
                    ForEach(placements(for: index), id: \.entry.id) { placement in
                        let height = max(proxy.size.height * placement.heightFraction, 10)
                        Text(placement.entry.shortTitle)
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity, minHeight: height, alignment: .top)
                            .padding(.top, 2)
                            .background {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(blockFill(for: placement.entry))
                                    .overlay {
                                        if isLuminanceReduced {
                                            RoundedRectangle(cornerRadius: 4)
                                                .stroke(.white, lineWidth: isCurrent(placement.entry) ? 2 : 1)
                                        }
                                    }
                            }
                            .offset(y: proxy.size.height * placement.startFraction)
                    }
                    currentTimeLine(height: proxy.size.height, index: index)
                }
            }
        }
    }

    private var statusStrip: some View {
        Group {
            switch snapshot.moment(at: now, calendar: localCalendar) {
            case .none:
                Text("No more events today")
            case let .current(entry):
                statusText(prefix: "NOW", entry: entry, boundary: entry.end, boundaryWord: "until")
            case let .next(entry), let .gap(entry):
                statusText(prefix: "NEXT", entry: entry, boundary: entry.start, boundaryWord: "at")
            }
        }
        .font(.caption2.weight(.semibold))
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var timeScale: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 14)
            GeometryReader { proxy in
                ZStack(alignment: .topTrailing) {
                    Text("09").offset(y: -4)
                    Text("13").offset(y: proxy.size.height * (4.0 / 9.0) - 4)
                    Text("18").offset(y: proxy.size.height - 8)
                }
                .font(.system(size: 7, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.56))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
        }
    }

    private func placements(for index: Int) -> [TimeRailPlacement] {
        TimeRailsLayout(calendar: localCalendar, startHour: railStartHour, endHour: railEndHour)
            .placements(snapshot: snapshot)
            .filter { $0.weekdayIndex == index }
    }

    private func isCurrent(_ entry: TimetableEntry) -> Bool {
        entry.start <= now && now < entry.end
    }

    @ViewBuilder
    private func currentTimeLine(height: CGFloat, index: Int) -> some View {
        if index == todayIndex, let fraction = currentTimeFraction {
            Rectangle()
                .fill(.white)
                .frame(height: isLuminanceReduced ? 2 : 1)
                .shadow(color: .black.opacity(0.5), radius: 1)
                .offset(y: height * fraction)
        }
    }

    private func statusText(
        prefix: String,
        entry: TimetableEntry,
        boundary: Date,
        boundaryWord: String
    ) -> Text {
        let location = entry.location.map { " · \($0)" } ?? ""
        return Text(
            "\(prefix)  \(entry.shortTitle) · \(entry.title) · \(boundaryWord) "
                + boundary.formatted(date: .omitted, time: .shortened)
                + location
        )
    }

    private func blockFill(for entry: TimetableEntry) -> Color {
        guard !isLuminanceReduced else { return .clear }
        return railAccent.opacity(isCurrent(entry) ? 1 : 0.62)
    }

    private var todayIndex: Int? {
        let value = (localCalendar.component(.weekday, from: now) + 5) % 7
        return (0..<5).contains(value) ? value : nil
    }

    private var currentTimeFraction: CGFloat? {
        let dayStart = localCalendar.startOfDay(for: now)
        guard
            let railStart = localCalendar.date(
                bySettingHour: railStartHour,
                minute: 0,
                second: 0,
                of: dayStart
            ),
            let railEnd = localCalendar.date(
                bySettingHour: railEndHour,
                minute: 0,
                second: 0,
                of: dayStart
            ),
            railStart <= now,
            now <= railEnd
        else { return nil }

        return CGFloat(now.timeIntervalSince(railStart) / railEnd.timeIntervalSince(railStart))
    }

    private var railAccent: Color {
        Color(red: 0.38, green: 0.73, blue: 0.68)
    }

    private var localCalendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: snapshot.timeZoneIdentifier) ?? .current
        return value
    }
}
