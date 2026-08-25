import Foundation

enum AgendaAccessibilityDescription {
    static func build(for item: AgendaItem) -> String {
        [
            sourceDescription(item.source),
            item.title,
            scheduleDescription(item.placement),
            completionDescription(item.isCompleted),
            modificationDescription(item.allowsModification)
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
    }

    static func scheduleDescription(_ placement: AgendaPlacement) -> String {
        switch placement {
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

    static func completionDescription(_ isCompleted: Bool) -> String {
        isCompleted ? String(localized: "Completed") : String(localized: "Not completed")
    }

    private static func sourceDescription(_ source: AgendaSource) -> String {
        switch source {
        case .event: String(localized: "Event")
        case .task: String(localized: "Task")
        case .routine: String(localized: "Routine")
        }
    }

    private static func modificationDescription(_ allowsModification: Bool) -> String? {
        allowsModification ? nil : String(localized: "Read-only")
    }
}
