import SwiftUI

enum DailyActivityColors {
    static let surface = Color(red: 0.075, green: 0.082, blue: 0.09)
    static let primaryText = Color.white
    static let secondaryText = Color.white.opacity(0.78)
    static let tertiaryText = Color.white.opacity(0.64)
    static let eventAccent = Color(red: 0.38, green: 0.86, blue: 0.78)
    static let taskAccent = Color(red: 1.0, green: 0.68, blue: 0.31)
    static let separator = Color.white.opacity(0.16)
}

struct DailyActivityView: View {
    let state: TimetableActivityAttributes.ContentState
    let attributes: TimetableActivityAttributes
    let now: Date
    let isSystemStale: Bool
    let hasEnded: Bool

    @Environment(\.timeZone) private var timeZone

    var body: some View {
        ViewThatFits(in: .vertical) {
            content(rowLimit: 3, condensed: false)
            content(rowLimit: 2, condensed: false)
            content(rowLimit: 1, condensed: true)
            content(rowLimit: 0, condensed: true)
            boundedFallback
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxHeight: 160, alignment: .top)
        .foregroundStyle(DailyActivityColors.primaryText)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func content(rowLimit: Int, condensed: Bool) -> some View {
        if let payload = state.daily {
            let snapshot = payload.snapshot
            let presentation = payload.presentation(at: now, rowLimit: rowLimit)
            VStack(alignment: .leading, spacing: condensed ? 7 : 9) {
                DailyActivityHeader(snapshot: snapshot, now: now, hasEnded: hasEnded)

                if hasEnded {
                    DailyActivityMessage(
                        symbol: "stop.circle",
                        title: "Activity ended",
                        detail: "Open the app to view this day."
                    )
                } else if dayHasRolledOver(snapshot) {
                    DailyActivityMessage(
                        symbol: "arrow.clockwise",
                        title: "Schedule needs a refresh",
                        detail: "Open the app for the current day."
                    )
                } else if isStale(snapshot) {
                    DailyActivityMessage(
                        symbol: "arrow.clockwise",
                        title: "Open app to refresh",
                        detail: "This schedule may be out of date."
                    )
                } else {
                    DailyActivityMainContent(
                        presentation: presentation,
                        snapshot: snapshot,
                        now: now,
                        condensed: condensed
                    )
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 9) {
                DailyLegacyHeader(profileName: attributes.profileName)
                DailyActivityMessage(
                    symbol: "arrow.clockwise",
                    title: hasEnded ? "Activity ended" : "Open app to refresh",
                    detail: "A new daily schedule is available in the app."
                )
            }
        }
    }

    private func dayHasRolledOver(_ snapshot: DailyActivitySnapshot) -> Bool {
        now < snapshot.dayStart || now >= snapshot.dayEnd
    }

    private func isStale(_ snapshot: DailyActivitySnapshot) -> Bool {
        isSystemStale || TimetableFreshness.generatedAt(snapshot.generatedAt, now: now) == .stale
    }

    private var boundedFallback: some View {
        let copy = fallbackCopy
        return DailyActivityBoundedFallback(
            symbol: copy.symbol,
            title: copy.title,
            accessibilityText: copy.accessibilityText
        )
    }

    private var fallbackCopy: (symbol: String, title: String, accessibilityText: String) {
        guard let payload = state.daily else {
            let title = hasEnded ? "Activity ended" : "Open app to refresh"
            return ("arrow.clockwise", title, "\(attributes.profileName) profile. \(title). Open the app for the daily schedule.")
        }
        let snapshot = payload.snapshot
        let presentation = payload.presentation(at: now, rowLimit: 0)
        let statusTitle: String
        let symbol: String
        if hasEnded {
            statusTitle = "Activity ended"
            symbol = "stop.circle"
        } else if dayHasRolledOver(snapshot) || isStale(snapshot) {
            statusTitle = "Open app to refresh"
            symbol = "arrow.clockwise"
        } else if sourceAvailabilityText(snapshot) != nil {
            statusTitle = "Some sources unavailable"
            symbol = "exclamationmark.triangle"
        } else if presentation.requiresRefresh {
            statusTitle = "More in app"
            symbol = "arrow.clockwise"
        } else {
            statusTitle = "Open daily schedule"
            symbol = presentation.hero?.kind == .task ? "circle" : "calendar"
        }
        var details = ["\(snapshot.profile.name) profile", statusTitle]
        let representative = presentation.hero
            ?? payload.presentation(at: now, rowLimit: 1).rows.first
        if let representative {
            details.append(itemAccessibilityLabel(representative, now: now, timeZone: timeZone))
        } else {
            details.append("\(presentation.remainingCount) items remaining")
        }
        if let sourceText = sourceAvailabilityText(snapshot) {
            details.append(sourceText)
        }
        details.append("Open to view this day in the app")
        return (symbol, statusTitle, details.joined(separator: ". "))
    }
}

struct DailyActivityExpandedView: View {
    let state: TimetableActivityAttributes.ContentState
    let attributes: TimetableActivityAttributes
    let now: Date
    let isSystemStale: Bool
    let hasEnded: Bool

    @Environment(\.timeZone) private var timeZone

    var body: some View {
        ViewThatFits(in: .vertical) {
            expandedContent(rowLimit: 1, showsAgenda: true)
            expandedContent(rowLimit: 0, showsAgenda: false)
            boundedFallback
        }
        .frame(maxHeight: 104, alignment: .top)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(DailyActivityColors.primaryText)
        .privacySensitive()
    }

    @ViewBuilder
    private func expandedContent(rowLimit: Int, showsAgenda: Bool) -> some View {
        if let payload = state.daily {
            let snapshot = payload.snapshot
            let presentation = payload.presentation(at: now, rowLimit: rowLimit)
            if hasEnded {
                DailyActivityMessage(
                    symbol: "stop.circle",
                    title: "Activity ended",
                    detail: "Open the app to view this day."
                )
            } else if now < snapshot.dayStart || now >= snapshot.dayEnd {
                DailyActivityMessage(
                    symbol: "arrow.clockwise",
                    title: "Schedule needs a refresh",
                    detail: "Open the app for the current day."
                )
            } else if isSystemStale
                        || TimetableFreshness.generatedAt(snapshot.generatedAt, now: now) == .stale {
                DailyActivityMessage(
                    symbol: "arrow.clockwise",
                    title: "Open app to refresh",
                    detail: "This schedule may be out of date."
                )
            } else if showsAgenda {
                DailyActivityMainContent(
                    presentation: presentation,
                    snapshot: snapshot,
                    now: now,
                    condensed: true
                )
            } else {
                DailyActivityIslandSummary(
                    presentation: presentation,
                    snapshot: snapshot,
                    now: now
                )
            }
        } else {
            DailyActivityMessage(
                symbol: "arrow.clockwise",
                title: hasEnded ? "Activity ended" : "Open app to refresh",
                detail: attributes.profileName
            )
        }
    }

    private var boundedFallback: some View {
        let copy = fallbackCopy
        return DailyActivityBoundedFallback(
            symbol: copy.symbol,
            title: copy.title,
            accessibilityText: copy.accessibilityText
        )
    }

    private var fallbackCopy: (symbol: String, title: String, accessibilityText: String) {
        guard let payload = state.daily else {
            let title = hasEnded ? "Activity ended" : "Open app to refresh"
            return ("arrow.clockwise", title, "\(attributes.profileName) profile. \(title). Open the app for the daily schedule.")
        }
        let snapshot = payload.snapshot
        let presentation = payload.presentation(at: now, rowLimit: 0)
        let title: String
        let symbol: String
        if hasEnded {
            title = "Activity ended"
            symbol = "stop.circle"
        } else if now < snapshot.dayStart || now >= snapshot.dayEnd
                    || isSystemStale
                    || TimetableFreshness.generatedAt(snapshot.generatedAt, now: now) == .stale {
            title = "Open app to refresh"
            symbol = "arrow.clockwise"
        } else if sourceAvailabilityText(snapshot) != nil {
            title = "Some sources unavailable"
            symbol = "exclamationmark.triangle"
        } else if presentation.requiresRefresh {
            title = "More in app"
            symbol = "arrow.clockwise"
        } else {
            title = "Open daily schedule"
            symbol = presentation.hero?.kind == .task ? "circle" : "calendar"
        }
        var details = ["\(snapshot.profile.name) profile", title]
        let representative = presentation.hero
            ?? payload.presentation(at: now, rowLimit: 1).rows.first
        if let representative {
            details.append(itemAccessibilityLabel(representative, now: now, timeZone: timeZone))
        } else {
            details.append("\(presentation.remainingCount) items remaining")
        }
        if let sourceText = sourceAvailabilityText(snapshot) {
            details.append(sourceText)
        }
        details.append("Open to view this day in the app")
        return (symbol, title, details.joined(separator: ". "))
    }
}

struct DailyActivityIslandLeadingView: View {
    let state: TimetableActivityAttributes.ContentState
    let attributes: TimetableActivityAttributes
    let now: Date
    let isSystemStale: Bool
    let hasEnded: Bool

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: leadingSymbol)
                .foregroundStyle(leadingColor)
            Text(profileName)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Daily schedule for \(profileName)")
        .privacySensitive()
    }

