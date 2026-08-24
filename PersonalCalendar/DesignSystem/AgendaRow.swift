import SwiftUI

struct AgendaRow: View {
    let item: AgendaItem
    let isMutating: Bool
    let complete: (Bool) -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: sourceSymbol)
                .foregroundStyle(sourceColor)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title).font(.body).strikethrough(item.isCompleted)
                Text(timeDescription).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if item.source == .task || item.source == .routine {
                if item.allowsModification {
                    Button { complete(!item.isCompleted) } label: {
                        Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                            .frame(width: CalendarTheme.minimumTapSize, height: CalendarTheme.minimumTapSize)
                    }
                    .disabled(isMutating)
                    .accessibilityLabel(item.isCompleted ? "Mark \(item.title) incomplete" : "Mark \(item.title) complete")
                    .accessibilityValue(item.isCompleted ? "Completed" : "Not completed")
                } else {
                    Text("Read-only").font(.caption).foregroundStyle(.secondary)
                        .accessibilityLabel("Read-only task")
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var sourceSymbol: String { switch item.source { case .event: "calendar"; case .task: "checkmark.circle"; case .routine: "repeat" } }
    private var sourceColor: Color { switch item.source { case .event: CalendarTheme.accent; case .task: .orange; case .routine: .purple } }
    private var timeDescription: String {
        switch item.placement {
        case .allDay: String(localized: "All Day")
        case let .timed(date): date.formatted(date: .omitted, time: .shortened)
        case let .window(window):
            switch window {
            case .morning: String(localized: "Morning")
            case .afternoon: String(localized: "Afternoon")
            case .evening: String(localized: "Evening")
            case .anytime: String(localized: "Anytime")
            }
        case .unscheduled: String(localized: "Priority")
        }
    }
}
