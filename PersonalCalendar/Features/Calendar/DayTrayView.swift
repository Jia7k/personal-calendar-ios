import SwiftUI

struct DayTrayView: View {
    let day: LocalDay
    let agenda: DayAgenda
    let state: TrayState
    let isLoading: Bool
    let errorMessage: String?
    let deniedSourceMessages: [String]
    let calendar: Calendar
    let onSetState: (TrayState) -> Void
    let onRetry: () -> Void

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
            if let errorMessage { Label(errorMessage, systemImage: "exclamationmark.triangle"); Button("Retry", action: onRetry) }
            ForEach(deniedSourceMessages, id: \.self) { message in
                Label(message, systemImage: "lock.fill").font(.footnote).foregroundStyle(.secondary).padding(8).background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
            }
            if state == .resting { restingContent } else { expandedContent }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: CalendarTheme.cornerRadius))
        .accessibilityElement(children: .contain)
    }

    private var restingContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let event = agenda.scheduled.first(where: { if case .timed = $0.placement { true } else { false } }) { trayRow(event, label: "Next") }
            if let task = agenda.priority.filter({ $0.source == .task }).sorted(by: AgendaItem.prioritySort).first { trayRow(task, label: "Priority") }
            if let routine = agenda.scheduled.first(where: { $0.source == .routine && !$0.isCompleted }) ?? agenda.priority.first(where: { $0.source == .routine && !$0.isCompleted }) { trayRow(routine, label: "Routine") }
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

    private func section(_ title: String, items: [AgendaItem]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            if items.isEmpty { Text("None").font(.subheadline).foregroundStyle(.secondary) }
            ForEach(items) { trayRow($0, label: nil) }
        }
    }

    private func trayRow(_ item: AgendaItem, label: String?) -> some View {
        HStack(spacing: 8) {
            Image(systemName: item.source == .event ? "calendar" : item.source == .task ? "checkmark.circle" : "repeat")
                .foregroundStyle(CalendarTheme.accent)
            VStack(alignment: .leading) {
                if let label { Text(label).font(.caption).foregroundStyle(.secondary) }
                Text(item.title).font(.body)
            }
            Spacer()
        }
    }
}