    private var profileName: String {
        state.daily?.snapshot.profile.name ?? attributes.profileName
    }

    private var leadingSymbol: String {
        guard !needsRefresh,
              let item = state.daily?.presentation(at: now, rowLimit: 0).hero else {
            return needsRefresh ? "arrow.clockwise" : "calendar"
        }
        return item.kind == .event ? "calendar" : "circle"
    }

    private var leadingColor: Color {
        guard !needsRefresh,
              let item = state.daily?.presentation(at: now, rowLimit: 0).hero else {
            return DailyActivityColors.secondaryText
        }
        return item.kind == .event ? DailyActivityColors.eventAccent : DailyActivityColors.taskAccent
    }

    private var needsRefresh: Bool {
        guard !hasEnded, let snapshot = state.daily?.snapshot else { return true }
        return isSystemStale
            || TimetableFreshness.generatedAt(snapshot.generatedAt, now: now) == .stale
            || now < snapshot.dayStart
            || now >= snapshot.dayEnd
            || state.daily?.presentation(at: now, rowLimit: 0).requiresRefresh == true
    }
}

struct DailyActivityIslandTrailingView: View {
    let state: TimetableActivityAttributes.ContentState
    let now: Date
    let isSystemStale: Bool
    let hasEnded: Bool

    var body: some View {
        DailyActivityCompactTrailingView(
            state: state,
            now: now,
            isSystemStale: isSystemStale,
            hasEnded: hasEnded
        )
        .font(.caption.monospacedDigit().weight(.semibold))
    }
}

