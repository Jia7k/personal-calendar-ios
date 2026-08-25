import SwiftUI

enum CalendarTheme {
    static let accent = Color("AccentColor")
    static let background = Color("CalendarBackground")
    static let surface = Color("CalendarSurface")
    static let selectionFill = Color("CalendarSelection")
    static let event = Color("EventColor")
    static let task = Color("TaskColor")
    static let routine = Color("RoutineColor")
    static let cornerRadius: CGFloat = 16
    static let minimumTapSize: CGFloat = 44

    static func sourceColor(_ source: AgendaSource) -> Color {
        switch source {
        case .event: event
        case .task: task
        case .routine: routine
        }
    }

    static func color(hex: String) -> Color? {
        let value = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard value.count == 6, let rgb = UInt64(value, radix: 16) else { return nil }
        return Color(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}
