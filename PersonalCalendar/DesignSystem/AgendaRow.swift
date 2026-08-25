import SwiftUI

struct AgendaRow: View {
    let item: AgendaItem
    let isMutating: Bool
    let open: (() -> Void)?
    let complete: (Bool) -> Void

    init(item: AgendaItem, isMutating: Bool, open: (() -> Void)? = nil, complete: @escaping (Bool) -> Void) {
        self.item = item
        self.isMutating = isMutating
        self.open = open
        self.complete = complete
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            if let open, let metadata = openMetadata {
                Button(action: open) {
                    primaryContent
                }
                .buttonStyle(.borderless)
                .frame(maxWidth: .infinity, minHeight: CalendarTheme.minimumTapSize, alignment: .leading)
                .contentShape(Rectangle())
                .accessibilityIdentifier(metadata)
                .accessibilityLabel(AgendaAccessibilityDescription.build(for: item))
            } else {
                primaryContent
                    .frame(maxWidth: .infinity, minHeight: CalendarTheme.minimumTapSize, alignment: .leading)
            }
            if item.source == .task || item.source == .routine {
                if item.allowsModification {
                    Button { complete(!item.isCompleted) } label: {
                        Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                            .frame(width: CalendarTheme.minimumTapSize, height: CalendarTheme.minimumTapSize)
                    }
                    .buttonStyle(.borderless)
                    .disabled(isMutating)
                    .accessibilityLabel(item.isCompleted ? "Mark \(item.title) incomplete" : "Mark \(item.title) complete")
                    .accessibilityValue(item.isCompleted ? "Completed" : "Not completed")
                    .accessibilityIdentifier(completionIdentifier)
                } else {
                    Text("Read-only").font(.caption).foregroundStyle(.secondary)
                        .accessibilityLabel("Read-only task")
                        .accessibilityHidden(true)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var primaryContent: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            if let categoryColor {
                Capsule()
                    .fill(categoryColor)
                    .frame(width: 4, height: 30)
                    .accessibilityHidden(true)
            }
            Image(systemName: sourceSymbol)
                .foregroundStyle(categoryColor ?? sourceColor)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title).font(.body).strikethrough(item.isCompleted)
                Text(timeDescription).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
        }
        .padding(.horizontal, item.category == nil ? 0 : 8)
        .background(categoryBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AgendaAccessibilityDescription.build(for: item))
    }

    private var categoryColor: Color? {
        item.category.flatMap { CalendarTheme.color(hex: $0.colorHex) }
    }

    @ViewBuilder private var categoryBackground: some View {
        if let categoryColor {
            categoryColor.opacity(item.placement == .allDay ? 0.22 : 0.09)
        } else {
            Color.clear
        }
    }

    private var openMetadata: String? {
        switch item.origin {
        case let .event(id):
            ("agenda-open-event-\(id)")
        case let .reminder(id):
            ("agenda-open-task-\(id)")
        case .routine, .synthetic:
            nil
        }
    }

    private var completionIdentifier: String {
        switch item.origin {
        case let .reminder(id): "agenda-complete-task-\(id)"
        case let .routine(id, day): "agenda-complete-routine-\(id.uuidString)-\(day.year)-\(day.month)-\(day.day)"
        case .event, .synthetic: "agenda-complete-\(item.id)"
        }
    }

    private var sourceSymbol: String { switch item.source { case .event: "calendar"; case .task: "checkmark.circle"; case .routine: "repeat" } }
    private var sourceColor: Color { switch item.source { case .event: CalendarTheme.accent; case .task: .orange; case .routine: .purple } }
    private var timeDescription: String { AgendaAccessibilityDescription.scheduleDescription(item.placement) }
}