struct DailyActivityCompactLeadingView: View {
    let state: TimetableActivityAttributes.ContentState
    let now: Date
    let isSystemStale: Bool
    let hasEnded: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .foregroundStyle(accent)
            if let text {
                Text(text)
                    .font(.caption2.weight(.heavy))
                    .foregroundStyle(DailyActivityColors.primaryText)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .privacySensitive()
    }

    private var presentation: DailyActivityPresentation? {
        validPresentation(state: state, now: now, isSystemStale: isSystemStale, hasEnded: hasEnded)
    }

    private var item: DailyActivityItem? { presentation?.hero }

    private var symbol: String {
        guard let item else { return presentation == nil ? "arrow.clockwise" : "calendar" }
        return item.kind == .event ? "calendar" : "circle"
    }

    private var accent: Color {
        guard let item else { return DailyActivityColors.secondaryText }
        return item.kind == .event ? DailyActivityColors.eventAccent : DailyActivityColors.taskAccent
    }

    private var text: String? {
        guard let presentation else { return "OPEN" }
        return presentation.hero?.shortTitle
    }

    private var accessibilityText: String {
        guard let presentation else { return hasEnded ? "Activity ended" : "Open app to refresh" }
        if let item = presentation.hero { return item.title }
        return "\(presentation.remainingCount) items remaining today"
    }
}

struct DailyActivityCompactTrailingView: View {
    let state: TimetableActivityAttributes.ContentState
    let now: Date
    let isSystemStale: Bool
    let hasEnded: Bool

    @Environment(\.timeZone) private var timeZone

    var body: some View {
        if let presentation = validPresentation(
            state: state,
            now: now,
            isSystemStale: isSystemStale,
            hasEnded: hasEnded
        ) {
            if let boundary = presentation.countdownBoundary, boundary > now {
                Text(timerInterval: now...boundary, countsDown: true)
                    .monospacedDigit()
                    .accessibilityLabel(countdownAccessibilityLabel(presentation, boundary: boundary))
            } else {
                Text("\(presentation.remainingCount)")
                    .monospacedDigit()
                    .accessibilityLabel("\(presentation.remainingCount) items remaining today")
            }
        } else {
            Text(hasEnded ? "END" : "OPEN")
                .accessibilityLabel(hasEnded ? "Activity ended" : "Open app to refresh")
        }
    }

