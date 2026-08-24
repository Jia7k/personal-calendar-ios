import SwiftUI

struct DayTrayView: View {
    let day: LocalDay
    let agenda: DayAgenda
    let state: TrayState
    let isLoading: Bool
    let errorMessage: String?
    let sourceAccessNotices: [SourceAccessNotice]
    let calendar: Calendar
    let openSettings: @MainActor () -> Void
    let onSetState: (TrayState) -> Void
    let onRetry: () -> Void
    let onOpenItem: @MainActor (AgendaItemOrigin) -> Void
    let onSetTaskCompleted: @MainActor (AgendaItem, Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(day.startDate(in: calendar).formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    .font(.title3.weight(.semibold))
                Spacer()
                Button(state == .resting ? "Expand day" : "Collapse day") { onSetState(state == .resting ? .expanded : .resting) }
                    .frame(minWidth: CalendarTheme.minimumTapSize, minHeight: CalendarTheme.minimumTapSize)
            }
            if isLoading { ProgressView("Loading your day") }
            if let errorMessage { Label(errorMessage, systemImage: "exclamationmark.triangle"); Button("Retry", action: onRetry).frame(minWidth: CalendarTheme.minimumTapSize, minHeight: CalendarTheme.minimumTapSize) }
            ForEach(sourceAccessNotices) { notice in
                VStack(alignment: .leading, spacing: 6) {
                    Label(notice.message, systemImage: "lock.fill").font(.footnote).foregroundStyle(.secondary)
                    if notice.canOpenSettings {
                        Button("Open Settings", action: openSettings)
                            .frame(minWidth: CalendarTheme.minimumTapSize, minHeight: CalendarTheme.minimumTapSize)
                            .accessibilityIdentifier(notice.settingsActionIdentifier)
                            .accessibilityLabel("Open in-app Settings for \(notice.source.displayName)")
                    }
                }.padding(8).background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
            }
            if state == .resting { restingContent } else { expandedContent }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: CalendarTheme.cornerRadius))
        .accessibilityElement(children: .contain)
    }

    private var restingContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let event = Self.nextEvent(in: agenda) { trayRow(event, label: "Next") }
            if let task = Self.highestPriorityTask(in: agenda) { trayRow(task, label: "Priority") }
            if let routine = Self.nextIncompleteRoutine(in: agenda) { trayRow(routine, label: "Routine") }
            if agenda.allDay.isEmpty && agenda.scheduled.isEmpty && agenda.priority.isEmpty { Text("Nothing planned yet.").foregroundStyle(.secondary) }
        }
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            section("All Day", items: agenda.allDay)
            section("Schedule", items: agenda.scheduled)
            section("Priority", items: agenda.priority)
        }
    }

    static func nextEvent(in agenda: DayAgenda) -> AgendaItem? { agenda.scheduled.filter { $0.source == .event }.sorted(by: AgendaItem.stableSort).first }
    static func highestPriorityTask(in agenda: DayAgenda) -> AgendaItem? { (agenda.scheduled + agenda.priority).filter { $0.source == .task && !$0.isCompleted }.sorted(by: AgendaItem.prioritySort).first }
    static func nextIncompleteRoutine(in agenda: DayAgenda) -> AgendaItem? {
        agenda.scheduled.first(where: { $0.source == .routine && !$0.isCompleted })
            ?? agenda.priority.first(where: { $0.source == .routine && !$0.isCompleted })
    }

    private func section(_ title: String, items: [AgendaItem]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            if items.isEmpty { Text("None").font(.subheadline).foregroundStyle(.secondary) }
            ForEach(items) { trayRow($0, label: nil) }
        }
    }

    @ViewBuilder private func trayRow(_ item: AgendaItem, label: String?) -> some View {
        switch item.origin {
        case let .event(displayID):
            Button { onOpenItem(.event(id: displayID)) } label: { trayRowContent(item, label: label) }
                .buttonStyle(.borderless)
                .frame(minHeight: CalendarTheme.minimumTapSize)
                .contentShape(Rectangle())
                .accessibilityIdentifier("agenda-open-event-\(displayID)")
                .accessibilityLabel("Open event \(item.title)")
        case let .reminder(reminderID):
            HStack(spacing: 8) {
                Button { onOpenItem(.reminder(id: reminderID)) } label: { trayRowContent(item, label: label) }
                    .buttonStyle(.borderless)
                    .frame(maxWidth: .infinity, minHeight: CalendarTheme.minimumTapSize)
                    .contentShape(Rectangle())
                    .accessibilityIdentifier("agenda-open-task-\(reminderID)")
                    .accessibilityLabel("Open task \(item.title)")
                if item.allowsModification {
                    Button { onSetTaskCompleted(item, !item.isCompleted) } label: {
                        Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                            .frame(width: CalendarTheme.minimumTapSize, height: CalendarTheme.minimumTapSize)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("agenda-complete-task-\(reminderID)")
                    .accessibilityLabel(item.isCompleted ? "Mark \(item.title) incomplete" : "Mark \(item.title) complete")
                    .accessibilityValue(item.isCompleted ? "Completed" : "Not completed")
                }
            }
        case .routine, .synthetic:
            trayRowContent(item, label: label)
                .frame(minHeight: CalendarTheme.minimumTapSize)
        }
    }

    private func trayRowContent(_ item: AgendaItem, label: String?) -> some View {
        HStack(spacing: 8) {
            Image(systemName: item.source == .event ? "calendar" : item.source == .task ? "checkmark.circle" : "repeat")
                .foregroundStyle(CalendarTheme.accent)
            VStack(alignment: .leading) {
                if let label { Text(label).font(.caption).foregroundStyle(.secondary) }
                Text(item.title).font(.body)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
