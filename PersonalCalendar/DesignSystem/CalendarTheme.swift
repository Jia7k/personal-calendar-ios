import SwiftUI

enum CalendarTheme {
    static let accent = Color(red: 0.20, green: 0.55, blue: 0.50)
    static let cornerRadius: CGFloat = 16
    static let minimumTapSize: CGFloat = 44

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