    private func countdownAccessibilityLabel(
        _ presentation: DailyActivityPresentation,
        boundary: Date
    ) -> String {
        let prefix: String
        if let hero = presentation.hero, DailyActivityPresentation.isActive(hero, at: now) {
            prefix = "Ends"
        } else if presentation.hero?.kind == .task {
            prefix = "Due"
        } else {
            prefix = "Starts"
        }
        return "\(prefix) at \(formattedTime(boundary, timeZone: timeZone))"
    }
}

struct DailyActivityMinimalView: View {
    let state: TimetableActivityAttributes.ContentState
    let now: Date
    let isSystemStale: Bool
    let hasEnded: Bool

    var body: some View {
        Image(systemName: symbol)
            .foregroundStyle(accent)
            .accessibilityLabel(accessibilityText)
    }

    private var presentation: DailyActivityPresentation? {
        validPresentation(state: state, now: now, isSystemStale: isSystemStale, hasEnded: hasEnded)
    }

    private var item: DailyActivityItem? { presentation?.hero }

    private var symbol: String {
        guard let item else {
            guard presentation != nil else { return "arrow.clockwise" }
            switch remainingKinds {
            case [.event]: return "calendar"
            case [.task]: return "circle"
            default: return "calendar.day.timeline.left"
            }
        }
        return item.kind == .event ? "calendar" : "circle"
    }

    private var accent: Color {
        guard let item else { return DailyActivityColors.secondaryText }
        return item.kind == .event ? DailyActivityColors.eventAccent : DailyActivityColors.taskAccent
    }

    private var accessibilityText: String {
        guard let presentation else { return hasEnded ? "Activity ended" : "Open app to refresh" }
        if let item = presentation.hero { return item.title }
        return "\(presentation.remainingCount) items remaining today"
    }

    private var remainingKinds: Set<DailyActivityItem.Kind> {
        guard let snapshot = state.daily?.snapshot else { return [] }
        return Set(snapshot.items.filter { $0.isEligible(in: snapshot, at: now) }.map(\.kind))
    }
}

private struct DailyActivityHeader: View {
    let snapshot: DailyActivitySnapshot
    let now: Date
    let hasEnded: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            HStack(spacing: 5) {
                Text(dayPrefix)
                Text("·")
                    .foregroundStyle(DailyActivityColors.tertiaryText)
                Text(snapshot.dayStart, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
            }
            .font(.caption2.weight(.bold))
            .textCase(.uppercase)
            .foregroundStyle(DailyActivityColors.secondaryText)
            .lineLimit(1)

            Spacer(minLength: 8)

            Label(snapshot.profile.name, systemImage: snapshot.profile.symbolName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(DailyActivityColors.primaryText)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(dayPrefix), \(formattedDay), \(snapshot.profile.name) profile")
    }

    private var dayPrefix: String {
        guard !hasEnded, now >= snapshot.dayStart, now < snapshot.dayEnd else { return "Schedule" }
        return "Today"
    }

    private var formattedDay: String {
        let zone = TimeZone(identifier: snapshot.timeZoneIdentifier) ?? .current
        let style = Date.FormatStyle(date: .complete, time: .omitted, timeZone: zone)
        return snapshot.dayStart.formatted(style)
    }
}

private struct DailyLegacyHeader: View {
    let profileName: String

    var body: some View {
        HStack {
            Text("DAILY SCHEDULE")
                .font(.caption2.weight(.bold))
                .foregroundStyle(DailyActivityColors.secondaryText)
            Spacer(minLength: 8)
            Text(profileName)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
    }
}

private struct DailyActivityMainContent: View {
    let presentation: DailyActivityPresentation
    let snapshot: DailyActivitySnapshot
    let now: Date
    let condensed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: condensed ? 6 : 8) {
            if presentation.requiresRefresh {
                DailyActivityMessage(
                    symbol: "arrow.clockwise",
                    title: "More in app",
                    detail: "Open to refresh the next item."
                )
            } else if let hero = presentation.hero {
                DailyActivityHero(item: hero, boundary: presentation.countdownBoundary, now: now)
            } else {
                DailyActivityNeutralHero(remainingCount: presentation.remainingCount)
            }

            if !presentation.rows.isEmpty {
                Divider().overlay(DailyActivityColors.separator)
                VStack(alignment: .leading, spacing: condensed ? 5 : 7) {
                    ForEach(presentation.rows) { item in
                        DailyActivityRow(item: item, now: now)
                    }
                }
            }

            DailyActivityFooter(presentation: presentation, snapshot: snapshot)
        }
    }
}

