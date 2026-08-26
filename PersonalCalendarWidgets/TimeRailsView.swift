import SwiftUI

struct TimeRailsView: View {
    let snapshot: TimetableSnapshotV1
    let now: Date
    let showsStatusStrip: Bool
    let profileName: String

    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    private let weekdayLabels = ["M", "T", "W", "T", "F"]

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
        let layout = TimeRailsLayout(calendar: localCalendar, snapshot: snapshot)
        let placements = layout.placements(snapshot: snapshot)

        VStack(spacing: 4) {
            HStack(spacing: 5) {
                Text(profileName.uppercased())
                    .font(.caption2.weight(.bold))
                    .lineLimit(1)
                Spacer(minLength: 2)
                if usesCompressedScale(layout) {
                    compressedScaleBadge(layout)
                }
                Text(snapshot.weekStart, format: .dateTime.month(.abbreviated).day())
                    .font(.caption2)
            }

            HStack(spacing: 4) {
                timeScale(layout)
                    .frame(width: 22)
                HStack(spacing: 3) {
                    ForEach(0..<5, id: \.self) { index in
                        dayRail(
                            index: index,
                            layout: layout,
                            placements: placements.filter { $0.weekdayIndex == index }
                        )
                    }
                }
            }

            if showsStatusStrip || snapshot.omittedEntryCount > 0 {
                HStack(spacing: 6) {
                    if showsStatusStrip {
                        statusStrip
                    }
                    if snapshot.omittedEntryCount > 0 {
                        omittedIndicator
                    }
                }
            }
        }
        .foregroundStyle(.white)
    }

    private func dayRail(
        index: Int,
        layout: TimeRailsLayout,
        placements: [TimeRailPlacement]
    ) -> some View {
        VStack(spacing: 2) {
            Text(weekdayLabels[index])
                .font(.caption2.weight(.bold))
                .foregroundStyle(index == todayIndex ? railAccent : .white.opacity(0.72))
            GeometryReader { proxy in
                ZStack(alignment: .top) {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(.white.opacity(isLuminanceReduced ? 0.02 : 0.08))
                    ForEach(placements, id: \.entry.id) { placement in
                        let height = min(
                            max(proxy.size.height * placement.heightFraction, 10),
                            proxy.size.height
                        )
                        let offset = min(
                            max(proxy.size.height * placement.startFraction, 0),
                            max(proxy.size.height - height, 0)
                        )
                        Text(placement.entry.shortTitle)
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .minimumScaleFactor(0.7)
                            .padding(.top, 2)
                            .frame(height: height, alignment: .top)
                            .frame(maxWidth: .infinity)
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
                            .offset(y: offset)
                    }
                    currentTimeLine(height: proxy.size.height, index: index, layout: layout)
                }
                .clipped()
            }
        }
    }

    private var statusStrip: some View {
        Group {
            switch snapshot.moment(at: now, calendar: localCalendar) {
            case .none:
                Text(
                    snapshot.omittedEntryCount > 0
                        ? "More events are not shown"
                        : "No more events today"
                )
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

    private var omittedIndicator: some View {
        Text("+\(snapshot.omittedEntryCount) more")
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white.opacity(0.78))
            .lineLimit(1)
            .fixedSize()
            .accessibilityLabel(omittedAccessibilityLabel)
    }

    private func timeScale(_ layout: TimeRailsLayout) -> some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 14)
            GeometryReader { proxy in
                ZStack(alignment: .topTrailing) {
                    Text(hourLabel(layout.startMinute)).offset(y: -4)
                    Text(hourLabel(middleMinute(layout)))
                        .offset(y: proxy.size.height * middleFraction(layout) - 4)
                    Text(hourLabel(layout.endMinute)).offset(y: proxy.size.height - 8)
                }
                .font(.system(size: 7, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.56))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
        }
        .accessibilityHidden(true)
    }

    private func isCurrent(_ entry: TimetableEntry) -> Bool {
        entry.start <= now && now < entry.end
    }

    @ViewBuilder
    private func currentTimeLine(
        height: CGFloat,
        index: Int,
        layout: TimeRailsLayout
    ) -> some View {
        if index == todayIndex, let fraction = layout.fraction(for: now) {
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

    private func usesCompressedScale(_ layout: TimeRailsLayout) -> Bool {
        layout.startMinute < 8 * 60 || layout.endMinute > 18 * 60
    }

    private func compressedScaleBadge(_ layout: TimeRailsLayout) -> some View {
        Text("FIT \(hourLabel(layout.startMinute))–\(hourLabel(layout.endMinute))")
            .font(.system(size: 7, weight: .bold, design: .rounded))
            .foregroundStyle(.white.opacity(0.78))
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(.white.opacity(isLuminanceReduced ? 0.04 : 0.1), in: Capsule())
            .fixedSize()
            .accessibilityLabel(
                "Timeline compressed from \(hourLabel(layout.startMinute)):00 "
                    + "to \(hourLabel(layout.endMinute)):00"
            )
    }

    private func middleMinute(_ layout: TimeRailsLayout) -> Int {
        let midpoint = (layout.startMinute + layout.endMinute) / 2
        let rounded = ((midpoint + 30) / 60) * 60
        return min(layout.endMinute - 60, max(layout.startMinute + 60, rounded))
    }

    private func middleFraction(_ layout: TimeRailsLayout) -> CGFloat {
        CGFloat(middleMinute(layout) - layout.startMinute)
            / CGFloat(layout.endMinute - layout.startMinute)
    }

    private func hourLabel(_ minute: Int) -> String {
        let hour = minute / 60
        return hour < 10 ? "0\(hour)" : "\(hour)"
    }

    private var omittedAccessibilityLabel: String {
        let noun = snapshot.omittedEntryCount == 1 ? "event" : "events"
        return "\(snapshot.omittedEntryCount) additional timetable \(noun) omitted"
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