private struct DailyActivityIslandSummary: View {
    let presentation: DailyActivityPresentation
    let snapshot: DailyActivitySnapshot
    let now: Date

    @Environment(\.timeZone) private var timeZone

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if presentation.requiresRefresh {
                DailyActivityMessage(
                    symbol: "arrow.clockwise",
                    title: "More in app",
                    detail: "Open to refresh."
                )
            } else if let hero = presentation.hero {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Image(systemName: hero.kind == .event ? "calendar" : "circle")
                        .foregroundStyle(hero.kind == .event
                            ? DailyActivityColors.eventAccent
                            : DailyActivityColors.taskAccent)
                    Text(hero.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                    Spacer(minLength: 4)
                    DailyActivityItemTime(item: hero, now: now)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(itemAccessibilityLabel(hero, now: now, timeZone: timeZone))
            } else {
                DailyActivityNeutralHero(remainingCount: presentation.remainingCount)
            }
            DailyActivityFooter(presentation: presentation, snapshot: snapshot)
        }
    }
}

private struct DailyActivityHero: View {
    let item: DailyActivityItem
    let boundary: Date?
    let now: Date

    @Environment(\.timeZone) private var timeZone

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                HStack(spacing: 5) {
                    Label(heroLabel, systemImage: item.kind == .event ? "calendar" : "circle")
                    if item.kind == .task, item.hasAlert {
                        Image(systemName: "bell.fill")
                            .accessibilityLabel("Alert set")
                    }
                }
                .font(.caption2.weight(.heavy))
                .foregroundStyle(accent)
                Spacer(minLength: 8)
                if let boundary, boundary > now {
                    HStack(spacing: 3) {
                        Text(countdownPrefix)
                        Text(timerInterval: now...boundary, countsDown: true)
                            .monospacedDigit()
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DailyActivityColors.secondaryText)
                }
            }

            Text(item.title)
                .font(.headline.weight(.bold))
                .foregroundStyle(DailyActivityColors.primaryText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 7) {
                DailyActivityItemTime(item: item, now: now)
                if let location = item.location, !location.isEmpty {
                    Label(location, systemImage: "location")
                        .lineLimit(1)
                }
            }
            .font(.caption)
            .foregroundStyle(DailyActivityColors.secondaryText)

            if DailyActivityPresentation.isActive(item, at: now), let end = item.end, end > item.start {
                ProgressView(timerInterval: item.start...end, countsDown: false)
                    .tint(DailyActivityColors.eventAccent)
                    .accessibilityLabel("Event progress")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(itemAccessibilityLabel(item, now: now, timeZone: timeZone))
    }

    private var heroLabel: String {
        if DailyActivityPresentation.isActive(item, at: now) { return "NOW" }
        if item.kind == .task {
            if item.isAllDay { return "TODAY" }
            return item.start <= now ? "OVERDUE" : "DUE"
        }
        return "NEXT"
    }

    private var countdownPrefix: String {
        if DailyActivityPresentation.isActive(item, at: now) { return "Ends in" }
        return item.kind == .task ? "Due in" : "Starts in"
    }

    private var accent: Color {
        item.kind == .event ? DailyActivityColors.eventAccent : DailyActivityColors.taskAccent
    }
}

private struct DailyActivityNeutralHero: View {
    let remainingCount: Int

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "calendar.day.timeline.left")
                .font(.title3)
                .foregroundStyle(DailyActivityColors.eventAccent)
            VStack(alignment: .leading, spacing: 1) {
                Text("Today")
                    .font(.headline.weight(.bold))
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(DailyActivityColors.secondaryText)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(summary)
    }

    private var summary: String {
        if remainingCount == 0 { return "No remaining items" }
        return "\(remainingCount) \(remainingCount == 1 ? "item" : "items") remaining"
    }
}

private struct DailyActivityRow: View {
    let item: DailyActivityItem
    let now: Date

    @Environment(\.timeZone) private var timeZone

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: item.kind == .event ? "calendar" : "circle")
                .font(.caption.weight(.semibold))
                .foregroundStyle(accent)
                .frame(width: 16, height: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DailyActivityColors.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 5) {
                    DailyActivityItemTime(item: item, now: now)
                    if item.kind == .task, item.hasAlert {
                        Image(systemName: "bell.fill")
                            .accessibilityLabel("Alert set")
                    }
                    if item.kind == .event, let location = item.location, !location.isEmpty {
                        Label(location, systemImage: "location")
                            .lineLimit(1)
                    }
                }
                .font(.caption2)
                .foregroundStyle(DailyActivityColors.secondaryText)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(itemAccessibilityLabel(item, now: now, timeZone: timeZone))
    }

    private var accent: Color {
        item.kind == .event ? DailyActivityColors.eventAccent : DailyActivityColors.taskAccent
    }
}

private struct DailyActivityItemTime: View {
    let item: DailyActivityItem
    let now: Date

    var body: some View {
        if item.isAllDay {
            Text(item.kind == .task ? "Today" : "All day")
        } else if item.kind == .task {
            HStack(spacing: 3) {
                Text(item.start <= now ? "Overdue ·" : "Due")
                Text(item.start, format: .dateTime.hour().minute())
            }
        } else if let end = item.end {
            HStack(spacing: 3) {
                Text(item.start, format: .dateTime.hour().minute())
                Text("–")
                Text(end, format: .dateTime.hour().minute())
            }
        }
    }
}

private struct DailyActivityFooter: View {
    let presentation: DailyActivityPresentation
    let snapshot: DailyActivitySnapshot

    var body: some View {
        if hiddenText != nil || sourceText != nil {
            VStack(alignment: .leading, spacing: 2) {
                if let hiddenText {
                    Text(hiddenText)
                }
                if let sourceText {
                    Label(sourceText, systemImage: "exclamationmark.triangle")
                }
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(DailyActivityColors.secondaryText)
            .accessibilityElement(children: .combine)
        }
    }

    private var hiddenText: String? {
        if let hidden = presentation.hiddenCount, hidden > 0 {
            return "+\(hidden) more today"
        }
        if presentation.requiresRefresh { return nil }
        return presentation.hiddenCount == nil ? "More in app" : nil
    }

    private var sourceText: String? {
        sourceAvailabilityText(snapshot)
    }
}

private struct DailyActivityBoundedFallback: View {
    let symbol: String
    let title: String
    let accessibilityText: String

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.headline.weight(.semibold))
            .foregroundStyle(DailyActivityColors.primaryText)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
            .accessibilityHint("Opens the represented day in the app")
    }
}

private struct DailyActivityMessage: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(DailyActivityColors.eventAccent)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline.weight(.bold))
                    .lineLimit(2)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(DailyActivityColors.secondaryText)
                    .lineLimit(2)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(detail)")
    }
}

private func validPresentation(
    state: TimetableActivityAttributes.ContentState,
    now: Date,
    isSystemStale: Bool,
    hasEnded: Bool
) -> DailyActivityPresentation? {
    guard !hasEnded, !isSystemStale, let payload = state.daily else { return nil }
    let snapshot = payload.snapshot
    guard now >= snapshot.dayStart, now < snapshot.dayEnd,
          TimetableFreshness.generatedAt(snapshot.generatedAt, now: now) == .fresh else { return nil }
    let presentation = payload.presentation(at: now, rowLimit: 0)
    return presentation.requiresRefresh ? nil : presentation
}

private func itemAccessibilityLabel(
    _ item: DailyActivityItem,
    now: Date,
    timeZone: TimeZone
) -> String {
    var parts = [item.kind == .event ? "Event" : "Task", item.title]
    if item.isAllDay {
        parts.append(item.kind == .task ? "Today" : "All day")
    } else if item.kind == .task {
        let prefix = item.start <= now ? "Overdue" : "Due"
        parts.append("\(prefix) \(formattedTime(item.start, timeZone: timeZone))")
    } else if let end = item.end {
        parts.append("\(formattedTime(item.start, timeZone: timeZone)) to \(formattedTime(end, timeZone: timeZone))")
    }
    if let location = item.location, !location.isEmpty { parts.append(location) }
    if item.kind == .task, item.hasAlert { parts.append("Alert set") }
    return parts.joined(separator: ", ")
}

private func formattedTime(_ date: Date, timeZone: TimeZone) -> String {
    date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: timeZone))
}

private func sourceAvailabilityText(_ snapshot: DailyActivitySnapshot) -> String? {
    switch (snapshot.calendarUnavailable, snapshot.tasksUnavailable) {
    case (true, true): "Some calendars and tasks unavailable"
    case (true, false): "Some calendars unavailable"
    case (false, true): "Some tasks unavailable"
    case (false, false): nil
    }
}
